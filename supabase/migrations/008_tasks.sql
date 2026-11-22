-- Migration 8: repeating tasks and subtasks
-- Run ONCE in Supabase → SQL Editor → New query → Run.

-- Repeat rule: daily, weekdays, weekly, monthly or yearly. Null = no repeat.
alter table public.notes
  add column if not exists repeat text;

-- Steps of a task: [{"id": "...", "text": "...", "done": false}]
alter table public.notes
  add column if not exists subtasks jsonb not null default '[]'::jsonb;
