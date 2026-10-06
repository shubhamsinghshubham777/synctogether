-- Moderation enforcement: user strikes, account bans, room bans, media snapshots,
-- and moderation audit actions.

-- ---------------------------------------------------------------------------
-- 1. Profiles moderation fields
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists strikes_count int not null default 0,
  add column if not exists moderation_status text not null default 'clean'
    check (moderation_status in ('clean', 'warned', 'banned')),
  add column if not exists warning_reason text,
  add column if not exists warning_acknowledged boolean not null default true,
  add column if not exists last_warned_at timestamptz,
  add column if not exists banned_at timestamptz,
  add column if not exists ban_reason text;

create index if not exists idx_profiles_moderation_status on public.profiles (moderation_status);

-- Prevent clients from tampering with moderation columns
create or replace function public.protect_profile_moderation_fields()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if coalesce(current_setting('synctogether.moderation_bypass', true), 'false') <> 'true' then
    if auth.role() = 'authenticated' then
      if (new.strikes_count is distinct from old.strikes_count) or
         (new.moderation_status is distinct from old.moderation_status) or
         (new.warning_reason is distinct from old.warning_reason) or
         (new.warning_acknowledged is distinct from old.warning_acknowledged) or
         (new.last_warned_at is distinct from old.last_warned_at) or
         (new.banned_at is distinct from old.banned_at) or
         (new.ban_reason is distinct from old.ban_reason) then
        raise exception 'moderation_fields_read_only';
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_protect_profile_moderation_fields on public.profiles;
create trigger tr_protect_profile_moderation_fields
before update on public.profiles
for each row execute function public.protect_profile_moderation_fields();

-- ---------------------------------------------------------------------------
-- 2. Rooms moderation fields
-- ---------------------------------------------------------------------------

alter table public.rooms
  add column if not exists is_banned boolean not null default false,
  add column if not exists banned_at timestamptz,
  add column if not exists ban_reason text;

-- ---------------------------------------------------------------------------
-- 3. Content reports: media snapshot & AI triage fields
-- ---------------------------------------------------------------------------

alter table public.content_reports
  add column if not exists media_kind text,
  add column if not exists media_title text,
  add column if not exists media_source_url text,
  add column if not exists room_code text,
  add column if not exists ai_risk_score int check (ai_risk_score is null or (ai_risk_score between 0 and 100)),
  add column if not exists ai_recommended_action text
    check (ai_recommended_action is null or ai_recommended_action in ('dismiss', 'warn_user', 'ban_room', 'ban_user', 'ban_room_and_warn_user', 'ban_room_and_ban_user', 'escalate')),
  add column if not exists ai_reasoning text,
  add column if not exists ai_analyzed_at timestamptz;

-- ---------------------------------------------------------------------------
-- 4. Moderation actions (Audit log)
-- ---------------------------------------------------------------------------

create table if not exists public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid references public.content_reports (id) on delete set null,
  action_type text not null check (action_type in ('warn_user', 'ban_user', 'ban_room', 'ban_room_and_warn_user', 'ban_room_and_ban_user', 'dismiss')),
  target_user_id uuid references public.profiles (id) on delete set null,
  target_room_id uuid,
  reason text not null,
  notes text,
  actioned_by text not null default 'reviewer',
  ai_assisted boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_moderation_actions_target_user on public.moderation_actions (target_user_id, created_at desc);
create index if not exists idx_moderation_actions_created_at on public.moderation_actions (created_at desc);

alter table public.moderation_actions enable row level security;
revoke all on public.moderation_actions from anon, authenticated;
grant all on public.moderation_actions to service_role;

-- ---------------------------------------------------------------------------
-- 5. Updated RPCs: report_content, create_room, join_room, acknowledge_warning
-- ---------------------------------------------------------------------------

-- Drop old 7-param signature to avoid overload resolution ambiguity with default args
drop function if exists public.report_content(uuid, text, uuid, text, uuid, text, text);

create or replace function public.report_content(
  p_reported_user_id uuid,
  p_reason text,
  p_room_id uuid default null,
  p_details text default null,
  p_message_id uuid default null,
  p_message_excerpt text default null,
  p_source text default 'report',
  p_media_kind text default null,
  p_media_title text default null,
  p_media_source_url text default null,
  p_room_code text default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_recent int;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_reported_user_id is null or p_reported_user_id = v_uid then
    raise exception 'invalid_target';
  end if;
  if p_reason not in ('harassment', 'hate_speech', 'sexual_content',
                      'violence', 'copyright', 'spam', 'other') then
    raise exception 'invalid_reason';
  end if;
  if p_source not in ('report', 'blocked') then
    raise exception 'invalid_source';
  end if;

  select count(*) into v_recent
    from public.content_reports
    where reporter_id = v_uid and created_at > now() - interval '1 hour';
  if v_recent >= 20 then
    raise exception 'report_rate_limited';
  end if;

  insert into public.content_reports (
    reporter_id, reported_user_id, room_id, message_id,
    message_excerpt, reason, details, source,
    media_kind, media_title, media_source_url, room_code)
  values (
    v_uid, p_reported_user_id, p_room_id, p_message_id,
    left(p_message_excerpt, 500), p_reason, left(p_details, 2000), p_source,
    left(p_media_kind, 20), left(p_media_title, 250), left(p_media_source_url, 1000), upper(trim(p_room_code)))
  returning id into v_id;

  return v_id;
end $$;

revoke all on function public.report_content(uuid, text, uuid, text, uuid, text, text, text, text, text, text) from public, anon;
grant execute on function public.report_content(uuid, text, uuid, text, uuid, text, text, text, text, text, text) to authenticated;

-- Warning acknowledgment
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

  perform set_config('synctogether.moderation_bypass', 'true', true);

  update public.profiles
     set warning_acknowledged = true,
         updated_at = now()
   where id = v_uid and moderation_status = 'warned';
end $$;

revoke all on function public.acknowledge_warning() from public, anon;
grant execute on function public.acknowledge_warning() to authenticated;

-- create_room with banned account check
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

  if exists (select 1 from public.profiles where id = v_uid and moderation_status = 'banned') then
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

-- join_room with room ban and banned account check
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

  if exists (select 1 from public.profiles where id = v_uid and moderation_status = 'banned') then
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

-- ---------------------------------------------------------------------------
-- 6. Administrative RPCs (Service Role only)
-- ---------------------------------------------------------------------------

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
  if v_room.media_r2_key is not null or v_room.media_upload_id is not null then
    insert into public.r2_cleanup_queue (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);

    update public.rooms
       set media_r2_key = null,
           media_upload_id = null,
           media_upload_state = 'none'
     where id = p_room_id;
  end if;

  -- Broadcast instant eviction via Realtime
  perform public.announce_room_ended(p_room_id, 'room_banned');

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

  -- Terminate any live rooms created by this banned user
  for v_room in
    select id from public.rooms where created_by = p_user_id and ended_at is null
  loop
    perform public.admin_ban_room(v_room.id, 'Host account suspended: ' || p_reason, null, p_notes, p_ai_assisted);
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
  end if;
end $$;

create or replace function public.admin_dismiss_report(
  p_report_id uuid,
  p_notes text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.content_reports
     set status = 'dismissed'
   where id = p_report_id;

  insert into public.moderation_actions (
    report_id, action_type, reason, notes, actioned_by
  ) values (
    p_report_id, 'dismiss', 'No violation found', p_notes, coalesce((select auth.uid())::text, 'reviewer')
  );
end $$;

create or replace function public.admin_record_ai_triage(
  p_report_id uuid,
  p_risk_score int,
  p_recommended_action text,
  p_reasoning text
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.content_reports
     set ai_risk_score = p_risk_score,
         ai_recommended_action = p_recommended_action,
         ai_reasoning = p_reasoning,
         ai_analyzed_at = now()
   where id = p_report_id;
end $$;

-- Revoke all admin functions from public, anon, authenticated; grant only to service_role
revoke all on function public.admin_ban_room(uuid, text, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.admin_ban_user(uuid, text, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.admin_warn_user(uuid, text, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.admin_dismiss_report(uuid, text) from public, anon, authenticated;
revoke all on function public.admin_record_ai_triage(uuid, int, text, text) from public, anon, authenticated;

grant execute on function public.admin_ban_room(uuid, text, uuid, text, boolean) to service_role;
grant execute on function public.admin_ban_user(uuid, text, uuid, text, boolean) to service_role;
grant execute on function public.admin_warn_user(uuid, text, uuid, text, boolean) to service_role;
grant execute on function public.admin_dismiss_report(uuid, text) to service_role;
grant execute on function public.admin_record_ai_triage(uuid, int, text, text) to service_role;
