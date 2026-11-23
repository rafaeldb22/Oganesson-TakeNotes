import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';

/// Completadas: tareas terminadas hace 10 minutos o más (salen solas de la
/// lista de notas). Se guardan 30 días y luego van a la papelera.
Future<void> showCompleted(BuildContext context, NotesRepository repo) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final notes = repo.completed;
          final p = Palette.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.task_alt_rounded, color: p.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(tr('Completadas'),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  trf(
                      'Las tareas completadas llegan aquí a los {0} minutos y '
                      'se guardan {1} días.',
                      [
                        NotesRepository.completedAfterMinutes,
                        NotesRepository.completedKeepDays
                      ]),
                  style: TextStyle(color: p.secondary),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Anim.medium,
                  child: notes.isEmpty
                      ? Center(
                          key: const ValueKey('vacia'),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.task_alt_rounded,
                                  size: 52,
                                  color: p.secondary.withValues(alpha: 0.5)),
                              const SizedBox(height: 10),
                              Text(tr('Todavía no hay tareas completadas'),
                                  style: TextStyle(color: p.secondary)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          key: const ValueKey('lista'),
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: notes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) => _CompletedTile(
                            key: ValueKey(notes[i].id),
                            note: notes[i],
                            until: repo.completedUntil(notes[i]),
                            onRestore: () => repo.toggleDone(notes[i].id),
                            onDelete: () => repo.delete(notes[i].id),
                          )
                              .animate(delay: (30 * i.clamp(0, 12)).ms)
                              .fadeIn(duration: Anim.medium)
                              .slideY(begin: 0.15, curve: Anim.curve),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _CompletedTile extends StatelessWidget {
  const _CompletedTile({
    super.key,
    required this.note,
    required this.until,
    required this.onRestore,
    required this.onDelete,
  });

  final Note note;
  final DateTime until;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final days = until.difference(DateTime.now().toUtc()).inDays;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: p.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: p.secondary)),
                  const SizedBox(height: 2),
                  Text(
                    '${note.doneAt == null ? '' : '${fechaCorta(note.doneAt!)} · '}'
                    '${trn(days < 0 ? 0 : days, 'se borra en {0} día', 'se borra en {0} días')}',
                    style: TextStyle(color: p.secondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Volver a pendiente'),
              icon: const Icon(Icons.undo_rounded),
              onPressed: onRestore,
            ),
            IconButton(
              tooltip: tr('Eliminar'),
              icon: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
