-- The pre-show check measures a connection against the real film before the
-- night starts. The media-share function signs the URL, but the pair tables are
-- RPC-only (service_role has no table grants), so the function asks here: which
-- staged object does this night hold, if the caller is one of its two people.
-- Service role only, like request_upload_slot: the caller id is trusted because
-- the function took it from a verified session.
create or replace function public.night_stream_source(p_user_id uuid, p_night_id uuid)
returns table (file_name text, file_size bigint, media_r2_key text, upload_state text)
language sql stable security definer set search_path = ''
as $$
  select n.file_name, n.file_size, n.media_r2_key, n.upload_state
    from public.date_nights n
    join public.pair_members m on m.pair_id = n.pair_id and m.user_id = p_user_id
   where n.id = p_night_id;
$$;

revoke execute on function public.night_stream_source(uuid, uuid) from public, anon, authenticated;
grant execute on function public.night_stream_source(uuid, uuid) to service_role;
