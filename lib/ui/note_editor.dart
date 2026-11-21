import 'dart:math';

import 'package:flutter/material.dart';

import '../data/notes_repository.dart';
import 'anim.dart';
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
    required this.onClose,
    required this.onDelete,
    this.showBack = true,
    this.autofocus = false,
  });

  final NotesRepository repo;
  final String noteId;

  /// Cerrar el editor (volver a la lista o vaciar el panel).
  final VoidCallback onClose;

  /// Borrar la nota (lo gestiona la pantalla principal para poder deshacer).
  final void Function(String id) onDelete;

  /// true en pantallas estrechas (móvil/ventana pequeña): botón "< Notas".
  final bool showBack;
  final bool autofocus;

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
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      return;
    }
    final recentlyTyped =
        DateTime.now().difference(_lastTyped) < const Duration(seconds: 2);
    if (n.content != _ctrl.text && !recentlyTyped) {
      final sel = _ctrl.selection.baseOffset;
      final off = min(sel < 0 ? n.content.length : sel, n.content.length);
      _ctrl.value = TextEditingValue(
        text: n.content,
        selection: TextSelection.collapsed(offset: off),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.repo.removeListener(_onRepo);
    _focus.removeListener(_onFocus);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.repo.byId(widget.noteId);
    final accent = Palette.accent(context);
    final pinned = n?.pinned ?? false;

    return Scaffold(
      backgroundColor: Palette.card(context),
      appBar: AppBar(
        backgroundColor: Palette.card(context),
        automaticallyImplyLeading: false,
        leadingWidth: widget.showBack ? 110 : 0,
        leading: widget.showBack
            ? Bouncy(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: accent),
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  label: const Text('Notas', style: TextStyle(fontSize: 17)),
                ),
              )
            : null,
        actions: [
          if (n != null)
            Bouncy(
              pressedScale: 0.85,
              child: IconButton(
                tooltip: pinned ? 'Desfijar' : 'Fijar arriba',
                onPressed: () => widget.repo.togglePin(widget.noteId),
                icon: AnimatedSwitcher(
                  duration: Anim.medium,
                  transitionBuilder: (c, a) => RotationTransition(
                    turns: Tween(begin: -0.15, end: 0.0).animate(a),
                    child: ScaleTransition(scale: a, child: c),
                  ),
                  child: Icon(
                    pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    key: ValueKey(pinned),
                  ),
                ),
              ),
            ),
          Bouncy(
            pressedScale: 0.85,
            child: IconButton(
              tooltip: 'Eliminar nota',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                _closing = true;
                widget.onDelete(widget.noteId);
              },
            ),
          ),
          AnimatedSwitcher(
            duration: Anim.medium,
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SizeTransition(
                sizeFactor: a,
                axis: Axis.horizontal,
                child: ScaleTransition(scale: a, child: c),
              ),
            ),
            child: _focus.hasFocus
                ? TextButton(
                    key: const ValueKey('ok'),
                    onPressed: () => _focus.unfocus(),
                    child: Text('OK',
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  )
                : const SizedBox(key: ValueKey('nada')),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            // En ventanas muy anchas el texto no se estira de lado a lado.
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  if (n != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AnimatedSwitcher(
                        duration: Anim.medium,
                        child: Text(
                          fechaLarga(n.updatedAt),
                          key: ValueKey(fechaLarga(n.updatedAt)),
                          style: TextStyle(
                              color: Palette.secondary(context), fontSize: 13),
                        ),
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
                      decoration: const InputDecoration.collapsed(
                          hintText: 'Escribe algo…'),
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
        ),
      ),
    );
  }
}
