begin;
select plan(3);

-- Referral credit goes to the host of the first room a *new* account joins; an
-- established account walking into a friend's room is nobody's referral.

insert into auth.users (id, is_anonymous, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d1', false, 'host@example.test',  '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000d2', false, 'new@example.test',   '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000d3', false, 'older@example.test', '{}'::jsonb);
update public.profiles set created_at = now() - interval '30 days'
 where id = '00000000-0000-0000-0000-0000000000d3';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1"}', true);
create temp table made on commit drop as select code from public.create_room('Referral', 60);
grant select on made to authenticated;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d2"}', true);
select public.join_room((select code from made));
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d3"}', true);
select public.join_room((select code from made));

reset role;
select is((select referred_by from public.profiles where id = '00000000-0000-0000-0000-0000000000d2'),
  '00000000-0000-0000-0000-0000000000d1'::uuid, 'a new account is credited to the room it joined');
select is((select referred_by from public.profiles where id = '00000000-0000-0000-0000-0000000000d3'),
  null, 'an established account is not');
select is((select referred_by from public.profiles where id = '00000000-0000-0000-0000-0000000000d1'),
  null, 'and the host is nobody''s referral');

select * from finish();
rollback;
