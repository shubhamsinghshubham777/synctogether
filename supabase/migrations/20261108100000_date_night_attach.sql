-- Date nights carry what you will watch. A night is a night with the film already
-- waiting: its planner may attach a YouTube link (a file uploaded ahead comes
-- later), and when the night starts Our Room opens with it loaded, so the two of
-- them only press play. Attaching is optional; "none" is exactly the old flow.
alter table public.date_nights
  add column attach_kind text not null default 'none'
    check (attach_kind in ('none', 'youtube', 'file')),
  add column youtube_url text check (youtube_url is null or char_length(youtube_url) <= 300),
  add column media_applied_at timestamptz,
  add constraint date_nights_attach_shape_chk check (
    (attach_kind = 'youtube') = (youtube_url is not null));

-- Domain check only. The app validates the link properly; the server just keeps
-- a date night from carrying an arbitrary address into a room.
create or replace function public.is_youtube_url(p_url text)
returns boolean
language sql immutable set search_path = ''
as $$
  select p_url ~* '^https?://([a-z0-9-]+\.)*(youtube\.com|youtube-nocookie\.com|youtu\.be)(/|$)'
     and char_length(p_url) <= 300;
$$;
revoke execute on function public.is_youtube_url(text) from public, anon, authenticated;

drop function public.create_date_night(text, timestamptz);
create or replace function public.create_date_night(
  p_title text, p_starts_at timestamptz, p_youtube_url text default null)
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
  if v_url is not null and not public.is_youtube_url(v_url) then
    raise exception 'invalid_link';
  end if;

  insert into public.date_nights (pair_id, title, starts_at, proposed_by, attach_kind, youtube_url)
  values (v_pair, v_title, p_starts_at, v_uid,
          case when v_url is null then 'none' else 'youtube' end, v_url)
  returning * into v_night;

  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_invite',
    public.partner_label(public.partner_of(v_uid), v_uid) || ' proposed a date night',
    v_title || ', ' || public.local_stamp(p_starts_at, public.partner_of(v_uid)),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnp:' || v_night.id::text);
  return v_night;
end $$;

revoke execute on function public.create_date_night(text, timestamptz, text) from public, anon;
grant execute on function public.create_date_night(text, timestamptz, text) to authenticated;

-- "Change what we're watching": the planner swaps or removes the attachment. The
-- reminder is rebuilt so its words match, and the film is put back to "not yet
-- loaded" so the new one is what the night starts with.
create or replace function public.set_date_night_attachment(p_id uuid, p_youtube_url text)
returns public.date_nights
language plpgsql security definer set search_path = ''
as $$
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
end $$;
revoke execute on function public.set_date_night_attachment(uuid, text) from public, anon;
grant execute on function public.set_date_night_attachment(uuid, text) to authenticated;

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
  select * into v_night from public.date_nights
    where pair_id = v_pair and status = 'accepted'
      and attach_kind = 'youtube' and youtube_url is not null
      and media_applied_at is null
      and starts_at - interval '15 minutes' <= now()
      and starts_at + interval '4 hours' >= now()
    order by starts_at limit 1
    for update;
  if found and (v_started or coalesce(v_room.media_kind, 'none') = 'none') then
    update public.rooms set
      media_kind = 'youtube',
      media_url = v_night.youtube_url,
      media_name = left(v_night.title, 255),
      media_duration_ms = null,
      media_updated_at = now(),
      media_position_ms = 0,
      media_position_at = now()
    where id = v_room.id
    returning * into v_room;
    update public.date_nights set media_applied_at = now() where id = v_night.id;
  end if;

  -- Partners are equals here: both are hosts, so either can choose what plays.
  -- Hosts cannot kick one another (kick_member refuses), so neither can remove
  -- the other, and succession on leave still has a host to fall back on.
  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host')
  on conflict (room_id, user_id) do update set role = 'host';

  return v_room;
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
      case when p_night.attach_kind = 'youtube' and p_night.youtube_url is not null
           then p_night.title || ' is ready. Open Our Room and press play.'
           else 'Pick something together in Our Room.' end,
      jsonb_build_object('route', 'our-room', 'night', p_night.id),
      greatest(p_night.starts_at - interval '15 minutes', now()),
      p_night.starts_at + interval '30 minutes',
      'dn:' || p_night.id::text);
  end loop;
end $function$;
