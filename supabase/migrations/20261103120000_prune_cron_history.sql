-- pg_cron logs one row per run into cron.job_run_details and never prunes it.
-- With minutely-maintenance (and the 5-minute R2 job) that is ~1,700 rows a
-- day: it had grown to ~40 MB, over half the database. The history is only
-- ever read to debug a recent failure, so keep two days and drop the rest
-- nightly.

do $$ begin perform cron.unschedule('prune-cron-history'); exception when others then null; end $$;

select cron.schedule(
  'prune-cron-history', '17 3 * * *',
  $$ delete from cron.job_run_details where end_time < now() - interval '2 days' $$);

-- One-off: a DELETE only frees space for reuse, it does not shrink the file, so
-- the 40 MB would stay on disk. Truncating gives it back now. Where the role
-- may not truncate, fall back to the delete (growth still stops).
do $$
begin
  truncate table cron.job_run_details;
exception when others then
  delete from cron.job_run_details where end_time < now() - interval '2 days';
end $$;
