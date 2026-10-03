-- Clients never write `staged_media_uploads`; only the media-share Edge
-- Function does, as service_role. The owner-scoped update/delete policies
-- made the row the user's to edit, which meant a free account could flip its
-- own row to `ready`, push `expires_at` out, shrink `file_size` or repoint
-- `r2_key` at any object in the bucket, then claim it through
-- `create_room(..., p_staged_id)` - skipping the upload, the per-file cap and
-- the weekly quota, and streaming somebody else's video into their room.
drop policy if exists staged_media_update_own on public.staged_media_uploads;
drop policy if exists staged_media_delete_own on public.staged_media_uploads;
revoke insert, update, delete, truncate on public.staged_media_uploads from public, anon, authenticated;
grant select on public.staged_media_uploads to authenticated;

-- TRUNCATE ignores RLS. PostgREST does not expose it, so this is defence in
-- depth, but no client role has any business holding it on any table.
do $$
declare
  t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('revoke truncate on public.%I from public, anon, authenticated', t.tablename);
  end loop;
end $$;

-- A staged upload is debited once, on the `uploading -> ready` edge. Applying
-- `ready` again (a replayed complete) must not re-stamp the row.
create or replace function public.set_staged_upload_state(
  p_staged_id uuid,
  p_user_id uuid,
  p_state text,
  p_file_size bigint default null,
  p_r2_key text default null,
  p_bytes_uploaded bigint default 0)
returns void
language plpgsql security definer set search_path to 'public', 'auth'
as $$
declare
  v_staged public.staged_media_uploads%rowtype;
begin
  select * into v_staged from public.staged_media_uploads
  where id = p_staged_id and user_id = p_user_id
  for update;

  if v_staged.id is null or v_staged.upload_state <> 'uploading' then
    return;
  end if;

  update public.staged_media_uploads set
    upload_state = p_state,
    upload_id = case when p_state = 'ready' then null else upload_id end,
    file_size = coalesce(p_file_size, file_size),
    r2_key = coalesce(p_r2_key, r2_key)
  where id = p_staged_id;

  if p_state = 'ready' then
    update public.profiles set
      r2_upload_bytes_7d = r2_upload_bytes_7d + coalesce(p_file_size, v_staged.file_size),
      r2_consecutive_aborts = 0,
      active_upload_staged_id = null,
      active_upload_started_at = null
    where id = p_user_id;
  elsif p_state = 'failed' then
    update public.profiles set
      r2_upload_bytes_7d = r2_upload_bytes_7d + p_bytes_uploaded,
      active_upload_staged_id = null,
      active_upload_started_at = null
    where id = p_user_id;
  end if;
end $$;

revoke execute on function public.set_staged_upload_state(uuid, uuid, text, bigint, text, bigint) from public, anon, authenticated;
grant execute on function public.set_staged_upload_state(uuid, uuid, text, bigint, text, bigint) to service_role;
