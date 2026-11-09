-- Migration: close two gaps the Supabase advisor found in the pairing migrations.
--
--   * pair_member_removed() is a trigger function. It is security definer and was
--     executable by PUBLIC, so anon and authenticated could reach it through the
--     API. A trigger needs no EXECUTE grant to fire, so nobody keeps one.
--   * pair_id_from_topic() was written without a pinned search_path and was
--     executable by anon. It is only read by the realtime policies, which run as
--     authenticated, so anon loses it and the path is pinned.

revoke execute on function public.pair_member_removed() from public, anon, authenticated;

create or replace function public.pair_id_from_topic(p_topic text)
returns uuid
language plpgsql immutable set search_path = ''
as $$
begin
  if p_topic is null or p_topic not like 'pair:%' then
    return null;
  end if;
  return substr(p_topic, 6)::uuid;
exception when others then
  return null;
end $$;

revoke execute on function public.pair_id_from_topic(text) from public, anon;
grant execute on function public.pair_id_from_topic(text) to authenticated;
