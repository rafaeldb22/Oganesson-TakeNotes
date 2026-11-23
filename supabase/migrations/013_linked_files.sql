-- Migration 13: files connected to a note without being inside its text
-- Run ONCE in Supabase → SQL Editor → New query → Run, AFTER migration 012.
--
-- These files live in notes.links (next to linked note ids). Sharing a note
-- must grant access to them too, with the same rule as files in the text:
-- only the account that owns a file can allow it.

begin;

create or replace function public.note_all_refs(p_rich text, p_links jsonb)
returns setof text language sql immutable set search_path = '' as $$
  select public.note_file_refs(
    coalesce(p_rich, '') || ' ' || coalesce(p_links::text, ''))
$$;

revoke all on function public.note_all_refs(text, jsonb)
  from public, anon, authenticated;

create or replace function public.can_read_shared_file(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.note_shared_files f
    join public.notes n on n.id = f.note_id
    where f.object_name = p_name and f.allowed
      and not n.vault and not n.deleted
      and p_name in (select public.note_all_refs(n.rich, n.links))
      and (n.user_id = auth.uid() or public.can_read_note(n.id)))
$$;

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
    and f.object_name not in (select public.note_all_refs(new.rich, new.links));
  if not exists (select 1 from public.note_shares s where s.note_id = new.id) then
    return null;
  end if;
  insert into public.note_shared_files (note_id, object_name, allowed)
  select new.id, r, split_part(r, '/', 1) = v_uid::text
  from public.note_all_refs(new.rich, new.links) r
  where split_part(r, '/', 1) = v_uid::text
     or r not in (select public.note_all_refs(old.rich, old.links))
  on conflict (note_id, object_name) do nothing;
  return null;
end $$;

drop trigger if exists notes_track_shared_files on public.notes;
create trigger notes_track_shared_files after update of rich, links on public.notes
  for each row execute function public.notes_track_shared_files();

create or replace function public.share_note(
  p_note uuid, p_email text, p_role text default 'edit')
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_target text := lower(trim(p_email));
  v_note public.notes;
  v_user uuid;
  v_key text;
begin
  select * into v_note from public.notes n
  where n.id = p_note and n.user_id = auth.uid();
  if not found then raise exception 'not_owner'; end if;
  if v_note.vault or v_note.deleted then raise exception 'vault'; end if;
  if p_role not in ('edit', 'read') then raise exception 'invalid_role'; end if;
  if v_target like '@%' or position('@' in v_target) = 0 then
    select p.user_id into v_user from public.profiles p
    where p.username = public.clean_username(v_target);
  else
    if v_target !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      raise exception 'invalid_email';
    end if;
    select u.id into v_user from auth.users u where lower(u.email) = v_target;
  end if;
  if v_user is null then raise exception 'no_account'; end if;
  if v_user = auth.uid() then raise exception 'self'; end if;
  v_key := 'u:' || v_user;
  if (select count(*) from public.note_shares s
      where s.note_id = p_note and s.email <> v_key) >= 20 then
    raise exception 'too_many';
  end if;
  insert into public.note_shares (note_id, email, role, created_by, user_id)
  values (p_note, v_key, p_role, auth.uid(), v_user)
  on conflict (note_id, email) do update
    set role = excluded.role, user_id = excluded.user_id;
  insert into public.note_shared_files (note_id, object_name, allowed)
  select p_note, r, true
  from public.note_all_refs(v_note.rich, v_note.links) r
  where split_part(r, '/', 1) = auth.uid()::text
  on conflict (note_id, object_name) do nothing;
end $$;

-- Notes that are already shared: allow the owner's connected files.
insert into public.note_shared_files (note_id, object_name, allowed)
select n.id, r, true
from public.notes n
cross join lateral public.note_all_refs(n.rich, n.links) r
where exists (select 1 from public.note_shares s where s.note_id = n.id)
  and split_part(r, '/', 1) = n.user_id::text
on conflict (note_id, object_name) do nothing;

commit;
