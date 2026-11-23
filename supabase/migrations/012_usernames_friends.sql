-- Migration 12: @usernames, friends and sign-in with @username
-- Run ONCE in Supabase → SQL Editor → New query → Run.
--
-- Emails stay private: shares are keyed by account id and people are shown by
-- @username. Tables are only reachable through the functions below.

begin;

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  username   text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  updated_at timestamptz not null default now()
);

create table if not exists public.friends (
  user_id    uuid not null references auth.users (id) on delete cascade,
  friend_id  uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table if not exists public.login_attempts (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  fails        int not null default 0,
  window_start timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.friends enable row level security;
alter table public.login_attempts enable row level security;
revoke all on public.profiles, public.friends, public.login_attempts
  from public, anon, authenticated;

create or replace function public.clean_username(p text)
returns text language sql immutable set search_path = '' as $$
  select ltrim(lower(trim(p)), '@')
$$;

create or replace function public.default_username(p_user uuid)
returns text language sql immutable set search_path = '' as $$
  select 'user_' || left(replace(p_user::text, '-', ''), 15)
$$;

-- Existing accounts get a neutral name (never derived from their email).
insert into public.profiles (user_id, username)
select u.id, public.default_username(u.id) from auth.users u
on conflict do nothing;

create or replace function public.profiles_on_signup()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_name text := public.clean_username(new.raw_user_meta_data ->> 'username');
begin
  if v_name is null or v_name !~ '^[a-z0-9_]{3,20}$' then
    v_name := public.default_username(new.id);
  end if;
  insert into public.profiles (user_id, username) values (new.id, v_name)
  on conflict do nothing;
  if not found then
    insert into public.profiles (user_id, username)
    values (new.id, public.default_username(new.id))
    on conflict do nothing;
  end if;
  return new;
exception when others then
  -- A profile problem must never block creating the account.
  return new;
end $$;

drop trigger if exists profiles_on_signup on auth.users;
create trigger profiles_on_signup after insert on auth.users
  for each row execute function public.profiles_on_signup();

-- ------------------------------------------------------------------ profile

create or replace function public.my_username()
returns text language sql stable security definer set search_path = '' as $$
  select p.username from public.profiles p where p.user_id = auth.uid()
$$;

create or replace function public.username_available(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.clean_username(p_name) ~ '^[a-z0-9_]{3,20}$'
    and not exists (select 1 from public.profiles p
                    where p.username = public.clean_username(p_name))
$$;

create or replace function public.set_username(p_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_name text := public.clean_username(p_name);
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if v_name !~ '^[a-z0-9_]{3,20}$' then raise exception 'invalid_username'; end if;
  insert into public.profiles (user_id, username) values (auth.uid(), v_name)
  on conflict (user_id) do update
    set username = excluded.username, updated_at = now();
  return v_name;
exception when unique_violation then
  raise exception 'username_taken';
end $$;

-- ------------------------------------------------------------------ friends

create or replace function public.search_users(p_query text)
returns table (user_id uuid, username text, is_friend boolean)
language sql stable security definer set search_path = '' as $$
  select p.user_id, p.username,
         exists (select 1 from public.friends f
                 where f.user_id = auth.uid() and f.friend_id = p.user_id)
  from public.profiles p
  where auth.uid() is not null
    and length(public.clean_username(p_query)) >= 2
    and starts_with(p.username, public.clean_username(p_query))
    and p.user_id <> auth.uid()
  order by p.username
  limit 8
$$;

create or replace function public.my_friends()
returns table (user_id uuid, username text)
language sql stable security definer set search_path = '' as $$
  select p.user_id, p.username
  from public.friends f join public.profiles p on p.user_id = f.friend_id
  where f.user_id = auth.uid()
  order by p.username
$$;

create or replace function public.add_friend(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_user = auth.uid() then raise exception 'self'; end if;
  if not exists (select 1 from public.profiles p where p.user_id = p_user) then
    raise exception 'no_account';
  end if;
  if (select count(*) from public.friends f where f.user_id = auth.uid()) >= 200 then
    raise exception 'too_many';
  end if;
  insert into public.friends (user_id, friend_id) values (auth.uid(), p_user)
  on conflict do nothing;
end $$;

create or replace function public.remove_friend(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.friends f
  where f.user_id = auth.uid() and f.friend_id = p_user
$$;

-- ------------------------------------------------------- sign in by @username

-- Returns the account email only to someone who already knows the password,
-- so the client can finish with the normal sign-in. Failures return null (an
-- exception would roll back the counter). 8 failures lock it for 15 minutes.
create or replace function public.login_email(p_username text, p_password text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_email text;
  v_hash text;
  v_fails int;
begin
  if p_password is null or length(p_password) > 200 then return null; end if;
  select u.id, u.email, u.encrypted_password into v_id, v_email, v_hash
  from public.profiles p join auth.users u on u.id = p.user_id
  where p.username = public.clean_username(p_username);
  if v_id is null or v_hash is null or v_hash = '' then return null; end if;

  -- The upsert locks the row, so parallel guesses are counted one by one.
  insert into public.login_attempts as a (user_id) values (v_id)
  on conflict (user_id) do update set
    fails = case when a.window_start < now() - interval '15 minutes'
                 then 0 else a.fails end,
    window_start = case when a.window_start < now() - interval '15 minutes'
                        then now() else a.window_start end
  returning a.fails into v_fails;
  if v_fails >= 8 then raise exception 'too_many_attempts'; end if;

  if extensions.crypt(p_password, v_hash) = v_hash then
    delete from public.login_attempts a where a.user_id = v_id;
    return v_email;
  end if;
  update public.login_attempts a set fails = a.fails + 1 where a.user_id = v_id;
  return null;
end $$;

-- ------------------------------------------------------------------- sharing

-- A collaborator could read note_shares.email, so it now holds the account id.
delete from public.note_shares a using public.note_shares b
where a.note_id = b.note_id and a.user_id = b.user_id and a.email <> b.email
  and ((a.role = 'read' and b.role = 'edit')
       or (a.role = b.role and a.email < b.email));

update public.note_shares set email = 'u:' || user_id
where user_id is not null and email <> 'u:' || user_id;

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
  from public.note_file_refs(v_note.rich) r
  where split_part(r, '/', 1) = auth.uid()::text
  on conflict (note_id, object_name) do nothing;
end $$;

create or replace function public.unshare_note(p_note uuid, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_target text := lower(trim(p_email));
begin
  if not public.owns_note(p_note) then raise exception 'not_owner'; end if;
  delete from public.note_shares s
  where s.note_id = p_note
    and (s.email = v_target
         or s.user_id = (select p.user_id from public.profiles p
                         where v_target like '@%'
                           and p.username = public.clean_username(v_target)));
end $$;

-- The "email" column keeps its name for older app versions, but carries @username.
create or replace function public.note_people(p_note uuid)
returns table (email text, role text, is_owner boolean)
language sql stable security definer set search_path = '' as $$
  select coalesce('@' || p.username, '@?'), 'owner'::text, true
  from public.notes n
  left join public.profiles p on p.user_id = n.user_id
  where n.id = p_note
    and (n.user_id = auth.uid() or public.can_read_note(p_note))
  union all
  select coalesce('@' || p.username, s.email), s.role, false
  from public.note_shares s
  left join public.profiles p on p.user_id = s.user_id
  where s.note_id = p_note
    and (public.owns_note(p_note) or public.can_read_note(p_note))
$$;

create or replace function public.my_shared_notes()
returns table (note_id uuid, role text, owner_email text)
language sql stable security definer set search_path = '' as $$
  select s.note_id, s.role, coalesce('@' || p.username, '@?')
  from public.note_shares s
  join public.notes n on n.id = s.note_id
  left join public.profiles p on p.user_id = n.user_id
  where s.user_id = auth.uid() and not n.vault and not n.deleted
$$;

-- ------------------------------------------------------------------- grants

do $$
declare f text;
begin
  foreach f in array array[
    'clean_username(text)', 'default_username(uuid)', 'profiles_on_signup()'
  ] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'my_username()', 'set_username(text)', 'search_users(text)', 'my_friends()',
    'add_friend(uuid)', 'remove_friend(uuid)', 'share_note(uuid, text, text)',
    'unshare_note(uuid, text)', 'note_people(uuid)', 'my_shared_notes()'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array[
    'username_available(text)', 'login_email(text, text)'
  ] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

commit;
