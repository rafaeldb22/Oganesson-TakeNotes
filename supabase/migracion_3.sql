-- Migración 3: color personalizado por nota
alter table public.notes add column if not exists color bigint;
