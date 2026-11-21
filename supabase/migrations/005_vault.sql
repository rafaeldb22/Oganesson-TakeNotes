-- Migration 5: Vault (notes protected by a master password)
-- Run ONCE in Supabase → SQL Editor → New query → Run.

-- Notes moved to the Vault are hidden in the app until it is unlocked.
alter table public.notes
  add column if not exists vault boolean not null default false;

-- Manual links between notes (right click → Link / Create sub-note), as ids.
alter table public.notes
  add column if not exists links jsonb not null default '[]'::jsonb;

-- When a task was completed: after 3 days it moves to "Completed", and it is
-- kept there for 30 days.
alter table public.notes
  add column if not exists done_at timestamptz;

-- Master password, stored only as a salted PBKDF2-SHA256 hash (one row per
-- user) so the same password works on every device.
create table if not exists public.vaults (
  user_id     uuid primary key default auth.uid()
              references auth.users (id) on delete cascade,
  data        text not null,
  updated_at  timestamptz not null default now()
);

alter table public.vaults enable row level security;

drop policy if exists "vault_leer" on public.vaults;
drop policy if exists "vault_crear" on public.vaults;
drop policy if exists "vault_editar" on public.vaults;
drop policy if exists "vault_borrar" on public.vaults;

create policy "vault_leer" on public.vaults
  for select to authenticated using (auth.uid() = user_id);

create policy "vault_crear" on public.vaults
  for insert to authenticated with check (auth.uid() = user_id);

create policy "vault_editar" on public.vaults
  for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "vault_borrar" on public.vaults
  for delete to authenticated using (auth.uid() = user_id);

grant select, insert, update, delete on public.vaults to authenticated;
