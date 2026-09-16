-- Gamification: watch ledger, streaks, achievements, leaderboards, recaps.
-- Plan: docs/gamification-plan.md
--
-- Doctrine this migration follows, and which any change to it must keep:
--   * Thresholds are CONFIG ROWS, not constants - tuning is an `update`, never a
--     deploy. Same reasoning as `tier_limits`.
--   * Every credit decision is made in a `security definer` RPC. A client that
--     lies gains nothing, because elapsed time is computed server-side.
--   * Guests earn nothing. `effective_tier` short-circuits on anonymous
--     accounts, and those accounts are purged after 3 days anyway - a streak
--     that cannot outlive the account is a promise we would break.
--   * Nothing here is published without `profiles.public_profile` being true.

-- ---------------------------------------------------------------------------
-- 1. Tuning surface
-- ---------------------------------------------------------------------------

create table public.reward_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.reward_config (key, value) values
  ('ledger_enabled',            'true'::jsonb),
  ('streak_min_minutes',        '10'::jsonb),
  ('daily_credit_cap_min',      '480'::jsonb),
  ('daily_points_cap_min',      '240'::jsonb),
  ('pair_daily_cap_min',        '120'::jsonb),
  ('heartbeat_clamp_sec',       '90'::jsonb),
  ('heartbeat_stale_sec',       '300'::jsonb),
  ('playback_grace_sec',        '180'::jsonb),
  ('min_members',               '2'::jsonb),
  ('freezes_per_week',          '2'::jsonb),
  ('freezes_per_week_premium',  '3'::jsonb),
  ('co_watcher_points',         '15'::jsonb),
  ('co_watcher_points_cap',     '5'::jsonb),
  ('full_house_members',        '4'::jsonb),
  ('full_house_bonus',          '25'::jsonb),
  ('leaderboard_min_participants', '30'::jsonb),
  ('recap_ttl_days',            '90'::jsonb),
  ('recap_max_reactions',       '500'::jsonb),
  ('recap_max_messages',        '1000'::jsonb),
  ('ledger_retention_days',     '400'::jsonb);

-- Reads a tuning value with an inline fallback, so a missing row degrades to a
-- sane default rather than a null-propagating arithmetic hole.
create or replace function public.reward_setting(p_key text, p_default numeric)
returns numeric
language sql stable security definer set search_path = ''
as $$
  select coalesce((select value::text::numeric from public.reward_config where key = p_key), p_default);
$$;

create or replace function public.reward_flag(p_key text, p_default boolean)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce((select value::text::boolean from public.reward_config where key = p_key), p_default);
$$;

-- ---------------------------------------------------------------------------
-- 2. Ledger tables
-- ---------------------------------------------------------------------------

-- Per-user, per-local-day roll-up. Incremented, never appended per heartbeat.
create table public.watch_ledger (
  user_id          uuid not null references public.profiles (id) on delete cascade,
  day              date not null,
  credited_seconds int  not null default 0 check (credited_seconds >= 0),
  co_watchers      int  not null default 0 check (co_watchers >= 0),
  rooms_touched    int  not null default 0 check (rooms_touched >= 0),
  peak_members     int  not null default 0 check (peak_members >= 0),
  points           int  not null default 0 check (points >= 0),
  updated_at       timestamptz not null default now(),
  primary key (user_id, day)
);

create index watch_ledger_day_points_idx on public.watch_ledger (day, points desc);
create index watch_ledger_user_day_idx on public.watch_ledger (user_id, day desc);

-- Per-room slice of a day. Carries the per-session facts achievements need
-- (longest single sitting, biggest room) without a row per heartbeat.
create table public.watch_day_rooms (
  user_id      uuid not null references public.profiles (id) on delete cascade,
  day          date not null,
  -- No foreign key, for the same reason `recaps.room_id` has none: this is a
  -- ledger of what somebody watched, and somebody *else* deleting the room must
  -- not rewrite it. It is also the durable proof of membership `create_recap`
  -- falls back on once `room_members` has gone, which is exactly the exit path
  -- - host deletes the room, member is offered the card - where a cascade here
  -- turned the share into `not_a_member`. `sweep_rewards` prunes it by age.
  room_id      uuid not null,
  seconds      int  not null default 0 check (seconds >= 0),
  peak_members int  not null default 0,
  was_host     boolean not null default false,
  started_at   timestamptz not null default now(),
  last_at      timestamptz not null default now(),
  primary key (user_id, day, room_id)
);

-- Per-pair daily accrual. Exists solely so two accounts cannot farm each other:
-- the 11th hour with the same person is worth zero points.
create table public.co_watch_daily (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  other_id uuid not null references public.profiles (id) on delete cascade,
  day      date not null,
  seconds  int  not null default 0 check (seconds >= 0),
  primary key (user_id, other_id, day)
);

-- Lifetime co-watch graph. Powers the Circle leaderboard and Wrapped.
create table public.co_watchers (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  other_id uuid not null references public.profiles (id) on delete cascade,
  sessions int not null default 0,
  seconds  bigint not null default 0,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  primary key (user_id, other_id)
);

create index co_watchers_user_seconds_idx on public.co_watchers (user_id, seconds desc);

-- The heartbeat anchor. Elapsed is `now() - last_at`, computed here, so call
-- frequency is irrelevant - this is the line that makes the RPC unspammable.
create table public.watch_heartbeats (
  user_id uuid not null references public.profiles (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  last_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

-- One row per user. Streak state plus every lifetime aggregate an achievement
-- can be evaluated against.
create table public.user_rewards (
  user_id                 uuid primary key references public.profiles (id) on delete cascade,
  current_streak          int  not null default 0,
  longest_streak          int  not null default 0,
  last_credited_day       date,
  freezes_available       int  not null default 1,
  freezes_refreshed       date,
  last_freeze_used_day    date,
  total_seconds           bigint not null default 0,
  total_sessions          int  not null default 0,
  total_hosted            int  not null default 0,
  longest_session_seconds int  not null default 0,
  max_room_members        int  not null default 0,
  distinct_co_watchers    int  not null default 0,
  days_active             int  not null default 0,
  double_feature_days     int  not null default 0,
  night_owl_sessions      int  not null default 0,
  clean_gate_sessions     int  not null default 0,
  reactions_sent          int  not null default 0,
  messages_sent           int  not null default 0,
  lifetime_points         bigint not null default 0,
  updated_at              timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3. Achievements catalogue (config, not code - a new badge is an insert)
-- ---------------------------------------------------------------------------

create table public.achievements (
  id          text primary key,
  title       text not null,
  description text not null,
  icon        text not null,          -- material_symbols name, resolved client-side
  grade       text not null check (grade in ('bronze', 'silver', 'gold', 'secret')),
  metric      text not null,          -- a key of the metrics object in record_watch_progress
  threshold   bigint not null check (threshold > 0),
  reward      jsonb not null default '{}'::jsonb,
  sort        int  not null default 0
);

insert into public.achievements (id, title, description, icon, grade, metric, threshold, reward, sort) values
  ('first_sync', 'First Sync', 'Finish a session with someone else.', 'handshake', 'bronze', 'total_sessions', 1, '{}'::jsonb, 10),
  ('week_one', 'Regular', 'Keep a 3-day watch streak.', 'local_fire_department', 'bronze', 'longest_streak', 3, '{"frame":"ember"}'::jsonb, 20),
  ('seven_up', 'Seven Up', 'Keep a 7-day watch streak.', 'whatshot', 'silver', 'longest_streak', 7, '{}'::jsonb, 30),
  ('unbroken', 'Unbroken', 'Keep a 30-day watch streak.', 'bolt', 'gold', 'longest_streak', 30, '{"frame":"aurora"}'::jsonb, 40),
  ('double_feature', 'Double Feature', 'Watch in two different rooms in one day.', 'theaters', 'bronze', 'double_feature_days', 1, '{}'::jsonb, 50),
  ('full_house', 'Full House', 'Be in a room with 8 or more people.', 'groups', 'silver', 'max_room_members', 8, '{}'::jsonb, 60),
  ('marathon', 'Marathon', 'Stay in one session for over 4 hours.', 'timer', 'silver', 'longest_session_seconds', 14400, '{}'::jsonb, 70),
  ('night_owl', 'Night Owl', 'Watch through 2am.', 'bedtime', 'bronze', 'night_owl_sessions', 1, '{}'::jsonb, 80),
  ('wide_circle', 'Wide Circle', 'Watch with 10 different people.', 'diversity_3', 'silver', 'distinct_co_watchers', 10, '{"frame":"halo"}'::jsonb, 90),
  ('century', 'Century', 'Watch 100 hours together.', 'military_tech', 'gold', 'total_seconds', 360000, '{"frame":"laurel"}'::jsonb, 100),
  ('hype_man', 'Hype Machine', 'Send 500 reactions.', 'celebration', 'bronze', 'reactions_sent', 500, '{}'::jsonb, 110),
  ('host_with_most', 'Host With The Most', 'Host 25 sessions.', 'stadia_controller', 'silver', 'total_hosted', 25, '{}'::jsonb, 120),
  ('perfect_sync', 'Perfect Sync', 'Ten sessions without ever holding the gate.', 'target', 'secret', 'clean_gate_sessions', 10, '{"frame":"pulse"}'::jsonb, 130),
  ('chatterbox', 'Chatterbox', 'Send 1,000 chat messages.', 'forum', 'bronze', 'messages_sent', 1000, '{}'::jsonb, 140),
  ('devoted', 'Devoted', 'Be active on 100 different days.', 'event_available', 'gold', 'days_active', 100, '{}'::jsonb, 150);

create table public.user_achievements (
  user_id        uuid not null references public.profiles (id) on delete cascade,
  achievement_id text not null references public.achievements (id) on delete cascade,
  unlocked_at    timestamptz not null default now(),
  seen           boolean not null default false,
  primary key (user_id, achievement_id)
);

create index user_achievements_user_idx on public.user_achievements (user_id, unlocked_at desc);

-- ---------------------------------------------------------------------------
-- 4. Shareable recaps
-- ---------------------------------------------------------------------------

-- Deliberately narrow: the payload is assembled by `create_recap`, never passed
-- through raw, so a client cannot smuggle a file name or a chat line into a
-- public URL. See the privacy boundary in the analytics doctrine - media is
-- reported as `kind` only.
create table public.recaps (
  id         text primary key,
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  -- Deliberately NOT a foreign key. A recap is a public URL with a 90-day life
  -- of its own; a room is deleted the moment its host says so. With an FK,
  -- `on delete cascade` would kill a link somebody had already posted, and
  -- `on delete set null` both broke the dedupe index (nulls never collide, so a
  -- second share would bank the counters twice) and made sharing the recap of a
  -- just-deleted room fail outright on the insert - which is precisely the exit
  -- path that offers the card.
  room_id    uuid not null,
  created_at timestamptz not null default now(),
  day        date not null default (now() at time zone 'utc')::date,
  expires_at timestamptz not null,
  views      int not null default 0,
  payload    jsonb not null
);

-- One recap per room per day per owner. Sharing twice must not credit the
-- session's reaction and message counters twice.
create unique index recaps_owner_room_day_key on public.recaps (owner_id, room_id, day);
create index recaps_owner_idx on public.recaps (owner_id, created_at desc);
create index recaps_expiry_idx on public.recaps (expires_at);

-- ---------------------------------------------------------------------------
-- 5. Profile columns
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column public_profile boolean not null default false,
  add column handle         text,
  add column equipped_frame text,
  add column referred_by    uuid references public.profiles (id) on delete set null,
  add column rewards_seen_at timestamptz;

create unique index profiles_handle_key on public.profiles (lower(handle));

-- The client may flip none of these directly; they are RPC-written.
revoke update on public.profiles from authenticated, anon;
grant update (display_name, avatar_url) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 6. RLS
-- ---------------------------------------------------------------------------

alter table public.reward_config     enable row level security;
alter table public.watch_ledger      enable row level security;
alter table public.watch_day_rooms   enable row level security;
alter table public.co_watch_daily    enable row level security;
alter table public.co_watchers       enable row level security;
alter table public.watch_heartbeats  enable row level security;
alter table public.user_rewards      enable row level security;
alter table public.achievements      enable row level security;
alter table public.user_achievements enable row level security;
alter table public.recaps            enable row level security;

create policy "reward config is readable by signed-in users"
  on public.reward_config for select to authenticated using (true);

create policy "achievement catalogue is readable by signed-in users"
  on public.achievements for select to authenticated using (true);

create policy "users read their own ledger"
  on public.watch_ledger for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "users read their own unlocks"
  on public.user_achievements for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "users read their own rewards row"
  on public.user_rewards for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "users read their own recaps"
  on public.recaps for select to authenticated
  using ((select auth.uid()) = owner_id);

-- No client-facing policy at all on the pair tables, the heartbeat anchor or the
-- per-room day slices: they are inputs to the anti-abuse arithmetic and reading
-- them tells an attacker exactly how much headroom is left.

-- Table DML is RPC-only, everywhere.
revoke insert, update, delete on
  public.reward_config, public.watch_ledger, public.watch_day_rooms,
  public.co_watch_daily, public.co_watchers, public.watch_heartbeats,
  public.user_rewards, public.achievements, public.user_achievements,
  public.recaps
from public, anon, authenticated;

revoke select on
  public.watch_day_rooms, public.co_watch_daily, public.co_watchers,
  public.watch_heartbeats
from public, anon, authenticated;

grant select on public.reward_config     to authenticated;
grant select on public.achievements      to authenticated;
grant select on public.watch_ledger      to authenticated;
grant select on public.user_achievements to authenticated;
grant select on public.user_rewards      to authenticated;
grant select on public.recaps            to authenticated;

grant all on
  public.reward_config, public.watch_ledger, public.watch_day_rooms,
  public.co_watch_daily, public.co_watchers, public.watch_heartbeats,
  public.user_rewards, public.achievements, public.user_achievements,
  public.recaps
to service_role;

-- ---------------------------------------------------------------------------
-- 7. Scoring primitives (pure, so pgTAP can assert them directly)
-- ---------------------------------------------------------------------------

-- Consistency is rewarded through the multiplier rather than raw time: someone
-- who watches 40 minutes every day for a month outranks someone who watched
-- twelve hours on one Saturday. That is the intended message of the board.
create or replace function public.streak_multiplier(p_streak int)
returns numeric
language sql immutable
as $$
  select case
    when coalesce(p_streak, 0) >= 30 then 1.50
    when coalesce(p_streak, 0) >= 7  then 1.25
    when coalesce(p_streak, 0) >= 3  then 1.10
    else 1.00
  end;
$$;

create or replace function public.reward_points(
  p_points_seconds int,
  p_co_watchers int,
  p_peak_members int,
  p_streak int)
returns int
language sql stable security definer set search_path = ''
as $$
  select greatest(0, round((
      least(coalesce(p_points_seconds, 0) / 60, public.reward_setting('daily_points_cap_min', 240))
    + public.reward_setting('co_watcher_points', 15)
      * least(coalesce(p_co_watchers, 0), public.reward_setting('co_watcher_points_cap', 5))
    + case
        when coalesce(p_peak_members, 0) >= public.reward_setting('full_house_members', 4)
          then public.reward_setting('full_house_bonus', 25)
        else 0
      end
  ) * public.streak_multiplier(p_streak))::int);
$$;

-- A stored streak is only meaningful inside its grace window. Past that it is
-- zero whether or not a heartbeat has run to write the zero down, so every
-- reader goes through here rather than reading `current_streak` raw.
create or replace function public.effective_streak(
  p_current int, p_last_day date, p_freezes int, p_today date)
returns int
language sql immutable
as $$
  select case
    when p_last_day is null then 0
    when p_today - p_last_day <= 1 then coalesce(p_current, 0)
    -- One freeze per missed day. A single freeze covering only a one-day gap
    -- made the budget useless for the way people actually watch together:
    -- almost nobody does it seven days a week, and a streak that punishes a
    -- Tuesday is a streak people abandon.
    when (p_today - p_last_day - 1) <= coalesce(p_freezes, 0) then coalesce(p_current, 0)
    else 0
  end;
$$;

create or replace function public.reward_period_start(p_period text)
returns date
language sql stable
as $$
  select case lower(coalesce(p_period, 'week'))
    when 'today' then (now() at time zone 'utc')::date
    when 'month' then date_trunc('month', now() at time zone 'utc')::date
    when 'all'   then '-infinity'::date
    else date_trunc('week', now() at time zone 'utc')::date
  end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The heartbeat
-- ---------------------------------------------------------------------------

-- Called on the same 60 s cadence as `update_media_position`, so no new timer
-- is introduced client-side.
--
-- Everything that decides whether a second is earned happens HERE, in the
-- server's own clock. `p_local_day` and `p_local_hour` are the only things the
-- client is trusted with, and both are range-checked: a lying client can shift
-- which calendar day it is crediting, never how much.
create or replace function public.record_watch_progress(
  p_room_id uuid,
  p_local_day date default null,
  p_local_hour int default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tier text;
  v_room public.rooms;
  v_role text;
  v_members int;
  v_day date;
  v_gap int;
  v_last timestamptz;
  v_elapsed int;
  v_grant int := 0;
  v_today_seconds int;
  v_credit_cap int;
  v_pair_cap int;
  v_points_seconds int;
  v_distinct_today int;
  v_rooms_today int;
  v_peak_today int;
  v_existing_room boolean;
  v_session_seconds int;
  v_night_owl boolean;
  v_was_night_owl boolean;
  v_r public.user_rewards;
  v_old_points int;
  v_new_points int;
  v_streak_min_seconds int;
  v_freeze_quota int;
  v_frozen boolean := false;
  v_metrics jsonb;
  v_unlocked jsonb := '[]'::jsonb;
  v_reason text;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if not public.reward_flag('ledger_enabled', true) then
    return jsonb_build_object('enabled', false, 'credited', false, 'reason', 'disabled');
  end if;

  v_tier := public.effective_tier(v_uid);
  if v_tier = 'guest' then
    -- Not a punishment: an anonymous account is purged after three days, so a
    -- streak held on one is a promise we would break. The client turns this
    -- into the sign-in offer.
    return jsonb_build_object(
      'enabled', true, 'credited', false, 'reason', 'guest', 'upgrade', true);
  end if;

  -- The client's calendar day, believed only within a day of the server's.
  v_day := coalesce(p_local_day, (now() at time zone 'utc')::date);
  if v_day < (now() at time zone 'utc')::date - 1
     or v_day > (now() at time zone 'utc')::date + 1 then
    v_day := (now() at time zone 'utc')::date;
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    return jsonb_build_object('enabled', true, 'credited', false, 'reason', 'room_not_found');
  end if;

  select role into v_role from public.room_members
    where room_id = p_room_id and user_id = v_uid;
  if v_role is null then
    return jsonb_build_object('enabled', true, 'credited', false, 'reason', 'not_a_member');
  end if;

  if public.room_state(v_room) <> 'live' then
    v_reason := 'room_ended';
  end if;

  select count(*) into v_members from public.room_members where room_id = p_room_id;
  if v_reason is null and v_members < public.reward_setting('min_members', 2)::int then
    -- Watching alone is fine. It just is not watching *together*.
    v_reason := 'solo';
  end if;

  if v_reason is null and coalesce(v_room.media_kind, 'none') = 'none' then
    v_reason := 'no_media';
  end if;

  -- Free liveness: `update_media_position` is authority-only and stops when
  -- playback stops, so a room left open overnight stops producing this and
  -- therefore stops earning.
  if v_reason is null
     and greatest(
           coalesce(v_room.media_position_at, '-infinity'::timestamptz),
           coalesce(v_room.media_updated_at, '-infinity'::timestamptz))
         < now() - make_interval(secs => public.reward_setting('playback_grace_sec', 180)) then
    v_reason := 'idle';
  end if;

  -- The anchor moves on every call, refused or not: a refused minute must not
  -- become a credited minute the moment the room qualifies again.
  -- `for update` is what makes the anchor read-modify-write atomic. Without it
  -- two concurrent calls (a retried request, two windows of the same account in
  -- the same room) both read the same `last_at` and both credit the interval.
  -- A row that does not exist yet cannot be locked, but that path grants zero
  -- seconds anyway, so it is safe.
  select last_at into v_last from public.watch_heartbeats
    where user_id = v_uid and room_id = p_room_id
    for update;
  insert into public.watch_heartbeats (user_id, room_id, last_at)
  values (v_uid, p_room_id, now())
  on conflict (user_id, room_id) do update set last_at = now();

  if v_reason is not null then
    return jsonb_build_object('enabled', true, 'credited', false, 'reason', v_reason);
  end if;

  -- THE line that makes this RPC unspammable: elapsed is the server's, and it
  -- is clamped. Calling ten times a second credits exactly what calling once a
  -- minute credits.
  if v_last is null then
    v_elapsed := 0;                       -- first call only anchors
  else
    v_elapsed := greatest(0, floor(extract(epoch from now() - v_last))::int);
    if v_elapsed > public.reward_setting('heartbeat_stale_sec', 300)::int then
      v_elapsed := 0;                     -- they were away, not watching
    else
      v_elapsed := least(v_elapsed, public.reward_setting('heartbeat_clamp_sec', 90)::int);
    end if;
  end if;

  v_credit_cap := (public.reward_setting('daily_credit_cap_min', 480) * 60)::int;
  v_pair_cap   := (public.reward_setting('pair_daily_cap_min', 120) * 60)::int;

  select credited_seconds into v_today_seconds from public.watch_ledger
    where user_id = v_uid and day = v_day;
  v_today_seconds := coalesce(v_today_seconds, 0);
  v_grant := least(v_elapsed, greatest(0, v_credit_cap - v_today_seconds));

  select points into v_old_points from public.watch_ledger
    where user_id = v_uid and day = v_day;
  v_old_points := coalesce(v_old_points, 0);

  insert into public.user_rewards (user_id) values (v_uid)
  on conflict (user_id) do nothing;

  -- Nothing earned, nothing written. The first call of a session only anchors
  -- the clock, and a session must be *watched* before it counts as a session -
  -- crediting one on room entry made "Finish a session with someone else"
  -- unlock before anybody had watched anything.
  if v_grant <= 0 then
    select * into v_r from public.user_rewards where user_id = v_uid;
    return jsonb_build_object(
      'enabled',         true,
      'credited',        false,
      'reason',          case when v_today_seconds >= v_credit_cap then 'daily_cap'
                              when v_last is null then 'anchored'
                              else 'no_elapsed' end,
      'granted_seconds', 0,
      'seconds_today',   v_today_seconds,
      'points_today',    v_old_points,
      'streak',          public.effective_streak(coalesce(v_r.current_streak, 0),
                           v_r.last_credited_day, coalesce(v_r.freezes_available, 0), v_day),
      'longest_streak',  coalesce(v_r.longest_streak, 0),
      'freezes',         coalesce(v_r.freezes_available, 0),
      'streak_frozen',   false,
      'day_qualified',   v_today_seconds >= (public.reward_setting('streak_min_minutes', 10) * 60),
      'unlocked',        '[]'::jsonb);
  end if;

  -- Per-room slice: carries longest-sitting and biggest-room for achievements.
  select true into v_existing_room from public.watch_day_rooms
    where user_id = v_uid and day = v_day and room_id = p_room_id;
  v_existing_room := coalesce(v_existing_room, false);
  v_night_owl := p_local_hour is not null and p_local_hour >= 2 and p_local_hour < 5;

  insert into public.watch_day_rooms
    (user_id, day, room_id, seconds, peak_members, was_host, started_at, last_at)
  values (v_uid, v_day, p_room_id, v_grant, v_members, v_role = 'host', now(), now())
  on conflict (user_id, day, room_id) do update set
    seconds      = public.watch_day_rooms.seconds + v_grant,
    peak_members = greatest(public.watch_day_rooms.peak_members, v_members),
    was_host     = public.watch_day_rooms.was_host or (v_role = 'host'),
    last_at      = now()
  returning seconds into v_session_seconds;

  -- Pair accrual, both directions. `co_watch_daily` exists only to make two
  -- accounts farming each other unprofitable; `co_watchers` is the lifetime
  -- graph the Circle board and Wrapped read.
  insert into public.co_watch_daily (user_id, other_id, day, seconds)
  select v_uid, m.user_id, v_day, v_grant
    from public.room_members m
   where m.room_id = p_room_id and m.user_id <> v_uid
  on conflict (user_id, other_id, day) do update
    set seconds = public.co_watch_daily.seconds + v_grant;

  insert into public.co_watchers (user_id, other_id, sessions, seconds, first_at, last_at)
  select v_uid, m.user_id, case when v_existing_room then 0 else 1 end, v_grant, now(), now()
    from public.room_members m
   where m.room_id = p_room_id and m.user_id <> v_uid
  on conflict (user_id, other_id) do update set
    sessions = public.co_watchers.sessions + (case when v_existing_room then 0 else 1 end),
    seconds  = public.co_watchers.seconds + v_grant,
    last_at  = now();

  insert into public.co_watchers (user_id, other_id, sessions, seconds, first_at, last_at)
  select m.user_id, v_uid, case when v_existing_room then 0 else 1 end, v_grant, now(), now()
    from public.room_members m
   where m.room_id = p_room_id and m.user_id <> v_uid
  on conflict (user_id, other_id) do update set
    sessions = public.co_watchers.sessions + (case when v_existing_room then 0 else 1 end),
    seconds  = public.co_watchers.seconds + v_grant,
    last_at  = now();

  select count(*) into v_distinct_today from public.co_watch_daily
    where user_id = v_uid and day = v_day and seconds > 0;

  select count(*), coalesce(max(peak_members), 0)
    into v_rooms_today, v_peak_today
    from public.watch_day_rooms where user_id = v_uid and day = v_day;

  -- Points-eligible seconds: the day's credited time, capped by what the
  -- per-pair allowances actually permit. Three hours with one person and twenty
  -- minutes with another scores the cap plus the twenty, not the lot.
  select least(v_today_seconds + v_grant, coalesce(sum(least(seconds, v_pair_cap)), 0))
    into v_points_seconds
    from public.co_watch_daily where user_id = v_uid and day = v_day;

  select * into v_r from public.user_rewards where user_id = v_uid for update;

  -- Freeze refill is lazy: no cron, and therefore no "which timezone does the
  -- cron think it is" bug.
  v_freeze_quota := (case when v_tier = 'premium'
    then public.reward_setting('freezes_per_week_premium', 3)
    else public.reward_setting('freezes_per_week', 2) end)::int;
  if v_r.freezes_refreshed is null or (v_day - v_r.freezes_refreshed) >= 7 then
    v_r.freezes_available := v_freeze_quota;
    v_r.freezes_refreshed := v_day;
  end if;

  -- A streak past saving is zero, written down rather than left to the reader.
  if v_r.last_credited_day is not null then
    v_gap := v_day - v_r.last_credited_day;
    if v_gap > 1 and (v_gap - 1) > v_r.freezes_available then
      v_r.current_streak := 0;
    end if;
  end if;

  v_streak_min_seconds := (public.reward_setting('streak_min_minutes', 10) * 60)::int;
  if (v_today_seconds + v_grant) >= v_streak_min_seconds
     and v_r.last_credited_day is distinct from v_day then
    v_gap := case when v_r.last_credited_day is null then null
                  else v_day - v_r.last_credited_day end;
    if v_gap is null then
      v_r.current_streak := 1;
    elsif v_gap = 1 then
      v_r.current_streak := v_r.current_streak + 1;
    elsif v_gap > 1 and (v_gap - 1) <= v_r.freezes_available then
      -- One freeze per missed day, consumed silently and reported afterwards.
      -- A streak you can lose to a busy Tuesday is a streak people quit.
      v_r.current_streak := v_r.current_streak + 1;
      v_r.freezes_available := v_r.freezes_available - (v_gap - 1);
      v_r.last_freeze_used_day := v_day - 1;
      v_frozen := true;
    elsif v_gap <= 0 then
      v_r.current_streak := greatest(v_r.current_streak, 1);
    else
      v_r.current_streak := 1;
    end if;
    v_r.longest_streak := greatest(v_r.longest_streak, v_r.current_streak);
    v_r.last_credited_day := v_day;
    v_r.days_active := v_r.days_active + 1;
  end if;

  v_new_points := public.reward_points(
    v_points_seconds, v_distinct_today, v_peak_today, v_r.current_streak);

  insert into public.watch_ledger
    (user_id, day, credited_seconds, co_watchers, rooms_touched, peak_members, points, updated_at)
  values (v_uid, v_day, v_grant, v_distinct_today, v_rooms_today, v_peak_today, v_new_points, now())
  on conflict (user_id, day) do update set
    credited_seconds = public.watch_ledger.credited_seconds + v_grant,
    co_watchers      = v_distinct_today,
    rooms_touched    = v_rooms_today,
    peak_members     = greatest(public.watch_ledger.peak_members, v_peak_today),
    points           = v_new_points,
    updated_at       = now();

  v_was_night_owl := v_night_owl and not v_existing_room;

  update public.user_rewards set
    current_streak          = v_r.current_streak,
    longest_streak          = v_r.longest_streak,
    last_credited_day       = v_r.last_credited_day,
    freezes_available       = v_r.freezes_available,
    freezes_refreshed       = v_r.freezes_refreshed,
    last_freeze_used_day    = v_r.last_freeze_used_day,
    days_active             = v_r.days_active,
    total_seconds           = public.user_rewards.total_seconds + v_grant,
    total_sessions          = public.user_rewards.total_sessions + (case when v_existing_room then 0 else 1 end),
    total_hosted            = public.user_rewards.total_hosted
                              + (case when not v_existing_room and v_role = 'host' then 1 else 0 end),
    longest_session_seconds = greatest(public.user_rewards.longest_session_seconds, v_session_seconds),
    max_room_members        = greatest(public.user_rewards.max_room_members, v_members),
    night_owl_sessions      = public.user_rewards.night_owl_sessions + (case when v_was_night_owl then 1 else 0 end),
    double_feature_days     = public.user_rewards.double_feature_days
                              + (case when v_rooms_today = 2 and not v_existing_room then 1 else 0 end),
    distinct_co_watchers    = (select count(*) from public.co_watchers where user_id = v_uid),
    lifetime_points         = greatest(0, public.user_rewards.lifetime_points + (v_new_points - v_old_points)),
    updated_at              = now()
  where user_id = v_uid
  returning * into v_r;

  v_metrics := jsonb_build_object(
    'total_seconds',           v_r.total_seconds,
    'current_streak',          v_r.current_streak,
    'longest_streak',          v_r.longest_streak,
    'total_sessions',          v_r.total_sessions,
    'total_hosted',            v_r.total_hosted,
    'longest_session_seconds', v_r.longest_session_seconds,
    'max_room_members',        v_r.max_room_members,
    'distinct_co_watchers',    v_r.distinct_co_watchers,
    'days_active',             v_r.days_active,
    'double_feature_days',     v_r.double_feature_days,
    'night_owl_sessions',      v_r.night_owl_sessions,
    'clean_gate_sessions',     v_r.clean_gate_sessions,
    'reactions_sent',          v_r.reactions_sent,
    'messages_sent',           v_r.messages_sent);

  v_unlocked := public.grant_achievements(v_uid, v_metrics);

  return jsonb_build_object(
    'enabled',          true,
    'credited',         v_grant > 0,
    'granted_seconds',  v_grant,
    'seconds_today',    v_today_seconds + v_grant,
    'points_today',     v_new_points,
    'streak',           v_r.current_streak,
    'longest_streak',   v_r.longest_streak,
    'freezes',          v_r.freezes_available,
    'streak_frozen',    v_frozen,
    'day_qualified',    (v_today_seconds + v_grant) >= v_streak_min_seconds,
    'unlocked',         v_unlocked);
end $$;

-- Data-driven, so a new badge is an insert into `achievements` and nothing else.
create or replace function public.grant_achievements(p_user_id uuid, p_metrics jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_out jsonb;
begin
  with fresh as (
    insert into public.user_achievements (user_id, achievement_id)
    select p_user_id, a.id
      from public.achievements a
     where coalesce((p_metrics ->> a.metric)::bigint, 0) >= a.threshold
    on conflict (user_id, achievement_id) do nothing
    returning achievement_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'title', a.title, 'description', a.description,
           'icon', a.icon, 'grade', a.grade, 'reward', a.reward) order by a.sort),
         '[]'::jsonb)
    into v_out
    from fresh join public.achievements a on a.id = fresh.achievement_id;
  return coalesce(v_out, '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- 9. Leaderboards
-- ---------------------------------------------------------------------------

-- The participation floor, same doctrine as website/lib/public-metrics.ts:
-- publishing a small number is worse than publishing none, and a global board
-- with fourteen names on it is exactly that failure, screenshot-ready.
create or replace function public.leaderboard_open()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select (
    select count(distinct l.user_id)
      from public.watch_ledger l
      join public.profiles p on p.id = l.user_id
     where p.public_profile
       and l.day >= public.reward_period_start('week')
       and l.points > 0
  ) >= public.reward_setting('leaderboard_min_participants', 30);
$$;

create or replace function public.leaderboard(
  p_scope text default 'circle',
  p_period text default 'week',
  p_limit int default 100)
returns table (
  rank         int,
  user_id      uuid,
  display_name text,
  avatar_url   text,
  handle       text,
  frame        text,
  is_premium   boolean,
  points       bigint,
  streak       int,
  seconds      bigint,
  is_me        boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_start date := public.reward_period_start(p_period);
  v_scope text := lower(coalesce(p_scope, 'circle'));
  v_limit int  := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_today date := (now() at time zone 'utc')::date;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if v_scope = 'global' and not public.leaderboard_open() then
    return;
  end if;

  return query
  with pool as (
    select p.id
      from public.profiles p
     where p.public_profile
       and (
         v_scope <> 'circle'
         or p.id = v_uid
         or exists (select 1 from public.co_watchers c
                     where c.user_id = v_uid and c.other_id = p.id)
       )
  ),
  totals as (
    select l.user_id as uid,
           sum(l.points)::bigint as pts,
           sum(l.credited_seconds)::bigint as secs
      from public.watch_ledger l
      join pool on pool.id = l.user_id
     where l.day >= v_start
     group by l.user_id
    having sum(l.points) > 0
  )
  select (row_number() over (order by t.pts desc, t.secs desc, pr.created_at asc))::int,
         t.uid,
         pr.display_name,
         pr.avatar_url,
         pr.handle,
         pr.equipped_frame,
         public.effective_tier(t.uid) = 'premium',
         t.pts,
         public.effective_streak(ur.current_streak, ur.last_credited_day,
                                 ur.freezes_available, v_today),
         t.secs,
         t.uid = v_uid
    from totals t
    join public.profiles pr on pr.id = t.uid
    left join public.user_rewards ur on ur.user_id = t.uid
   order by t.pts desc, t.secs desc, pr.created_at asc
   limit v_limit;
end $$;

-- Own rank is computed even for a user who has not opted in - they simply are
-- not in anyone else's board. Knowing privately where you would stand is what
-- makes the opt-in a real choice rather than a blind one.
create or replace function public.my_rank(p_scope text default 'global', p_period text default 'week')
returns int
language sql stable security definer set search_path = ''
as $$
  with mine as (
    select coalesce(sum(points), 0)::bigint as pts
      from public.watch_ledger
     where user_id = auth.uid() and day >= public.reward_period_start(p_period)
  ),
  pool as (
    select p.id
      from public.profiles p
     where p.public_profile
       and p.id <> auth.uid()
       and (
         lower(coalesce(p_scope, 'global')) <> 'circle'
         or exists (select 1 from public.co_watchers c
                     where c.user_id = auth.uid() and c.other_id = p.id)
       )
  ),
  ahead as (
    select count(*) as n from (
      select l.user_id, sum(l.points) as pts
        from public.watch_ledger l
        join pool on pool.id = l.user_id
       where l.day >= public.reward_period_start(p_period)
       group by l.user_id
      having sum(l.points) > (select pts from mine)
    ) x
  )
  select case when (select pts from mine) <= 0 then 0 else (select n from ahead)::int + 1 end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The client's one round trip
-- ---------------------------------------------------------------------------

create or replace function public.my_rewards()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
  v_tier  text;
  v_p     public.profiles;
  v_r     public.user_rewards;
  v_secs  int;
  v_streak int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  select * into v_p from public.profiles where id = v_uid;
  select * into v_r from public.user_rewards where user_id = v_uid;
  v_tier := public.effective_tier(v_uid);
  select coalesce(credited_seconds, 0) into v_secs
    from public.watch_ledger where user_id = v_uid and day = v_today;
  v_secs := coalesce(v_secs, 0);
  v_streak := public.effective_streak(
    coalesce(v_r.current_streak, 0), v_r.last_credited_day,
    coalesce(v_r.freezes_available, 0), v_today);

  return jsonb_build_object(
    'enabled', public.reward_flag('ledger_enabled', true),
    'tier', v_tier,
    'public_profile', coalesce(v_p.public_profile, false),
    'handle', v_p.handle,
    'equipped_frame', v_p.equipped_frame,
    'streak', jsonb_build_object(
      'current', v_streak,
      'stored', coalesce(v_r.current_streak, 0),
      'longest', coalesce(v_r.longest_streak, 0),
      'freezes', coalesce(v_r.freezes_available, 0),
      'last_day', v_r.last_credited_day,
      'last_freeze_day', v_r.last_freeze_used_day,
      'seconds_today', v_secs,
      'min_minutes', public.reward_setting('streak_min_minutes', 10)::int,
      'qualified_today', v_secs >= (public.reward_setting('streak_min_minutes', 10) * 60)),
    'totals', jsonb_build_object(
      'seconds', coalesce(v_r.total_seconds, 0),
      'sessions', coalesce(v_r.total_sessions, 0),
      'hosted', coalesce(v_r.total_hosted, 0),
      'co_watchers', coalesce(v_r.distinct_co_watchers, 0),
      'days_active', coalesce(v_r.days_active, 0),
      'longest_session_seconds', coalesce(v_r.longest_session_seconds, 0),
      'reactions', coalesce(v_r.reactions_sent, 0),
      'messages', coalesce(v_r.messages_sent, 0),
      'lifetime_points', coalesce(v_r.lifetime_points, 0)),
    'points', jsonb_build_object(
      'today', (select coalesce(sum(points), 0) from public.watch_ledger
                 where user_id = v_uid and day = v_today),
      'week',  (select coalesce(sum(points), 0) from public.watch_ledger
                 where user_id = v_uid and day >= public.reward_period_start('week')),
      'month', (select coalesce(sum(points), 0) from public.watch_ledger
                 where user_id = v_uid and day >= public.reward_period_start('month')),
      'all',   coalesce(v_r.lifetime_points, 0)),
    'rank', jsonb_build_object(
      'week', public.my_rank('global', 'week'),
      'circle', public.my_rank('circle', 'week')),
    'global_board', jsonb_build_object(
      'open', public.leaderboard_open(),
      'participants', (select count(distinct l.user_id) from public.watch_ledger l
                         join public.profiles p on p.id = l.user_id
                        where p.public_profile
                          and l.day >= public.reward_period_start('week')
                          and l.points > 0),
      'min_required', public.reward_setting('leaderboard_min_participants', 30)::int),
    'achievements', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', a.id, 'title', a.title, 'description', a.description,
               'icon', a.icon, 'grade', a.grade, 'reward', a.reward,
               'threshold', a.threshold, 'metric', a.metric,
               'unlocked_at', ua.unlocked_at, 'seen', coalesce(ua.seen, false),
               'unlocked', ua.user_id is not null)
             order by a.sort), '[]'::jsonb)
        from public.achievements a
        left join public.user_achievements ua
               on ua.achievement_id = a.id and ua.user_id = v_uid
       where ua.user_id is not null or a.grade <> 'secret'),
    'metrics', jsonb_build_object(
      'total_seconds', coalesce(v_r.total_seconds, 0),
      'current_streak', v_streak,
      'longest_streak', coalesce(v_r.longest_streak, 0),
      'total_sessions', coalesce(v_r.total_sessions, 0),
      'total_hosted', coalesce(v_r.total_hosted, 0),
      'longest_session_seconds', coalesce(v_r.longest_session_seconds, 0),
      'max_room_members', coalesce(v_r.max_room_members, 0),
      'distinct_co_watchers', coalesce(v_r.distinct_co_watchers, 0),
      'days_active', coalesce(v_r.days_active, 0),
      'double_feature_days', coalesce(v_r.double_feature_days, 0),
      'night_owl_sessions', coalesce(v_r.night_owl_sessions, 0),
      'clean_gate_sessions', coalesce(v_r.clean_gate_sessions, 0),
      'reactions_sent', coalesce(v_r.reactions_sent, 0),
      'messages_sent', coalesce(v_r.messages_sent, 0)),
    'frames', (
      select coalesce(jsonb_agg(distinct a.reward ->> 'frame'), '[]'::jsonb)
        from public.user_achievements ua
        join public.achievements a on a.id = ua.achievement_id
       where ua.user_id = v_uid and (a.reward ->> 'frame') is not null),
    'seasons', public.my_season_awards());
end $$;

-- ---------------------------------------------------------------------------
-- 11. Consent, handles, cosmetics
-- ---------------------------------------------------------------------------

-- Server-side, not shared_preferences: the server is what publishes, so the
-- server is what must be able to refuse.
create or replace function public.set_public_profile(p_value boolean)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if public.effective_tier(v_uid) = 'guest' then
    raise exception 'guest_not_eligible';
  end if;
  update public.profiles set public_profile = coalesce(p_value, false), updated_at = now()
   where id = v_uid;
  return coalesce(p_value, false);
end $$;

create or replace function public.claim_handle(p_handle text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_h   text := lower(trim(coalesce(p_handle, '')));
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  -- A handle is a permanent, globally unique, first-come name, which makes it
  -- the one thing here worth squatting. Gating it on premium is both the
  -- squat deterrent and a perk that costs nobody anything: a free account still
  -- appears on every board, it just does not get a page of its own.
  if public.effective_tier(v_uid) <> 'premium' then
    raise exception 'premium_required';
  end if;
  if v_h !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'invalid_handle';
  end if;
  -- Reserved so a handle can never shadow a website route.
  if v_h = any (array['admin','api','auth','join','premium','pricing','download','faq',
                      'terms','privacy','refund','changelog','account','leaderboard',
                      'wrapped','u','r','internal','support','help','about','app',
                      'synctogether','root','system','null','undefined']) then
    raise exception 'handle_reserved';
  end if;
  if exists (select 1 from public.profiles where lower(handle) = v_h and id <> v_uid) then
    raise exception 'handle_taken';
  end if;
  update public.profiles set handle = v_h, updated_at = now() where id = v_uid;
  return v_h;
end $$;

-- Cosmetics only, and validated here rather than trusted from the client: the
-- frame must have been unlocked, or be the one Premium wears by right.
create or replace function public.equip_frame(p_frame text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_f   text := nullif(lower(trim(coalesce(p_frame, ''))), '');
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if v_f is not null
     and not (v_f = 'aurum' and public.effective_tier(v_uid) = 'premium')
     and not exists (
       select 1 from public.user_achievements ua
         join public.achievements a on a.id = ua.achievement_id
        where ua.user_id = v_uid and (a.reward ->> 'frame') = v_f) then
    raise exception 'frame_locked';
  end if;
  update public.profiles set equipped_frame = v_f, updated_at = now() where id = v_uid;
  return v_f;
end $$;

create or replace function public.mark_achievements_seen(p_ids text[] default null)
returns void
language sql security definer set search_path = ''
as $$
  update public.user_achievements set seen = true
   where user_id = auth.uid()
     and not seen
     and (p_ids is null or achievement_id = any (p_ids));
$$;

-- ---------------------------------------------------------------------------
-- 12. Shareable recaps
-- ---------------------------------------------------------------------------

-- A person as a public recap is allowed to describe them. Someone who has not
-- opted in appears as their avatar gradient and nothing else - a recap is a
-- public URL, and it must not out a co-watcher who never agreed to be named.
-- The gradient seed is a hash, never the user id: public pages do not carry
-- account identifiers.
create or replace function public.recap_person(p_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select case
    when p.public_profile then jsonb_build_object(
      'seed',    substr(md5(p.id::text), 1, 8),
      'name',    p.display_name,
      'avatar',  p.avatar_url,
      'handle',  p.handle,
      'frame',   p.equipped_frame,
      'premium', public.effective_tier(p.id) = 'premium',
      'public',  true)
    else jsonb_build_object(
      'seed',   substr(md5(p.id::text), 1, 8),
      'public', false)
  end
  from public.profiles p where p.id = p_id;
$$;

create or replace function public.create_recap(
  p_room_id       uuid,
  p_seconds       int,
  p_peak_members  int default 0,
  p_messages      int default 0,
  p_reactions     int default 0,
  p_top_emoji     text default null,
  p_modes         text[] default '{}',
  p_facecam       boolean default false,
  p_clean_gate    boolean default false,
  p_participants  uuid[] default '{}',
  p_superlatives  jsonb default '[]'::jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms;
  v_id    text;
  v_day   date := (now() at time zone 'utc')::date;
  v_secs  int;
  v_msgs  int;
  v_rx    int;
  v_modes text[];
  v_host  boolean := false;
  v_people jsonb;
  v_supers jsonb;
  v_existing text;
  v_payload jsonb;
  v_r     public.user_rewards;
  v_metrics jsonb;
  v_unlocked jsonb := '[]'::jsonb;
  v_emoji text;
  v_earned int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if public.effective_tier(v_uid) = 'guest' then
    raise exception 'guest_not_eligible';
  end if;

  select * into v_room from public.rooms where id = p_room_id;

  -- Eligibility survives leaving: `leave_room` deletes the membership row, and
  -- sharing happens after the exit. The ledger is the durable proof that this
  -- account really was in this room.
  if not exists (select 1 from public.room_members
                  where room_id = p_room_id and user_id = v_uid)
     and not exists (select 1 from public.watch_day_rooms
                      where user_id = v_uid and room_id = p_room_id
                        and day >= v_day - 2) then
    raise exception 'not_a_member';
  end if;

  select exists (
    select 1 from public.room_members
     where room_id = p_room_id and user_id = v_uid and role = 'host')
     or coalesce(v_room.created_by = v_uid, false)
  into v_host;

  v_secs  := greatest(0, least(coalesce(p_seconds, 0), 86400));

  -- `reactions_sent` and `messages_sent` are the only achievement metrics a
  -- client supplies rather than the server computing, and "Hype Machine" (500
  -- reactions) and "Chatterbox" (1,000 messages) sit exactly at the per-share
  -- caps - so a single crafted call unlocked both. The counters are therefore
  -- additionally rated against the seconds this account was *credited* in this
  -- room, which comes from `watch_day_rooms` and cannot be argued with. An
  -- honest session is nowhere near the rate ceiling (a 90-minute sitting allows
  -- ~1,080 reactions, so the config cap is what binds); a fabricated one has no
  -- credited seconds and therefore banks nothing.
  select coalesce(sum(seconds), 0) into v_earned
    from public.watch_day_rooms where user_id = v_uid and room_id = p_room_id;

  v_msgs  := greatest(0, least(coalesce(p_messages, 0),
                               public.reward_setting('recap_max_messages', 1000)::int,
                               v_earned / 3));
  v_rx    := greatest(0, least(coalesce(p_reactions, 0),
                               public.reward_setting('recap_max_reactions', 500)::int,
                               v_earned / 5));
  v_modes := array(select unnest(coalesce(p_modes, '{}')) intersect select unnest(array['local','youtube']));
  v_emoji := case when char_length(coalesce(p_top_emoji, '')) between 1 and 8
                  then p_top_emoji else null end;

  -- Participants: only ids that genuinely shared a room with this account.
  -- Named people first, then a stable tiebreak: a public page must render the
  -- same order every time it is opened, and the anonymous avatars belong after
  -- the people the card can actually introduce.
  select coalesce(jsonb_agg(public.recap_person(x.id) order by x.ord, x.id), '[]'::jsonb)
    into v_people
    from (
      select distinct u.id,
             (select case when p.public_profile then 0 else 1 end
                from public.profiles p where p.id = u.id) as ord
        from unnest(coalesce(p_participants, '{}')) as u(id)
       where u.id <> v_uid
         and (exists (select 1 from public.room_members m
                       where m.room_id = p_room_id and m.user_id = u.id)
              or exists (select 1 from public.co_watchers c
                          where c.user_id = v_uid and c.other_id = u.id))
       limit 16
    ) x;

  -- Superlatives are an allow-list. The client picks the winner; it does not
  -- get to invent the award.
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', s.key, 'person', public.recap_person(s.uid))), '[]'::jsonb)
    into v_supers
    from (
      select (e ->> 'key') as key, (e ->> 'user_id')::uuid as uid
        from jsonb_array_elements(coalesce(p_superlatives, '[]'::jsonb)) as e
       where (e ->> 'key') = any (array['reactions','chat','steady','pauser',
                                        'night_owl','ride_or_die','host','first_in','camera'])
         and (e ->> 'user_id') is not null
       limit 6
    ) s
   where exists (select 1 from public.profiles pr where pr.id = s.uid);

  v_payload := jsonb_build_object(
    'v', 1,
    'room_name', case when v_host then left(coalesce(v_room.name, 'Watch party'), 40) else null end,
    'seconds', v_secs,
    'peak_members', greatest(0, least(coalesce(p_peak_members, 0), 64)),
    'messages', v_msgs,
    'reactions', v_rx,
    'top_emoji', v_emoji,
    'modes', to_jsonb(v_modes),
    'facecam', coalesce(p_facecam, false),
    'owner', public.recap_person(v_uid),
    'people', v_people,
    'superlatives', v_supers,
    'ended_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));

  v_id := substr(md5(random()::text || clock_timestamp()::text), 1, 12)
          || substr(md5(random()::text || v_uid::text), 1, 10);

  insert into public.recaps (id, owner_id, room_id, day, expires_at, payload)
  values (v_id, v_uid, p_room_id, v_day,
          now() + make_interval(days => public.reward_setting('recap_ttl_days', 90)::int),
          v_payload)
  -- Re-sharing hands back the page that already exists rather than rebuilding
  -- it. The session is over; a second call has nothing newer to say, and a
  -- second call made with fewer arguments would quietly degrade the recap.
  on conflict (owner_id, room_id, day) do update set expires_at = excluded.expires_at
  returning id into v_existing;

  -- Counters credit once per session, on the first share only: the unique index
  -- above is what makes a second share an update rather than a second credit.
  if v_existing = v_id then
    insert into public.user_rewards (user_id) values (v_uid) on conflict do nothing;
    update public.user_rewards set
      reactions_sent      = public.user_rewards.reactions_sent + v_rx,
      messages_sent       = public.user_rewards.messages_sent + v_msgs,
      clean_gate_sessions = public.user_rewards.clean_gate_sessions
                            + (case when coalesce(p_clean_gate, false) then 1 else 0 end),
      updated_at          = now()
     where user_id = v_uid
    returning * into v_r;

    v_metrics := jsonb_build_object(
      'total_seconds', v_r.total_seconds, 'current_streak', v_r.current_streak,
      'longest_streak', v_r.longest_streak, 'total_sessions', v_r.total_sessions,
      'total_hosted', v_r.total_hosted,
      'longest_session_seconds', v_r.longest_session_seconds,
      'max_room_members', v_r.max_room_members,
      'distinct_co_watchers', v_r.distinct_co_watchers, 'days_active', v_r.days_active,
      'double_feature_days', v_r.double_feature_days,
      'night_owl_sessions', v_r.night_owl_sessions,
      'clean_gate_sessions', v_r.clean_gate_sessions,
      'reactions_sent', v_r.reactions_sent, 'messages_sent', v_r.messages_sent);
    v_unlocked := public.grant_achievements(v_uid, v_metrics);
  end if;

  return jsonb_build_object('id', v_existing, 'unlocked', v_unlocked);
end $$;

-- ---------------------------------------------------------------------------
-- 13. Referral: credited at the join, never at the install
-- ---------------------------------------------------------------------------

-- Desktop has no install-referrer, so attribution at download is not buildable.
-- This is the thing that *is* knowable and unfakeable: the room a brand-new
-- account first walked into belonged to somebody, and that somebody brought
-- them. Set once, never overwritten.
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

  select * into v_room from public.rooms where code = upper(trim(p_code));
  if not found then
    raise exception 'room_not_found';
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

create or replace function public.my_referrals()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'total', (select count(*) from public.profiles where referred_by = auth.uid()),
    'joined_since', (select count(*) from public.profiles
                      where referred_by = auth.uid() and created_at > now() - interval '30 days'));
$$;

-- ---------------------------------------------------------------------------
-- 14. Website reads (service_role only - no anon surface at all)
-- ---------------------------------------------------------------------------

create or replace function public.public_recap(p_id text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_row public.recaps;
begin
  select * into v_row from public.recaps where id = p_id and expires_at > now();
  if not found then return null; end if;
  update public.recaps set views = views + 1 where id = p_id;
  return v_row.payload || jsonb_build_object('id', v_row.id, 'created_at', v_row.created_at);
end $$;

create or replace function public.public_leaderboard(
  p_period text default 'week', p_limit int default 100)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select case when not public.leaderboard_open() then
    jsonb_build_object('open', false, 'rows', '[]'::jsonb)
  else
    jsonb_build_object('open', true, 'period', coalesce(p_period, 'week'), 'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'rank', x.rn, 'name', x.display_name, 'avatar', x.avatar_url,
               'handle', x.handle, 'frame', x.equipped_frame, 'premium', x.premium,
               'points', x.pts, 'streak', x.streak) order by x.rn)
        from (
          select row_number() over (order by sum(l.points) desc,
                                             sum(l.credited_seconds) desc,
                                             p.created_at asc) as rn,
                 p.display_name, p.avatar_url, p.handle, p.equipped_frame,
                 public.effective_tier(p.id) = 'premium' as premium,
                 sum(l.points)::bigint as pts,
                 public.effective_streak(ur.current_streak, ur.last_credited_day,
                                         ur.freezes_available,
                                         (now() at time zone 'utc')::date) as streak
            from public.watch_ledger l
            join public.profiles p on p.id = l.user_id
            left join public.user_rewards ur on ur.user_id = l.user_id
           where p.public_profile and l.day >= public.reward_period_start(p_period)
           group by p.id, p.display_name, p.avatar_url, p.handle, p.equipped_frame,
                    p.created_at, ur.current_streak, ur.last_credited_day, ur.freezes_available
          having sum(l.points) > 0
           order by pts desc
           limit least(greatest(coalesce(p_limit, 100), 1), 200)
        ) x), '[]'::jsonb))
  end;
$$;

create or replace function public.public_wrapped(p_handle text, p_year int)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'year', p_year,
    'handle', p.handle,
    'name', p.display_name,
    'avatar', p.avatar_url,
    'seconds', coalesce((select sum(credited_seconds) from public.watch_ledger
                          where user_id = p.id
                            and day >= make_date(p_year, 1, 1)
                            and day <= make_date(p_year, 12, 31)), 0),
    'days', coalesce((select count(*) from public.watch_ledger
                       where user_id = p.id and credited_seconds > 0
                         and day >= make_date(p_year, 1, 1)
                         and day <= make_date(p_year, 12, 31)), 0),
    'points', coalesce((select sum(points) from public.watch_ledger
                         where user_id = p.id
                           and day >= make_date(p_year, 1, 1)
                           and day <= make_date(p_year, 12, 31)), 0),
    'longest_streak', coalesce(ur.longest_streak, 0),
    'top_co_watchers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', case when o.public_profile then o.display_name else null end,
               'avatar', case when o.public_profile then o.avatar_url else null end,
               'seed', substr(md5(o.id::text), 1, 8),
               'hours', round(c.seconds / 3600.0, 1)) order by c.seconds desc)
        from (select * from public.co_watchers where user_id = p.id
               order by seconds desc limit 5) c
        join public.profiles o on o.id = c.other_id), '[]'::jsonb),
    'badges', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'icon', a.icon,
                                          'grade', a.grade) order by ua.unlocked_at)
        from public.user_achievements ua
        join public.achievements a on a.id = ua.achievement_id
       where ua.user_id = p.id
         and ua.unlocked_at >= make_date(p_year, 1, 1)
         and ua.unlocked_at < make_date(p_year + 1, 1, 1)), '[]'::jsonb))
    from public.profiles p
    left join public.user_rewards ur on ur.user_id = p.id
   where lower(p.handle) = lower(trim(coalesce(p_handle, ''))) and p.public_profile;
$$;

-- ---------------------------------------------------------------------------
-- 15. Housekeeping
-- ---------------------------------------------------------------------------

create or replace function public.sweep_rewards()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_keep int := public.reward_setting('ledger_retention_days', 400)::int;
begin
  delete from public.recaps where expires_at < now();
  delete from public.watch_day_rooms where day < (now() at time zone 'utc')::date - v_keep;
  delete from public.co_watch_daily  where day < (now() at time zone 'utc')::date - 35;
  delete from public.watch_heartbeats where last_at < now() - interval '2 days';
end $$;

select cron.schedule('sweep-rewards', '19 4 * * *', $$ select public.sweep_rewards(); $$);

-- ---------------------------------------------------------------------------
-- 16. Grants
-- ---------------------------------------------------------------------------

revoke execute on function
  public.reward_setting(text, numeric),
  public.reward_flag(text, boolean),
  public.reward_points(int, int, int, int),
  public.record_watch_progress(uuid, date, int),
  public.grant_achievements(uuid, jsonb),
  public.leaderboard_open(),
  public.leaderboard(text, text, int),
  public.my_rank(text, text),
  public.my_rewards(),
  public.set_public_profile(boolean),
  public.claim_handle(text),
  public.equip_frame(text),
  public.mark_achievements_seen(text[]),
  public.recap_person(uuid),
  public.create_recap(uuid, int, int, int, int, text, text[], boolean, boolean, uuid[], jsonb),
  public.my_referrals(),
  public.public_recap(text),
  public.public_leaderboard(text, int),
  public.public_wrapped(text, int),
  public.sweep_rewards()
from public, anon, authenticated;

grant execute on function
  public.record_watch_progress(uuid, date, int),
  public.leaderboard_open(),
  public.leaderboard(text, text, int),
  public.my_rank(text, text),
  public.my_rewards(),
  public.set_public_profile(boolean),
  public.claim_handle(text),
  public.equip_frame(text),
  public.mark_achievements_seen(text[]),
  public.create_recap(uuid, int, int, int, int, text, text[], boolean, boolean, uuid[], jsonb),
  public.my_referrals()
to authenticated;

-- Website-only reads. No anon grant anywhere: the marketing site talks to
-- Supabase with the service role, exactly as website/lib/public-metrics.ts does.
grant execute on function
  public.public_recap(text),
  public.public_leaderboard(text, int),
  public.public_wrapped(text, int)
to service_role;

-- `streak_multiplier`, `effective_streak` and `reward_period_start` are pure and
-- carry no data, so they stay readable - the scoring rule is published on the
-- board itself and there is nothing to hide.
grant execute on function
  public.streak_multiplier(int),
  public.effective_streak(int, date, int, date),
  public.reward_period_start(text)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 17. Cosmetics in the room
-- ---------------------------------------------------------------------------

-- Extended rather than joined by a second RPC: this already answers the whole
-- room in one round trip, and a frame is exactly the same kind of fact as a
-- crown. Presence was considered for this and rejected for the same reason it
-- was rejected for tiers - it is self-reported, so any client could wear any
-- frame, and the presence budget is 5 calls per 30 seconds with the whole
-- channel at stake.
--
-- Note the trap: `returns table` cannot be changed by `create or replace`, so
-- this drops first - and a drop takes the grants with it. The re-grant below is
-- not optional, and 07_grants_test.sql is what catches its absence.
drop function if exists public.room_member_tiers(uuid);

create function public.room_member_tiers(p_room_id uuid)
returns table (user_id uuid, tier text, frame text)
language sql stable security definer set search_path = ''
as $$
  select m.user_id, public.effective_tier(m.user_id), p.equipped_frame
  from public.room_members m
  join public.profiles p on p.id = m.user_id
  where m.room_id = p_room_id
    and auth.uid() is not null
    and exists (
      select 1 from public.room_members me
      where me.room_id = p_room_id and me.user_id = auth.uid()
    );
$$;

revoke execute on function public.room_member_tiers(uuid) from public, anon;
grant execute on function public.room_member_tiers(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 18. Seasons
-- ---------------------------------------------------------------------------

-- A permanent trophy for a temporary achievement, which is what makes anybody
-- care about a temporary achievement. The weekly board resets and is forgotten;
-- a season placing is kept forever and shows on the public profile.
--
-- Deliberately NOT modelled as an `achievements` row: that table's whole shape
-- is `metric >= threshold`, and a placing is neither.
create table public.seasons (
  id        text primary key,                 -- 'YYYY-MM'
  starts_on date not null,
  ends_on   date not null,
  closed_at timestamptz,
  constraint seasons_range_chk check (ends_on >= starts_on)
);

create table public.season_awards (
  season_id  text not null references public.seasons (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  rank       int  not null check (rank between 1 and 3),
  points     bigint not null,
  awarded_at timestamptz not null default now(),
  primary key (season_id, user_id)
);

create index season_awards_user_idx on public.season_awards (user_id, season_id desc);

alter table public.seasons enable row level security;
alter table public.season_awards enable row level security;

create policy "seasons are readable by signed-in users"
  on public.seasons for select to authenticated using (true);

-- Placings are published facts about people who opted in; a non-consenting
-- account cannot place at all, so there is nothing here to leak.
create policy "season placings are readable by signed-in users"
  on public.season_awards for select to authenticated using (true);

revoke insert, update, delete on public.seasons, public.season_awards
  from public, anon, authenticated;
grant select on public.seasons, public.season_awards to authenticated;
grant all on public.seasons, public.season_awards to service_role;

insert into public.reward_config (key, value) values
  ('seasons_enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- Closes exactly one month: the one that just ended.
--
-- Never catches up. A run that was disabled, or a stack that was down for a
-- month, simply skips it - the alternative is a cron that one day mints a year
-- of trophies at once, and a trophy handed out cannot be taken back.
create or replace function public.close_seasons()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_start date := (date_trunc('month', (now() at time zone 'utc')) - interval '1 month')::date;
  v_end   date := (date_trunc('month', (now() at time zone 'utc')) - interval '1 day')::date;
  v_id    text := to_char(v_start, 'YYYY-MM');
begin
  if not public.reward_flag('seasons_enabled', false) then
    return;
  end if;
  if exists (select 1 from public.seasons where id = v_id and closed_at is not null) then
    return;
  end if;

  insert into public.seasons (id, starts_on, ends_on)
  values (v_id, v_start, v_end)
  on conflict (id) do nothing;

  -- The participation floor applies here too: a podium picked from four people
  -- is not a podium. The season still closes, with nobody on it, so the cron
  -- does not retry it forever.
  if (
    select count(distinct l.user_id)
      from public.watch_ledger l
      join public.profiles p on p.id = l.user_id
     where p.public_profile and l.day between v_start and v_end and l.points > 0
  ) >= public.reward_setting('leaderboard_min_participants', 30) then
    insert into public.season_awards (season_id, user_id, rank, points)
    select v_id, x.user_id, x.rn::int, x.pts
      from (
        select l.user_id,
               sum(l.points) as pts,
               row_number() over (
                 order by sum(l.points) desc,
                          sum(l.credited_seconds) desc,
                          p.created_at asc) as rn
          from public.watch_ledger l
          join public.profiles p on p.id = l.user_id
         where p.public_profile and l.day between v_start and v_end
         group by l.user_id, p.created_at
        having sum(l.points) > 0
      ) x
     where x.rn <= 3
    on conflict (season_id, user_id) do nothing;
  end if;

  update public.seasons set closed_at = now() where id = v_id;
end $$;

select cron.schedule('close-seasons', '23 5 * * *', $$ select public.close_seasons(); $$);

create or replace function public.my_season_awards()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select jsonb_agg(jsonb_build_object(
             'season', a.season_id, 'rank', a.rank, 'points', a.points)
           order by a.season_id desc)
      from public.season_awards a
     where a.user_id = auth.uid()), '[]'::jsonb);
$$;

revoke execute on function public.close_seasons(), public.my_season_awards()
  from public, anon, authenticated;
grant execute on function public.my_season_awards() to authenticated;

-- `language sql` bodies are validated when the function is created, so
-- `public_profile_card` is defined here after `season_awards` exists.
create or replace function public.public_profile_card(p_handle text)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'handle', p.handle,
    'name', p.display_name,
    'avatar', p.avatar_url,
    'frame', p.equipped_frame,
    'premium', public.effective_tier(p.id) = 'premium',
    'joined', to_char(p.created_at at time zone 'utc', 'YYYY-MM-DD'),
    'streak', public.effective_streak(ur.current_streak, ur.last_credited_day,
                                      ur.freezes_available, (now() at time zone 'utc')::date),
    'longest_streak', coalesce(ur.longest_streak, 0),
    'hours', round(coalesce(ur.total_seconds, 0) / 3600.0, 1),
    'sessions', coalesce(ur.total_sessions, 0),
    'co_watchers', coalesce(ur.distinct_co_watchers, 0),
    'points_week', (select coalesce(sum(points), 0) from public.watch_ledger
                     where user_id = p.id and day >= public.reward_period_start('week')),
    'badges', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title,
                                          'icon', a.icon, 'grade', a.grade)
             order by a.sort)
        from public.user_achievements ua
        join public.achievements a on a.id = ua.achievement_id
       where ua.user_id = p.id), '[]'::jsonb),
    'seasons', coalesce((
      select jsonb_agg(jsonb_build_object('season', sa.season_id, 'rank', sa.rank)
             order by sa.season_id desc)
        from public.season_awards sa where sa.user_id = p.id), '[]'::jsonb))
    from public.profiles p
    left join public.user_rewards ur on ur.user_id = p.id
   where lower(p.handle) = lower(trim(coalesce(p_handle, ''))) and p.public_profile;
$$;

revoke execute on function public.public_profile_card(text) from public, anon, authenticated;
grant execute on function public.public_profile_card(text) to service_role;

-- ---------------------------------------------------------------------------
-- 19. Taking a recap back
-- ---------------------------------------------------------------------------

-- A shared recap is a public URL. Somebody who changes their mind - about the
-- session, about the people on it, about having posted it at all - must be able
-- to make the link stop working, and must not have to wait 90 days for the
-- sweep to do it. Deletion is immediate and total: the row goes, so
-- `public_recap` answers null and the page 404s.
create or replace function public.delete_recap(p_id text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_deleted int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from public.recaps where id = p_id and owner_id = auth.uid();
  get diagnostics v_deleted = row_count;
  return v_deleted > 0;
end $$;

-- Everything the owner needs to decide what to take down: when, which room, and
-- how many people have opened it. Never the payload - the list is a management
-- screen, not a second copy of the page.
create or replace function public.my_recaps(p_limit int default 50)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id,
             'created_at', r.created_at,
             'expires_at', r.expires_at,
             'views', r.views,
             'room_name', r.payload ->> 'room_name',
             'seconds', (r.payload ->> 'seconds')::int,
             'people', jsonb_array_length(coalesce(r.payload -> 'people', '[]'::jsonb)))
           order by r.created_at desc)
      from (
        select * from public.recaps
         where owner_id = auth.uid() and expires_at > now()
         order by created_at desc
         limit least(greatest(coalesce(p_limit, 50), 1), 200)
      ) r), '[]'::jsonb);
$$;

revoke execute on function public.delete_recap(text), public.my_recaps(int)
  from public, anon, authenticated;
grant execute on function public.delete_recap(text), public.my_recaps(int)
  to authenticated;
