-- Run after restoring a backup into a new Supabase project (backups are taken with --no-acl,
-- so table permissions must be re-applied). Security policies and triggers are restored
-- with the backup itself; this only re-applies who may read and write. Safe to run twice.
do $$
declare t text;
begin
  foreach t in array array['contractors', 'districts', 'cable_sizes', 'work_orders', 'permits', 'segments', 'meters',
                           'cable_runs', 'steps', 'hold_periods', 'attachments', 'followups', 'saved_views', 'settings'] loop
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke delete, truncate on public.%I from authenticated', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
  end loop;
end $$;
revoke all on public.activity_log from anon;
revoke insert, update, delete, truncate on public.activity_log from authenticated;
grant select on public.activity_log to authenticated;
revoke usage on sequence public.activity_log_id_seq from authenticated, anon;

-- Data health (migration 3).
revoke all on function public.data_health() from public, anon;
grant execute on function public.data_health() to authenticated;
