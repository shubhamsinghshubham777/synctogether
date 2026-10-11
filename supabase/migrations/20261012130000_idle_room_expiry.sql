-- Migration: saved (idle) rooms expire after a stretch of disuse.
--
-- An idle persistent room holds one of a Premium user's persistent_room_cap
-- slots until they delete it by hand, so forgotten rooms eventually block
-- create_room with room_limit_reached. sweep_rooms now deletes a saved room that
-- has been idle (no session) for ttl_days. `ended_at` is the moment it went
-- idle: retire_room stamps it and resume_room clears it, so a room that is
-- started again gets a fresh clock.
--
-- Config, not a constant: update public.app_settings where key = 'idle_rooms'.
-- The fallbacks below must equal this seed (see docs/feature-toggles.md).

insert into public.app_settings (key, value)
values ('idle_rooms', '{"enabled": true, "ttl_days": 90}'::jsonb)
on conflict (key) do nothing;

create or replace function public.sweep_rooms()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_idle jsonb;
begin
  for v_id in
    select id from public.rooms where ended_at is null and expires_at <= now()
  loop
    perform public.retire_room(v_id);
  end loop;

  -- Drop persistence for users who lapsed from premium
  update public.rooms r set
    persistent = false,
    resumable_until = now() + interval '7 days'
  where r.persistent
    and r.ended_at is not null
    and public.effective_tier(r.created_by) <> 'premium';

  delete from public.rooms r
  where r.ended_at is not null
    and not r.persistent
    and (r.resumable_until is null or r.resumable_until <= now());

  -- Saved rooms nobody has started in a long while. Nobody can be inside one
  -- (an idle room has no session), so there is nobody to announce to.
  select value into v_idle from public.app_settings where key = 'idle_rooms';
  if coalesce((v_idle ->> 'enabled')::boolean, true) then
    delete from public.rooms r
    where r.persistent
      and r.ended_at is not null
      and r.ended_at < now() - make_interval(days => coalesce((v_idle ->> 'ttl_days')::int, 90))
      and public.room_state(r) = 'idle';
  end if;
end $$;
