-- Run ONCE in Supabase → SQL Editor → New query → Run.

create table if not exists public.notes (
  id          uuid primary key,
  user_id     uuid not null default auth.uid()
              references auth.users (id) on delete cascade,
  content     text not null default '',
  pinned      boolean not null default false,
  deleted     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists notes_user_idx on public.notes (user_id);

-- Each user can only read and modify their own notes.
alter table public.notes enable row level security;

drop policy if exists "notas_leer" on public.notes;
drop policy if exists "notas_crear" on public.notes;
drop policy if exists "notas_editar" on public.notes;

create policy "notas_leer" on public.notes
  for select to authenticated using (auth.uid() = user_id);

create policy "notas_crear" on public.notes
  for insert to authenticated with check (auth.uid() = user_id);

create policy "notas_editar" on public.notes
  for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Lets the app (signed-in users) access the table through the API.
grant select, insert, update on public.notes to authenticated;

-- Enables realtime (this is what makes other devices update instantly).
do $$
begin
  alter publication supabase_realtime add table public.notes;
exception when duplicate_object then null;
end $$;
