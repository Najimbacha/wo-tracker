-- Minimal stand-in for what Supabase provides, so the migration can be tested on plain Postgres.
-- Safe to run more than once on the same server.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
create schema if not exists auth;
grant usage on schema auth to anon, authenticated;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'public') then
    grant usage on schema public to anon, authenticated;
  end if;
end $$;
