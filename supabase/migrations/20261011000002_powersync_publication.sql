-- PowerSync reads every change through Postgres logical replication, from a publication
-- that must be named "powersync". Without it, devices never receive any data.
-- History (activity_log) is not synced to devices, so it is left out.
-- Safe to run more than once (also run it after restoring a backup).
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    create publication powersync for table
      public.contractors, public.districts, public.cable_sizes, public.work_orders, public.permits,
      public.segments, public.meters, public.cable_runs, public.steps, public.hold_periods,
      public.attachments, public.followups, public.saved_views, public.settings;
    -- reminders joins it in 20261016000001_reminders.sql
  end if;
end $$;
