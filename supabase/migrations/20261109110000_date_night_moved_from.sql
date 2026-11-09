-- A night that was moved remembers where it was, so the person who has to answer the new
-- time can see "Mon 9 Nov becomes Wed 11 Nov" instead of a time that changed under them.
--
-- Set by reschedule_date_night to the time it moved from; cleared once the new time is
-- answered (accepted). A decline keeps it, since the card still describes that move.

alter table public.date_nights add column if not exists moved_from timestamptz;

comment on column public.date_nights.moved_from is
  'The start time this night was moved away from, while the new time is waiting for an answer.';

create or replace function public.reschedule_date_night(p_id uuid, p_starts_at timestamptz)
returns public.date_nights
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_night public.date_nights;
  v_old timestamptz;
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

  v_old := v_night.starts_at;
  update public.date_nights set
    starts_at = p_starts_at, proposed_by = v_uid, status = 'proposed', updated_at = now(),
    -- Moving it again before it is answered keeps the original time, not the interim one.
    moved_from = case
      when p_starts_at = v_old then moved_from
      when moved_from is not null and v_night.status = 'proposed' then moved_from
      else v_old end
  where id = p_id returning * into v_night;

  perform public.cancel_push('dn:' || p_id::text);
  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_invite',
    public.display_name_of(v_uid) || ' suggested another time',
    v_night.title || ', ' || public.local_stamp(p_starts_at, public.partner_of(v_uid)),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnp:' || p_id::text);
  return v_night;
end $$;

create or replace function public.trig_date_nights_moved_from()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    new.moved_from := null;
  end if;
  return new;
end $$;

drop trigger if exists date_nights_moved_from on public.date_nights;
create trigger date_nights_moved_from
  before update on public.date_nights
  for each row execute function public.trig_date_nights_moved_from();
