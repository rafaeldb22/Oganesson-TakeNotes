import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'theme.dart';

/// Papelera: notas borradas en los últimos 3 días. Se pueden recuperar o
/// borrar para siempre. Pasados los 3 días se borran solas.
Future<void> showTrash(BuildContext context, NotesRepository repo) {
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
          final notes = repo.trash;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Papelera',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                    if (notes.isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.red),
                        onPressed: () => _confirmEmpty(context, repo),
                        child: const Text('Vaciar'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Las notas se borran para siempre a los '
                  '${NotesRepository.trashDays} días.',
                  style: TextStyle(color: Palette.secondary(context)),
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
                              Icon(Icons.auto_delete_outlined,
                                  size: 52,
                                  color: Palette.secondary(context)
                                      .withValues(alpha: 0.5)),
                              const SizedBox(height: 10),
                              Text('La papelera está vacía',
                                  style: TextStyle(
                                      color: Palette.secondary(context))),
                            ],
                          ),
                        )
                      : ListView.separated(
                          key: const ValueKey('lista'),
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: notes.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _TrashTile(
                            key: ValueKey(notes[i].id),
                            note: notes[i],
                            purgeAt: repo.purgeDate(notes[i]),
                            onRestore: () => repo.restore(notes[i].id),
                            onDelete: () =>
                                _confirmDelete(context, repo, notes[i]),
                          )
                              .animate(delay: (30 * i).ms)
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

Future<void> _confirmDelete(
    BuildContext context, NotesRepository repo, Note n) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Borrar para siempre?'),
      content: Text('«${n.title}» se eliminará y no se podrá recuperar.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  if (ok == true) repo.deleteForever(n.id);
}

Future<void> _confirmEmpty(BuildContext context, NotesRepository repo) async {
  final count = repo.trash.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Vaciar la papelera?'),
      content: Text(count == 1
          ? 'Se borrará 1 nota para siempre.'
          : 'Se borrarán $count notas para siempre.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Vaciar'),
        ),
      ],
    ),
  );
  if (ok == true) repo.emptyTrash();
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    super.key,
    required this.note,
    required this.purgeAt,
    required this.onRestore,
    required this.onDelete,
  });

  final Note note;
  final DateTime purgeAt;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  String _left() {
    final d = purgeAt.difference(DateTime.now().toUtc());
    if (d.inHours >= 24) {
      final days = (d.inHours / 24).ceil();
      return days == 1 ? 'Se borra en 1 día' : 'Se borra en $days días';
    }
    if (d.inHours >= 1) return 'Se borra en ${d.inHours} h';
    return 'Se borra en menos de 1 h';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.background(context),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(_left(),
                      style: TextStyle(
                          fontSize: 12.5, color: Palette.secondary(context))),
                ],
              ),
            ),
            Bouncy(
              child: TextButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Recuperar'),
              ),
            ),
            IconButton(
              tooltip: 'Borrar para siempre',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_forever_outlined,
                  color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
