-- Storage & Quotas telemetry helper for admin mission control
create or replace function public.get_system_storage_stats()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_db_bytes bigint;
  v_r2_7d_bytes bigint;
  v_active_r2_media_bytes bigint;
begin
  -- Only service_role can call this
  if auth.role() <> 'service_role' then
    raise exception 'Unauthorized: service_role required';
  end if;

  select pg_database_size(current_database()) into v_db_bytes;
  select coalesce(sum(r2_upload_bytes_7d), 0) from public.profiles into v_r2_7d_bytes;
  select coalesce(sum(media_file_size), 0) from public.rooms
    where ended_at is null and expires_at > now() and media_upload_state = 'ready'
    into v_active_r2_media_bytes;

  return jsonb_build_object(
    'db_bytes', v_db_bytes,
    'r2_upload_bytes_7d', v_r2_7d_bytes,
    'active_r2_media_bytes', v_active_r2_media_bytes
  );
end;
$$;

revoke all on function public.get_system_storage_stats() from public, anon, authenticated;
grant execute on function public.get_system_storage_stats() to service_role;
