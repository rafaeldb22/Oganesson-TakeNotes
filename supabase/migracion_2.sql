-- Migración 2: carpetas, texto con formato y notas temporales.
alter table public.notes add column if not exists folder_id uuid;
alter table public.notes add column if not exists rich text;
alter table public.notes add column if not exists remind_at timestamptz;
alter table public.notes add column if not exists due_at timestamptz;
alter table public.notes add column if not exists done boolean not null default false;

create table if not exists public.folders (
  id          uuid primary key,
  user_id     uuid not null default auth.uid()
              references auth.users (id) on delete cascade,
  name        text not null default '',
  color       bigint,
  deleted     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists folders_user_idx on public.folders (user_id);
alter table public.folders enable row level security;

drop policy if exists "carpetas_leer" on public.folders;
drop policy if exists "carpetas_crear" on public.folders;
drop policy if exists "carpetas_editar" on public.folders;

create policy "carpetas_leer" on public.folders
  for select to authenticated using (auth.uid() = user_id);
create policy "carpetas_crear" on public.folders
  for insert to authenticated with check (auth.uid() = user_id);
create policy "carpetas_editar" on public.folders
  for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update on public.folders to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.folders;
exception when duplicate_object then null;
end $$;
