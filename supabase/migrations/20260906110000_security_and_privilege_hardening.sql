-- Security Hardening & Privilege Lockdown
-- 1. Revoke execute on security definer staged upload RPCs from PUBLIC/anon/authenticated
-- 2. Revoke table DML on public.rooms, tier_limits, subscriptions from anon/authenticated
-- 3. Lock down debug_grant_premium to local development only
-- 4. Align request_upload_slot free max fallback to 2.0 GB (2,147,483,648 bytes) and revoke public execute

-- 1. Revoke execute privileges on staged upload RPCs
revoke execute on function public.request_staged_upload_slot(uuid, bigint, text, bigint, text, text) from public, anon, authenticated;
grant execute on function public.request_staged_upload_slot(uuid, bigint, text, bigint, text, text) to service_role;

revoke execute on function public.set_staged_upload_state(uuid, uuid, text, bigint, text, bigint) from public, anon, authenticated;
grant execute on function public.set_staged_upload_state(uuid, uuid, text, bigint, text, bigint) to service_role;

revoke execute on function public.clear_staged_upload(uuid, bigint) from public, anon, authenticated;
grant execute on function public.clear_staged_upload(uuid, bigint) to service_role;

-- 2. Revoke table-level DML on rooms, tier_limits, subscriptions
revoke insert, update, delete on public.rooms from public, anon, authenticated;
revoke update, delete on public.tier_limits from public, anon, authenticated;
revoke insert, update, delete on public.subscriptions from public, anon, authenticated;

grant select on public.rooms to authenticated;
grant select on public.tier_limits to authenticated;
grant select on public.subscriptions to authenticated;

-- 3. Lock down debug_grant_premium to local stack only
create or replace function public.debug_grant_premium(p_months int default 1)
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- Gate: only allow on local development stack when explicitly permitted.
  if coalesce(current_setting('app.settings.is_local', true), '') <> 'true' then
    raise exception 'debug_grant_premium is only available on the local stack';
  end if;

  insert into public.subscriptions (user_id, tier, source, current_period_end)
  values (auth.uid(), 'premium', 'debug', now() + make_interval(months => p_months))
  on conflict (user_id) do update
    set tier = 'premium',
        source = 'debug',
        current_period_end = excluded.current_period_end,
        updated_at = now();
end;
$$;

revoke execute on function public.debug_grant_premium(int) from public, anon;
grant execute on function public.debug_grant_premium(int) to authenticated;

-- 4. Align request_upload_slot free max fallback to 2.0 GB (2,147,483,648 bytes)
create or replace function public.request_upload_slot(
  p_room_id uuid,
  p_user_id uuid,
  p_file_size bigint,
  p_r2_key text,
  p_upload_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_room public.rooms;
  v_profile public.profiles;
  v_settings jsonb;
  v_enabled boolean;
  v_free_max bigint;
  v_premium_max bigint;
  v_tier text;
  v_limits public.tier_limits;
  v_weekly_limit bigint;
begin
  if p_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if v_room.id is null or not public.is_room_live(p_room_id) then
    raise exception 'room_ended';
  end if;

  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_user_id and role = 'host'
  ) then
    raise exception 'not_host';
  end if;

  if v_room.media_kind != 'local' or v_room.media_name is null then
    raise exception 'invalid_media';
  end if;

  select value into v_settings from public.app_settings where key = 'media_sharing';
  v_enabled := coalesce((v_settings->>'enabled')::boolean, true);
  if not v_enabled then
    raise exception 'media_sharing_disabled';
  end if;

  v_free_max := coalesce((v_settings->>'free_tier_max_file_bytes')::bigint, 2147483648);
  v_premium_max := coalesce((v_settings->>'premium_max_file_bytes')::bigint, 10737418240);

  v_tier := public.effective_tier(p_user_id);
  select * into v_limits from public.tier_limits where tier = v_tier;

  if v_limits.media_sharing = 'none' then
    raise exception 'media_sharing_disabled';
  end if;

  if p_file_size is null or p_file_size <= 0 then
    raise exception 'invalid_file_size';
  end if;

  if v_limits.media_sharing = 'limited' and p_file_size > v_free_max then
    raise exception 'upload_quota_exceeded';
  elsif v_limits.media_sharing = 'full' and p_file_size > v_premium_max then
    raise exception 'upload_quota_exceeded';
  end if;

  -- Lock profile row
  select * into v_profile from public.profiles where id = p_user_id for update;

  if v_profile.r2_cooldown_until is not null and v_profile.r2_cooldown_until > now() then
    raise exception 'upload_cooldown_active';
  end if;

  -- Multi-Factor Stale Lock Auto-Clearing
  if v_profile.active_upload_room_id is not null and v_profile.active_upload_room_id != p_room_id then
    declare
      v_prev_live boolean := public.is_room_live(v_profile.active_upload_room_id);
      v_prev_state text;
      v_prev_host boolean;
    begin
      select media_upload_state into v_prev_state from public.rooms where id = v_profile.active_upload_room_id;
      select exists(
        select 1 from public.room_members
        where room_id = v_profile.active_upload_room_id and user_id = p_user_id and role = 'host'
      ) into v_prev_host;

      if (not v_prev_live)
         or (v_prev_state is distinct from 'uploading')
         or (not v_prev_host)
         or (v_profile.active_upload_started_at < now() - interval '30 minutes') then
        update public.profiles set active_upload_room_id = null, active_upload_started_at = null where id = p_user_id;
      else
        raise exception 'active_upload_in_progress';
      end if;
    end;
  end if;

  -- Orphaned Multipart Cleanup on Same-Room Re-upload
  if v_room.media_upload_id is not null and v_room.media_upload_id != p_upload_id then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);
  end if;

  -- Weekly Quota Check for limited tier
  if v_limits.media_sharing = 'limited' then
    v_weekly_limit := v_limits.media_sharing_weekly_bytes;
    if v_profile.r2_upload_window_start < now() - interval '7 days' then
      update public.profiles
      set r2_upload_window_start = now(), r2_upload_bytes_7d = 0
      where id = p_user_id;
      v_profile.r2_upload_bytes_7d := 0;
    end if;

    if v_profile.r2_upload_bytes_7d + p_file_size > v_weekly_limit then
      raise exception 'upload_quota_exceeded';
    end if;
  end if;

  update public.profiles set
    active_upload_room_id = p_room_id,
    active_upload_started_at = now()
  where id = p_user_id;

  update public.rooms set
    media_upload_state = 'uploading',
    media_file_size = p_file_size,
    media_r2_key = p_r2_key,
    media_upload_id = p_upload_id
  where id = p_room_id;
end;
$$;

revoke execute on function public.request_upload_slot(uuid, uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.request_upload_slot(uuid, uuid, bigint, text, text) to service_role;
