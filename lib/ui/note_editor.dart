import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../data/note_links.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'editor_toolbar.dart';
import 'folders.dart';
import 'note_color_sheet.dart';
import 'image_tools.dart';
import 'note_image.dart';
import 'note_tools.dart';
import 'format.dart';
import 'link_picker.dart';
import 'schedule_sheet.dart';
import 'smooth_scroll.dart';
import 'text_menu.dart';
import 'theme.dart';
import 'urgency.dart';
import 'i18n.dart';

/// Editor de una nota con formato (negrita, títulos, listas, casillas,
/// colores, alineación…) usando flutter_quill.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.repo,
    required this.noteId,
    required this.onClose,
    required this.onDelete,
    this.onOpenNote,
    this.onCommandPalette,
    this.showBack = true,
    this.autofocus = false,
  });

  final NotesRepository repo;
  final String noteId;

  /// Cerrar el editor (volver a la lista o vaciar el panel).
  final VoidCallback onClose;

  /// Borrar la nota (lo gestiona la pantalla principal para poder deshacer).
  final void Function(String id) onDelete;

  /// Abrir otra nota (desde el panel de enlaces).
  final void Function(String id)? onOpenNote;

  /// Ctrl+K dentro del editor (Quill lo usa para enlaces si no se indica).
  final VoidCallback? onCommandPalette;

  /// true en pantallas estrechas (móvil/ventana pequeña): botón "< notas".
  final bool showBack;
  final bool autofocus;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final QuillController _ctrl;
  final _focus = FocusNode();
  final _editorKey = GlobalKey<EditorState>();
  final _scroll = SmoothScrollController();
  DateTime _lastTyped = DateTime(2000);
  bool _closing = false;
  bool _applyingRemote = false;
  bool _toolbarOpen = true;

  /// El cursor está justo al lado de una imagen: ahí se oculta, porque
  /// tomaría la altura de la imagen y se vería gigante.
  bool _caretByImage = false;
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
      // Ctrl+V con una imagen en el portapapeles (p. ej. una captura): se
      // pega como imagen; si hay texto, se pega el texto como siempre.
      // ignore: experimental_member_use
      config: QuillControllerConfig(
        // ignore: experimental_member_use
        clipboardConfig: QuillClipboardConfig(
          // ignore: experimental_member_use
          onClipboardPaste: () async =>
              mounted && await pasteImagesFromClipboard(context, _ctrl),
        ),
      ),
    );
    // Nota nueva: lo primero que escribas sale en grande, como un título.
    // Al pulsar Intro la siguiente línea ya es texto normal.
    if (_ctrl.document.toPlainText().trim().isEmpty) {
      _ctrl.formatSelection(Attribute.h1);
    }
    _lastSaved = _richJson();
    _ctrl.addListener(_onEdit);
    _ctrl.addListener(_onCaret);
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

  void _onCaret() {
    final by = caretNextToImage(_ctrl);
    if (by != _caretByImage && mounted) setState(() => _caretByImage = by);
  }

  /// Crea la nota de un enlace que aún no existe y la abre.
  void _createLinked(String title) {
    final n = repo.createNote(folderId: repo.byId(widget.noteId)?.folderId);
    repo.updateContent(n.id, title);
    widget.onOpenNote?.call(n.id);
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
    // Nota nueva aún vacía en los dos lados: no es un cambio remoto. Si se
    // tratara como tal, se perdería el formato de título que la nota nueva
    // tiene preparado antes de escribir la primera letra.
    if (n.rich == null && n.content.trim().isEmpty && _plain().trim().isEmpty) {
      setState(() {});
      return;
    }
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
    _ctrl.removeListener(_onCaret);
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
    // La fuente del tema, como el resto de la app.
    final font = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    const h0 = HorizontalSpacing(0, 0);
    const v0 = VerticalSpacing(0, 0);
    DefaultTextBlockStyle block(
            double size, FontWeight w, double top, double bottom,
            {double height = 1.3}) =>
        DefaultTextBlockStyle(
          TextStyle(
              fontFamily: font,
              fontSize: size,
              fontWeight: w,
              height: height,
              color: fg),
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
            fontFamily: font,
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

  bool _subtasksOpen = false;

  void _toolAction(String v) {
    final n = repo.byId(widget.noteId);
    if (n == null) return;
    switch (v) {
      case 'subtareas':
        setState(() => _subtasksOpen = !_subtasksOpen);
      case 'historial':
        showHistorySheet(context, repo, n.id);
      case 'plantilla':
        saveAsTemplate(context, n);
      case 'exportar':
        showExportNote(context, n);
    }
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
                  tooltip: tr('Volver'),
                  color: accent,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
              )
            : null,
        actions: [
          // Fechas / recordatorio
          _iconAction(
            tooltip: tr('Nota temporal y avisos'),
            icon: Icon(
              n?.isTemporal == true ? Icons.alarm_on : Icons.alarm_add_outlined,
            ),
            onPressed: () => showScheduleSheet(context, repo, widget.noteId),
          ),
          // Color de la nota (y de su mecha)
          _iconAction(
            tooltip: tr('Color de la nota'),
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
              tooltip: tr('Mover a carpeta'),
              icon: Icon(folder == null ? Icons.folder_outlined : Icons.folder,
                  color:
                      folder?.color != null ? Color(folder!.color!) : accent),
              onSelected: (v) =>
                  repo.moveToFolder(widget.noteId, v == '' ? null : v),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                    value: '',
                    checked: n?.folderId == null,
                    child: Text(tr('Sin carpeta'))),
                for (final f in repo.folders)
                  CheckedPopupMenuItem(
                      value: f.id,
                      checked: n?.folderId == f.id,
                      child: Text(f.name)),
              ],
            ),
            if (n != null)
              _iconAction(
                tooltip: pinned ? tr('Desfijar') : tr('Fijar arriba'),
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
              tooltip:
                  _toolbarOpen ? tr('Ocultar formato') : tr('Mostrar formato'),
              icon: Icon(_toolbarOpen ? Icons.text_format : Icons.text_fields),
              onPressed: () => setState(() => _toolbarOpen = !_toolbarOpen),
            ),
            PopupMenuButton<String>(
              tooltip: tr('Más'),
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: _toolAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'subtareas',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.checklist_rounded),
                        title: Text(tr('Subtareas')))),
                PopupMenuItem(
                    value: 'historial',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(tr('Historial de versiones')))),
                PopupMenuItem(
                    value: 'plantilla',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bookmark_add_outlined),
                        title: Text(tr('Guardar como plantilla')))),
                PopupMenuItem(
                    value: 'exportar',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.ios_share_rounded),
                        title: Text(tr('Exportar')))),
              ],
            ),
            _iconAction(
              tooltip: tr('Eliminar nota'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                _closing = true;
                widget.onDelete(widget.noteId);
              },
            ),
          ] else
            // Móvil: el resto va en un menú para que nada se monte.
            PopupMenuButton<String>(
              tooltip: tr('Más'),
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
                  case 'imagen':
                    await pickAndInsertImages(context, _ctrl);
                  case 'borrar':
                    _closing = true;
                    widget.onDelete(widget.noteId);
                  default:
                    _toolAction(v);
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
                        title: Text(folder?.name ?? tr('Mover a carpeta')))),
                PopupMenuItem(
                    value: 'fijar',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                            pinned ? Icons.push_pin : Icons.push_pin_outlined),
                        title: Text(
                            pinned ? tr('Desfijar') : tr('Fijar arriba')))),
                PopupMenuItem(
                    value: 'formato',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.text_format),
                        title: Text(_toolbarOpen
                            ? tr('Ocultar formato')
                            : tr('Mostrar formato')))),
                PopupMenuItem(
                    value: 'imagen',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.add_photo_alternate_outlined),
                        title: Text(tr('Añadir imagen')))),
                PopupMenuItem(
                    value: 'subtareas',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.checklist_rounded),
                        title: Text(tr('Subtareas')))),
                PopupMenuItem(
                    value: 'historial',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(tr('Historial de versiones')))),
                PopupMenuItem(
                    value: 'plantilla',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bookmark_add_outlined),
                        title: Text(tr('Guardar como plantilla')))),
                PopupMenuItem(
                    value: 'exportar',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.ios_share_rounded),
                        title: Text(tr('Exportar')))),
                PopupMenuItem(
                    value: 'borrar',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text(tr('Eliminar'),
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
                      child: Text(tr('OK'),
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    ).animate().fadeIn(duration: Anim.fast).scale(
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
                  ? EditorToolbar(
                      controller: _ctrl,
                      onImage: () => pickAndInsertImages(context, _ctrl),
                      onLink: () =>
                          showLinkNotesPicker(context, repo, widget.noteId),
                    )
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
                        if (n != null &&
                            (_subtasksOpen || n.subtasks.isNotEmpty))
                          SubtasksPanel(repo: repo, note: n),
                        Expanded(
                          child: ImageDropZone(
                            onImages: (images) =>
                                insertImages(context, _ctrl, images),
                            child: ImageMoveTarget(
                              controller: _ctrl,
                              editorKey: _editorKey,
                              child: QuillEditor(
                                controller: _ctrl,
                                focusNode: _focus,
                                scrollController: _scroll,
                                config: QuillEditorConfig(
                                  editorKey: _editorKey,
                                  showCursor: !_caretByImage,
                                  placeholder: tr('Escribe algo…'),
                                  autoFocus: widget.autofocus,
                                  expands: true,
                                  padding: const EdgeInsets.only(bottom: 40),
                                  customStyles: _styles(context),
                                  // Imágenes: se dibujan con su propio estilo,
                                  // Ctrl+V pega capturas y el teclado de Android
                                  // puede insertar imágenes directamente.
                                  embedBuilders: const [
                                    NoteImageEmbedBuilder()
                                  ],
                                  customShortcuts:
                                      widget.onCommandPalette == null
                                          ? null
                                          : const {
                                              SingleActivator(
                                                LogicalKeyboardKey.keyK,
                                                control: true,
                                              ): _PaletteIntent(),
                                            },
                                  customActions: widget.onCommandPalette == null
                                      ? null
                                      : {
                                          _PaletteIntent:
                                              CallbackAction<_PaletteIntent>(
                                            onInvoke: (_) {
                                              widget.onCommandPalette!();
                                              return null;
                                            },
                                          ),
                                        },
                                  contentInsertionConfiguration:
                                      ContentInsertionConfiguration(
                                    allowedMimeTypes: const [
                                      'image/png',
                                      'image/jpeg',
                                      'image/gif',
                                      'image/webp',
                                    ],
                                    onContentInserted: (c) {
                                      final data = c.data;
                                      if (data != null && data.isNotEmpty) {
                                        insertImages(context, _ctrl, [data]);
                                      }
                                    },
                                  ),
                                  // Menú de cortar/copiar/pegar con el estilo de la app.
                                  contextMenuBuilder: (context, state) =>
                                      buildTextMenu(
                                          context,
                                          state.contextMenuButtonItems,
                                          state.contextMenuAnchors),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (n != null)
                          _LinksBar(
                            graph: NoteGraph.of(repo),
                            noteId: n.id,
                            repo: repo,
                            onOpen: widget.onOpenNote,
                            onCreate: _createLinked,
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

class _PaletteIntent extends Intent {
  const _PaletteIntent();
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
            tooltip: note.done ? tr('Marcar pendiente') : tr('Completar'),
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

/// Enlaces de la nota: a qué notas enlaza (→), cuáles la mencionan (←)
/// y enlaces a notas que aún no existen (+, al tocarlos se crean).
class _LinksBar extends StatelessWidget {
  const _LinksBar({
    required this.graph,
    required this.noteId,
    required this.repo,
    required this.onOpen,
    required this.onCreate,
  });

  final NoteGraph graph;
  final String noteId;
  final NotesRepository repo;
  final void Function(String id)? onOpen;
  final void Function(String title) onCreate;

  @override
  Widget build(BuildContext context) {
    final out = graph.outgoing[noteId] ?? const <String>{};
    final back = graph.incoming[noteId] ?? const <String>{};
    final missing = graph.unresolved[noteId] ?? const <String>{};
    if (out.isEmpty && back.isEmpty && missing.isEmpty) {
      return const SizedBox.shrink();
    }
    final p = Palette.of(context);

    Widget chip(
        IconData icon, String label, String tooltip, VoidCallback? onTap,
        {bool dashed = false}) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: dashed ? Colors.transparent : p.searchFill,
            shape: StadiumBorder(
                side: BorderSide(
                    color: dashed
                        ? p.accent.withValues(alpha: 0.6)
                        : p.separator)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 14, color: dashed ? p.accent : p.secondary),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    String title(String id) => repo.byId(id)?.title ?? tr('Nota');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.separator)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.hub_outlined, size: 16, color: p.accent),
            ),
            for (final id in out)
              chip(
                  Icons.north_east_rounded,
                  title(id),
                  tr('Enlaza a esta nota'),
                  onOpen == null ? null : () => onOpen!(id)),
            for (final id in back)
              chip(
                  Icons.south_west_rounded,
                  title(id),
                  tr('Esta nota te menciona'),
                  onOpen == null ? null : () => onOpen!(id)),
            for (final t in missing)
              chip(Icons.add_rounded, t, trf('Crear la nota «{0}»', [t]),
                  () => onCreate(t),
                  dashed: true),
          ],
        ),
      ),
    ).animate().fadeIn(duration: Anim.fast);
  }
}
