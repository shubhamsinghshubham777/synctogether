-- Three per-minute cron jobs (sweep_rooms, invoke_av_cleanup, close_video_trials)
-- each wrote a "starting" and a "completed" line to postgres_logs, ~8.6k rows a
-- day that say nothing. Hosted Supabase meters log ingestion, and that was ~28%
-- of all rows on the free plan. One job calling the three in turn writes two
-- lines a minute instead of six.
--
-- Each call keeps its own exception block, so one failing does not starve the
-- others - the isolation separate cron jobs used to give for free. Cadence is
-- unchanged: all three still run every minute.

create or replace function public.minutely_maintenance()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  begin
    perform public.sweep_rooms();
  exception when others then
    raise warning 'minutely_maintenance: sweep_rooms failed: %', sqlerrm;
  end;
  begin
    perform public.invoke_av_cleanup();
  exception when others then
    raise warning 'minutely_maintenance: invoke_av_cleanup failed: %', sqlerrm;
  end;
  begin
    perform public.close_video_trials();
  exception when others then
    raise warning 'minutely_maintenance: close_video_trials failed: %', sqlerrm;
  end;
end $$;

revoke all on function public.minutely_maintenance() from public, anon, authenticated;
grant execute on function public.minutely_maintenance() to service_role;

-- unschedule raises for a job that does not exist; each is independent.
do $$ begin perform cron.unschedule('sweep-rooms'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('invoke-av-cleanup'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('close-video-trials'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('minutely-maintenance'); exception when others then null; end $$;

select cron.schedule('minutely-maintenance', '* * * * *', $$ select public.minutely_maintenance(); $$);
