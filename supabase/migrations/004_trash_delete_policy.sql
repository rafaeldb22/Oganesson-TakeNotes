-- Migration 4: permanent deletion from the trash
drop policy if exists "notas_borrar" on public.notes;
create policy "notas_borrar" on public.notes
  for delete to authenticated using (auth.uid() = user_id);
grant delete on public.notes to authenticated;
