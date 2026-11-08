-- Our Room keeps a finished shared film for a while after its session ends.
--
-- Until now `retire_room` queued the room's R2 object for deletion the moment a
-- session ended. For a couple watching one film over several evenings that meant a
-- re-upload every night, and for a free account a second upload of a 2 GB film was
-- refused by the 2.5 GB weekly allowance - "continue tomorrow" did not work.
--
-- A pair room now holds its *finished* shared copy until `media_expires_at`, set when
-- the session ends to now() plus a retention that follows the better of the two
-- partners' tiers (one Patron seat covers both): 36 hours free, 7 days with Patron
-- (`app_settings.our_room_media`, tunable without a release). Restarting Our Room
-- before then takes the clock off the file, so nothing re-uploads and the weekly
-- allowance is not charged twice. `sweep_rooms` releases the file once the time is
-- up and stamps `media_share_expired_at` so the app can say so instead of leaving
-- two people staring at a film nobody can stream.
--
-- Everything else is unchanged: replacing the media, stopping sharing, unpairing and
-- deleting an account still delete at once, and an unfinished multipart upload is
-- still aborted when the session ends (a half-uploaded part is not reusable).

alter table public.rooms
  add column if not exists media_expires_at timestamptz,
  add column if not exists media_share_expired_at timestamptz;

comment on column public.rooms.media_expires_at is
  'Our Room only: when the retained shared film is released. NULL while a session is live.';
comment on column public.rooms.media_share_expired_at is
  'Our Room only: set when the retained film was released, cleared when the room''s media or sharing state changes.';

insert into public.app_settings (key, value)
values ('our_room_media', '{"free_hours": 36, "patron_hours": 168}'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- How long a pair's shared film outlives its session.
-- ---------------------------------------------------------------------------
create or replace function public.our_room_media_retention(p_pair_id uuid)
returns interval
language sql
stable
security definer
set search_path = ''
as $$
  select make_interval(hours => coalesce(
    (select case when public.pair_is_patron(p_pair_id)
                 then (s.value ->> 'patron_hours')::int
                 else (s.value ->> 'free_hours')::int end
       from public.app_settings s where s.key = 'our_room_media'),
    case when public.pair_is_patron(p_pair_id) then 168 else 36 end));
$$;

revoke execute on function public.our_room_media_retention(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- retire_room: a pair room keeps its finished film for the retention window.
-- (Body is the live definition; only the R2 block changed.)
-- ---------------------------------------------------------------------------
create or replace function public.retire_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room public.rooms;
begin
  update public.rooms r set
    ended_at = coalesce(r.ended_at, now()),
    resumable_until = case
      when r.persistent then null
      when r.dormant_hours > 0
        then greatest(r.expires_at, now()) + make_interval(hours => r.dormant_hours)
      else null
    end
  where r.id = p_room_id
  returning * into v_room;

  if v_room.id is null then
    return;
  end if;

  if v_room.media_r2_key is not null or v_room.media_upload_id is not null then
    if v_room.pair_id is not null
       and v_room.media_r2_key is not null
       and v_room.media_upload_id is null then
      -- Our Room: a finished film outlives the session for a while. coalesce so a
      -- second call for an already-ended room does not push the deadline out.
      update public.rooms r set
        media_expires_at = coalesce(
          r.media_expires_at, now() + public.our_room_media_retention(v_room.pair_id))
      where r.id = p_room_id;
    else
      -- Active R2 objects of ordinary rooms, and unfinished multipart uploads of any room.
      insert into public.pending_r2_deletions (r2_key, upload_id)
      values (v_room.media_r2_key, v_room.media_upload_id);

      update public.rooms set
        media_r2_key = null,
        media_upload_id = null,
        media_file_size = null,
        media_upload_state = 'none',
        media_expires_at = null
      where id = p_room_id;
    end if;
  end if;

  -- Clear upload locks
  update public.profiles set
    active_upload_room_id = null,
    active_upload_started_at = null
  where active_upload_room_id = p_room_id;

  -- Our Room keeps its chat between sessions; the sweep prunes it by age.
  if v_room.pair_id is null then
    delete from public.messages where room_id = p_room_id;
  end if;

  if not v_room.persistent and v_room.resumable_until is null then
    delete from public.rooms where id = p_room_id;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- sweep_rooms: release a retained film once its time is up.
-- (Body is the live definition plus the new step.)
-- ---------------------------------------------------------------------------
create or replace function public.sweep_rooms()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_key text;
  v_idle jsonb;
begin
  for v_id in
    select id from public.rooms where ended_at is null and expires_at <= now()
  loop
    perform public.retire_room(v_id);
  end loop;

  -- Our Room: a film kept past its session is released when its time is up. A room
  -- that has been restarted has no deadline (the trigger below took it off), so a
  -- film is never released from under a live session.
  for v_id, v_key in
    select id, media_r2_key from public.rooms
    where pair_id is not null
      and ended_at is not null
      and media_expires_at is not null
      and media_expires_at <= now()
      and media_r2_key is not null
    for update skip locked
  loop
    insert into public.pending_r2_deletions (r2_key, upload_id) values (v_key, null);
    update public.rooms set
      media_r2_key = null,
      media_upload_id = null,
      media_file_size = null,
      media_upload_state = 'none',
      media_expires_at = null,
      media_share_expired_at = now()
    where id = v_id;
  end loop;

  update public.rooms r set
    persistent = false,
    resumable_until = now() + interval '7 days'
  where r.persistent
    and r.pair_id is null
    and r.ended_at is not null
    and public.effective_tier(r.created_by) <> 'premium';

  delete from public.rooms r
  where r.ended_at is not null
    and not r.persistent
    and (r.resumable_until is null or r.resumable_until <= now());

  select value into v_idle from public.app_settings where key = 'idle_rooms';
  if coalesce((v_idle ->> 'enabled')::boolean, true) then
    delete from public.rooms r
    where r.persistent
      and r.pair_id is null
      and r.ended_at is not null
      and r.ended_at < now() - make_interval(days => coalesce((v_idle ->> 'ttl_days')::int, 90))
      and public.room_state(r) = 'idle';
  end if;

  -- Our Room chat is kept between sessions, but not forever.
  delete from public.messages m
  using public.rooms r
  where m.room_id = r.id
    and r.pair_id is not null
    and m.created_at < now() - interval '90 days';
end $$;

-- ---------------------------------------------------------------------------
-- The clock and the notice follow what the room is doing.
-- ---------------------------------------------------------------------------
create or replace function public.trig_rooms_media_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Restarting a resting Our Room takes the retention clock off the file: it is
  -- in use again, and nothing needs to be uploaded.
  if new.pair_id is not null and old.ended_at is not null and new.ended_at is null then
    new.media_expires_at := null;
  end if;
  -- No object, nothing to expire.
  if new.media_r2_key is null then
    new.media_expires_at := null;
  end if;
  -- The "your shared copy was removed" notice describes the media the room had then;
  -- any change to the media or its sharing state retires it (unless this very update
  -- is what set it).
  if new.media_share_expired_at is not distinct from old.media_share_expired_at
     and (new.media_upload_state is distinct from old.media_upload_state
          or new.media_name is distinct from old.media_name
          or new.media_kind is distinct from old.media_kind) then
    new.media_share_expired_at := null;
  end if;
  return new;
end $$;

drop trigger if exists rooms_media_lifecycle on public.rooms;
create trigger rooms_media_lifecycle
  before update on public.rooms
  for each row execute function public.trig_rooms_media_lifecycle();
