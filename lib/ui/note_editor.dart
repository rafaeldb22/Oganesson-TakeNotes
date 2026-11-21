import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/notes_repository.dart';
import 'format.dart';
import 'theme.dart';

/// Pinta la primera línea en grande y en negrita (título), como en iPhone.
class _TitleController extends TextEditingController {
  _TitleController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final titleStyle = base.copyWith(
        fontSize: 26, fontWeight: FontWeight.w700, height: 1.3);
    final t = text;
    final nl = t.indexOf('\n');
    if (nl == -1) return TextSpan(style: titleStyle, text: t);
    return TextSpan(style: base, children: [
      TextSpan(text: t.substring(0, nl), style: titleStyle),
      TextSpan(text: t.substring(nl)),
    ]);
  }
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.repo,
    required this.noteId,
    this.embedded = false,
    this.autofocus = false,
    this.onClosed,
  });

  final NotesRepository repo;
  final String noteId;

  /// true = panel derecho en pantallas anchas (PC); false = pantalla completa.
  final bool embedded;
  final bool autofocus;
  final VoidCallback? onClosed;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _TitleController _ctrl;
  final _focus = FocusNode();
  DateTime _lastTyped = DateTime(2000);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = _TitleController(text: widget.repo.byId(widget.noteId)?.content);
    widget.repo.addListener(_onRepo);
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  /// Cambios que llegan desde el otro dispositivo mientras la nota está abierta.
  void _onRepo() {
    if (!mounted || _closing) return;
    final n = widget.repo.byId(widget.noteId);
    if (n == null || n.deleted) {
      _close();
      return;
    }
    final recentlyTyped =
        DateTime.now().difference(_lastTyped) < const Duration(seconds: 2);
    if (n.content != _ctrl.text && !recentlyTyped) {
      final off = min(_ctrl.selection.baseOffset < 0 ? n.content.length
          : _ctrl.selection.baseOffset, n.content.length);
      _ctrl.value = TextEditingValue(
        text: n.content,
        selection: TextSelection.collapsed(offset: off),
      );
    }
    setState(() {});
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    if (widget.embedded) {
      widget.onClosed?.call();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _delete() {
    _closing = true;
    final id = widget.noteId;
    if (widget.embedded) {
      widget.onClosed?.call();
    } else {
      Navigator.of(context).pop();
    }
    widget.repo.delete(id);
  }

  @override
  void dispose() {
    widget.repo.removeListener(_onRepo);
    _focus.removeListener(_onFocus);
    final repo = widget.repo;
    final id = widget.noteId;
    // Se ejecuta tras el frame actual para no notificar con el árbol bloqueado.
    scheduleMicrotask(() => repo.finishEditing(id));
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.repo.byId(widget.noteId);
    final accent = Palette.accent(context);

    final actions = <Widget>[
      if (n != null)
        IconButton(
          tooltip: n.pinned ? 'Desfijar' : 'Fijar arriba',
          icon: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined),
          onPressed: () => widget.repo.togglePin(widget.noteId),
        ),
      IconButton(
        tooltip: 'Eliminar nota',
        icon: const Icon(Icons.delete_outline),
        onPressed: _delete,
      ),
      if (_focus.hasFocus)
        TextButton(
          onPressed: () => _focus.unfocus(),
          child: Text('OK',
              style: TextStyle(
                  color: accent, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      const SizedBox(width: 6),
    ];

    return Scaffold(
      backgroundColor: Palette.card(context),
      appBar: AppBar(
        backgroundColor: Palette.card(context),
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              if (n != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    fechaLarga(n.updatedAt),
                    style: TextStyle(
                        color: Palette.secondary(context), fontSize: 13),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 17, height: 1.45),
                  decoration:
                      const InputDecoration.collapsed(hintText: 'Escribe algo…'),
                  onChanged: (t) {
                    _lastTyped = DateTime.now();
                    widget.repo.updateContent(widget.noteId, t);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
