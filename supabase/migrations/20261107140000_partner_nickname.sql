-- A private nickname for your person. Couples have pet names, and an account whose
-- provider shared no name (Sign in with Apple's hidden address) is otherwise
-- stuck as a random handle until its owner renames it.
--
-- It is the viewer's own label and nobody else's: a separate table with no
-- client grants and no policy, read only through my_pair() (the viewer's own
-- row) and partner_label(), so the person it names can neither select it nor
-- be sent it over realtime. It lives and dies with the pair.
create table public.pair_nicknames (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  pair_id uuid not null references public.pairs (id) on delete cascade,
  nickname text not null check (char_length(nickname) between 1 and 40)
);
alter table public.pair_nicknames enable row level security;
revoke all on public.pair_nicknames from public, anon, authenticated;

-- What [p_viewer] calls [p_other]: their nickname for their current partner, else
-- the real display name. Used where the server writes a person's name into
-- somebody else's notification, so "Mayu is calling" says what Sam calls Maya.
create or replace function public.partner_label(p_viewer uuid, p_other uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select n.nickname from public.pair_nicknames n
      where n.user_id = p_viewer
        and n.pair_id = (select m.pair_id from public.pair_members m where m.user_id = p_viewer)
        and public.partner_of(p_viewer) = p_other),
    public.display_name_of(p_other));
$$;
revoke execute on function public.partner_label(uuid, uuid) from public, anon, authenticated;

create or replace function public.set_partner_nickname(p_nickname text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair uuid;
  v_name text := nullif(trim(coalesce(p_nickname, '')), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  select pair_id into v_pair from public.pair_members where user_id = v_uid;
  if v_pair is null then
    raise exception 'not_paired';
  end if;
  if v_name is null then
    delete from public.pair_nicknames where user_id = v_uid;
  elsif char_length(v_name) > 40 then
    raise exception 'invalid_nickname';
  else
    insert into public.pair_nicknames (user_id, pair_id, nickname)
    values (v_uid, v_pair, v_name)
    on conflict (user_id) do update set pair_id = excluded.pair_id, nickname = excluded.nickname;
  end if;
end $$;
revoke execute on function public.set_partner_nickname(text) from public, anon;
grant execute on function public.set_partner_nickname(text) to authenticated;

CREATE OR REPLACE FUNCTION public.my_pair()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_pair public.pairs;
  v_partner public.profiles;
  v_me public.profiles;
  v_room public.rooms;
begin
  if v_uid is null then
    return null;
  end if;

  select p.* into v_pair from public.pairs p
    join public.pair_members m on m.pair_id = p.id and m.user_id = v_uid;
  if not found then
    return null;
  end if;

  select pr.* into v_partner from public.profiles pr
    join public.pair_members m on m.user_id = pr.id
    where m.pair_id = v_pair.id and m.user_id <> v_uid;
  select * into v_me from public.profiles where id = v_uid;
  select * into v_room from public.rooms where pair_id = v_pair.id;

  return jsonb_build_object(
    'pair_id', v_pair.id,
    'since', v_pair.created_at,
    'reunion_on', v_pair.reunion_on,
    'reunion_label', v_pair.reunion_label,
    'patron', public.pair_is_patron(v_pair.id),
    'my_timezone', v_me.timezone,
    'room_id', v_room.id,
    'room_code', v_room.code,
    'partner', jsonb_build_object(
      'id', v_partner.id,
      'display_name', v_partner.display_name,
      -- What *I* call them. Theirs of me never leaves their own row.
      'nickname', (select n.nickname from public.pair_nicknames n
                   where n.user_id = v_uid and n.pair_id = v_pair.id),
      'avatar_url', v_partner.avatar_url,
      'timezone', v_partner.timezone));
end $function$;

CREATE OR REPLACE FUNCTION public.call_partner()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_pair uuid := public.my_pair_id();
  v_partner uuid;
begin
  if v_uid is null or v_pair is null then
    raise exception 'not_paired';
  end if;
  v_partner := public.partner_of(v_uid);

  -- One ring a minute: a held-down button must not become a barrage.
  if exists (select 1 from public.push_outbox
             where user_id = v_partner and kind = 'call'
               and created_at > now() - interval '1 minute') then
    return jsonb_build_object('sent', false, 'reason', 'throttled');
  end if;

  perform public.enqueue_push(
    v_partner, 'call',
    public.partner_label(v_partner, v_uid) || ' is calling',
    'Our Room is open. Tap to join.',
    jsonb_build_object('route', 'our-room', 'urgent', true),
    now(), now() + interval '90 seconds', null);
  return jsonb_build_object('sent', true);
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
  perform public.cancel_push('dn:' || p_id::text);
  perform public.cancel_push('dnp:' || p_id::text);
  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_response',
    public.partner_label(public.partner_of(v_uid), v_uid) || ' cancelled ' || v_night.title,
    'Plan another when you are both free.',
    jsonb_build_object('route', 'date-night'),
    now(), now() + interval '2 days', 'dnr:' || p_id::text);
end $function$;

CREATE OR REPLACE FUNCTION public.create_date_night(p_title text, p_starts_at timestamp with time zone)
 RETURNS date_nights
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_pair uuid := public.my_pair_id();
  v_night public.date_nights;
  v_title text := left(trim(coalesce(p_title, '')), 120);
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

  insert into public.date_nights (pair_id, title, starts_at, proposed_by)
  values (v_pair, v_title, p_starts_at, v_uid)
  returning * into v_night;

  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_invite',
    public.partner_label(public.partner_of(v_uid), v_uid) || ' proposed a date night',
    v_title || ', ' || public.local_stamp(p_starts_at, public.partner_of(v_uid)),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnp:' || v_night.id::text);
  return v_night;
end $function$;

CREATE OR REPLACE FUNCTION public.reschedule_date_night(p_id uuid, p_starts_at timestamp with time zone)
 RETURNS date_nights
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
  if not found then
    raise exception 'night_not_found';
  end if;
  if v_night.status = 'cancelled' then
    raise exception 'night_not_open';
  end if;
  if p_starts_at is null or p_starts_at < now() + interval '5 minutes'
     or p_starts_at > now() + interval '1 year' then
    raise exception 'invalid_time';
  end if;

  update public.date_nights set
    starts_at = p_starts_at, proposed_by = v_uid, status = 'proposed', updated_at = now()
  where id = p_id returning * into v_night;

  perform public.cancel_push('dn:' || p_id::text);
  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_invite',
    public.partner_label(public.partner_of(v_uid), v_uid) || ' suggested another time',
    v_night.title || ', ' || public.local_stamp(p_starts_at, public.partner_of(v_uid)),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnp:' || p_id::text);
  return v_night;
end $function$;

CREATE OR REPLACE FUNCTION public.respond_date_night(p_id uuid, p_accept boolean)
 RETURNS date_nights
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
  if not found then
    raise exception 'night_not_found';
  end if;
  if v_night.proposed_by = v_uid then
    raise exception 'own_proposal';
  end if;
  if v_night.status <> 'proposed' then
    raise exception 'night_not_open';
  end if;

  update public.date_nights set
    status = case when p_accept then 'accepted' else 'declined' end,
    updated_at = now()
  where id = p_id returning * into v_night;

  perform public.cancel_push('dnp:' || p_id::text);
  if p_accept then
    perform public.schedule_date_night_reminders(v_night);
  end if;
  perform public.enqueue_push(
    v_night.proposed_by, 'date_night_response',
    case when p_accept then public.partner_label(v_night.proposed_by, v_uid) || ' is in'
         else public.partner_label(v_night.proposed_by, v_uid) || ' cannot make it' end,
    v_night.title || ', ' || public.local_stamp(v_night.starts_at, v_night.proposed_by),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnr:' || p_id::text);
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
      p_night.title || ' with ' || public.partner_label(v_member, public.partner_of(v_member))
        || ', ' || to_char(p_night.starts_at at time zone
            coalesce((select timezone from public.profiles where id = v_member), 'UTC'), 'FMHH12:MI AM')
        || ' your time',
      jsonb_build_object('route', 'our-room', 'night', p_night.id),
      greatest(p_night.starts_at - interval '15 minutes', now()),
      p_night.starts_at + interval '30 minutes',
      'dn:' || p_night.id::text);
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.enqueue_reunion_pushes()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  v_days int;
  v_local timestamp;
begin
  for r in
    select m.user_id, p.id as pair_id, p.reunion_on, p.reunion_label,
           coalesce(pr.timezone, 'UTC') as tz
    from public.pairs p
    join public.pair_members m on m.pair_id = p.id
    join public.profiles pr on pr.id = m.user_id
    where p.reunion_on is not null and p.reunion_on >= current_date - 1
  loop
    v_local := now() at time zone r.tz;
    continue when extract(hour from v_local) <> 9;
    v_days := r.reunion_on - v_local::date;
    continue when v_days < 0;
    if v_days = 1 then
      perform public.enqueue_push(
        r.user_id, 'reunion', 'Tomorrow',
        coalesce(r.reunion_label, 'You and ' || coalesce(public.partner_label(r.user_id, public.partner_of(r.user_id)), 'your person') || ' are in the same room.'),
        jsonb_build_object('route', 'lobby'), now(), now() + interval '12 hours',
        'reunion:' || r.pair_id::text || ':' || r.user_id::text);
    elsif v_days = 0 then
      perform public.enqueue_push(
        r.user_id, 'reunion', 'Today',
        'Enjoy every minute of it.',
        jsonb_build_object('route', 'lobby'), now(), now() + interval '12 hours',
        'reunion:' || r.pair_id::text || ':' || r.user_id::text);
    elsif extract(dow from v_local) = 0 then
      perform public.enqueue_push(
        r.user_id, 'reunion', v_days || ' days to go',
        'Until you and ' || coalesce(public.partner_label(r.user_id, public.partner_of(r.user_id)), 'your person') || ' are in the same room.',
        jsonb_build_object('route', 'lobby'), now(), now() + interval '12 hours',
        'reunion:' || r.pair_id::text || ':' || r.user_id::text);
    end if;
  end loop;
end $function$;
