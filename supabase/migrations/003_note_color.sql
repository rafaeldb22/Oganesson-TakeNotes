-- Migration 3: custom colour per note
alter table public.notes add column if not exists color bigint;
