import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'editor_toolbar.dart';
import 'folders.dart';
import 'note_color_sheet.dart';
import 'format.dart';
import 'schedule_sheet.dart';
import 'theme.dart';
import 'urgency.dart';

/// Editor de una nota con formato (negrita, títulos, listas, casillas,
/// colores, alineación…) usando flutter_quill.
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

  /// true en pantallas estrechas (móvil/ventana pequeña): botón "< notas".
  final bool showBack;
  final bool autofocus;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final QuillController _ctrl;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  DateTime _lastTyped = DateTime(2000);
  bool _closing = false;
  bool _applyingRemote = false;
  bool _toolbarOpen = true;
  String _lastSaved = '';

  NotesRepository get repo => widget.repo;

  static Document _docFor(Note? n) {
    if (n?.rich != null) {
      try {
        return Document.fromJson(jsonDecode(n!.rich!) as List);
      } catch (_) {}
    }
    final d = Document();
    final text = n?.content ?? '';
    if (text.isNotEmpty) {
      d.insert(0, text);
      // La primera línea de las notas de texto plano se ve como título.
      final first = text.indexOf('\n');
      d.format(0, first == -1 ? text.length : first, Attribute.h1);
    }
    return d;
  }

  String _plain() {
    final t = _ctrl.document.toPlainText();
    return t.endsWith('\n') ? t.substring(0, t.length - 1) : t;
  }

  String _richJson() => jsonEncode(_ctrl.document.toDelta().toJson());

  @override
  void initState() {
    super.initState();
    final n = repo.byId(widget.noteId);
    _ctrl = QuillController(
      document: _docFor(n),
      selection: const TextSelection.collapsed(offset: 0),
    );
    // Nota nueva: lo primero que escribas sale en grande, como un título.
    // Al pulsar Intro la siguiente línea ya es texto normal.
    if (_ctrl.document.toPlainText().trim().isEmpty) {
      _ctrl.formatSelection(Attribute.h1);
    }
    _lastSaved = _richJson();
    _ctrl.addListener(_onEdit);
    repo.addListener(_onRepo);
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  void _onEdit() {
    if (_applyingRemote || _closing) return;
    final rich = _richJson();
    if (rich == _lastSaved) return; // solo cambió el cursor
    _lastSaved = rich;
    _lastTyped = DateTime.now();
    repo.updateContent(widget.noteId, _plain(), rich: rich);
  }

  /// Cambios que llegan desde el otro dispositivo mientras la nota está abierta.
  void _onRepo() {
    if (!mounted || _closing) return;
    final n = repo.byId(widget.noteId);
    if (n == null || n.deleted) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      return;
    }
    final recentlyTyped =
        DateTime.now().difference(_lastTyped) < const Duration(seconds: 2);
    final remoteRich = n.rich ?? jsonEncode(_docFor(n).toDelta().toJson());
    if (!recentlyTyped && remoteRich != _lastSaved) {
      _applyingRemote = true;
      final sel = _ctrl.selection.baseOffset;
      _ctrl.document = _docFor(n);
      final len = max(0, _ctrl.document.length - 1);
      _ctrl.updateSelection(
          TextSelection.collapsed(offset: min(max(sel, 0), len)),
          ChangeSource.local);
      _lastSaved = _richJson();
      _applyingRemote = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    repo.removeListener(_onRepo);
    _ctrl.removeListener(_onEdit);
    _focus.removeListener(_onFocus);
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Tipografía del editor: títulos claros, texto cómodo de leer y citas
  /// con el color del tema.
  DefaultStyles _styles(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF151515);
    const h0 = HorizontalSpacing(0, 0);
    const v0 = VerticalSpacing(0, 0);
    DefaultTextBlockStyle block(double size, FontWeight w, double top,
            double bottom, {double height = 1.3}) =>
        DefaultTextBlockStyle(
          TextStyle(fontSize: size, fontWeight: w, height: height, color: fg),
          h0,
          VerticalSpacing(top, bottom),
          v0,
          null,
        );
    return DefaultStyles(
      h1: block(28, FontWeight.w800, 12, 6, height: 1.2),
      h2: block(22, FontWeight.w700, 10, 4, height: 1.25),
      h3: block(18, FontWeight.w700, 8, 2),
      paragraph: block(16.5, FontWeight.w400, 2, 2, height: 1.55),
      quote: DefaultTextBlockStyle(
        TextStyle(
            fontSize: 16.5,
            height: 1.55,
            fontStyle: FontStyle.italic,
            color: fg.withValues(alpha: 0.75)),
        h0,
        const VerticalSpacing(6, 6),
        v0,
        BoxDecoration(
          border: Border(
              left: BorderSide(color: Palette.accent(context), width: 3)),
        ),
      ),
    );
  }

  Widget _iconAction({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
  }) =>
      Bouncy(
        pressedScale: 0.85,
        child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon),
      );

  @override
  Widget build(BuildContext context) {
    final n = repo.byId(widget.noteId);
    final accent = Palette.accent(context);
    final pinned = n?.pinned ?? false;
    final folder = repo.folderById(n?.folderId);
    // Barra compacta en móvil / ventanas estrechas.
    final compact = MediaQuery.sizeOf(context).width < 640;

    return Scaffold(
      backgroundColor: Palette.card(context),
      appBar: AppBar(
        backgroundColor: Palette.card(context),
        automaticallyImplyLeading: false,
        leadingWidth: widget.showBack ? 52 : 0,
        leading: widget.showBack
            ? Bouncy(
                pressedScale: 0.85,
                child: IconButton(
                  tooltip: 'Volver',
                  color: accent,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
              )
            : null,
        actions: [
          // Fechas / recordatorio
          _iconAction(
            tooltip: 'Nota temporal y avisos',
            icon: Icon(
              n?.isTemporal == true
                  ? Icons.alarm_on
                  : Icons.alarm_add_outlined,
            ),
            onPressed: () => showScheduleSheet(context, repo, widget.noteId),
          ),
          // Color de la nota (y de su mecha)
          _iconAction(
            tooltip: 'Color de la nota',
            icon: n?.color == null
                ? const Icon(Icons.palette_outlined)
                : Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: fusePalette(n!.color)),
                    ),
                  ),
            onPressed: () => showNoteColorSheet(context, repo, widget.noteId),
          ),
          if (!compact) ...[
            // Carpeta
            PopupMenuButton<String>(
              tooltip: 'Mover a carpeta',
              icon: Icon(folder == null ? Icons.folder_outlined : Icons.folder,
                  color:
                      folder?.color != null ? Color(folder!.color!) : accent),
              onSelected: (v) =>
                  repo.moveToFolder(widget.noteId, v == '' ? null : v),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                    value: '',
                    checked: n?.folderId == null,
                    child: const Text('Sin carpeta')),
                for (final f in repo.folders)
                  CheckedPopupMenuItem(
                      value: f.id,
                      checked: n?.folderId == f.id,
                      child: Text(f.name)),
              ],
            ),
            if (n != null)
              _iconAction(
                tooltip: pinned ? 'Desfijar' : 'Fijar arriba',
                onPressed: () => repo.togglePin(widget.noteId),
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
            _iconAction(
              tooltip: _toolbarOpen ? 'Ocultar formato' : 'Mostrar formato',
              icon: Icon(_toolbarOpen ? Icons.text_format : Icons.text_fields),
              onPressed: () => setState(() => _toolbarOpen = !_toolbarOpen),
            ),
            _iconAction(
              tooltip: 'Eliminar nota',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                _closing = true;
                widget.onDelete(widget.noteId);
              },
            ),
          ] else
            // Móvil: el resto va en un menú para que nada se monte.
            PopupMenuButton<String>(
              tooltip: 'Más',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) async {
                switch (v) {
                  case 'carpeta':
                    final r = await pickFolder(context, repo, n?.folderId);
                    if (r != null) {
                      repo.moveToFolder(widget.noteId, r.isEmpty ? null : r);
                    }
                  case 'fijar':
                    repo.togglePin(widget.noteId);
                  case 'formato':
                    setState(() => _toolbarOpen = !_toolbarOpen);
                  case 'borrar':
                    _closing = true;
                    widget.onDelete(widget.noteId);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'carpeta',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(folder == null
                            ? Icons.folder_outlined
                            : Icons.folder),
                        title: Text(folder?.name ?? 'Mover a carpeta'))),
                PopupMenuItem(
                    value: 'fijar',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined),
                        title: Text(pinned ? 'Desfijar' : 'Fijar arriba'))),
                PopupMenuItem(
                    value: 'formato',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.text_format),
                        title: Text(_toolbarOpen
                            ? 'Ocultar formato'
                            : 'Mostrar formato'))),
                const PopupMenuItem(
                    value: 'borrar',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Eliminar',
                            style: TextStyle(color: Colors.red)))),
              ],
            ),
          // Botón OK: aparece con un pequeño "pop", siempre centrado.
          AnimatedSize(
            duration: Anim.medium,
            curve: Anim.curve,
            child: _focus.hasFocus
                ? Center(
                    child: TextButton(
                      onPressed: () => _focus.unfocus(),
                      child: Text('OK',
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    )
                        .animate()
                        .fadeIn(duration: Anim.fast)
                        .scale(
                            begin: const Offset(0.6, 0.6),
                            curve: Curves.easeOutBack,
                            duration: Anim.medium),
                  )
                : const SizedBox(height: kToolbarHeight),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Barra de formato (se puede ocultar).
            AnimatedSize(
              duration: Anim.medium,
              curve: Anim.curve,
              alignment: Alignment.topCenter,
              child: _toolbarOpen
                  ? EditorToolbar(controller: _ctrl)
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  // En ventanas muy anchas el texto no se estira de lado a lado.
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        if (n != null && n.isTemporal)
                          _TemporalBanner(
                            note: n,
                            onToggleDone: () => repo.toggleDone(n.id),
                            onEdit: () =>
                                showScheduleSheet(context, repo, n.id),
                          ),
                        if (n != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              fechaLarga(n.updatedAt),
                              style: TextStyle(
                                  color: Palette.secondary(context),
                                  fontSize: 13),
                            ),
                          ),
                        Expanded(
                          child: QuillEditor(
                            controller: _ctrl,
                            focusNode: _focus,
                            scrollController: _scroll,
                            config: QuillEditorConfig(
                              placeholder: 'Escribe algo…',
                              autoFocus: widget.autofocus,
                              expands: true,
                              padding: const EdgeInsets.only(bottom: 40),
                              customStyles: _styles(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: Anim.medium, curve: Anim.curve);
  }
}

class _TemporalBanner extends StatelessWidget {
  const _TemporalBanner({
    required this.note,
    required this.onToggleDone,
    required this.onEdit,
  });

  final Note note;
  final VoidCallback onToggleDone;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = urgencyColor(context, note);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: note.done ? 'Marcar pendiente' : 'Completar',
            onPressed: onToggleDone,
            icon: AnimatedSwitcher(
              duration: Anim.medium,
              transitionBuilder: (c, a) => ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                  child: c),
              child: Icon(
                note.done ? Icons.check_circle : Icons.radio_button_unchecked,
                key: ValueKey(note.done),
                color: color,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TimeBar(note: note),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: Anim.medium).slideY(begin: -0.2);
  }
}
