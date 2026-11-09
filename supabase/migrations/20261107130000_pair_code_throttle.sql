-- A pair code is a bearer credential: whoever holds a pending one can accept it,
-- and accepting pairs you at once. Six characters from a 32-letter alphabet is a
-- large space, but nothing stopped a signed-in script from walking it, and one
-- hit is a stranger forced into somebody's Our Room (their pushes, their calls).
-- So every look-up and every accept spends from a small hourly budget per
-- account. A real person uses two or three.
--
-- A miss has to *return*, not raise: an exception rolls the whole call back,
-- including the row that counts it, so a script guessing blind would never be
-- counted. Hits that raise (used, expired, ...) reveal only that a dead code
-- exists, and cannot pair anyone.
create table public.pair_code_lookups (
  user_id uuid not null references public.profiles (id) on delete cascade,
  looked_up_at timestamptz not null default now()
);
create index pair_code_lookups_user_idx on public.pair_code_lookups (user_id, looked_up_at desc);
alter table public.pair_code_lookups enable row level security;
revoke all on public.pair_code_lookups from public, anon, authenticated;

create or replace function public.pair_code_throttle()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return;
  end if;
  if (select count(*) from public.pair_code_lookups
      where user_id = v_uid and looked_up_at > now() - interval '1 hour') >= 30 then
    raise exception 'too_many_attempts';
  end if;
  insert into public.pair_code_lookups (user_id) values (v_uid);
end $$;

revoke execute on function public.pair_code_throttle() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_pair_invite(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_inv public.pair_invites;
  v_status text;
  v_inviter public.profiles;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  perform public.pair_code_throttle();

  select * into v_inv from public.pair_invites where code = upper(trim(p_code));
  if not found then
    -- Returned, not raised: a raise rolls back the look-up that was just
    -- counted, and a miss is precisely what a guesser produces.
    return jsonb_build_object('status', 'not_found');
  end if;

  v_status := case
    when v_inv.status = 'pending' and v_inv.expires_at <= now() then 'expired'
    else v_inv.status
  end;

  if v_status = 'pending'
     and v_inv.inviter_id <> v_uid
     and public.effective_tier(v_uid) <> 'guest'
     and v_inv.seen_by is distinct from v_uid then
    update public.pair_invites set seen_by = v_uid where id = v_inv.id;
  end if;

  select * into v_inviter from public.profiles where id = v_inv.inviter_id;
  return jsonb_build_object(
    'code', v_inv.code,
    'status', v_status,
    'is_mine', v_inv.inviter_id = v_uid,
    -- Someone who has since paired cannot be paired with, whatever the invite
    -- itself says: the accept screen reads this to say so up front.
    'inviter_paired', exists (select 1 from public.pair_members where user_id = v_inv.inviter_id),
    'created_at', v_inv.created_at,
    'expires_at', v_inv.expires_at,
    'inviter', jsonb_build_object(
      'id', v_inviter.id,
      'display_name', v_inviter.display_name,
      'avatar_url', v_inviter.avatar_url));
end $function$;

CREATE OR REPLACE FUNCTION public.accept_pair_invite(p_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_inv public.pair_invites;
  v_pair uuid;
begin
  perform public.pair_code_throttle();
  perform public.assert_can_pair(v_uid);

  select * into v_inv from public.pair_invites
    where code = upper(trim(p_code)) for update;
  if not found then
    -- Null, not an exception, for the same reason as get_pair_invite: the
    -- attempt has to survive to be counted. The client reads null as "not found".
    return null;
  end if;
  if v_inv.status = 'accepted' then
    raise exception 'invite_used';
  end if;
  if v_inv.inviter_id = v_uid then
    raise exception 'cannot_pair_self';
  end if;
  if exists (select 1 from public.pair_members where user_id = v_uid) then
    raise exception 'already_paired';
  end if;
  -- Before cancelled/expired: when somebody pairs, their other pending invites
  -- are cancelled (below), and "they paired with someone else" is the true and
  -- kinder answer for anyone still holding one.
  if exists (select 1 from public.pair_members where user_id = v_inv.inviter_id) then
    raise exception 'partner_already_paired';
  end if;
  if v_inv.status = 'cancelled' then
    raise exception 'invite_cancelled';
  end if;
  if v_inv.expires_at <= now() then
    raise exception 'invite_expired';
  end if;

  insert into public.pairs default values returning id into v_pair;
  insert into public.pair_members (user_id, pair_id)
    values (v_inv.inviter_id, v_pair), (v_uid, v_pair);
  update public.pair_invites set status = 'accepted', pair_id = v_pair where id = v_inv.id;

  -- Two people who have paired have no use for any other open invite of theirs.
  update public.pair_invites set status = 'cancelled'
    where status = 'pending' and id <> v_inv.id
      and inviter_id in (v_inv.inviter_id, v_uid);

  perform public.enqueue_push(
    v_inv.inviter_id, 'pair_accepted',
    public.display_name_of(v_uid) || ' paired with you',
    'Your private room is ready.',
    jsonb_build_object('route', 'our-room'),
    now(), now() + interval '2 days', 'pair:' || v_pair::text);
  return v_pair;
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
end $function$;
