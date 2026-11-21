-- Migration 6: archived notes and manual order
-- Run ONCE in Supabase → SQL Editor → New query → Run.

-- Swipe left → archive: the note leaves the lists and shows in ⋯ → Archived.
alter table public.notes
  add column if not exists archived boolean not null default false;

-- Manual order (drag notes up/down). Null = not placed yet.
alter table public.notes
  add column if not exists position double precision;
