-- Migration 10: notes shared with other accounts
-- Run ONCE in Supabase → SQL Editor → New query → Run.
--
-- A share is stored by email, so inviting someone never reveals whether that
-- address has an account. Access requires a CONFIRMED email on the account:
-- keep "Confirm email" enabled in Supabase → Authentication.

create table if not exists public.note_shares (
  note_id    uuid not null references public.notes (id) on delete cascade,
  email      text not null check (email = lower(email)),
  role       text not null default 'edit' check (role in ('edit', 'read')),
  created_by uuid not null default auth.uid()
             references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (note_id, email)
);

create index if not exists note_shares_email_idx on public.note_shares (email);

alter table public.note_shares enable row level security;

-- ------------------------------------------------------------ access checks

create or replace function public.my_email()
returns text language sql stable security definer set search_path = '' as $$
  select lower(u.email) from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null
$$;

create or replace function public.owns_note(p_note uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.notes n
                 where n.id = p_note and n.user_id = auth.uid())
$$;

create or replace function public.can_read_note(p_note uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.note_shares s
    join public.notes n on n.id = s.note_id
    where s.note_id = p_note and s.email = public.my_email()
      and not n.vault and not n.deleted)
$$;

create or replace function public.can_edit_note(p_note uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.note_shares s
    join public.notes n on n.id = s.note_id
    where s.note_id = p_note and s.email = public.my_email()
      and s.role = 'edit' and not n.vault and not n.deleted)
$$;

-- Images and files: a path written in a note grants nothing by itself, or
-- anyone who once saw a path could paste it into a note and keep reading it.
-- Only the account that owns the file can allow it (allowed = true). A path
-- added by someone else is recorded as allowed = false and stays blocked.
create table if not exists public.note_shared_files (
  note_id     uuid not null references public.notes (id) on delete cascade,
  object_name text not null,
  allowed     boolean not null,
  primary key (note_id, object_name)
);

alter table public.note_shared_files enable row level security;
revoke all on public.note_shared_files from public, anon, authenticated;

create or replace function public.note_file_refs(p_rich text)
returns setof text language sql immutable set search_path = '' as $$
  select distinct m[1]
  from regexp_matches(coalesce(p_rich, ''), '(?:sb|ogf)://([^"?\\]+)', 'g') m
$$;

revoke all on function public.note_file_refs(text) from public, anon, authenticated;

create or replace function public.can_read_shared_file(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.note_shared_files f
    join public.notes n on n.id = f.note_id
    where f.object_name = p_name and f.allowed
      and not n.vault and not n.deleted
      and p_name in (select public.note_file_refs(n.rich))
      and (n.user_id = auth.uid() or public.can_read_note(n.id)))
$$;

-- ----------------------------------------------------------------- policies

drop policy if exists "compartir_ver" on public.note_shares;
create policy "compartir_ver" on public.note_shares
  for select to authenticated
  using (email = public.my_email() or public.owns_note(note_id));

grant select on public.note_shares to authenticated;

drop policy if exists "notas_compartidas_leer" on public.notes;
create policy "notas_compartidas_leer" on public.notes
  for select to authenticated using (public.can_read_note(id));

drop policy if exists "notas_compartidas_editar" on public.notes;
create policy "notas_compartidas_editar" on public.notes
  for update to authenticated
  using (public.can_edit_note(id)) with check (public.can_edit_note(id));

drop policy if exists "compartidos_leer" on storage.objects;
create policy "compartidos_leer" on storage.objects
  for select to authenticated
  using (bucket_id in ('note-images', 'note-files')
         and public.can_read_shared_file(name));

-- ----------------------------------------------------------------- triggers

-- Someone else's note: only its text can change. Folder, pin, trash, Vault
-- and the rest belong to the owner.
create or replace function public.notes_guard_shared()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_content text := new.content;
  v_rich text := new.rich;
  v_updated timestamptz := new.updated_at;
begin
  if auth.uid() is null or old.user_id = auth.uid() then
    return new;
  end if;
  new := old;
  new.content := v_content;
  new.rich := v_rich;
  new.updated_at := least(v_updated, now() + interval '1 minute');
  return new;
end $$;

drop trigger if exists notes_guard_shared on public.notes;
create trigger notes_guard_shared before update on public.notes
  for each row execute function public.notes_guard_shared();

-- Records who put each file path into a shared note.
create or replace function public.notes_track_shared_files()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return null;
  end if;
  -- A file its owner took out of the note loses its permission. Removal by
  -- anyone else keeps it, so a collaborator's undo doesn't break the image.
  delete from public.note_shared_files f
  where f.note_id = new.id and f.allowed
    and split_part(f.object_name, '/', 1) = v_uid::text
    and f.object_name not in (select public.note_file_refs(new.rich));
  if not exists (select 1 from public.note_shares s where s.note_id = new.id) then
    return null;
  end if;
  insert into public.note_shared_files (note_id, object_name, allowed)
  select new.id, r, split_part(r, '/', 1) = v_uid::text
  from public.note_file_refs(new.rich) r
  where split_part(r, '/', 1) = v_uid::text
     or r not in (select public.note_file_refs(old.rich))
  on conflict (note_id, object_name) do nothing;
  return null;
end $$;

drop trigger if exists notes_track_shared_files on public.notes;
create trigger notes_track_shared_files after update of rich on public.notes
  for each row execute function public.notes_track_shared_files();

-- A note moved to the Vault stops being shared.
create or replace function public.notes_vault_unshare()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.note_shares where note_id = new.id;
  return null;
end $$;

drop trigger if exists notes_vault_unshare on public.notes;
create trigger notes_vault_unshare after update of vault on public.notes
  for each row when (new.vault and not old.vault)
  execute function public.notes_vault_unshare();

-- ---------------------------------------------------------------------- API

create or replace function public.share_note(
  p_note uuid, p_email text, p_role text default 'edit')
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(p_email));
  v_note public.notes;
begin
  select * into v_note from public.notes n
  where n.id = p_note and n.user_id = auth.uid();
  if not found then raise exception 'not_owner'; end if;
  if v_note.vault or v_note.deleted then raise exception 'vault'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email';
  end if;
  if p_role not in ('edit', 'read') then raise exception 'invalid_role'; end if;
  if v_email = (select lower(u.email) from auth.users u where u.id = auth.uid())
  then raise exception 'self'; end if;
  if (select count(*) from public.note_shares s
      where s.note_id = p_note and s.email <> v_email) >= 20 then
    raise exception 'too_many';
  end if;
  insert into public.note_shares (note_id, email, role, created_by)
  values (p_note, v_email, p_role, auth.uid())
  on conflict (note_id, email) do update set role = excluded.role;
  -- The owner's own files already in the note.
  insert into public.note_shared_files (note_id, object_name, allowed)
  select p_note, r, true
  from public.note_file_refs(v_note.rich) r
  where split_part(r, '/', 1) = auth.uid()::text
  on conflict (note_id, object_name) do nothing;
end $$;

create or replace function public.unshare_note(p_note uuid, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.owns_note(p_note) then raise exception 'not_owner'; end if;
  delete from public.note_shares s
  where s.note_id = p_note and s.email = lower(trim(p_email));
end $$;

create or replace function public.leave_note(p_note uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.note_shares s
  where s.note_id = p_note and s.email = public.my_email()
$$;

create or replace function public.note_people(p_note uuid)
returns table (email text, role text, is_owner boolean)
language sql stable security definer set search_path = '' as $$
  select lower(u.email)::text, 'owner'::text, true
  from public.notes n join auth.users u on u.id = n.user_id
  where n.id = p_note
    and (n.user_id = auth.uid() or public.can_read_note(p_note))
  union all
  select s.email, s.role, false
  from public.note_shares s
  where s.note_id = p_note
    and (public.owns_note(p_note) or public.can_read_note(p_note))
$$;

create or replace function public.my_shared_notes()
returns table (note_id uuid, role text, owner_email text)
language sql stable security definer set search_path = '' as $$
  select s.note_id, s.role, lower(u.email)::text
  from public.note_shares s
  join public.notes n on n.id = s.note_id
  join auth.users u on u.id = n.user_id
  where s.email = public.my_email() and not n.vault and not n.deleted
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'my_email()', 'owns_note(uuid)', 'can_read_note(uuid)',
    'can_edit_note(uuid)', 'can_read_shared_file(text)',
    'share_note(uuid, text, text)', 'unshare_note(uuid, text)',
    'leave_note(uuid)', 'note_people(uuid)', 'my_shared_notes()'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- New shares reach the other person's app right away.
do $$
begin
  alter publication supabase_realtime add table public.note_shares;
exception when duplicate_object then null;
end $$;
