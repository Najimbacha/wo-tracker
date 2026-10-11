-- Work Order Tracker: initial schema.
-- Principles: nothing is ever hard-deleted (soft delete only, enforced by the database),
-- every change is recorded in an append-only history, every row belongs to one owner
-- and Row-Level Security limits all access to that owner.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.riyadh_today() returns date
language sql stable as $$ select (now() at time zone 'Asia/Riyadh')::date $$;

create or replace function public.tg_set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  -- Identity and ownership never change after insert.
  new.id := old.id;
  new.owner_id := old.owner_id;
  new.created_at := old.created_at;
  return new;
end $$;

-- Dates of work cannot be in the future (Riyadh time). Checked only when the date
-- itself changes, so editing other fields of an old row never fails.
create or replace function public.tg_check_step_date() returns trigger
language plpgsql as $$
begin
  if new.done_date is not null
     and (tg_op = 'INSERT' or new.done_date is distinct from old.done_date)
     and new.done_date > public.riyadh_today() then
    raise exception 'A step date cannot be in the future.' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create or replace function public.tg_check_received_date() returns trigger
language plpgsql as $$
begin
  if (tg_op = 'INSERT' or new.received_date is distinct from old.received_date)
     and new.received_date > public.riyadh_today() then
    raise exception 'The received date cannot be in the future.' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create or replace function public.tg_block_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'Permanent delete is not allowed on %. Set deleted_at instead.', tg_table_name
    using errcode = 'insufficient_privilege';
end $$;

-- Append-only history. Records only the columns that changed. The app's cached figures
-- (status, stage, progress, last change date) are left out: they are recomputed from the
-- steps at any time, and logging them made up about 40% of all history rows.
create table public.activity_log (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null,
  table_name  text not null,
  row_id      uuid not null,
  action      text not null check (action in ('insert', 'update', 'soft_delete', 'restore')),
  old_data    jsonb,
  new_data    jsonb,
  actor       uuid,
  changed_at  timestamptz not null default now()
);
create index activity_log_row_idx on public.activity_log (row_id, changed_at);
create index activity_log_owner_time_idx on public.activity_log (owner_id, changed_at);

create or replace function public.tg_log_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o jsonb;
  n jsonb;
  k text;
  old_diff jsonb := '{}'::jsonb;
  new_diff jsonb := '{}'::jsonb;
  act text;
begin
  if tg_op = 'INSERT' then
    insert into public.activity_log (owner_id, table_name, row_id, action, new_data, actor)
    values (new.owner_id, tg_table_name, new.id, 'insert', to_jsonb(new), auth.uid());
    return new;
  end if;

  o := to_jsonb(old);
  n := to_jsonb(new);
  for k in select jsonb_object_keys(n) loop
    if k <> all (array['updated_at', 'status_cache', 'stage_cache', 'progress_closed', 'progress_total', 'last_change_date'])
       and (o -> k) is distinct from (n -> k) then
      old_diff := old_diff || jsonb_build_object(k, o -> k);
      new_diff := new_diff || jsonb_build_object(k, n -> k);
    end if;
  end loop;
  if new_diff = '{}'::jsonb then
    return new;
  end if;

  act := case
    when old.deleted_at is null and new.deleted_at is not null then 'soft_delete'
    when old.deleted_at is not null and new.deleted_at is null then 'restore'
    else 'update'
  end;
  insert into public.activity_log (owner_id, table_name, row_id, action, old_data, new_data, actor)
  values (new.owner_id, tg_table_name, new.id, act, old_diff, new_diff, auth.uid());
  return new;
end $$;

create or replace function public.tg_block_log_change() returns trigger
language plpgsql as $$
begin
  raise exception 'History is append-only.' using errcode = 'insufficient_privilege';
end $$;

create trigger activity_log_no_update before update on public.activity_log
  for each row execute function public.tg_block_log_change();
create trigger activity_log_no_delete before delete on public.activity_log
  for each row execute function public.tg_block_log_change();
create trigger activity_log_no_truncate before truncate on public.activity_log
  for each statement execute function public.tg_block_log_change();

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------
create table public.contractors (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid(),
  name        text not null check (length(trim(name)) > 0),
  phone       text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create unique index contractors_name_uq on public.contractors (owner_id, lower(trim(name))) where deleted_at is null;

create table public.districts (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid(),
  name        text not null check (length(trim(name)) > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create unique index districts_name_uq on public.districts (owner_id, lower(trim(name))) where deleted_at is null;

create table public.cable_sizes (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid(),
  size_mm2    integer not null check (size_mm2 > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create unique index cable_sizes_uq on public.cable_sizes (owner_id, size_mm2) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Work orders
-- ---------------------------------------------------------------------------
create table public.work_orders (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null default auth.uid(),
  wo_number         text not null check (length(trim(wo_number)) > 0),
  category          text not null check (category in ('extension', 'emergency')),
  type_code         text not null check (type_code in ('401','402','403','404','409','801','802','803','804','805')),
  received_date     date not null,
  district_id       uuid references public.districts (id) on delete restrict,
  street            text,
  network_ref       text,
  contractor_id     uuid references public.contractors (id) on delete restrict,
  needs_excavation  boolean not null default false,
  state             text not null default 'open' check (state in ('open', 'on_hold', 'cancelled', 'merged')),
  state_reason      text,
  merged_into       uuid references public.work_orders (id) on delete restrict,
  notes             text,
  rules_version     integer not null default 1,
  -- Cached results of the rules engine, for fast lists and reports. Always recomputable.
  status_cache      text,
  stage_cache       text,
  progress_closed   integer,
  progress_total    integer,
  last_change_date  date,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  constraint wo_extension_9_digits check (category <> 'extension' or wo_number ~ '^[0-9]{9}$'),
  constraint wo_merged_needs_target check (state <> 'merged' or merged_into is not null),
  constraint wo_not_merged_into_self check (merged_into is null or merged_into <> id),
  constraint wo_excavation_switch check (not needs_excavation or type_code in ('401', '409'))
);
create unique index work_orders_number_uq on public.work_orders (owner_id, wo_number) where deleted_at is null;
create index work_orders_owner_state_idx on public.work_orders (owner_id, state) where deleted_at is null;
create index work_orders_received_idx on public.work_orders (owner_id, received_date);
create index work_orders_contractor_idx on public.work_orders (contractor_id);
create index work_orders_network_idx on public.work_orders (owner_id, network_ref);

-- Child tables all carry work_order_id and the same owner as their order.
create table public.permits (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid(),
  work_order_id  uuid not null references public.work_orders (id) on delete restrict,
  permit_number  text,
  applied_date   date,
  start_date     date,
  end_date       date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  constraint permit_end_after_start check (end_date is null or start_date is null or end_date >= start_date),
  constraint permit_start_after_applied check (start_date is null or applied_date is null or start_date >= applied_date)
);
create index permits_order_idx on public.permits (work_order_id);
create unique index permits_number_uq on public.permits (owner_id, permit_number) where deleted_at is null and permit_number is not null;
create index permits_end_idx on public.permits (owner_id, end_date) where deleted_at is null;

create table public.segments (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid(),
  work_order_id  uuid not null references public.work_orders (id) on delete restrict,
  base           text not null check (base in ('soil', 'asphalt')),
  width_cm       integer not null check (width_cm in (40, 80)),
  length_m       numeric(9, 2) not null check (length_m > 0),
  tiled          boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index segments_order_idx on public.segments (work_order_id);

create table public.meters (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null default auth.uid(),
  work_order_id     uuid not null references public.work_orders (id) on delete restrict,
  seq               integer not null check (seq > 0),
  meter_number      text,
  meter_type        text check (meter_type in ('single_phase', 'three_phase', 'ct')),
  breaker_amps      integer check (breaker_amps > 0),
  old_meter_number  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create unique index meters_seq_uq on public.meters (work_order_id, seq) where deleted_at is null;
create index meters_number_idx on public.meters (owner_id, meter_number);

create table public.cable_runs (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid(),
  work_order_id  uuid not null references public.work_orders (id) on delete restrict,
  size_mm2       integer not null check (size_mm2 > 0),
  voltage        text not null check (voltage in ('LV', 'MV')),
  length_m       numeric(9, 2) not null check (length_m > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index cable_runs_order_idx on public.cable_runs (work_order_id);

create table public.steps (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null default auth.uid(),
  work_order_id   uuid not null references public.work_orders (id) on delete restrict,
  step_key        text not null,
  segment_id      uuid references public.segments (id) on delete restrict,
  meter_id        uuid references public.meters (id) on delete restrict,
  done_date       date,
  not_applicable  boolean not null default false,
  na_reason       text,
  note            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  constraint step_done_or_na check (not (done_date is not null and not_applicable)),
  constraint step_na_needs_reason check (not not_applicable or length(trim(coalesce(na_reason, ''))) > 0),
  constraint step_one_instance check (num_nonnulls(segment_id, meter_id) <= 1)
);
create unique index steps_instance_uq on public.steps (
  work_order_id, step_key,
  coalesce(segment_id, '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(meter_id, '00000000-0000-0000-0000-000000000000'::uuid)
) where deleted_at is null;
create index steps_done_idx on public.steps (owner_id, done_date) where deleted_at is null;

create table public.hold_periods (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid(),
  work_order_id  uuid not null references public.work_orders (id) on delete restrict,
  from_date      date not null,
  to_date        date,
  reason         text not null check (length(trim(reason)) > 0),
  review_date    date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  constraint hold_to_after_from check (to_date is null or to_date >= from_date)
);
create index hold_periods_order_idx on public.hold_periods (work_order_id);

create table public.attachments (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null default auth.uid(),
  work_order_id   uuid not null references public.work_orders (id) on delete restrict,
  step_id         uuid references public.steps (id) on delete restrict,
  kind            text not null check (kind in ('photo', 'sec_pdf', 'other')),
  drive_file_id   text,
  file_name       text not null,
  sha256          text,
  taken_at        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index attachments_order_idx on public.attachments (work_order_id);

create table public.followups (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid(),
  contractor_id  uuid not null references public.contractors (id) on delete restrict,
  followed_at    timestamptz not null default now(),
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create table public.saved_views (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid(),
  name        text not null check (length(trim(name)) > 0),
  filter      jsonb not null default '{}'::jsonb,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.settings (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default auth.uid(),
  alert_overrides  jsonb not null default '{}'::jsonb,
  prepared_by      text not null default 'Engr Najim',
  language         text not null default 'en' check (language in ('en', 'ar')),
  show_hijri       boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
create unique index settings_owner_uq on public.settings (owner_id);

-- ---------------------------------------------------------------------------
-- Triggers and security, applied to every data table the same way
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  child_tables text[] := array['permits', 'segments', 'meters', 'cable_runs', 'steps', 'hold_periods', 'attachments'];
  all_tables text[] := array['contractors', 'districts', 'cable_sizes', 'work_orders', 'permits', 'segments', 'meters',
                             'cable_runs', 'steps', 'hold_periods', 'attachments', 'followups', 'saved_views', 'settings'];
begin
  foreach t in array all_tables loop
    execute format('create trigger %I before update on public.%I for each row execute function public.tg_set_updated_at()', t || '_updated_at', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.tg_block_delete()', t || '_no_delete', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public.tg_block_delete()', t || '_no_truncate', t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.tg_log_change()', t || '_history', t);

    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke delete, truncate on public.%I from authenticated', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);

    execute format('create policy %I on public.%I for select to authenticated using (owner_id = auth.uid())', t || '_select', t);
    execute format('create policy %I on public.%I for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid())', t || '_update', t);
    if t = any (child_tables) then
      execute format(
        'create policy %I on public.%I for insert to authenticated with check (owner_id = auth.uid() and exists (select 1 from public.work_orders w where w.id = work_order_id and w.owner_id = auth.uid()))',
        t || '_insert', t);
    else
      execute format('create policy %I on public.%I for insert to authenticated with check (owner_id = auth.uid())', t || '_insert', t);
    end if;
  end loop;
end $$;

-- Dates of work cannot be in the future.
create trigger steps_dates before insert or update on public.steps for each row execute function public.tg_check_step_date();
create trigger work_orders_dates before insert or update on public.work_orders for each row execute function public.tg_check_received_date();

-- Child rows can never be moved onto an order that belongs to someone else.
do $$
declare t text;
begin
  foreach t in array array['permits', 'segments', 'meters', 'cable_runs', 'steps', 'hold_periods', 'attachments'] loop
    execute format('drop policy %I on public.%I', t || '_update', t);
    execute format(
      'create policy %I on public.%I for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid() and exists (select 1 from public.work_orders w where w.id = work_order_id and w.owner_id = auth.uid()))',
      t || '_update', t);
  end loop;
end $$;

-- Followups must point at the owner's own contractor.
drop policy followups_insert on public.followups;
create policy followups_insert on public.followups for insert to authenticated
  with check (owner_id = auth.uid() and exists (select 1 from public.contractors c where c.id = contractor_id and c.owner_id = auth.uid()));

-- History: readable by its owner, written only by the trigger function.
alter table public.activity_log enable row level security;
alter table public.activity_log force row level security;
revoke all on public.activity_log from anon;
revoke insert, update, delete, truncate on public.activity_log from authenticated;
grant select on public.activity_log to authenticated;
create policy activity_log_select on public.activity_log for select to authenticated using (owner_id = auth.uid());
-- The trigger function runs as the table owner; let it insert regardless of RLS.
create policy activity_log_trigger_insert on public.activity_log for insert to public with check (true);
revoke usage on sequence public.activity_log_id_seq from authenticated, anon;
