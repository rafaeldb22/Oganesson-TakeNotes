-- Migration 7: images inside notes (Supabase Storage)
-- Run ONCE in Supabase → SQL Editor → New query → Run.
--
-- Images live in a PRIVATE bucket, one folder per user: `<user id>/<image id>`.
-- Notes reference them as `sb://<user id>/<image id>?w=<width>&h=<height>`.
-- Until this migration runs, the app keeps new images on the device and
-- retries the upload later.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'note-images',
  'note-images',
  false,
  10485760, -- 10 MB (the app compresses photos to ≤ 2048 px first)
  array['image/png', 'image/jpeg', 'image/gif', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Each user can only see and change the files in their own folder.
drop policy if exists "imagenes_leer" on storage.objects;
drop policy if exists "imagenes_subir" on storage.objects;
drop policy if exists "imagenes_editar" on storage.objects;
drop policy if exists "imagenes_borrar" on storage.objects;

create policy "imagenes_leer" on storage.objects
  for select to authenticated
  using (bucket_id = 'note-images'
         and (storage.foldername(name))[1] = auth.uid()::text);

create policy "imagenes_subir" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'note-images'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "imagenes_editar" on storage.objects
  for update to authenticated
  using (bucket_id = 'note-images'
         and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'note-images'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "imagenes_borrar" on storage.objects
  for delete to authenticated
  using (bucket_id = 'note-images'
         and (storage.foldername(name))[1] = auth.uid()::text);
