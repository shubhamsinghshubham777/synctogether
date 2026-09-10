-- Ensure delete_account cleans up user storage objects (avatars) before cascading user deletion.
create or replace function public.delete_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Delete user's avatar from storage if it exists
  delete from storage.objects
  where bucket_id = 'avatars' and (name = uid::text || '.jpg' or owner = uid);

  -- Delete auth user, which cascades to profiles, rooms, room_members, messages, subscriptions
  delete from auth.users where id = uid;
end $$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
