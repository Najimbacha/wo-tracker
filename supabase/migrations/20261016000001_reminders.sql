-- Reminders: "check tasreeh on Sunday" attached to one work order. Shown on the Today
-- screen from the due date until done. Nothing is deleted: a removed reminder gets deleted_at.
-- Safe to run more than once. After running it, add the reminders line to the PowerSync
-- sync rules (powersync/sync-rules.yaml) and deploy them.
create table if not exists public.reminders (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid(),
  work_order_id  uuid not null references public.work_orders (id) on delete restrict,
  due_date       date not null,
  note           text not null check (length(trim(note)) > 0),
  done_at        timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index if not exists reminders_order_idx on public.reminders (work_order_id);
create index if not exists reminders_due_idx on public.reminders (owner_id, due_date) where deleted_at is null and done_at is null;

drop trigger if exists reminders_updated_at on public.reminders;
create trigger reminders_updated_at before update on public.reminders for each row execute function public.tg_set_updated_at();
drop trigger if exists reminders_no_delete on public.reminders;
create trigger reminders_no_delete before delete on public.reminders for each row execute function public.tg_block_delete();
drop trigger if exists reminders_no_truncate on public.reminders;
create trigger reminders_no_truncate before truncate on public.reminders for each statement execute function public.tg_block_delete();
drop trigger if exists reminders_history on public.reminders;
create trigger reminders_history after insert or update on public.reminders for each row execute function public.tg_log_change();

alter table public.reminders enable row level security;
alter table public.reminders force row level security;
revoke all on public.reminders from anon;
revoke delete, truncate on public.reminders from authenticated;
grant select, insert, update on public.reminders to authenticated;

drop policy if exists reminders_select on public.reminders;
create policy reminders_select on public.reminders for select to authenticated using (owner_id = auth.uid());
drop policy if exists reminders_insert on public.reminders;
create policy reminders_insert on public.reminders for insert to authenticated
  with check (owner_id = auth.uid() and exists (select 1 from public.work_orders w where w.id = work_order_id and w.owner_id = auth.uid()));
drop policy if exists reminders_update on public.reminders;
create policy reminders_update on public.reminders for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid() and exists (select 1 from public.work_orders w where w.id = work_order_id and w.owner_id = auth.uid()));

-- Devices receive it through the PowerSync publication.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'powersync')
     and not exists (select 1 from pg_publication_tables where pubname = 'powersync' and tablename = 'reminders') then
    alter publication powersync add table public.reminders;
  end if;
end $$;
