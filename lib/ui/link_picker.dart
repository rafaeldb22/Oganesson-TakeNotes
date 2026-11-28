import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/ai_actions.dart';
import '../data/ai_assistant.dart';
import '../data/note_attachments.dart';
import '../data/note_links.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'attachments_ui.dart';
import 'i18n.dart';
import 'text_menu.dart';
import 'theme.dart';
import 'toast.dart';

/// Elegir con qué notas está enlazada [noteId] (casillas). Marca las que ya
/// lo están (en cualquier sentido) y aplica los cambios al guardar.
Future<void> showLinkNotesPicker(
    BuildContext context, NotesRepository repo, String noteId,
    {bool suggest = false}) async {
  final graph = NoteGraph.of(repo);
  final current = graph.neighbors(noteId);
  final result = await showDialog<Set<String>>(
    context: context,
    builder: (_) => _LinkPicker(
        repo: repo, noteId: noteId, initial: {...current}, suggest: suggest),
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
      {required this.repo,
      required this.noteId,
      required this.initial,
      this.suggest = false});
  final NotesRepository repo;
  final String noteId;
  final Set<String> initial;

  /// Pedir sugerencias a la IA nada más abrir.
  final bool suggest;

  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
  final _query = TextEditingController();
  late final Set<String> _selected = {...widget.initial};

  /// Las que ha sugerido la IA (salen primero y con un destello).
  Set<String> _suggested = {};
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    if (widget.suggest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _suggest());
    }
  }

  Future<void> _suggest() async {
    final note = widget.repo.byId(widget.noteId);
    if (note == null || _thinking) return;
    if (!AiSettings.instance.configured) {
      await AiSettings.instance.load();
    }
    if (!AiSettings.instance.configured) {
      if (mounted) {
        showToast(
            context, tr('Pon tu clave en el Asistente IA para usar esto.'),
            icon: Icons.auto_awesome_outlined);
      }
      return;
    }
    setState(() => _thinking = true);
    try {
      final ids = await suggestLinks(widget.repo, note);
      if (!mounted) return;
      setState(() {
        _suggested = ids.toSet();
        _selected.addAll(ids);
      });
      showToast(
          context,
          ids.isEmpty
              ? tr('La IA no ha encontrado notas relacionadas')
              : trn(ids.length, 'La IA sugiere {0} nota',
                  'La IA sugiere {0} notas'),
          icon: Icons.auto_awesome_rounded);
    } on AiException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _attach(String kind) async {
    await pickAndConnect(context, widget.repo, widget.noteId, kind);
    if (mounted) setState(() {});
  }

  /// Añadir archivos conectados (salen abajo de la nota, no en su texto).
  Widget _files(BuildContext context, Note note) {
    final p = Palette.of(context);
    final linked = linkedMedia(note);
    Widget add(String kind, IconData icon, String label) => Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _attach(kind),
            icon: Icon(icon, size: 17),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Conectar con archivos'),
              style: TextStyle(
                  color: p.secondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              add('imagen', Icons.image_outlined, tr('Imagen')),
              const SizedBox(width: 6),
              add('voz', Icons.mic_none_rounded, tr('Voz')),
              const SizedBox(width: 6),
              add('archivo', Icons.insert_drive_file_outlined, tr('Archivo')),
            ],
          ),
          if (linked.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final m in linked)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        avatar: Icon(mediaIcon(m), size: 16),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: Text(
                              m.kind == MediaKind.image ? tr('Imagen') : m.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        onPressed: () => openMediaItem(context, m),
                        deleteButtonTooltipMessage: tr('Quitar'),
                        onDeleted: () {
                          removeLinkedMedia(widget.repo, widget.noteId, m.path);
                          setState(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Note> _matches() {
    final q = _query.text.trim().toLowerCase();
    final all = widget.repo.notes
        .where((n) => !n.isEmpty && n.id != widget.noteId)
        .toList()
      // Primero las ya enlazadas, luego las editadas hace menos.
      ..sort((a, b) {
        final sa = _suggested.contains(a.id);
        final sb = _suggested.contains(b.id);
        if (sa != sb) return sa ? -1 : 1;
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
      title: Row(children: [
        Expanded(child: Text(tr('Enlazar notas y archivos'))),
        if (note != null && !note.vault)
          _thinking
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton.icon(
                  onPressed: _suggest,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(tr('Sugerir con IA')),
                ),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 440,
        height: (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                210)
            .clamp(200.0, 510.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Con el teclado abierto no cabe: se deja sitio a la búsqueda.
            if (note != null && MediaQuery.viewInsetsOf(context).bottom == 0)
              _files(context, note),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  trf('Marca las notas que quieres conectar con «{0}».',
                      [note.title]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                          secondary: _suggested.contains(n.id)
                              ? Icon(Icons.auto_awesome_rounded,
                                  size: 18, color: p.accent)
                              : n.color == null
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
