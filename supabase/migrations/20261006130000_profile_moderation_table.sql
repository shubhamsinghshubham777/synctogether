-- Moderation state moves off `profiles`.
--
-- `profiles` is readable by every signed-in user (that is how members see each
-- other's names), so strikes, warning reasons and ban reasons were readable by
-- anyone. They now live in `profile_moderation`: owner-select only, no client
-- writes. The columns are copied across, then dropped from `profiles`, along
-- with the trigger that existed only to stop clients writing them.

create table if not exists public.profile_moderation (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  strikes_count int not null default 0,
  moderation_status text not null default 'clean'
    check (moderation_status in ('clean', 'warned', 'banned')),
  warning_reason text,
  warning_acknowledged boolean not null default true,
  last_warned_at timestamptz,
  banned_at timestamptz,
  ban_reason text,
  updated_at timestamptz not null default now()
);

create index if not exists idx_profile_moderation_status
  on public.profile_moderation (moderation_status);

insert into public.profile_moderation (
  user_id, strikes_count, moderation_status, warning_reason,
  warning_acknowledged, last_warned_at, banned_at, ban_reason)
select id, strikes_count, moderation_status, warning_reason,
       warning_acknowledged, last_warned_at, banned_at, ban_reason
  from public.profiles
 where moderation_status <> 'clean' or strikes_count > 0
on conflict (user_id) do nothing;

drop trigger if exists tr_protect_profile_moderation_fields on public.profiles;
drop function if exists public.protect_profile_moderation_fields();
drop index if exists public.idx_profiles_moderation_status;

alter table public.profiles
  drop column if exists strikes_count,
  drop column if exists moderation_status,
  drop column if exists warning_reason,
  drop column if exists warning_acknowledged,
  drop column if exists last_warned_at,
  drop column if exists banned_at,
  drop column if exists ban_reason;

alter table public.profile_moderation enable row level security;
revoke all on public.profile_moderation from anon, authenticated;
grant select on public.profile_moderation to authenticated;
grant all on public.profile_moderation to service_role;

create policy "users read their own moderation state"
  on public.profile_moderation for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.acknowledge_warning()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  update public.profile_moderation
     set warning_acknowledged = true,
         updated_at = now()
   where user_id = v_uid and moderation_status = 'warned';
end $$;

create or replace function public.create_room(
  p_name text,
  p_duration_minutes int,
  p_staged_id uuid default null
)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tier text;
  v_limits public.tier_limits;
  v_held int;
  v_code text;
  v_room public.rooms;
  v_staged public.staged_media_uploads%rowtype;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'not_authenticated';
  end if;

  if exists (select 1 from public.profile_moderation where user_id = v_uid and moderation_status = 'banned') then
    raise exception 'account_banned';
  end if;

  v_tier := public.effective_tier(v_uid);
  select * into v_limits from public.tier_limits where tier = v_tier;

  if p_duration_minutes is null
     or p_duration_minutes < 5
     or p_duration_minutes > v_limits.max_session_minutes then
    raise exception 'invalid_duration';
  end if;

  -- If staged media provided, validate ownership and ready status
  if p_staged_id is not null then
    select * into v_staged from public.staged_media_uploads
    where id = p_staged_id
      and user_id = v_uid
      and upload_state = 'ready'
      and claimed_room_id is null
      and expires_at > now();

    if v_staged.id is null then
      raise exception 'staged_media_invalid';
    end if;
  end if;

  select count(*) into v_held from public.rooms r
    where r.created_by = v_uid and public.room_state(r) = 'live';
  if v_held >= v_limits.max_live_rooms then
    if v_tier = 'guest' then
      raise exception 'guest_room_limit';
    end if;
    raise exception 'room_limit_reached';
  end if;

  if v_limits.persistent_room_cap > 0 then
    select count(*) into v_held from public.rooms r
      where r.created_by = v_uid and r.persistent;
    if v_held >= v_limits.persistent_room_cap then
      raise exception 'room_limit_reached';
    end if;
  end if;

  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
      into v_code from generate_series(1, 6);
    exit when not exists (select 1 from public.rooms where code = v_code);
  end loop;

  insert into public.rooms (
    code,
    name,
    created_by,
    duration_minutes,
    expires_at,
    persistent,
    dormant_hours,
    av_level,
    max_members,
    media_kind,
    media_name,
    media_duration_ms,
    media_file_size,
    media_r2_key,
    media_upload_state,
    media_sharing_level,
    media_updated_at
  )
  values (
    v_code,
    coalesce(nullif(left(trim(p_name), 60), ''), 'Watch party'),
    v_uid,
    p_duration_minutes,
    now() + make_interval(mins => p_duration_minutes),
    v_limits.persistent_room_cap > 0,
    v_limits.dormant_hours,
    v_limits.av_level,
    v_limits.max_members,
    case when p_staged_id is not null then 'local' else 'none' end,
    case when p_staged_id is not null then v_staged.file_name else null end,
    case when p_staged_id is not null then v_staged.duration_ms else null end,
    case when p_staged_id is not null then v_staged.file_size else null end,
    case when p_staged_id is not null then v_staged.r2_key else null end,
    case when p_staged_id is not null then 'ready' else 'none' end,
    v_limits.media_sharing,
    case when p_staged_id is not null then now() else null end
  )
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host');

  -- Mark staged upload as claimed
  if p_staged_id is not null then
    update public.staged_media_uploads
    set claimed_room_id = v_room.id
    where id = p_staged_id;
  end if;

  return v_room;
end $$;

grant execute on function public.create_room(text, int, uuid) to authenticated;

create or replace function public.join_room(p_code text)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
  v_count int;
  v_has_host boolean;
  v_was_member boolean;
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'not_authenticated';
  end if;

  if exists (select 1 from public.profile_moderation where user_id = v_uid and moderation_status = 'banned') then
    raise exception 'account_banned';
  end if;

  select * into v_room from public.rooms where code = upper(trim(p_code));
  if not found then
    raise exception 'room_not_found';
  end if;

  if v_room.is_banned then
    raise exception 'room_closed_by_admin';
  end if;

  if exists (select 1 from public.room_bans
             where room_id = v_room.id and user_id = v_uid) then
    raise exception 'room_banned';
  end if;

  if public.room_state(v_room) <> 'live' then
    raise exception 'room_ended';
  end if;

  select exists (select 1 from public.room_members
                 where room_id = v_room.id and role = 'host') into v_has_host;

  select exists (select 1 from public.room_members where user_id = v_uid)
    into v_was_member;

  if exists (select 1 from public.room_members
             where room_id = v_room.id and user_id = v_uid) then
    if not v_has_host and v_uid = v_room.created_by then
      update public.room_members set role = 'host'
        where room_id = v_room.id and user_id = v_uid;
    end if;
    return v_room;
  end if;

  select count(*) into v_count from public.room_members where room_id = v_room.id;
  if v_count >= v_room.max_members then
    raise exception 'room_full';
  end if;

  insert into public.room_members (room_id, user_id, role)
  values (
    v_room.id,
    v_uid,
    case when not v_has_host and v_uid = v_room.created_by then 'host' else 'member' end
  );

  if not v_was_member and v_room.created_by <> v_uid then
    update public.profiles
       set referred_by = v_room.created_by, updated_at = now()
     where id = v_uid and referred_by is null;
  end if;

  return v_room;
end $$;

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

  insert into public.profile_moderation (
    user_id, strikes_count, moderation_status, banned_at, ban_reason)
  values (p_user_id, 2, 'banned', now(), p_reason)
  on conflict (user_id) do update
    set strikes_count = greatest(public.profile_moderation.strikes_count, 2),
        moderation_status = 'banned',
        banned_at = coalesce(public.profile_moderation.banned_at, now()),
        ban_reason = p_reason,
        updated_at = now();

  for v_room in
    select id from public.rooms where created_by = p_user_id and ended_at is null
  loop
    perform public.admin_ban_room(v_room.id, 'Host account suspended: ' || p_reason, p_report_id, p_notes, p_ai_assisted);
  end loop;

  if p_report_id is not null then
    update public.content_reports set status = 'actioned' where id = p_report_id;
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
  v_strikes int;
begin
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'user_not_found';
  end if;

  select coalesce((select strikes_count from public.profile_moderation
                    where user_id = p_user_id), 0) + 1
    into v_strikes;

  if v_strikes >= 2 then
    perform public.admin_ban_user(
      p_user_id => p_user_id,
      p_reason => coalesce(p_reason, 'Accumulated 2 moderation strikes'),
      p_report_id => p_report_id,
      p_notes => p_notes,
      p_ai_assisted => p_ai_assisted
    );
  else
    insert into public.profile_moderation (
      user_id, strikes_count, moderation_status, warning_reason,
      warning_acknowledged, last_warned_at)
    values (p_user_id, v_strikes, 'warned', p_reason, false, now())
    on conflict (user_id) do update
      set strikes_count = v_strikes,
          moderation_status = 'warned',
          warning_reason = p_reason,
          warning_acknowledged = false,
          last_warned_at = now(),
          updated_at = now();

    if p_report_id is not null then
      update public.content_reports set status = 'actioned' where id = p_report_id;
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
