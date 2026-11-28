import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_quill/flutter_quill.dart';
// ignore: implementation_imports
import 'package:flutter_quill/src/editor/widgets/text/text_selection.dart'
    show DragTextSelection;

import '../data/note_attachments.dart';
import '../data/note_board.dart';
import '../data/note_images.dart';
import '../data/note_links.dart';
import '../data/notes_repository.dart';
import '../data/similar_notes.dart';
import '../models/note.dart';
import 'ai_tools_ui.dart';
import 'anim.dart';
import 'attachments_ui.dart';
import 'editor_toolbar.dart';
import 'folders.dart';
import 'note_color_sheet.dart';
import 'image_tools.dart';
import 'drawing_pad.dart';
import 'note_image.dart';
import 'note_media.dart';
import 'note_tools.dart';
import 'format.dart';
import 'link_picker.dart';
import 'schedule_sheet.dart';
import 'share_sheet.dart';
import 'smooth_scroll.dart';
import 'text_menu.dart';
import 'update_dialog.dart' show openLink, webUrl;
import 'theme.dart';
import 'toast.dart';
import 'urgency.dart';
import 'whiteboard.dart';
import 'i18n.dart';

/// Ctrl+F con una nota abierta: abre el buscador de la nota.
final noteFindRequests = StreamController<void>.broadcast();

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

  /// Modo pizarra: mientras existe, `_ctrl` no se toca y se guarda el Delta
  /// de la nota directamente.
  BoardController? _board;
  Timer? _boardSave;

  NotesRepository get repo => widget.repo;

  // Buscar en la nota (Ctrl+F).
  bool _finding = false;
  final _findCtrl = TextEditingController();
  final _findFocus = FocusNode();
  List<int> _matches = const [];
  int _matchAt = 0;
  StreamSubscription<void>? _findSub;

  void _openFind() {
    if (_board != null) return;
    final sel = _ctrl.selection;
    if (!sel.isCollapsed && sel.end - sel.start < 80) {
      _findCtrl.text = _ctrl.document
          .toPlainText()
          .substring(sel.start, sel.end)
          .split('\n')
          .first;
    }
    setState(() => _finding = true);
    _findFocus.requestFocus();
    _findCtrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _findCtrl.text.length);
    _search();
  }

  void _closeFind() {
    setState(() {
      _finding = false;
      _matches = const [];
    });
    _focus.requestFocus();
  }

  void _search() {
    final q = _findCtrl.text.toLowerCase();
    final text = _ctrl.document.toPlainText().toLowerCase();
    final found = <int>[];
    if (q.isNotEmpty) {
      for (var i = text.indexOf(q); i != -1; i = text.indexOf(q, i + 1)) {
        found.add(i);
      }
    }
    // La coincidencia más cercana al cursor.
    final from = _ctrl.selection.start;
    final at = found.indexWhere((i) => i >= from);
    setState(() {
      _matches = found;
      _matchAt = at == -1 ? 0 : at;
    });
    _showMatch();
  }

  void _stepMatch(int d) {
    if (_matches.isEmpty) return;
    setState(() => _matchAt = (_matchAt + d) % _matches.length);
    _showMatch();
  }

  void _showMatch() {
    if (_matches.isEmpty) return;
    final start = _matches[_matchAt];
    _ctrl.updateSelection(
        TextSelection(
            baseOffset: start, extentOffset: start + _findCtrl.text.length),
        ChangeSource.local);
    _editorKey.currentState?.bringIntoView(TextPosition(offset: start));
  }

  Widget _findBar(BuildContext context) {
    final p = Palette.of(context);
    final count = _findCtrl.text.isEmpty
        ? ''
        : _matches.isEmpty
            ? tr('Sin resultados')
            : '${_matchAt + 1}/${_matches.length}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.background,
        borderRadius: BorderRadius.circular(12),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
            const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
                _stepMatch(-1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _stepMatch(-1),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _stepMatch(1),
          },
          child: Row(children: [
            const SizedBox(width: 10),
            Icon(Icons.search_rounded, size: 18, color: p.secondary),
            Expanded(
              child: TextField(
                controller: _findCtrl,
                focusNode: _findFocus,
                onChanged: (_) => _search(),
                onSubmitted: (_) {
                  _stepMatch(1);
                  _findFocus.requestFocus();
                },
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: tr('Buscar en la nota'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
              ),
            ),
            Text(count, style: TextStyle(color: p.secondary, fontSize: 12.5)),
            IconButton(
              tooltip: tr('Anterior'),
              visualDensity: VisualDensity.compact,
              onPressed: _matches.isEmpty ? null : () => _stepMatch(-1),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: tr('Siguiente'),
              visualDensity: VisualDensity.compact,
              onPressed: _matches.isEmpty ? null : () => _stepMatch(1),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            IconButton(
              tooltip: tr('Cerrar'),
              visualDensity: VisualDensity.compact,
              onPressed: _closeFind,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ]),
        ),
      ),
    ).animate().fadeIn(duration: Anim.fast).slideY(begin: -0.3);
  }

  /// Abre la pizarra [id] (sin id, la primera; con [fresh], una nueva).
  void _enterBoard({String? id, bool fresh = false}) {
    final n = repo.byId(widget.noteId);
    if (n == null) return;
    if (_board != null) {
      if (!fresh && _board!.id == id) return;
      _leaveBoard();
    }
    _focus.unfocus();
    _titleCtrl.text = n.title;
    final data = (fresh ? null : BoardData.of(n.rich, id: id)) ??
        BoardData(id: BoardData.newId());
    setState(() {
      _board = BoardController(data, onChanged: _queueBoardSave);
    });
    _saveBoard();
  }

  /// Título editable arriba mientras se ve la pizarra. Se guarda mientras se
  /// escribe (y al cerrar): antes solo con Intro, y al salir con Esc o cambiar
  /// de nota se perdía y no llegaba a los otros dispositivos.
  final _titleCtrl = TextEditingController();
  Timer? _titleSave;

  void _renameFromBoard() {
    _titleSave?.cancel();
    final n = repo.byId(widget.noteId);
    final title = _titleCtrl.text.replaceAll('\n', ' ').trim();
    if (n == null || !repo.canEdit(n) || title.isEmpty || title == n.title) {
      return;
    }
    final doc = _docFor(n);
    final first = doc.toPlainText().split('\n').first;
    if (first.isEmpty || first.contains('\uFFFC')) {
      doc.insert(0, '$title\n');
      doc.format(0, title.length, Attribute.h1);
    } else {
      doc.replace(0, first.length, title);
    }
    final rich = jsonEncode(doc.toDelta().toJson());
    final plain = doc.toPlainText();
    _lastSaved = rich;
    repo.updateContent(widget.noteId,
        plain.endsWith('\n') ? plain.substring(0, plain.length - 1) : plain,
        rich: rich);
  }

  void _leaveBoard() {
    _boardSave?.cancel();
    _renameFromBoard();
    final c = _board;
    final saved = repo.byId(widget.noteId);
    // Pizarra vacía: no se queda en la nota.
    final removed = c != null &&
        c.isEmpty &&
        saved != null &&
        repo.canEdit(saved) &&
        BoardData.of(saved.rich, id: c.id) != null;
    if (removed) {
      final (content, rich) =
          BoardData.remove(saved.content, saved.rich!, id: c.id);
      repo.updateContent(widget.noteId, content, rich: rich);
    }
    _saveBoard(active: false);
    final n = repo.byId(widget.noteId);
    final old = _board;
    // Sin pizarra guardada el texto no ha cambiado (y conserva su formato).
    if (n != null && (removed || BoardData.of(n.rich) != null)) {
      _applyingRemote = true;
      _ctrl.document = _docFor(n);
      _ctrl.updateSelection(
          const TextSelection.collapsed(offset: 0), ChangeSource.local);
      _lastSaved = _richJson();
      _applyingRemote = false;
      // Mismo Delta que Quill: si no, cada aviso lo volvería a aplicar.
      if (repo.canEdit(n) && n.rich != _lastSaved) {
        repo.updateContent(widget.noteId, _plain(), rich: _lastSaved);
      }
    }
    setState(() => _board = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  /// Quita una pizarra de la nota (la abierta si no se dice cuál); el texto
  /// no se toca.
  Future<void> _removeBoard([String? id]) async {
    final which = id ?? _board?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Eliminar la pizarra?')),
        content:
            Text(tr('Podrás recuperarla desde el historial de versiones.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Eliminar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_boardSave?.isActive ?? false) {
      _boardSave!.cancel();
      _saveBoard();
    }
    final n = repo.byId(widget.noteId);
    if (n == null || !repo.canEdit(n)) return;
    repo.history.record(n, force: true);
    final (content, rich) =
        BoardData.remove(n.content, n.rich ?? _richJson(), id: which);
    final old = which == _board?.id ? _board : null;
    if (old == null && _board != null) {
      // Se quitó otra pizarra: la abierta sigue.
      _lastSaved = rich;
      repo.updateContent(widget.noteId, content, rich: rich);
      setState(() {});
      return;
    }
    _applyingRemote = true;
    _lastSaved = rich;
    repo.updateContent(widget.noteId, content, rich: rich);
    _ctrl.document = _docFor(repo.byId(widget.noteId));
    _ctrl.updateSelection(
        const TextSelection.collapsed(offset: 0), ChangeSource.local);
    _lastSaved = _richJson();
    _applyingRemote = false;
    if (n.rich != _lastSaved) {
      repo.updateContent(widget.noteId, _plain(), rich: _lastSaved);
    }
    setState(() => _board = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  void _queueBoardSave() {
    _boardSave?.cancel();
    _boardSave = Timer(const Duration(milliseconds: 500), _saveBoard);
  }

  void _saveBoard({bool active = true}) {
    final c = _board;
    final n = repo.byId(widget.noteId);
    if (c == null || n == null || !repo.canEdit(n)) return;
    // Abrir la pizarra sin dibujar no convierte una nota vacía en nota real.
    if (c.isEmpty && BoardData.of(n.rich, id: c.id) == null) return;
    final (content, rich) = BoardData.store(
        n.content, n.rich ?? _richJson(), c.toData(active: active));
    if (rich == n.rich) return;
    _lastSaved = rich;
    _lastTyped = DateTime.now();
    repo.updateContent(widget.noteId, content, rich: rich);
  }

  /// Pasa a texto con la IA solo lo que aún no ha leído.
  Future<void> _boardToText() async {
    final c = _board;
    if (c == null) return;
    void insert(String text) {
      final n = repo.byId(widget.noteId);
      if (n == null || text.isEmpty) return;
      final (content, rich) = withText(n.content, n.rich, text);
      _lastSaved = rich;
      _lastTyped = DateTime.now();
      repo.updateContent(widget.noteId, content, rich: rich);
    }

    final fresh = c.unreadData();
    if (fresh.strokes.isEmpty && fresh.images.isEmpty) {
      if (c.readText.isEmpty) {
        showToast(context, tr('No hay nada nuevo que leer'),
            icon: Icons.info_outline_rounded);
      } else {
        await showBoardText(context, c.readText, onInsert: insert);
      }
      return;
    }
    final png = await renderBoardPng(fresh, NoteImages.instance.load);
    if (png == null || !mounted) return;
    await readBoardText(context, png, previous: c.readText, onRead: (text) {
      if (identical(_board, c)) c.markRead(fresh, text);
    }, onInsert: insert);
  }

  /// Cambios de la pizarra que llegan desde otro dispositivo.
  void _syncBoard(Note n) {
    final c = _board;
    if (c == null || c.busy) return;
    final remote = BoardData.of(n.rich, id: c.id);
    if (remote == null) {
      // Eliminada en otro dispositivo. Si aquí hay trazos sin guardar, ganan.
      if (c.isEmpty || (_boardSave?.isActive ?? false)) return;
      _applyingRemote = true;
      _ctrl.document = _docFor(n);
      _ctrl.updateSelection(
          const TextSelection.collapsed(offset: 0), ChangeSource.local);
      _lastSaved = _richJson();
      _applyingRemote = false;
      _board = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
      return;
    }
    remote.active = true;
    if (remote.encode() != c.toData().encode()) c.load(remote);
  }

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
              mounted &&
              (await pasteImagesFromClipboard(context, _ctrl) ||
                  await _pasteIntoTitle()),
          // El HTML del portapapeles de Windows trae cabeceras
          // ("SourceURL:…") que acababan pegadas como texto.
          // ignore: experimental_member_use
          enableExternalRichPaste: false,
        ),
      ),
    );
    // Nota nueva: lo primero que escribas sale en grande, como un título.
    // Al pulsar Intro la siguiente línea ya es texto normal.
    if (_ctrl.document.toPlainText().trim().isEmpty) {
      _ctrl.formatSelection(Attribute.h1);
    }
    _lastSaved = _richJson();
    _allChecked = _everyBoxChecked();
    // Va antes que el listener del editor: en el móvil, los cambios que no
    // vienen de tocar el texto no deben abrir el teclado.
    _ctrl.addListener(_guardKeyboard);
    _guardKeyboard();
    _ctrl.addListener(_onEdit);
    _ctrl.addListener(_onCaret);
    _ctrl.addListener(_dragReveal);
    repo.addListener(_onRepo);
    _focus.addListener(_onFocus);
    _findSub = noteFindRequests.stream.listen((_) => _openFind());
    // La fuente de las notas puede cambiar con la nota abierta.
    themeSettings.addListener(_onTheme);
    final saved = BoardData.all(n?.rich).where((b) => b.active).firstOrNull;
    if (saved != null) {
      _board = BoardController(saved, onChanged: _queueBoardSave);
    }
  }

  /// Pegar varias líneas en el título: solo la primera sigue siendo título.
  Future<bool> _pasteIntoTitle() async {
    final sel = _ctrl.selection;
    if (_ctrl.getSelectionStyle().attributes[Attribute.header.key]?.value !=
        1) {
      return false;
    }
    final raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (raw == null || !mounted) return false;
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final cut = text.indexOf('\n');
    if (cut == -1) return false;
    _ctrl.replaceText(sel.start, sel.end - sel.start, text,
        TextSelection.collapsed(offset: sel.start + text.length));
    _ctrl.formatText(sel.start + cut + 1, text.length - cut,
        Attribute.clone(Attribute.h1, null));
    return true;
  }

  void _guardKeyboard() {
    if (!autoKeyboard) _ctrl.ignoreFocusOnTextChange = !_focus.hasFocus;
  }

  void _onFocus() {
    _guardKeyboard();
    if (mounted) setState(() {});
  }

  void _onEdit() {
    if (_applyingRemote || _closing || _board != null) return;
    final rich = _richJson();
    if (rich == _lastSaved) return; // solo cambió el cursor
    _lastSaved = rich;
    _lastTyped = DateTime.now();
    repo.updateContent(widget.noteId, _plain(), rich: rich);
    _checkTasks();
    _dupTimer?.cancel();
    _dupTimer = Timer(const Duration(milliseconds: 1500), _findSimilar);
  }

  // Aviso de nota parecida (sin IA).
  Timer? _dupTimer;
  Note? _similar;
  bool _dupOff = false;

  Future<void> _findSimilar() async {
    final n = repo.byId(widget.noteId);
    if (n == null || _dupOff || n.vault || !mounted) return;
    if ((await SimilarNotes.ignored()).contains(n.id)) {
      _dupOff = true;
      return;
    }
    final s = SimilarNotes.mostSimilar(n, repo.notes);
    if (mounted && s?.id != _similar?.id) setState(() => _similar = s);
  }

  Widget _similarBanner(BuildContext context, Note s) {
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.content_copy_rounded, size: 17, color: p.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(trf('Se parece a «{0}»', [s.title]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5)),
        ),
        if (widget.onOpenNote != null)
          TextButton(
              onPressed: () => widget.onOpenNote!(s.id),
              child: Text(tr('Abrir'))),
        TextButton(
          onPressed: () {
            SimilarNotes.ignore(widget.noteId);
            setState(() {
              _similar = null;
              _dupOff = true;
            });
          },
          child: Text(tr('Ignorar')),
        ),
      ]),
    ).animate().fadeIn(duration: Anim.medium).slideY(begin: -0.2);
  }

  /// Todas las casillas marcadas en una nota temporal: ¿tarea hecha?
  bool _allChecked = false;
  bool _askingDone = false;

  bool _everyBoxChecked() {
    var checked = 0, open = 0;
    for (final op in _ctrl.document.toDelta().toList()) {
      final l = op.attributes?['list'];
      if (l == 'checked') checked++;
      if (l == 'unchecked') open++;
    }
    return checked > 0 && open == 0;
  }

  Future<void> _checkTasks() async {
    final all = _everyBoxChecked();
    final was = _allChecked;
    _allChecked = all;
    final n = repo.byId(widget.noteId);
    if (!all || was || _askingDone || n == null || !n.isTemporal || n.done) {
      return;
    }
    if (repo.isForeign(n)) return;
    _askingDone = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.task_alt_rounded,
            size: 40, color: Palette.accent(context)),
        title: Text(tr('¿Has completado la tarea?')),
        content:
            Text(trf('Has marcado todas las casillas de «{0}».', [n.title])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Todavía no'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Sí, completar'))),
        ],
      ),
    );
    _askingDone = false;
    if (ok != true || !mounted) return;
    if (!n.checkable) repo.setCheckable(n.id, true);
    completeTask(context, repo, n.id);
  }

  /// Seleccionando con el ratón: Quill hace scroll hasta el *inicio* de una
  /// selección normal, así que al arrastrar hacia abajo volvía a subir (el
  /// "bucle"). Como selección de arrastre enseña el extremo que se mueve.
  bool _mouseDown = false;

  void _dragReveal() {
    final s = _ctrl.selection;
    if (!_mouseDown || s.isCollapsed || s is DragTextSelection) return;
    _ctrl.updateSelection(
        DragTextSelection(
            baseOffset: s.baseOffset,
            extentOffset: s.extentOffset,
            affinity: s.affinity,
            first: s.extentOffset < s.baseOffset),
        ChangeSource.local);
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
    if (_board != null) {
      if (!recentlyTyped && remoteRich != _lastSaved) {
        _lastSaved = remoteRich;
        _syncBoard(n);
      }
      setState(() {});
      return;
    }
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

  void _onTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeSettings.removeListener(_onTheme);
    if (_titleSave?.isActive ?? false) {
      _titleSave!.cancel();
      _renameFromBoard();
    }
    _dupTimer?.cancel();
    _titleCtrl.dispose();
    _findSub?.cancel();
    _findCtrl.dispose();
    _findFocus.dispose();
    if (_boardSave?.isActive ?? false) {
      _boardSave!.cancel();
      _saveBoard();
    }
    _board?.dispose();
    repo.removeListener(_onRepo);
    _ctrl.removeListener(_guardKeyboard);
    _ctrl.removeListener(_onEdit);
    _ctrl.removeListener(_onCaret);
    _ctrl.removeListener(_dragReveal);
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
    // Fuente de las notas (Tema y colores), no la de la app.
    final note = themeSettings.font;
    final font =
        note.family ?? Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final fallback = note.family == null ? null : note.fallback;
    const h0 = HorizontalSpacing(0, 0);
    const v0 = VerticalSpacing(0, 0);
    DefaultTextBlockStyle block(
            double size, FontWeight w, double top, double bottom,
            {double height = 1.3}) =>
        DefaultTextBlockStyle(
          TextStyle(
              fontFamily: font,
              fontFamilyFallback: fallback,
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
            fontFamilyFallback: fallback,
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

  static TextStyle _highlight(BuildContext context, Attribute a) {
    final v = a.value;
    // Fuente puesta a un trozo de texto: su familia con alternativas.
    if (a.key == Attribute.font.key && v is String) {
      final f = fontById(v);
      return f.id == v ? fontStyleOf(f) : const TextStyle();
    }
    if (a.key != Attribute.background.key || v is! String) {
      return const TextStyle();
    }
    final hex = int.tryParse(v.replaceFirst('#', ''), radix: 16);
    if (hex == null) return const TextStyle();
    final c = Color(0xFF000000 | hex);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
        backgroundColor: c.withValues(alpha: dark ? 0.32 : 0.75),
        decorationColor: c);
  }

  /// Las pizarras de la nota, abajo: tocar una la abre, + crea otra.
  Widget _boardsStrip(BuildContext context, Note n, bool writable) {
    final boards = BoardData.all(n.rich);
    final current = _board?.id;
    if (boards.isEmpty && _board == null) return const SizedBox.shrink();
    final shown = [
      ...boards,
      // Una pizarra nueva aún sin trazos también sale (resaltada).
      if (_board != null && !boards.any((b) => b.id == current))
        _board!.toData(),
    ];
    return SizedBox(
      height: _board == null ? 136 : 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (i, b) in shown.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: BoardThumb(
                key: ValueKey('pizarra-${b.id}'),
                data: b.id == current ? _board!.toData() : b,
                label: b.name.isNotEmpty ? b.name : trf('Pizarra {0}', [i + 1]),
                selected: b.id == current,
                size: _board == null ? 120 : 80,
                onTap: () =>
                    b.id == current ? _leaveBoard() : _enterBoard(id: b.id),
                onRemove: !writable || _board != null
                    ? null
                    : () => _removeBoard(b.id),
              ).animate(delay: (40 * i).ms).fadeIn(duration: Anim.medium).scale(
                  begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
            ),
          if (writable)
            Tooltip(
              message: tr('Nueva pizarra'),
              child: Bouncy(
                pressedScale: 0.92,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _enterBoard(fresh: true),
                  child: Container(
                    width: _board == null ? 120 : 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Palette.separator(context), width: 1.4),
                    ),
                    child: Icon(Icons.add_rounded,
                        size: 28, color: Palette.accent(context)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _draw() async {
    final png = await showDrawingPad(context);
    if (png != null && mounted) await insertImages(context, _ctrl, [png]);
  }

  void _toolAction(String v) {
    final n = repo.byId(widget.noteId);
    if (n == null) return;
    switch (v) {
      case 'info':
        showNoteInfo(context, repo, n);
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
    // Nota de otra cuenta: solo se toca el texto (si hay permiso).
    final foreign = n != null && repo.isForeign(n);
    final writable = n == null || repo.canEdit(n);
    if (_ctrl.readOnly == writable) _ctrl.readOnly = !writable;

    return Scaffold(
      backgroundColor: Palette.card(context),
      appBar: AppBar(
        backgroundColor: Palette.card(context),
        automaticallyImplyLeading: false,
        leadingWidth: widget.showBack ? 52 : 0,
        titleSpacing: 4,
        title: _board == null || !writable
            ? null
            : TextField(
                controller: _titleCtrl,
                maxLines: 1,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: tr('Título de la pizarra'),
                ),
                onChanged: (_) {
                  _titleSave?.cancel();
                  _titleSave = Timer(
                      const Duration(milliseconds: 700), _renameFromBoard);
                },
                onSubmitted: (_) => _renameFromBoard(),
                onTapOutside: (_) => _renameFromBoard(),
              ).animate().fadeIn(duration: Anim.medium),
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
          if (!foreign)
            _iconAction(
              tooltip: tr('Nota temporal y avisos'),
              icon: Icon(
                n?.isTemporal == true
                    ? Icons.alarm_on
                    : Icons.alarm_add_outlined,
              ),
              onPressed: () => showScheduleSheet(context, repo, widget.noteId),
            ),
          // Modo pizarra, junto al reloj.
          if (n != null)
            _iconAction(
              tooltip:
                  _board != null ? tr('Volver al texto') : tr('Modo pizarra'),
              icon: AnimatedSwitcher(
                duration: Anim.medium,
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: Icon(
                  _board != null
                      ? Icons.sticky_note_2_outlined
                      : Icons.gesture_rounded,
                  key: ValueKey(_board != null),
                ),
              ),
              onPressed: _board != null ? _leaveBoard : _enterBoard,
            ),
          // Color de la nota (y de su mecha)
          if (!foreign && n?.isTemporal == true)
            _iconAction(
              tooltip: tr('Color de la nota'),
              icon: n?.color == null
                  ? const Icon(Icons.palette_outlined)
                  : Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: notePalette(n!)),
                      ),
                    ),
              onPressed: () => showNoteColorSheet(context, repo, widget.noteId),
            ),
          if (!compact) ...[
            // Carpeta
            if (!foreign)
              PopupMenuButton<String>(
                tooltip: tr('Mover a carpeta'),
                icon: Icon(
                    folder == null ? Icons.folder_outlined : Icons.folder,
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
            if (n != null && !foreign)
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
            if (_board == null)
              _iconAction(
                tooltip: _toolbarOpen
                    ? tr('Ocultar formato')
                    : tr('Mostrar formato'),
                icon:
                    Icon(_toolbarOpen ? Icons.text_format : Icons.text_fields),
                onPressed: () => setState(() => _toolbarOpen = !_toolbarOpen),
              ),
            PopupMenuButton<String>(
              tooltip: tr('Más'),
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: _toolAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'info',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline_rounded),
                        title: Text(tr('Información')))),
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
            if (!foreign)
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
                if (!foreign)
                  PopupMenuItem(
                      value: 'carpeta',
                      child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(folder == null
                              ? Icons.folder_outlined
                              : Icons.folder),
                          title: Text(folder?.name ?? tr('Mover a carpeta')))),
                if (!foreign)
                  PopupMenuItem(
                      value: 'fijar',
                      child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined),
                          title: Text(
                              pinned ? tr('Desfijar') : tr('Fijar arriba')))),
                if (_board == null)
                  PopupMenuItem(
                      value: 'formato',
                      child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.text_format),
                          title: Text(_toolbarOpen
                              ? tr('Ocultar formato')
                              : tr('Mostrar formato')))),
                if (_board == null && writable)
                  PopupMenuItem(
                      value: 'imagen',
                      child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading:
                              const Icon(Icons.add_photo_alternate_outlined),
                          title: Text(tr('Añadir imagen')))),
                PopupMenuItem(
                    value: 'info',
                    child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline_rounded),
                        title: Text(tr('Información')))),
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
                if (!foreign)
                  PopupMenuItem(
                      value: 'borrar',
                      child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading:
                              Icon(Icons.delete_outline, color: Colors.red),
                          title: Text(tr('Eliminar'),
                              style: TextStyle(color: Colors.red)))),
              ],
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Barra de formato (se puede ocultar). Ancho fijo al de la
            // ventana: AnimatedSize solo anima la altura, si no la barra
            // tardaba en estirarse al ensanchar la ventana.
            SizedBox(
              width: double.infinity,
              child: AnimatedSize(
                duration: Anim.medium,
                curve: Anim.curve,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: Anim.medium,
                  switchInCurve: Anim.curve,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (c, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position:
                          Tween(begin: const Offset(0, -0.25), end: Offset.zero)
                              .animate(a),
                      child: c,
                    ),
                  ),
                  child: _board != null
                      ? BoardToolbar(
                          key: const ValueKey('barra-pizarra'),
                          controller: _board!,
                          readOnly: !writable,
                          onShare: n == null || n.vault
                              ? null
                              : () => showShareSheet(context, repo, n.id),
                          onAi: n == null || n.vault || foreign
                              ? null
                              : () => showNoteAiActions(context, repo, n.id),
                          onReadText: n == null || n.vault || foreign
                              ? null
                              : _boardToText,
                        )
                      : _toolbarOpen
                          ? EditorToolbar(
                              key: const ValueKey('barra-formato'),
                              controller: _ctrl,
                              readOnly: !writable,
                              onImage: !writable
                                  ? null
                                  : () => pickAndInsertImages(context, _ctrl),
                              onLink: foreign
                                  ? null
                                  : () => showLinkNotesPicker(
                                      context, repo, widget.noteId),
                              onVoice: !writable
                                  ? null
                                  : () => showVoiceRecorder(context, _ctrl),
                              onAttach: !writable
                                  ? null
                                  : () => pickAndAttachFiles(context, _ctrl),
                              onDraw: !writable ? null : _draw,
                              onShare: n == null || n.vault
                                  ? null
                                  : () => showShareSheet(context, repo, n.id),
                              // Ni las del Vault ni las de otra persona van a la IA.
                              onAi: n == null || n.vault || foreign
                                  ? null
                                  : () =>
                                      showNoteAiActions(context, repo, n.id),
                            )
                          : const SizedBox(
                              key: ValueKey('sin-barra'),
                              width: double.infinity),
                ),
              ),
            ),
            if (_board != null)
              Expanded(
                child: Whiteboard(
                  key: const ValueKey('pizarra-nota'),
                  controller: _board!,
                  readOnly: !writable,
                  onRemove: _removeBoard,
                ).animate().fadeIn(duration: Anim.medium, curve: Anim.curve),
              ),
            if (_board != null && n != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _boardsStrip(context, n, writable),
              ),
            if (_board != null && n != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _LinksBar(
                  graph: NoteGraph.of(repo),
                  noteId: n.id,
                  repo: repo,
                  onOpen: widget.onOpenNote,
                  onCreate: _createLinked,
                ),
              ),
            if (_board == null)
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
                          if (foreign)
                            _SharedBanner(
                              owner: repo.incomingShare(n.id)?.ownerEmail,
                              canEdit: writable,
                            ),
                          if (_finding) _findBar(context),
                          if (_similar case final s?
                              when repo.byId(s.id)?.deleted == false)
                            _similarBanner(context, s),
                          if (n != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${fechaLarga(n.updatedAt)} · ${textStats(n.content)}',
                                style: TextStyle(
                                    color: Palette.secondary(context),
                                    fontSize: 13),
                              ),
                            ),
                          Expanded(
                            child: ImageDropZone(
                              onImages: (images) =>
                                  insertImages(context, _ctrl, images),
                              child: ImageMoveTarget(
                                controller: _ctrl,
                                editorKey: _editorKey,
                                child: NoteMediaScope(
                                  allowAi: n != null && !n.vault && !foreign,
                                  child: Listener(
                                    onPointerDown: (e) => _mouseDown =
                                        e.kind == PointerDeviceKind.mouse,
                                    onPointerUp: (_) => _mouseDown = false,
                                    onPointerCancel: (_) => _mouseDown = false,
                                    child: QuillEditor(
                                      controller: _ctrl,
                                      focusNode: _focus,
                                      scrollController: _scroll,
                                      config: QuillEditorConfig(
                                        editorKey: _editorKey,
                                        showCursor: !_caretByImage,
                                        placeholder: tr('Escribe algo…'),
                                        // En el móvil el teclado solo sale al
                                        // tocar el texto.
                                        autoFocus:
                                            widget.autofocus && autoKeyboard,
                                        expands: true,
                                        padding:
                                            const EdgeInsets.only(bottom: 40),
                                        customStyles: _styles(context),
                                        // Resaltado como un rotulador: suave
                                        // y legible también en modo oscuro.
                                        customStyleBuilder: (a) =>
                                            _highlight(context, a),
                                        // Markdown al escribir: "# ", "- ",
                                        // "1. ", **negrita**, *cursiva*…
                                        // ignore: experimental_member_use
                                        characterShortcutEvents:
                                            standardCharactersShortcutEvents,
                                        // ignore: experimental_member_use
                                        spaceShortcutEvents:
                                            standardSpaceShorcutEvents,
                                        // Un clic en un enlace lo abre en el
                                        // navegador (Quill pedía Ctrl+clic).
                                        customRecognizerBuilder: (a, _) => a
                                                        .key !=
                                                    Attribute.link.key ||
                                                a.value is! String
                                            ? null
                                            : (TapGestureRecognizer()
                                              ..onTap = () => openLink(context,
                                                  webUrl(a.value as String))),
                                        // Imágenes: se dibujan con su propio estilo,
                                        // Ctrl+V pega capturas y el teclado de Android
                                        // puede insertar imágenes directamente.
                                        embedBuilders: [
                                          const NoteImageEmbedBuilder(),
                                          const NoteFileEmbedBuilder(),
                                          const NoteBoardEmbedBuilder(),
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
                                        customActions: widget
                                                    .onCommandPalette ==
                                                null
                                            ? null
                                            : {
                                                _PaletteIntent: CallbackAction<
                                                    _PaletteIntent>(
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
                                            if (data != null &&
                                                data.isNotEmpty) {
                                              insertImages(
                                                  context, _ctrl, [data]);
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
                            ),
                          ),
                          if (n != null) _boardsStrip(context, n, writable),
                          if (n != null)
                            _LinksBar(
                              graph: NoteGraph.of(repo),
                              noteId: n.id,
                              repo: repo,
                              onOpen: widget.onOpenNote,
                              onCreate: _createLinked,
                            ),
                          if (n != null && n.isTemporal)
                            _TemporalBanner(
                              note: n,
                              onToggleDone: () =>
                                  completeTask(context, repo, n.id),
                              onEdit: foreign
                                  ? () {}
                                  : () =>
                                      showScheduleSheet(context, repo, n.id),
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

/// Aviso de quién ha compartido la nota.
class _SharedBanner extends StatelessWidget {
  const _SharedBanner({required this.owner, required this.canEdit});
  final String? owner;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: p.background, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(canEdit ? Icons.group_outlined : Icons.visibility_outlined,
              size: 16, color: p.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${owner == null ? tr('Nota compartida') : trf('Compartida por {0}', [
                      owner!
                    ])}'
              '${canEdit ? '' : ' · ${tr('Solo ver')}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.secondary),
            ),
          ),
        ],
      ),
    );
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
      margin: const EdgeInsets.only(top: 6, bottom: 10),
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (!note.checkable && !note.done)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Icon(Icons.event_rounded, size: 22, color: color),
            )
          else
            IconButton(
              tooltip: note.done ? tr('Marcar pendiente') : tr('Completar'),
              onPressed: onToggleDone,
              icon: AnimatedSwitcher(
                duration: Anim.medium,
                transitionBuilder: (c, a) => ScaleTransition(
                    scale:
                        CurvedAnimation(parent: a, curve: Curves.easeOutBack),
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
    ).animate().fadeIn(duration: Anim.medium).slideY(begin: 0.2);
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
    final note = repo.byId(noteId);
    final files = note == null ? const <MediaItem>[] : linkedMedia(note);
    final canRemove = note != null && !repo.isForeign(note);
    if (out.isEmpty && back.isEmpty && missing.isEmpty && files.isEmpty) {
      return const SizedBox.shrink();
    }
    final p = Palette.of(context);

    Widget fileChip(MediaItem m) {
      final label = m.kind == MediaKind.image ? tr('Imagen') : m.name;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Tooltip(
          message: label,
          child: Material(
            color: p.accent.withValues(alpha: 0.12),
            shape: StadiumBorder(
                side: BorderSide(color: p.accent.withValues(alpha: 0.4))),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => openMediaItem(context, m),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(10, 5, canRemove ? 4 : 10, 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(mediaIcon(m), size: 14, color: p.accent),
                        const SizedBox(width: 5),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canRemove)
                  InkWell(
                    onTap: () => removeLinkedMedia(repo, noteId, m.path),
                    child: Semantics(
                      button: true,
                      label: tr('Quitar'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(2, 5, 8, 5),
                        child: Icon(Icons.close_rounded,
                            size: 13, color: p.secondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

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
            for (final m in files) fileChip(m),
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
