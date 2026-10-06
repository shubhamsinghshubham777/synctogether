-- Moderation follow-ups: R2 queue fix, banned rooms are fully retired, and
-- warn/ban reach the affected user's client immediately.
--
-- admin_ban_room queued R2 cleanup into public.r2_cleanup_queue, which does not
-- exist (the table is pending_r2_deletions), so banning any room that held shared
-- media raised and rolled back. It also left media_file_size set while resetting
-- media_upload_state to 'none', which rooms_media_shape_chk rejects.

create or replace function public.admin_ban_room(
  p_room_id uuid,
  p_reason text,
  p_report_id uuid default null,
  p_notes text default null,
  p_ai_assisted boolean default false
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_room public.rooms;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'room_not_found';
  end if;

  update public.rooms
     set is_banned = true,
         banned_at = coalesce(banned_at, now()),
         ban_reason = p_reason,
         ended_at = coalesce(ended_at, now())
   where id = p_room_id;

  -- Queue R2 media cleanup if room had uploaded media
  if v_room.media_r2_key is not null then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);
  end if;

  if v_room.media_r2_key is not null or v_room.media_upload_id is not null then
    update public.rooms
       set media_r2_key = null,
           media_upload_id = null,
           media_file_size = null,
           media_upload_state = 'none'
     where id = p_room_id;
  end if;

  -- Same cleanup retire_room does: release upload locks, drop the chat.
  update public.profiles set
    active_upload_room_id = null,
    active_upload_started_at = null
  where active_upload_room_id = p_room_id;

  delete from public.messages where room_id = p_room_id;

  -- Broadcast instant eviction via Realtime, then drop the memberships: the
  -- private channel is authorized on membership at subscribe time, so an
  -- evicted client must not be able to resubscribe to a closed room.
  perform public.announce_room_ended(p_room_id, 'room_banned');
  delete from public.room_members where room_id = p_room_id;

  if p_report_id is not null then
    update public.content_reports
       set status = 'actioned'
     where id = p_report_id;
  end if;

  insert into public.moderation_actions (
    report_id, action_type, target_room_id, target_user_id, reason, notes, actioned_by, ai_assisted
  ) values (
    p_report_id, 'ban_room', p_room_id, v_room.created_by, p_reason, p_notes, coalesce((select auth.uid())::text, 'reviewer'), p_ai_assisted
  );
end $$;

-- create or replace keeps existing grants; restated so the file stands alone.
revoke all on function public.admin_ban_room(uuid, text, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.admin_ban_room(uuid, text, uuid, text, boolean) to service_role;

-- ---------------------------------------------------------------------------
-- Live delivery: a user-scoped private channel, readable only by that user.
-- ---------------------------------------------------------------------------

create policy "users can receive their own moderation broadcasts"
  on realtime.messages for select to authenticated
  using (realtime.topic() = 'user:' || (select auth.uid())::text);

create or replace function public.notify_moderation_changed(p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('timestamp', (extract(epoch from clock_timestamp()) * 1000)::bigint),
    'moderation_changed',
    'user:' || p_user_id::text,
    true);
exception when others then
  raise warning 'notify_moderation_changed failed for %: %', p_user_id, sqlerrm;
end $$;

revoke all on function public.notify_moderation_changed(uuid) from public, anon, authenticated;
grant execute on function public.notify_moderation_changed(uuid) to service_role;

create or replace function public.admin_ban_user(
  p_user_id uuid,
  p_reason text,
  p_report_id uuid default null,
  p_notes text default null,
  p_ai_assisted boolean default false
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_room record;
begin
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'user_not_found';
  end if;

  perform set_config('synctogether.moderation_bypass', 'true', true);

  update public.profiles
     set strikes_count = greatest(strikes_count, 2),
         moderation_status = 'banned',
         banned_at = coalesce(banned_at, now()),
         ban_reason = p_reason,
         updated_at = now()
   where id = p_user_id;

  -- Terminate any live rooms created by this banned user. The report id rides
  -- along so each room's audit row stays linked to the report that caused it.
  for v_room in
    select id from public.rooms where created_by = p_user_id and ended_at is null
  loop
    perform public.admin_ban_room(v_room.id, 'Host account suspended: ' || p_reason, p_report_id, p_notes, p_ai_assisted);
  end loop;

  if p_report_id is not null then
    update public.content_reports
       set status = 'actioned'
     where id = p_report_id;
  end if;

  insert into public.moderation_actions (
    report_id, action_type, target_user_id, reason, notes, actioned_by, ai_assisted
  ) values (
    p_report_id, 'ban_user', p_user_id, p_reason, p_notes, coalesce((select auth.uid())::text, 'reviewer'), p_ai_assisted
  );

  perform public.notify_moderation_changed(p_user_id);
end $$;

create or replace function public.admin_warn_user(
  p_user_id uuid,
  p_reason text,
  p_report_id uuid default null,
  p_notes text default null,
  p_ai_assisted boolean default false
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_strikes int;
begin
  select * into v_profile from public.profiles where id = p_user_id;
  if not found then
    raise exception 'user_not_found';
  end if;

  v_strikes := v_profile.strikes_count + 1;

  if v_strikes >= 2 then
    perform public.admin_ban_user(
      p_user_id => p_user_id,
      p_reason => coalesce(p_reason, 'Accumulated 2 moderation strikes'),
      p_report_id => p_report_id,
      p_notes => p_notes,
      p_ai_assisted => p_ai_assisted
    );
  else
    perform set_config('synctogether.moderation_bypass', 'true', true);

    update public.profiles
       set strikes_count = v_strikes,
           moderation_status = 'warned',
           warning_reason = p_reason,
           warning_acknowledged = false,
           last_warned_at = now(),
           updated_at = now()
     where id = p_user_id;

    if p_report_id is not null then
      update public.content_reports
         set status = 'actioned'
       where id = p_report_id;
    end if;

    insert into public.moderation_actions (
      report_id, action_type, target_user_id, reason, notes, actioned_by, ai_assisted
    ) values (
      p_report_id, 'warn_user', p_user_id, p_reason, p_notes, coalesce((select auth.uid())::text, 'reviewer'), p_ai_assisted
    );

    perform public.notify_moderation_changed(p_user_id);
  end if;
end $$;

revoke all on function public.admin_ban_user(uuid, text, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.admin_warn_user(uuid, text, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.admin_ban_user(uuid, text, uuid, text, boolean) to service_role;
grant execute on function public.admin_warn_user(uuid, text, uuid, text, boolean) to service_role;
