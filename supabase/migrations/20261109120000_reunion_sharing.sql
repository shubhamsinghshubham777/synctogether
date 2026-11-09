-- The reunion date gets the two switches the design promises:
--
--  * "Either of us can edit" is now a real permission. Until now either partner could
--    always change the date; now whoever set it can lock it to themselves
--    (pairs.reunion_shared_edit = false) and the other person's change is refused with
--    'reunion_locked'. It starts shared, as before. Only the person who set the date can
--    flip the switch, and clearing the date hands it back to both.
--  * "Show on the lobby" is per person (pair_members.show_reunion): one of you can hide
--    the countdown on their own lobby without touching the other's.

alter table public.pairs
  add column if not exists reunion_shared_edit boolean not null default true,
  add column if not exists reunion_set_by uuid references public.profiles (id) on delete set null;

alter table public.pair_members
  add column if not exists show_reunion boolean not null default true;

comment on column public.pairs.reunion_shared_edit is
  'When false, only reunion_set_by may change or clear the reunion date.';
comment on column public.pairs.reunion_set_by is
  'Who last set the reunion date. NULL when none is set.';

drop function if exists public.set_reunion(date, text);

create or replace function public.set_reunion(
  p_on date,
  p_label text,
  p_shared_edit boolean default null,
  p_show boolean default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair public.pairs;
begin
  select p.* into v_pair from public.pairs p
    join public.pair_members m on m.pair_id = p.id and m.user_id = v_uid
    for update of p;
  if not found then
    raise exception 'not_paired';
  end if;

  -- My own lobby preference is mine to change whatever the date's permission is.
  if p_show is not null then
    update public.pair_members set show_reunion = p_show where user_id = v_uid;
  end if;

  -- Nothing about the date itself is being changed: only the lobby switch moved.
  if p_on is not distinct from v_pair.reunion_on
     and nullif(left(trim(coalesce(p_label, '')), 60), '') is not distinct from v_pair.reunion_label
     and p_shared_edit is null then
    return;
  end if;

  if v_pair.reunion_set_by is not null
     and v_pair.reunion_set_by <> v_uid
     and not v_pair.reunion_shared_edit then
    raise exception 'reunion_locked';
  end if;

  if p_on is null then
    -- Clearing hands the date back to both of you.
    update public.pairs set
      reunion_on = null, reunion_label = null, reunion_set_by = null, reunion_shared_edit = true
    where id = v_pair.id;
    return;
  end if;

  update public.pairs set
    reunion_on = p_on,
    reunion_label = nullif(left(trim(coalesce(p_label, '')), 60), ''),
    reunion_set_by = v_uid,
    -- Only the person who set it may change who can edit it.
    reunion_shared_edit = case
      when p_shared_edit is not null then p_shared_edit
      else reunion_shared_edit end
  where id = v_pair.id;
end $$;

-- (Body is the live definition from the partner-nickname migration, plus the reunion fields.)
create or replace function public.my_pair()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair public.pairs;
  v_partner public.profiles;
  v_me public.profiles;
  v_room public.rooms;
  v_show boolean;
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
  select show_reunion into v_show from public.pair_members where user_id = v_uid;

  return jsonb_build_object(
    'pair_id', v_pair.id,
    'since', v_pair.created_at,
    'reunion_on', v_pair.reunion_on,
    'reunion_label', v_pair.reunion_label,
    'reunion_shared_edit', v_pair.reunion_shared_edit,
    'reunion_set_by', v_pair.reunion_set_by,
    'show_reunion', coalesce(v_show, true),
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
end $$;

revoke execute on function public.set_reunion(date, text, boolean, boolean) from public, anon;
grant execute on function public.set_reunion(date, text, boolean, boolean) to authenticated;
revoke execute on function public.my_pair() from public, anon;
grant execute on function public.my_pair() to authenticated;
