-- Cloud copy of attached files (pictures, PDFs...). The files live in a private Supabase
-- Storage bucket, one folder per user: <user id>/<attachment id>.<ext>. The attachments row
-- (which syncs to every device) gets storage_path once the file is uploaded, and a device
-- that has the row but not the file downloads it. Nothing is ever deleted from the bucket:
-- there is no delete policy. Safe to run more than once.
alter table public.attachments add column if not exists storage_path text;

do $$
begin
  -- Plain Postgres (the test database) has no Storage; Supabase does.
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice 'Storage is not available here: bucket and policies skipped';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit)
  values ('attachments', 'attachments', false, 26214400) -- 25 MB per file
  on conflict (id) do update set public = false, file_size_limit = 26214400;

  drop policy if exists attachments_files_select on storage.objects;
  create policy attachments_files_select on storage.objects for select to authenticated
    using (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);

  drop policy if exists attachments_files_insert on storage.objects;
  create policy attachments_files_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);

  -- Re-uploading the same file after an interrupted upload replaces it.
  drop policy if exists attachments_files_update on storage.objects;
  create policy attachments_files_update on storage.objects for update to authenticated
    using (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text)
    with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = auth.uid()::text);
end $$;
