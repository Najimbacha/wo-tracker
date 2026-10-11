-- Data health: how full the database is against the free plan's 500 MB.
-- Above 500 MB Supabase makes the project read-only, so the app's Data health screen
-- and the nightly backup both warn at 80%. Safe to run more than once.
create or replace function public.data_health() returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'limit_bytes', 500 * 1024 * 1024,
    'warn_percent', 80,
    'percent', round(100.0 * pg_database_size(current_database()) / (500 * 1024 * 1024), 1),
    'largest_tables', (
      select coalesce(jsonb_object_agg(name, bytes), '{}'::jsonb) from (
        select c.relname as name, pg_total_relation_size(c.oid) as bytes
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relkind = 'r'
        order by 2 desc limit 5
      ) t),
    'orders', (select count(*) from public.work_orders where deleted_at is null),
    'history_rows', (select count(*) from public.activity_log)
  )
$$;
revoke all on function public.data_health() from public, anon;
grant execute on function public.data_health() to authenticated;
