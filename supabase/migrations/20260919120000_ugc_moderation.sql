-- User-generated content moderation: durable blocks and reports that reach us.
--
-- App Review guideline 1.2 asks for three things on any app carrying UGC: an
-- agreement presented before sign-in, a way to flag objectionable content, and
-- a way to block abusive users - where blocking "notifies the developer of the
-- inappropriate content and removes it from the user's feed instantly".
--
-- The client already had a flag affordance and a block, but the block was an
-- in-memory Set<String> keyed on *display name*, scoped to one room and lost
-- on leave, and nothing about it ever reached us. Both halves live here now,
-- because both halves have to outlive the room they happened in.

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------

-- Account-scoped, not room-scoped: somebody you blocked is still somebody you
-- blocked when you meet them in a different room next week. Deliberately
-- one-way - the blocker stops seeing the blocked, which is the standard shape
-- and the one the guideline describes.
create table public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_no_self check (blocker_id <> blocked_id)
);

create index user_blocks_blocker_idx on public.user_blocks (blocker_id);

alter table public.user_blocks enable row level security;

-- You may read your own block list (the profile screen renders it) and
-- nothing else. Writes go through the RPCs so a block can never be recorded
-- without the report that accompanies it.
create policy "users read their own blocks"
  on public.user_blocks for select to authenticated
  using (blocker_id = (select auth.uid()));

revoke all on public.user_blocks from anon, authenticated;
grant select on public.user_blocks to authenticated;
grant all on public.user_blocks to service_role;

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------

-- No foreign key to rooms, for the same reason recaps carry none: a report has
-- to survive the room it was filed in, and the host deleting the room is not
-- an acceptable way to destroy the evidence. room_id is kept as a bare uuid.
create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles (id) on delete set null,
  reported_user_id uuid references public.profiles (id) on delete set null,
  room_id uuid,
  message_id uuid,
  -- Capped, and the only place chat text is ever retained beyond the room.
  -- Without it a report is unactionable; with the whole message it becomes a
  -- second copy of the chat log.
  message_excerpt text check (message_excerpt is null or char_length(message_excerpt) <= 500),
  reason text not null,
  details text check (details is null or char_length(details) <= 2000),
  -- 'blocked' is filed by block_user itself: the guideline asks to be notified
  -- when somebody blocks, not only when they fill in a form.
  source text not null default 'report' check (source in ('report', 'blocked')),
  status text not null default 'open' check (status in ('open', 'reviewing', 'actioned', 'dismissed')),
  created_at timestamptz not null default now()
);

create index content_reports_status_idx on public.content_reports (status, created_at desc);
create index content_reports_reported_idx on public.content_reports (reported_user_id, created_at desc);

-- Two layers, as with room_bans: RLS on with deliberately no policy (a report
-- is never read back by any client - not by the reporter, and certainly not by
-- the person reported), plus an explicit revoke so the platform's default
-- grants on a new public table cannot quietly expose it. Triage happens in the
-- dashboard, under service_role.
alter table public.content_reports enable row level security;
revoke all on public.content_reports from anon, authenticated;
grant all on public.content_reports to service_role;

-- ---------------------------------------------------------------------------
-- Blocked senders disappear from chat history
-- ---------------------------------------------------------------------------

-- "Instantly" has to mean the reload too. The broadcast path is filtered on
-- the client (a realtime broadcast carries no RLS), but history is a plain
-- select, so the block belongs in the policy - otherwise every reconnect
-- re-materialises exactly the messages the user asked never to see again.
drop policy "members can read room chat" on public.messages;

create policy "members can read room chat"
  on public.messages for select to authenticated
  using (
    public.is_room_member(room_id)
    and not exists (
      select 1 from public.user_blocks b
      where b.blocker_id = (select auth.uid())
        and b.blocked_id = messages.sender_id
    )
  );

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create or replace function public.report_content(
  p_reported_user_id uuid,
  p_reason text,
  p_room_id uuid default null,
  p_details text default null,
  p_message_id uuid default null,
  p_message_excerpt text default null,
  p_source text default 'report')
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

  -- A report queue anyone can flood is a report queue nobody reads.
  select count(*) into v_recent
    from public.content_reports
    where reporter_id = v_uid and created_at > now() - interval '1 hour';
  if v_recent >= 20 then
    raise exception 'report_rate_limited';
  end if;

  insert into public.content_reports (
    reporter_id, reported_user_id, room_id, message_id,
    message_excerpt, reason, details, source)
  values (
    v_uid, p_reported_user_id, p_room_id, p_message_id,
    left(p_message_excerpt, 500), p_reason, left(p_details, 2000), p_source)
  returning id into v_id;

  return v_id;
end $$;

-- Blocking files its own report, which is what "notify the developer" asks
-- for: the common case is somebody who blocks and closes the app rather than
-- staying to fill in a form, and that signal is the one worth having.
create or replace function public.block_user(
  p_user_id uuid,
  p_room_id uuid default null,
  p_reason text default 'other',
  p_message_excerpt text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_user_id is null then
    raise exception 'invalid_target';
  end if;
  if p_user_id = v_uid then
    raise exception 'cannot_block_self';
  end if;

  insert into public.user_blocks (blocker_id, blocked_id)
  values (v_uid, p_user_id)
  on conflict (blocker_id, blocked_id) do nothing;

  -- Only on a new block: re-blocking after an unblock is not fresh evidence,
  -- and would let the queue be padded by toggling.
  --
  -- The report must never be able to fail the block. Blocking is the user's
  -- safety action and it has to succeed even when they have tripped the
  -- reporting rate limit - losing the notification is the acceptable half of
  -- that trade, losing the block is not.
  if found then
    begin
      perform public.report_content(
        p_reported_user_id => p_user_id,
        p_reason => p_reason,
        p_room_id => p_room_id,
        p_message_excerpt => p_message_excerpt,
        p_source => 'blocked');
    exception when others then
      raise warning 'block_user: could not file accompanying report: %', sqlerrm;
    end;
  end if;
end $$;

create or replace function public.unblock_user(p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  delete from public.user_blocks
    where blocker_id = v_uid and blocked_id = p_user_id;
end $$;

-- Backs the "Blocked people" list in the profile. A block the user cannot see
-- is a block the user cannot undo, and an un-undoable block is its own
-- support problem.
create or replace function public.my_blocked_users()
returns table (user_id uuid, display_name text, avatar_url text, created_at timestamptz)
language sql security definer set search_path = ''
as $$
  select b.blocked_id, p.display_name, p.avatar_url, b.created_at
    from public.user_blocks b
    join public.profiles p on p.id = b.blocked_id
    where b.blocker_id = auth.uid()
    order by b.created_at desc
$$;

revoke all on function public.report_content(uuid, text, uuid, text, uuid, text, text) from public, anon;
revoke all on function public.block_user(uuid, uuid, text, text) from public, anon;
revoke all on function public.unblock_user(uuid) from public, anon;
revoke all on function public.my_blocked_users() from public, anon;

grant execute on function public.report_content(uuid, text, uuid, text, uuid, text, text) to authenticated;
grant execute on function public.block_user(uuid, uuid, text, text) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
grant execute on function public.my_blocked_users() to authenticated;
