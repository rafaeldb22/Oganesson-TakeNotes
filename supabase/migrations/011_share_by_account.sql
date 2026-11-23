-- Migration 11: shares belong to an account, not to an email address
-- Run ONCE in Supabase → SQL Editor → New query → Run, BEFORE turning off
-- "Confirm email".
--
-- Sign-up doesn't need a confirmation email after this. A note can only be
-- shared with an account that already exists, and access follows that account
-- id, so registering later with an invited address grants nothing.

begin;

alter table public.note_shares
  add column if not exists user_id uuid references auth.users (id) on delete cascade;

create index if not exists note_shares_user_idx on public.note_shares (user_id);

-- Invitations without a confirmed account stay inactive until the owner
-- removes them and shares again.
update public.note_shares s
set user_id = u.id
from auth.users u
where s.user_id is null
  and lower(u.email) = s.email
  and u.email_confirmed_at is not null;

create or replace function public.can_read_note(p_note uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.note_shares s
    join public.notes n on n.id = s.note_id
    where s.note_id = p_note and s.user_id = auth.uid()
      and not n.vault and not n.deleted)
$$;

create or replace function public.can_edit_note(p_note uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.note_shares s
    join public.notes n on n.id = s.note_id
    where s.note_id = p_note and s.user_id = auth.uid()
      and s.role = 'edit' and not n.vault and not n.deleted)
$$;

drop policy if exists "compartir_ver" on public.note_shares;
create policy "compartir_ver" on public.note_shares
  for select to authenticated
  using (user_id = auth.uid() or public.owns_note(note_id));

create or replace function public.share_note(
  p_note uuid, p_email text, p_role text default 'edit')
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(p_email));
  v_note public.notes;
  v_user uuid;
begin
  select * into v_note from public.notes n
  where n.id = p_note and n.user_id = auth.uid();
  if not found then raise exception 'not_owner'; end if;
  if v_note.vault or v_note.deleted then raise exception 'vault'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email';
  end if;
  if p_role not in ('edit', 'read') then raise exception 'invalid_role'; end if;
  select u.id into v_user from auth.users u where lower(u.email) = v_email;
  if v_user is null then raise exception 'no_account'; end if;
  if v_user = auth.uid() then raise exception 'self'; end if;
  if (select count(*) from public.note_shares s
      where s.note_id = p_note and s.email <> v_email) >= 20 then
    raise exception 'too_many';
  end if;
  insert into public.note_shares (note_id, email, role, created_by, user_id)
  values (p_note, v_email, p_role, auth.uid(), v_user)
  on conflict (note_id, email) do update
    set role = excluded.role, user_id = excluded.user_id;
  insert into public.note_shared_files (note_id, object_name, allowed)
  select p_note, r, true
  from public.note_file_refs(v_note.rich) r
  where split_part(r, '/', 1) = auth.uid()::text
  on conflict (note_id, object_name) do nothing;
end $$;

create or replace function public.leave_note(p_note uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.note_shares s
  where s.note_id = p_note and s.user_id = auth.uid()
$$;

create or replace function public.my_shared_notes()
returns table (note_id uuid, role text, owner_email text)
language sql stable security definer set search_path = '' as $$
  select s.note_id, s.role, lower(u.email)::text
  from public.note_shares s
  join public.notes n on n.id = s.note_id
  join auth.users u on u.id = n.user_id
  where s.user_id = auth.uid() and not n.vault and not n.deleted
$$;

drop function if exists public.my_email();

commit;
