import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'i18n.dart';
import 'notes_home.dart' show confirmDelete;
import 'theme.dart';
import 'toast.dart';

/// Archivadas: notas que se deslizaron a la izquierda. Se pueden devolver a
/// las notas o eliminar.
Future<void> showArchived(BuildContext context, NotesRepository repo) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final notes = repo.archivedNotes;
          final p = Palette.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, color: p.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(tr('Archivadas'),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                    tr('Desliza una nota hacia la izquierda para archivarla.'),
                    style: TextStyle(color: p.secondary)),
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
                              Icon(Icons.inventory_2_outlined,
                                  size: 52,
                                  color: p.secondary.withValues(alpha: 0.5)),
                              const SizedBox(height: 10),
                              Text(tr('No hay notas archivadas'),
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
                          itemBuilder: (context, i) => _ArchivedTile(
                            key: ValueKey(notes[i].id),
                            note: notes[i],
                            onRestore: () {
                              repo.setArchived(notes[i].id, false);
                              showToast(context, tr('Nota desarchivada'),
                                  icon: Icons.unarchive_outlined);
                            },
                            onDelete: () async {
                              final n = notes[i];
                              if (await confirmDelete(context, n.title)) {
                                repo.delete(n.id);
                              }
                            },
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

class _ArchivedTile extends StatelessWidget {
  const _ArchivedTile({
    super.key,
    required this.note,
    required this.onRestore,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Icon(Icons.archive_outlined, color: p.secondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${fechaCorta(note.updatedAt)}'
                    '${note.hasPreview ? ' · ${note.preview}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.secondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Desarchivar'),
              icon: const Icon(Icons.unarchive_outlined),
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
