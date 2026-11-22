-- Migration 9: attachments and voice notes (Supabase Storage)
-- Run ONCE in Supabase → SQL Editor → New query → Run.
--
-- Files live in a PRIVATE bucket, one folder per user: `<user id>/<file id>`.
-- Until this migration runs, the app keeps new files on the device and
-- retries the upload later.

insert into storage.buckets (id, name, public, file_size_limit)
values ('note-files', 'note-files', false, 26214400) -- 25 MB
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit;

drop policy if exists "archivos_leer" on storage.objects;
drop policy if exists "archivos_subir" on storage.objects;
drop policy if exists "archivos_editar" on storage.objects;
drop policy if exists "archivos_borrar" on storage.objects;

create policy "archivos_leer" on storage.objects
  for select to authenticated
  using (bucket_id = 'note-files'
         and (storage.foldername(name))[1] = auth.uid()::text);

create policy "archivos_subir" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'note-files'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "archivos_editar" on storage.objects
  for update to authenticated
  using (bucket_id = 'note-files'
         and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'note-files'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "archivos_borrar" on storage.objects
  for delete to authenticated
  using (bucket_id = 'note-files'
         and (storage.foldername(name))[1] = auth.uid()::text);
