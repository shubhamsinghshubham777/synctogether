-- Date nights, phase 2: the planner can attach a FILE, uploaded ahead of the night
-- through the same staged-upload slot a lobby pre-upload uses (so the size caps,
-- the weekly allowance, the abort penalties and the R2 clean-up all apply
-- unchanged). The night adopts the slot and keeps it until a day after the night;
-- when the night starts, Our Room claims the object exactly as create_room claims
-- a staged one. See docs/agent/pairing.md.
alter table public.date_nights
  add column file_name text,
  add column file_size bigint check (file_size is null or file_size > 0),
  add column file_duration_ms bigint,
  add column media_r2_key text,
  add column upload_state text not null default 'none'
    check (upload_state in ('none', 'uploading', 'ready', 'stopped')),
  add column upload_bytes bigint not null default 0 check (upload_bytes >= 0),
  add constraint date_nights_file_shape_chk check (
    (attach_kind = 'file') = (file_name is not null and file_size is not null)),
  add constraint date_nights_file_state_chk check (
    (attach_kind = 'file') = (upload_state <> 'none'));

alter table public.staged_media_uploads
  add column date_night_id uuid references public.date_nights (id) on delete set null;
create unique index staged_media_one_per_night
  on public.staged_media_uploads (date_night_id) where date_night_id is not null;

-- Whether a night is "on": accepted, from 15 minutes before to four hours after.
create or replace function public.date_night_is_on(p_night public.date_nights)
returns boolean
language sql stable set search_path = ''
as $$
  select p_night.status = 'accepted'
     and p_night.starts_at - interval '15 minutes' <= now()
     and p_night.starts_at + interval '4 hours' >= now();
$$;

-- The 15-minute reminder's words, from the night as it is at that moment.
create or replace function public.date_night_reminder_body(p_night public.date_nights)
returns text
language sql stable set search_path = ''
as $$
  select case
    when p_night.attach_kind = 'youtube' and p_night.youtube_url is not null
      then p_night.title || ' is ready. Open Our Room and press play.'
    when p_night.attach_kind = 'file' and p_night.upload_state = 'ready'
      then p_night.title || ' is ready. Open Our Room and press play.'
    when p_night.attach_kind = 'file' and p_night.upload_state = 'uploading'
      then p_night.title || ' is still arriving ('
           || least(99, floor(100.0 * p_night.upload_bytes / nullif(p_night.file_size, 0))::int)
           || '%). The room opens on time.'
    else 'Pick something together in Our Room.'
  end;
$$;

-- Put the attached film into Our Room and tell everyone already inside. The
-- server changes the row itself, and the channel is how members hear about it
-- (the host's app is not the one acting), so the same two events the host's app
-- would send go out: the media, and - for a file - that it is ready to stream.
create or replace function public.apply_date_night_media(p_night public.date_nights, p_room public.rooms)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_room public.rooms := p_room;
  v_staged public.staged_media_uploads;
  v_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  -- Whatever the room held before leaves R2 with it.
  if v_room.media_r2_key is not null or v_room.media_upload_id is not null then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);
  end if;

  if p_night.attach_kind = 'youtube' and p_night.youtube_url is not null then
    update public.rooms set
      media_kind = 'youtube', media_url = p_night.youtube_url,
      media_name = left(p_night.title, 255), media_duration_ms = null,
      media_r2_key = null, media_upload_id = null, media_file_size = null,
      media_upload_state = 'none', media_updated_at = now(),
      media_position_ms = 0, media_position_at = now()
    where id = v_room.id
    returning * into v_room;
  elsif p_night.attach_kind = 'file' and p_night.upload_state = 'ready' then
    select * into v_staged from public.staged_media_uploads
      where date_night_id = p_night.id and upload_state = 'ready' and claimed_room_id is null
      for update;
    if not found then
      return v_room;
    end if;
    update public.rooms set
      media_kind = 'local', media_url = null, media_name = left(v_staged.file_name, 255),
      media_duration_ms = coalesce(v_staged.duration_ms, p_night.file_duration_ms),
      media_file_size = v_staged.file_size, media_r2_key = v_staged.r2_key,
      media_upload_id = null, media_upload_state = 'ready', media_updated_at = now(),
      media_position_ms = 0, media_position_at = now()
    where id = v_room.id
    returning * into v_room;
    -- The room owns the object now: claimed rows are neither swept nor queued
    -- for deletion with the slot.
    update public.staged_media_uploads set claimed_room_id = v_room.id where id = v_staged.id;
  else
    return v_room;
  end if;

  update public.date_nights set media_applied_at = now() where id = p_night.id;

  begin
    perform realtime.send(
      jsonb_build_object('kind', v_room.media_kind, 'name', v_room.media_name,
        'durationMs', v_room.media_duration_ms, 'url', v_room.media_url, 'updatedAtMs', v_ms),
      'media_set', 'room:' || v_room.id::text, true);
    if v_room.media_kind = 'local' then
      perform realtime.send(
        jsonb_build_object('fraction', 1.0, 'speedBps', 0, 'etaSeconds', 0, 'state', 'ready'),
        'upload_progress', 'room:' || v_room.id::text, true);
    end if;
  exception when others then
    raise warning 'apply_date_night_media: broadcast failed for %: %', v_room.id, sqlerrm;
  end;
  return v_room;
end $$;

-- "Your movie is ready", to the partner, once the film is there and they have
-- said yes. (Said at whichever of those happens second.)
create or replace function public.date_night_notify_ready(p_night public.date_nights)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_partner uuid := public.partner_of(p_night.proposed_by);
begin
  if p_night.status <> 'accepted' or v_partner is null then
    return;
  end if;
  if not ((p_night.attach_kind = 'file' and p_night.upload_state = 'ready')) then
    return;
  end if;
  perform public.enqueue_push(
    v_partner, 'date_night_ready',
    'Your movie is ready',
    p_night.title || ' is waiting in Our Room for ' || public.local_stamp(p_night.starts_at, v_partner) || '.',
    jsonb_build_object('route', 'our-room', 'night', p_night.id),
    now(), p_night.starts_at + interval '4 hours', 'dn-ready:' || p_night.id::text);
end $$;

-- The file finished: tell the partner, and if the night is already on with the
-- room live and empty, hand it over now.
create or replace function public.date_night_file_ready(p_night_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_night public.date_nights;
  v_room public.rooms;
begin
  select * into v_night from public.date_nights where id = p_night_id;
  if not found then
    return;
  end if;
  perform public.date_night_notify_ready(v_night);
  select * into v_room from public.rooms where pair_id = v_night.pair_id;
  if found and public.date_night_is_on(v_night) and v_night.media_applied_at is null
     and public.room_state(v_room) = 'live' and coalesce(v_room.media_kind, 'none') = 'none' then
    perform public.apply_date_night_media(v_night, v_room);
  end if;
end $$;

-- Let a night's file go: the unclaimed slot (deleting it queues the R2 object and
-- any half-finished multipart for the cleanup job) and the night's own columns.
create or replace function public.free_date_night_file(p_night_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.staged_media_uploads
    where date_night_id = p_night_id and claimed_room_id is null;
  update public.date_nights set
    attach_kind = case when attach_kind = 'file' then 'none' else attach_kind end,
    file_name = null, file_size = null, file_duration_ms = null, media_r2_key = null,
    upload_state = 'none', upload_bytes = 0,
    media_applied_at = case when attach_kind = 'file' then null else media_applied_at end
  where id = p_night_id and (attach_kind = 'file' or file_name is not null);
end $$;

-- A night's slot is kept in step with it: finished or failed updates the night,
-- and a slot that disappears (aborted, or swept at its expiry) takes the file
-- off the night rather than leave it promising one.
create or replace function public.trig_staged_night_sync()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.date_night_id is not null and new.upload_state is distinct from old.upload_state then
      if new.upload_state = 'ready' then
        update public.date_nights set upload_state = 'ready', upload_bytes = file_size
          where id = new.date_night_id and attach_kind = 'file';
        perform public.date_night_file_ready(new.date_night_id);
      elsif new.upload_state = 'failed' then
        update public.date_nights set upload_state = 'stopped'
          where id = new.date_night_id and attach_kind = 'file';
      end if;
    end if;
    return new;
  end if;
  if old.date_night_id is not null and old.claimed_room_id is null then
    update public.date_nights set
      attach_kind = 'none', file_name = null, file_size = null, file_duration_ms = null,
      media_r2_key = null, upload_state = 'none', upload_bytes = 0
    where id = old.date_night_id and attach_kind = 'file';
  end if;
  return old;
end $$;
create trigger staged_night_sync_update after update on public.staged_media_uploads
  for each row execute function public.trig_staged_night_sync();
create trigger staged_night_sync_delete after delete on public.staged_media_uploads
  for each row execute function public.trig_staged_night_sync();

-- A night that is deleted (its pair ended) lets its unclaimed file go with it.
create or replace function public.trig_night_deleted_free_file()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.staged_media_uploads
    where date_night_id = old.id and claimed_room_id is null;
  return old;
end $$;
create trigger date_night_deleted_free_file before delete on public.date_nights
  for each row execute function public.trig_night_deleted_free_file();

-- A day after the night, an unused file goes. (A file the room claimed is the
-- room's, and leaves with the session.)
create or replace function public.sweep_date_night_files()
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_count int := 0;
begin
  for v_id in
    select id from public.date_nights
    where starts_at + interval '1 day' < now()
      and (attach_kind = 'file' or file_name is not null)
      and media_applied_at is null
  loop
    perform public.free_date_night_file(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- The planner's app reports how far it has got, and when the connection drops.
create or replace function public.set_date_night_upload_progress(
  p_night_id uuid, p_bytes bigint, p_state text default 'uploading')
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_night public.date_nights;
begin
  select * into v_night from public.date_nights
    where id = p_night_id and pair_id = public.my_pair_id() for update;
  if not found then
    raise exception 'night_not_found';
  end if;
  if v_night.proposed_by <> v_uid then
    raise exception 'not_planner';
  end if;
  if p_state not in ('uploading', 'stopped') then
    raise exception 'invalid_state';
  end if;
  if v_night.attach_kind <> 'file' or v_night.upload_state not in ('uploading', 'stopped') then
    return;
  end if;

  update public.date_nights set
    upload_bytes = greatest(upload_bytes, least(coalesce(p_bytes, 0), file_size)),
    upload_state = p_state
  where id = p_night_id
  returning * into v_night;

  if p_state = 'stopped' and (select upload_state from public.date_nights where id = p_night_id) = 'stopped'
     and not exists (select 1 from public.push_outbox
                     where collapse_key = 'dn-stop:' || p_night_id::text and sent_at is null) then
    perform public.enqueue_push(
      v_uid, 'date_night_upload',
      'Your upload paused',
      v_night.title || ' stopped at '
        || least(99, floor(100.0 * v_night.upload_bytes / nullif(v_night.file_size, 0))::int)
        || '%. Open SyncTogether to carry on.',
      jsonb_build_object('route', 'date-night', 'night', v_night.id),
      now() + interval '2 minutes', now() + interval '1 day', 'dn-stop:' || p_night_id::text);
  elsif p_state = 'uploading' then
    perform public.cancel_push('dn-stop:' || p_night_id::text);
  end if;
end $$;
revoke execute on function public.set_date_night_upload_progress(uuid, bigint, text) from public, anon;
grant execute on function public.set_date_night_upload_progress(uuid, bigint, text) to authenticated;

-- Adopt a staged slot as a night's file. Shared by creating a night and by
-- choosing the file again later (after a stopped upload, or from "Change").
create or replace function public.date_night_link_staged(p_night public.date_nights, p_staged_id uuid)
returns public.date_nights
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := p_night.proposed_by;
  v_staged public.staged_media_uploads;
  v_night public.date_nights;
begin
  select * into v_staged from public.staged_media_uploads
    where id = p_staged_id and user_id = v_uid and claimed_room_id is null
      and date_night_id is null and upload_state in ('uploading', 'ready')
      and expires_at > now()
    for update;
  if not found then
    raise exception 'staged_media_invalid';
  end if;
  if exists (select 1 from public.date_nights
             where proposed_by = v_uid and upload_state = 'uploading' and id <> p_night.id) then
    raise exception 'upload_in_progress';
  end if;

  update public.date_nights set
    attach_kind = 'file', youtube_url = null, media_applied_at = null,
    file_name = v_staged.file_name, file_size = v_staged.file_size,
    file_duration_ms = v_staged.duration_ms, media_r2_key = v_staged.r2_key,
    upload_state = v_staged.upload_state,
    upload_bytes = case when v_staged.upload_state = 'ready' then v_staged.file_size else 0 end,
    updated_at = now()
  where id = p_night.id
  returning * into v_night;

  update public.staged_media_uploads set
    date_night_id = v_night.id,
    expires_at = greatest(now() + interval '1 hour', v_night.starts_at + interval '1 day')
  where id = p_staged_id;
  -- The slot is no longer "the" upload in flight, so a lobby pre-upload started
  -- meanwhile does not destroy it (that rule is for the lobby's own slot).
  update public.profiles set active_upload_staged_id = null, active_upload_started_at = null
    where id = v_uid and active_upload_staged_id = p_staged_id;
  return v_night;
end $$;
revoke execute on function public.date_night_link_staged(public.date_nights, uuid) from public, anon, authenticated;

create or replace function public.date_night_attach_staged(p_night_id uuid, p_staged_id uuid)
returns public.date_nights
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_night public.date_nights;
begin
  select * into v_night from public.date_nights
    where id = p_night_id and pair_id = public.my_pair_id() for update;
  if not found then
    raise exception 'night_not_found';
  end if;
  if v_night.proposed_by <> v_uid then
    raise exception 'not_planner';
  end if;
  if v_night.status not in ('proposed', 'accepted')
     or v_night.starts_at + interval '4 hours' < now() then
    raise exception 'night_not_open';
  end if;
  perform public.free_date_night_file(p_night_id);
  select * into v_night from public.date_nights where id = p_night_id;
  v_night := public.date_night_link_staged(v_night, p_staged_id);
  if v_night.status = 'accepted' then
    perform public.schedule_date_night_reminders(v_night);
  end if;
  return v_night;
end $$;
revoke execute on function public.date_night_attach_staged(uuid, uuid) from public, anon;
grant execute on function public.date_night_attach_staged(uuid, uuid) to authenticated;

-- Creating a night can now adopt a staged upload in the same step, so a night
-- with a file exists only once its slot was granted and is valid.
drop function public.create_date_night(text, timestamptz, text);
create or replace function public.create_date_night(
  p_title text, p_starts_at timestamptz, p_youtube_url text default null,
  p_staged_id uuid default null)
returns public.date_nights
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair uuid := public.my_pair_id();
  v_night public.date_nights;
  v_title text := left(trim(coalesce(p_title, '')), 120);
  v_url text := nullif(trim(coalesce(p_youtube_url, '')), '');
begin
  if v_uid is null or v_pair is null then
    raise exception 'not_paired';
  end if;
  if not public.pair_is_patron(v_pair) then
    raise exception 'patron_required';
  end if;
  if v_title = '' then
    raise exception 'invalid_title';
  end if;
  if p_starts_at is null or p_starts_at < now() + interval '5 minutes'
     or p_starts_at > now() + interval '1 year' then
    raise exception 'invalid_time';
  end if;
  if v_url is not null and p_staged_id is not null then
    raise exception 'invalid_attachment';
  end if;
  if v_url is not null and not public.is_youtube_url(v_url) then
    raise exception 'invalid_link';
  end if;

  insert into public.date_nights (pair_id, title, starts_at, proposed_by, attach_kind, youtube_url)
  values (v_pair, v_title, p_starts_at, v_uid,
          case when v_url is null then 'none' else 'youtube' end, v_url)
  returning * into v_night;

  if p_staged_id is not null then
    v_night := public.date_night_link_staged(v_night, p_staged_id);
  end if;

  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_invite',
    public.partner_label(public.partner_of(v_uid), v_uid) || ' proposed a date night',
    v_title || ', ' || public.local_stamp(p_starts_at, public.partner_of(v_uid)),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnp:' || v_night.id::text);
  return v_night;
end $$;
revoke execute on function public.create_date_night(text, timestamptz, text, uuid) from public, anon;
grant execute on function public.create_date_night(text, timestamptz, text, uuid) to authenticated;

do $$
declare
  f text;
begin
  foreach f in array array[
    'date_night_is_on(public.date_nights)', 'date_night_reminder_body(public.date_nights)',
    'apply_date_night_media(public.date_nights, public.rooms)',
    'date_night_notify_ready(public.date_nights)', 'date_night_file_ready(uuid)',
    'free_date_night_file(uuid)', 'sweep_date_night_files()',
    'trig_staged_night_sync()', 'trig_night_deleted_free_file()']
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

CREATE OR REPLACE FUNCTION public.open_our_room()
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_pair uuid;
  v_room public.rooms;
  v_limits public.tier_limits;
  v_av text;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_minutes constant int := 240;
  v_started boolean := false;
  v_night public.date_nights;
begin
  perform public.assert_can_pair(v_uid);

  select pair_id into v_pair from public.pair_members where user_id = v_uid;
  if v_pair is null then
    raise exception 'not_paired';
  end if;

  select * into v_limits from public.tier_limits
    where tier = public.effective_tier(v_uid);

  -- Whichever partner has the better AV level sets it for the room.
  select l.av_level into v_av
  from public.pair_members pm
  join public.tier_limits l on l.tier = public.effective_tier(pm.user_id)
  where pm.pair_id = v_pair
  order by case l.av_level when 'video' then 2 when 'voice' then 1 else 0 end desc
  limit 1;

  select * into v_room from public.rooms where pair_id = v_pair for update;
  if not found then
    loop
      select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
        into v_code from generate_series(1, 6);
      exit when not exists (select 1 from public.rooms where code = v_code);
    end loop;

    insert into public.rooms (
      code, name, created_by, pair_id, duration_minutes, expires_at, persistent,
      dormant_hours, av_level, max_members, media_kind, media_upload_state,
      media_sharing_level)
    values (
      v_code, 'Our Room', v_uid, v_pair, v_minutes,
      now() + make_interval(mins => v_minutes), true,
      0, coalesce(v_av, 'none'), 2, 'none', 'none', v_limits.media_sharing)
    returning * into v_room;
    v_started := true;
  elsif public.room_state(v_room) <> 'live' then
    update public.rooms set
      ended_at = null,
      resumable_until = null,
      duration_minutes = v_minutes,
      expires_at = now() + make_interval(mins => v_minutes),
      av_level = coalesce(v_av, 'none'),
      max_members = 2,
      media_sharing_level = v_limits.media_sharing
    where id = v_room.id
    returning * into v_room;
    v_started := true;
  end if;

  -- A date night that is on: the film its planner attached is already in the
  -- room, so the two of them only press play. Once per night, and never over a
  -- session that is already running with something chosen: it lands when this
  -- opening starts a session, or when the room has nothing in it.
  select n.* into v_night from public.date_nights n
    where n.pair_id = v_pair and public.date_night_is_on(n)
      and n.attach_kind in ('youtube', 'file') and n.media_applied_at is null
      and (n.attach_kind = 'youtube' or n.upload_state = 'ready')
    order by n.starts_at limit 1
    for update;
  if found and (v_started or coalesce(v_room.media_kind, 'none') = 'none') then
    v_room := public.apply_date_night_media(v_night, v_room);
  end if;

  -- Partners are equals here: both are hosts, so either can choose what plays.
  -- Hosts cannot kick one another (kick_member refuses), so neither can remove
  -- the other, and succession on leave still has a host to fall back on.
  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host')
  on conflict (room_id, user_id) do update set role = 'host';

  return v_room;
end $function$;

CREATE OR REPLACE FUNCTION public.minutely_maintenance()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  begin
    perform public.sweep_rooms();
  exception when others then
    raise warning 'minutely_maintenance: sweep_rooms failed: %', sqlerrm;
  end;
  begin
    perform public.invoke_av_cleanup();
  exception when others then
    raise warning 'minutely_maintenance: invoke_av_cleanup failed: %', sqlerrm;
  end;
  begin
    perform public.close_video_trials();
  exception when others then
    raise warning 'minutely_maintenance: close_video_trials failed: %', sqlerrm;
  end;
  begin
    if extract(minute from now()) = 0 then
      perform public.enqueue_reunion_pushes();
    end if;
    -- Due reminders and held rows go out on the next tick.
    if exists (select 1 from public.push_outbox
               where sent_at is null and send_after <= now()
                 and (expires_at is null or expires_at > now()) and attempts < 5) then
      perform public.invoke_push_dispatch();
    end if;
    delete from public.push_outbox where created_at < now() - interval '2 days';
  exception when others then
    raise warning 'minutely_maintenance: push failed: %', sqlerrm;
  end;
  begin
    delete from public.pair_code_lookups where looked_up_at < now() - interval '2 hours';
  exception when others then
    raise warning 'minutely_maintenance: pair_code_lookups cleanup failed: %', sqlerrm;
  end;
  begin
    perform public.sweep_date_night_files();
  exception when others then
    raise warning 'minutely_maintenance: sweep_date_night_files failed: %', sqlerrm;
  end;
end $function$;

CREATE OR REPLACE FUNCTION public.claim_push_batch(p_limit integer DEFAULT 50)
 RETURNS TABLE(id bigint, user_id uuid, kind text, title text, body text, data jsonb, expires_at timestamp with time zone, tokens jsonb)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with due as (
    select o.id
    from public.push_outbox o
    left join public.profiles pr on pr.id = o.user_id
    left join public.push_prefs pp on pp.user_id = o.user_id
    where o.sent_at is null
      and o.send_after <= now()
      and (o.expires_at is null or o.expires_at > now())
      and o.attempts < 5
      and (o.locked_until is null or o.locked_until < now())
      and (
        o.kind = 'call'
        or not coalesce(pp.quiet_hours, true)
        or extract(hour from now() at time zone coalesce(pr.timezone, 'UTC')) between 8 and 22
      )
    order by o.send_after
    limit p_limit
    for update of o skip locked
  ), claimed as (
    update public.push_outbox o
       set attempts = o.attempts + 1, locked_until = now() + interval '2 minutes'
      from due where o.id = due.id
    returning o.*
  )
  select c.id, c.user_id, c.kind, c.title,
         -- A reminder says what is true when it goes out, not when it was queued:
         -- the film may have finished (or failed) uploading in between.
         case when c.kind = 'date_night_reminder'
              then coalesce((select public.date_night_reminder_body(n)
                             from public.date_nights n
                             where n.id = (c.data->>'night')::uuid), c.body)
              else c.body end,
         c.data, c.expires_at,
         coalesce((select jsonb_agg(jsonb_build_object(
                     'platform', t.platform, 'token', t.token, 'environment', t.environment))
                   from public.push_tokens t where t.user_id = c.user_id), '[]'::jsonb)
  from claimed c;
$function$;

CREATE OR REPLACE FUNCTION public.clear_staged_upload(p_staged_id uuid, p_bytes_uploaded bigint DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  v_staged public.staged_media_uploads%rowtype;
  v_new_aborts int;
  v_cooldown timestamptz := null;
begin
  select * into v_staged from public.staged_media_uploads where id = p_staged_id;
  if v_staged.id is null then
    return;
  end if;

  -- Abort penalty tracking
  -- A finished upload that simply outlived its date night was not abandoned, so
  -- it does not count against the person (nothing else about the sweep changes).
  select coalesce(r2_consecutive_aborts, 0)
         + case when v_staged.date_night_id is not null and v_staged.upload_state = 'ready'
                then 0 else 1 end
    into v_new_aborts
  from public.profiles where id = v_staged.user_id;

  if v_new_aborts >= 5 then
    v_cooldown := now() + interval '30 minutes';
  end if;

  update public.profiles set
    r2_upload_bytes_7d = r2_upload_bytes_7d + p_bytes_uploaded,
    r2_consecutive_aborts = v_new_aborts,
    r2_cooldown_until = coalesce(v_cooldown, r2_cooldown_until),
    active_upload_staged_id = null,
    active_upload_started_at = null
  where id = v_staged.user_id;

  -- Deleting row fires on_staged_media_deleted_cleanup trigger to enqueue to pending_r2_deletions
  delete from public.staged_media_uploads where id = p_staged_id;
end $function$;

CREATE OR REPLACE FUNCTION public.cancel_date_night(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_night public.date_nights;
begin
  select * into v_night from public.date_nights
    where id = p_id and pair_id = public.my_pair_id() for update;
  if not found or v_night.status = 'cancelled' then
    return;
  end if;
  update public.date_nights set status = 'cancelled', updated_at = now() where id = p_id;
  -- The file is only for that night: free it now rather than a day later.
  perform public.free_date_night_file(p_id);
  perform public.cancel_push('dn:' || p_id::text);
  perform public.cancel_push('dnp:' || p_id::text);
  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_response',
    public.partner_label(public.partner_of(v_uid), v_uid) || ' cancelled ' || v_night.title,
    'Plan another when you are both free.',
    jsonb_build_object('route', 'date-night'),
    now(), now() + interval '2 days', 'dnr:' || p_id::text);
end $function$;

CREATE OR REPLACE FUNCTION public.set_date_night_attachment(p_id uuid, p_youtube_url text)
 RETURNS date_nights
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_night public.date_nights;
  v_url text := nullif(trim(coalesce(p_youtube_url, '')), '');
begin
  select * into v_night from public.date_nights
    where id = p_id and pair_id = public.my_pair_id() for update;
  if not found then
    raise exception 'night_not_found';
  end if;
  if v_night.proposed_by <> v_uid then
    raise exception 'not_planner';
  end if;
  if v_night.status not in ('proposed', 'accepted')
     or v_night.starts_at + interval '4 hours' < now() then
    raise exception 'night_not_open';
  end if;
  if v_url is not null and not public.is_youtube_url(v_url) then
    raise exception 'invalid_link';
  end if;

  -- Swapping a file for a link (or for nothing) lets the file go.
  perform public.free_date_night_file(p_id);

  update public.date_nights set
    attach_kind = case when v_url is null then 'none' else 'youtube' end,
    youtube_url = v_url,
    media_applied_at = null,
    updated_at = now()
  where id = p_id returning * into v_night;

  if v_night.status = 'accepted' then
    perform public.schedule_date_night_reminders(v_night);
  end if;
  return v_night;
end $function$;

CREATE OR REPLACE FUNCTION public.schedule_date_night_reminders(p_night date_nights)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_member uuid;
begin
  for v_member in select user_id from public.pair_members where pair_id = p_night.pair_id loop
    perform public.enqueue_push(
      v_member, 'date_night_reminder',
      'Date night in 15 minutes',
      public.date_night_reminder_body(p_night),
      jsonb_build_object('route', 'our-room', 'night', p_night.id),
      greatest(p_night.starts_at - interval '15 minutes', now()),
      p_night.starts_at + interval '30 minutes',
      'dn:' || p_night.id::text);
  end loop;
  -- Said now if the film is already waiting: the answer is what makes it theirs.
  perform public.date_night_notify_ready(p_night);
end $function$;
