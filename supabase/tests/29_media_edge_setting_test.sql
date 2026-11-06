begin;
select plan(5);

select is((select value->>'enabled' from public.app_settings where key = 'media_edge'), 'false',
  'media_edge ships disabled');
select ok((select value->'base_url' = 'null'::jsonb from public.app_settings where key = 'media_edge'),
  'with no base_url');
select is((select (value->>'chunk_bytes')::int from public.app_settings where key = 'media_edge'), 8388608,
  'an 8 MiB chunk hint');
select is((select (value->>'max_parallel')::int from public.app_settings where key = 'media_edge'), 4,
  'and 4 parallel fetches');

set local role authenticated;
select is((select count(*)::int from public.app_settings where key = 'media_edge'), 0,
  'signed-in clients cannot read it');

select * from finish();
rollback;
