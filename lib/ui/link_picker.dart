import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/note_links.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'i18n.dart';
import 'text_menu.dart';
import 'theme.dart';

/// Elegir con qué notas está enlazada [noteId] (casillas). Marca las que ya
/// lo están (en cualquier sentido) y aplica los cambios al guardar.
Future<void> showLinkNotesPicker(
    BuildContext context, NotesRepository repo, String noteId) async {
  final graph = NoteGraph.of(repo);
  final current = graph.neighbors(noteId);
  final result = await showDialog<Set<String>>(
    context: context,
    builder: (_) =>
        _LinkPicker(repo: repo, noteId: noteId, initial: {...current}),
  );
  if (result == null) return;
  final added = result.difference(current);
  final removed = current.difference(result);
  if (added.isNotEmpty) repo.addLinks(noteId, added);
  for (final id in removed) {
    repo.removeLink(noteId, id);
  }
}

class _LinkPicker extends StatefulWidget {
  const _LinkPicker(
      {required this.repo, required this.noteId, required this.initial});
  final NotesRepository repo;
  final String noteId;
  final Set<String> initial;

  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
  final _query = TextEditingController();
  late final Set<String> _selected = {...widget.initial};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Note> _matches() {
    final q = _query.text.trim().toLowerCase();
    final all = widget.repo.notes
        .where((n) => !n.isEmpty && n.id != widget.noteId)
        .toList()
      // Primero las ya enlazadas, luego las editadas hace menos.
      ..sort((a, b) {
        final la = widget.initial.contains(a.id);
        final lb = widget.initial.contains(b.id);
        if (la != lb) return la ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    if (q.isEmpty) return all;
    return all
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.content.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final note = widget.repo.byId(widget.noteId);
    final matches = _matches();

    return AlertDialog(
      title: Text(tr('Enlazar notas')),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  trf('Marca las notas que quieres conectar con «{0}».',
                      [note.title]),
                  style: TextStyle(color: p.secondary, fontSize: 13),
                ),
              ),
            TextField(
              contextMenuBuilder: textFieldMenu,
              controller: _query,
              autofocus: autoKeyboard,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: tr('Buscar notas…'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(tr('No hay otras notas'),
                          style: TextStyle(color: p.secondary)),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (_, i) {
                        final n = matches[i];
                        final on = _selected.contains(n.id);
                        return CheckboxListTile(
                          value: on,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          onChanged: (v) => setState(() => v == true
                              ? _selected.add(n.id)
                              : _selected.remove(n.id)),
                          title: Text(n.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: !n.hasPreview
                              ? null
                              : Text(n.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: p.secondary)),
                          secondary: n.color == null
                              ? null
                              : Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                      color: Color(n.color!),
                                      shape: BoxShape.circle),
                                ),
                        )
                            .animate(delay: (12 * i.clamp(0, 20)).ms)
                            .fadeIn(duration: Anim.fast);
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancelar'))),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(_selected.isEmpty
              ? tr('Guardar')
              : trn(_selected.length, 'Guardar ({0} enlace)',
                  'Guardar ({0} enlaces)')),
        ),
      ],
    );
  }
}
