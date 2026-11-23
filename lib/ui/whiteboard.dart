import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../data/note_board.dart';
import '../data/note_images.dart';
import 'anim.dart';
import 'context_menu.dart';
import 'i18n.dart';
import 'note_image.dart';
import 'theme.dart';
import 'toast.dart';

enum BoardTool { lasso, pen, eraser }

/// Estado de una pizarra: contenido, selección, deshacer y herramienta.
class BoardController extends ChangeNotifier {
  BoardController(BoardData data, {required this.onChanged})
      : strokes = List.of(data.strokes),
        images = List.of(data.images);

  final VoidCallback onChanged;
  List<BoardStroke> strokes;
  List<BoardImage> images;
  Set<int> selectedStrokes = {};
  Set<int> selectedImages = {};

  /// Sube cuando cambia lo que hay que volver a grabar en la imagen fija.
  int paintVersion = 0;

  /// Hay un trazo o movimiento a medias: no se aplican cambios remotos.
  bool busy = false;

  final _undo = <(List<BoardStroke>, List<BoardImage>)>[];
  final _redo = <(List<BoardStroke>, List<BoardImage>)>[];
  static const _maxUndo = 80;

  // La herramienta se recuerda al cambiar de nota.
  static BoardTool _tool = BoardTool.pen;
  static int _color = 0;
  static double _penWidth = 3;
  static double _penForce = 0.5;
  static double _eraserWidth = 22;
  static double _eraserForce = 0;

  // Copiar y pegar también entre pizarras de notas distintas.
  static List<BoardStroke> _clipStrokes = const [];
  static List<BoardImage> _clipImages = const [];

  BoardTool get tool => _tool;
  int get color => _color;
  double get penWidth => _penWidth;
  double get penForce => _penForce;
  double get eraserWidth => _eraserWidth;
  double get eraserForce => _eraserForce;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasSelection =>
      selectedStrokes.isNotEmpty || selectedImages.isNotEmpty;
  bool get hasClip => _clipStrokes.isNotEmpty || _clipImages.isNotEmpty;
  bool get isEmpty => strokes.isEmpty && images.isEmpty;

  set tool(BoardTool t) {
    _tool = t;
    if (t != BoardTool.lasso) clearSelection();
    notifyListeners();
  }

  void setPen({int? color, double? width, double? force}) {
    _color = color ?? _color;
    _penWidth = width ?? _penWidth;
    _penForce = force ?? _penForce;
    notifyListeners();
  }

  void setEraser({double? width, double? force}) {
    _eraserWidth = width ?? _eraserWidth;
    _eraserForce = force ?? _eraserForce;
    notifyListeners();
  }

  BoardData toData({bool active = true}) => BoardData(
      active: active, strokes: List.of(strokes), images: List.of(images));

  /// Cambios que llegan de otro dispositivo.
  void load(BoardData d) {
    strokes = List.of(d.strokes);
    images = List.of(d.images);
    selectedStrokes = {};
    selectedImages = {};
    _undo.clear();
    _redo.clear();
    paintVersion++;
    notifyListeners();
  }

  void checkpoint() {
    _undo.add((List.of(strokes), List.of(images)));
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  void _changed() {
    paintVersion++;
    notifyListeners();
    onChanged();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add((strokes, images));
    final (s, i) = _undo.removeLast();
    strokes = s;
    images = i;
    selectedStrokes = {};
    selectedImages = {};
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add((strokes, images));
    final (s, i) = _redo.removeLast();
    strokes = s;
    images = i;
    selectedStrokes = {};
    selectedImages = {};
    _changed();
  }

  /// Anula el último [checkpoint] sin dejar rastro (gesto cancelado).
  void rollback() {
    if (_undo.isEmpty) return;
    final (s, i) = _undo.removeLast();
    strokes = s;
    images = i;
    _changed();
  }

  void addStroke(BoardStroke s) {
    checkpoint();
    strokes = [...strokes, s];
    _changed();
  }

  void addImage(BoardImage i) {
    checkpoint();
    images = [...images, i];
    selectedStrokes = {};
    selectedImages = {images.length - 1};
    _tool = BoardTool.lasso;
    _changed();
  }

  /// Un paso de la goma. El [checkpoint] lo hace quien empieza el gesto.
  bool erase(Offset from, Offset to, double radius) {
    final out = eraseStrokes(strokes, from, to, radius);
    if (out == null) return false;
    strokes = out;
    paintVersion++;
    notifyListeners();
    return true;
  }

  void commitErase() => onChanged();

  void selectLasso(List<Offset> lasso) {
    selectedStrokes = strokesInLasso(strokes, lasso);
    selectedImages = {
      for (var i = 0; i < images.length; i++)
        if (insidePolygon(images[i].rect.center, lasso)) i,
    };
    paintVersion++;
    notifyListeners();
  }

  void selectAll() {
    _tool = BoardTool.lasso;
    selectedStrokes = {for (var i = 0; i < strokes.length; i++) i};
    selectedImages = {for (var i = 0; i < images.length; i++) i};
    paintVersion++;
    notifyListeners();
  }

  void clearSelection() {
    if (!hasSelection) return;
    selectedStrokes = {};
    selectedImages = {};
    paintVersion++;
    notifyListeners();
  }

  Rect? get selectionBounds {
    Rect? r;
    for (final i in selectedStrokes) {
      final b = strokes[i].bounds;
      r = r?.expandToInclude(b) ?? b;
    }
    for (final i in selectedImages) {
      final b = images[i].rect;
      r = r?.expandToInclude(b) ?? b;
    }
    return r;
  }

  void moveSelection(Offset by) {
    if (by == Offset.zero || !hasSelection) return;
    checkpoint();
    strokes = [
      for (var i = 0; i < strokes.length; i++)
        selectedStrokes.contains(i) ? strokes[i].moved(by) : strokes[i],
    ];
    images = [
      for (var i = 0; i < images.length; i++)
        selectedImages.contains(i) ? images[i].moved(by) : images[i],
    ];
    _changed();
  }

  void deleteSelection() {
    if (!hasSelection) return;
    checkpoint();
    strokes = [
      for (var i = 0; i < strokes.length; i++)
        if (!selectedStrokes.contains(i)) strokes[i],
    ];
    images = [
      for (var i = 0; i < images.length; i++)
        if (!selectedImages.contains(i)) images[i],
    ];
    selectedStrokes = {};
    selectedImages = {};
    _changed();
  }

  void copySelection() {
    if (!hasSelection) return;
    _clipStrokes = [for (final i in selectedStrokes) strokes[i]];
    _clipImages = [for (final i in selectedImages) images[i]];
  }

  /// Pega lo copiado con su centro en [at] y lo deja seleccionado.
  void paste(Offset at) {
    if (!hasClip) return;
    Rect? box;
    for (final s in _clipStrokes) {
      box = box?.expandToInclude(s.bounds) ?? s.bounds;
    }
    for (final i in _clipImages) {
      box = box?.expandToInclude(i.rect) ?? i.rect;
    }
    final by = at - box!.center;
    checkpoint();
    final firstStroke = strokes.length, firstImage = images.length;
    strokes = [...strokes, for (final s in _clipStrokes) s.moved(by)];
    images = [...images, for (final i in _clipImages) i.moved(by)];
    selectedStrokes = {for (var i = firstStroke; i < strokes.length; i++) i};
    selectedImages = {for (var i = firstImage; i < images.length; i++) i};
    _tool = BoardTool.lasso;
    _changed();
  }

  void clearAll() {
    if (isEmpty) return;
    checkpoint();
    strokes = [];
    images = [];
    selectedStrokes = {};
    selectedImages = {};
    _changed();
  }
}

/// Pinta un trazo; con presión, cada tramo lleva su propio grosor.
void paintBoardStroke(Canvas canvas, BoardStroke s, Color ink) {
  final paint = Paint()
    ..color = s.color == 0 ? ink : Color(s.color)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final p = s.points;
  if (p.length == 1) {
    canvas.drawCircle(p.first, s.width * s.factors.first / 2,
        paint..style = PaintingStyle.fill);
    return;
  }
  final first = s.factors.first;
  if (s.factors.every((f) => (f - first).abs() < 0.02)) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 1; i < p.length - 1; i++) {
      final mid = (p[i] + p[i + 1]) / 2;
      path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(p.last.dx, p.last.dy);
    canvas.drawPath(path, paint..strokeWidth = s.width * first);
    return;
  }
  var from = p.first;
  for (var i = 1; i < p.length - 1; i++) {
    final mid = (p[i] + p[i + 1]) / 2;
    canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy),
        paint..strokeWidth = s.width * s.factors[i]);
    from = mid;
  }
  canvas.drawLine(from, p.last, paint..strokeWidth = s.width * s.factors.last);
}

/// Lienzo infinito con puntos de referencia. Dibuja con ratón, dedo o lápiz;
/// dos dedos o la rueda mueven la vista, Ctrl + rueda hace zoom.
class Whiteboard extends StatefulWidget {
  const Whiteboard(
      {super.key, required this.controller, this.readOnly = false});
  final BoardController controller;
  final bool readOnly;

  @override
  State<Whiteboard> createState() => _WhiteboardState();
}

class _WhiteboardState extends State<Whiteboard> {
  BoardController get _c => widget.controller;

  final _focus = FocusNode(debugLabel: 'pizarra');
  final _live = ValueNotifier<int>(0);
  Offset _offset = Offset.zero;
  double _scale = 1;
  Size _size = Size.zero;

  final _pointers = <int, Offset>{};
  int? _drawing;
  Offset _downAt = Offset.zero;
  Timer? _hold;
  bool _stylusSeen = false;
  bool _panning = false;
  double _pinchDistance = 0;
  double _pinchScale = 1;

  // Trazo en curso.
  List<Offset>? _points;
  List<double>? _factors;
  double _lastFactor = 1;
  Duration _lastTime = Duration.zero;
  Offset _lastWorld = Offset.zero;

  List<Offset>? _lasso;
  bool _moving = false;
  Offset _moveBy = Offset.zero;
  bool _erasing = false;
  bool _erased = false;
  bool _invertedStylus = false;
  Offset? _hover;

  final _bitmaps = <String, ui.Image>{};
  final _bitmapsLoading = <String>{};

  ui.Picture? _picture;
  int _pictureVersion = -1;
  Color? _pictureInk;

  static const _holdSlop = 8.0;

  @override
  void dispose() {
    _hold?.cancel();
    _focus.dispose();
    _live.dispose();
    _picture?.dispose();
    for (final b in _bitmaps.values) {
      b.dispose();
    }
    super.dispose();
  }

  Offset _world(Offset local) => (local - _offset) / _scale;

  void _repaint() => _live.value++;

  Future<void> _loadBitmap(String src) async {
    final path = NoteImages.pathOf(src);
    if (_bitmaps.containsKey(path) || !_bitmapsLoading.add(path)) return;
    try {
      final bytes = await NoteImages.instance.load(path);
      if (bytes == null) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) return image.dispose();
      _bitmaps[path] = image;
      _pictureVersion = -1;
      _repaint();
    } catch (_) {
      // Se queda el recuadro vacío en su sitio.
    } finally {
      _bitmapsLoading.remove(path);
    }
  }

  void _paintImage(Canvas canvas, BoardImage i, Color frame) {
    final bmp = _bitmaps[NoteImages.pathOf(i.src)];
    if (bmp == null) {
      _loadBitmap(i.src);
      canvas.drawRect(
          i.rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = frame);
      return;
    }
    canvas.drawImageRect(
        bmp,
        Rect.fromLTWH(0, 0, bmp.width.toDouble(), bmp.height.toDouble()),
        i.rect,
        Paint()..filterQuality = FilterQuality.medium);
  }

  /// Lo no seleccionado se graba una vez: repintar no recorre cada trazo.
  ui.Picture _fixedPicture(Color ink, Color frame) {
    final cached = _picture;
    if (cached != null &&
        _pictureVersion == _c.paintVersion &&
        _pictureInk == ink) {
      return cached;
    }
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    for (var i = 0; i < _c.images.length; i++) {
      if (!_c.selectedImages.contains(i)) {
        _paintImage(canvas, _c.images[i], frame);
      }
    }
    for (var i = 0; i < _c.strokes.length; i++) {
      if (!_c.selectedStrokes.contains(i)) {
        paintBoardStroke(canvas, _c.strokes[i], ink);
      }
    }
    cached?.dispose();
    _pictureVersion = _c.paintVersion;
    _pictureInk = ink;
    return _picture = rec.endRecording();
  }

  double _pressure(PointerEvent e, Offset world, double force) {
    if (force <= 0) return 1;
    final stylus = e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    double p;
    if (stylus && e.pressureMax > e.pressureMin) {
      p = ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin))
          .clamp(0.0, 1.0);
    } else {
      // Ratón y dedo no tienen presión: cuanto más rápido, más fino.
      final ms = (e.timeStamp - _lastTime).inMicroseconds / 1000;
      final speed = ms <= 0 ? 0.0 : (world - _lastWorld).distance / ms;
      p = (1 - speed / 3).clamp(0.15, 1.0);
    }
    final target = (1 - force) + force * (0.35 + 1.3 * p);
    return _lastFactor = _lastFactor + (target - _lastFactor) * 0.45;
  }

  // ------------------------------------------------------------- gestos

  void _onDown(PointerDownEvent e) {
    _focus.requestFocus();
    _pointers[e.pointer] = e.localPosition;
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      _stylusSeen = true;
    }
    if (e.kind == PointerDeviceKind.mouse &&
        e.buttons & kSecondaryMouseButton != 0) {
      _menu(e.localPosition, e.position);
      _pointers.remove(e.pointer);
      return;
    }
    if (e.buttons & kSecondaryStylusButton != 0 &&
        e.kind == PointerDeviceKind.stylus) {
      _menu(e.localPosition, e.position);
      _pointers.remove(e.pointer);
      return;
    }
    if (e.kind == PointerDeviceKind.mouse &&
        e.buttons & kMiddleMouseButton != 0) {
      _panning = true;
      return;
    }
    if (e.kind == PointerDeviceKind.touch) {
      final touches = _pointers.length;
      if (touches >= 2) {
        _cancelAction();
        _startPinch();
        return;
      }
      // Con lápiz, la mano apoyada no dibuja: un dedo mueve la vista.
      if (_stylusSeen) {
        _panning = true;
        _armHold(e);
        return;
      }
    }
    if (_drawing != null) return;
    _drawing = e.pointer;
    _downAt = e.localPosition;
    if (e.kind != PointerDeviceKind.mouse) _armHold(e);
    if (widget.readOnly) {
      _panning = true;
      _drawing = null;
      return;
    }
    _invertedStylus = e.kind == PointerDeviceKind.invertedStylus;
    _startTool(e);
  }

  void _armHold(PointerDownEvent e) {
    _downAt = e.localPosition;
    _hold?.cancel();
    final local = e.localPosition, global = e.position;
    _hold = Timer(const Duration(milliseconds: 480), () {
      if (!mounted || _pointers.length != 1) return;
      _cancelAction();
      _panning = false;
      HapticFeedback.mediumImpact();
      _menu(local, global);
    });
  }

  void _startPinch() {
    final pts = _pointers.values.take(2).toList();
    _pinchDistance = (pts[0] - pts[1]).distance;
    _pinchScale = _scale;
    _hold?.cancel();
  }

  void _startTool(PointerDownEvent e) {
    final at = _world(e.localPosition);
    _lastWorld = at;
    _lastTime = e.timeStamp;
    _lastFactor = 1;
    final tool = _invertedStylus ? BoardTool.eraser : _c.tool;
    _c.busy = true;
    switch (tool) {
      case BoardTool.pen:
        _points = [at];
        _factors = [_pressure(e, at, _c.penForce)];
      case BoardTool.eraser:
        _c.checkpoint();
        _erasing = true;
        _erased = _c.erase(at, at, _eraserRadius(e, at));
      case BoardTool.lasso:
        final box = _c.selectionBounds?.inflate(8);
        if (box != null && box.contains(at)) {
          _moving = true;
          _moveBy = Offset.zero;
        } else {
          _c.clearSelection();
          _lasso = [at];
        }
    }
    _repaint();
  }

  double _eraserRadius(PointerEvent e, Offset at) =>
      _c.eraserWidth / 2 * _pressure(e, at, _c.eraserForce);

  void _onMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    _pointers[e.pointer] = e.localPosition;
    if ((e.localPosition - _downAt).distance > _holdSlop) _hold?.cancel();

    if (_pointers.length >= 2) {
      final pts = _pointers.values.take(2).toList();
      final focal = (pts[0] + pts[1]) / 2;
      final world = _world(focal - e.delta / 2);
      if (_pinchDistance > 0) {
        final d = (pts[0] - pts[1]).distance;
        _scale = (_pinchScale * d / _pinchDistance).clamp(0.25, 5.0);
      }
      _offset = focal - world * _scale;
      _repaint();
      return;
    }
    if (_panning) {
      _offset += e.delta;
      _repaint();
      return;
    }
    if (e.pointer != _drawing) return;
    final at = _world(e.localPosition);
    if (_points != null) {
      if ((at - _points!.last).distance < 0.7 / _scale) return;
      final f = _pressure(e, at, _c.penForce);
      _points!.add(at);
      _factors!.add(f);
    } else if (_erasing) {
      if (_c.erase(_lastWorld, at, _eraserRadius(e, at))) _erased = true;
    } else if (_lasso != null) {
      if ((at - _lasso!.last).distance > 2 / _scale) _lasso!.add(at);
    } else if (_moving) {
      _moveBy += e.delta / _scale;
    }
    _lastWorld = at;
    _lastTime = e.timeStamp;
    _repaint();
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    _hold?.cancel();
    if (_pointers.length < 2) _pinchDistance = 0;
    if (_pointers.isEmpty) _panning = false;
    if (e.pointer != _drawing) return;
    _drawing = null;
    _c.busy = false;
    if (_points != null) {
      _c.addStroke(BoardStroke(_c.color, _c.penWidth, _points!, _factors!));
      _points = null;
      _factors = null;
    } else if (_erasing) {
      _erasing = false;
      _erased ? _c.commitErase() : _c.rollback();
    } else if (_lasso != null) {
      final loop = _lasso!;
      _lasso = null;
      // Al soltar se cierra solo y selecciona todo lo de dentro.
      if (loop.length >= 3) _c.selectLasso(loop);
    } else if (_moving) {
      _moving = false;
      final by = _moveBy;
      _moveBy = Offset.zero;
      _c.moveSelection(by);
    }
    _repaint();
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _hold?.cancel();
    if (_pointers.isEmpty) _panning = false;
    if (e.pointer == _drawing) _cancelAction();
  }

  void _cancelAction() {
    _hold?.cancel();
    if (_erasing) _c.rollback();
    _drawing = null;
    _points = null;
    _factors = null;
    _lasso = null;
    _moving = false;
    _moveBy = Offset.zero;
    _erasing = false;
    _erased = false;
    _c.busy = false;
    _repaint();
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final s = ev as PointerScrollEvent;
        if (HardwareKeyboard.instance.isControlPressed) {
          _zoomAt(
              s.localPosition, math.pow(0.998, s.scrollDelta.dy).toDouble());
        } else if (HardwareKeyboard.instance.isShiftPressed) {
          _offset -= Offset(s.scrollDelta.dy, 0);
          _repaint();
        } else {
          _offset -= s.scrollDelta;
          _repaint();
        }
      });
    } else if (e is PointerScaleEvent) {
      _zoomAt(e.localPosition, e.scale);
    }
  }

  void _zoomAt(Offset focal, double factor) {
    final world = _world(focal);
    _scale = (_scale * factor).clamp(0.25, 5.0);
    _offset = focal - world * _scale;
    _repaint();
  }

  // ---------------------------------------------------------------- menú

  Future<void> _addImage(Uint8List bytes, Offset at) async {
    final src = await NoteImages.instance.add(bytes);
    if (!mounted) return;
    if (src == null) {
      showToast(context, tr('Algún archivo no es una imagen'),
          icon: Icons.broken_image_outlined);
      return;
    }
    final size = NoteImages.sizeOf(src) ?? const Size(320, 240);
    final k = math.min(1.0, 420 / math.max(size.width, size.height));
    _c.addImage(BoardImage(
        src,
        Rect.fromCenter(
            center: at, width: size.width * k, height: size.height * k)));
  }

  Future<void> _paste(Offset at) async {
    final images = await readClipboardImages();
    if (!mounted) return;
    if (images.isNotEmpty) {
      for (final (i, b) in images.indexed) {
        await _addImage(b, at + Offset(24.0 * i, 24.0 * i));
      }
      return;
    }
    if (_c.hasClip) {
      _c.paste(at);
    } else {
      showToast(context, tr('No hay nada que pegar'),
          icon: Icons.content_paste_off_rounded);
    }
  }

  void _copy() {
    if (!_c.hasSelection) return;
    _c.copySelection();
    // Si no, una captura antigua del portapapeles ganaría al pegar.
    Clipboard.setData(const ClipboardData(text: ''));
  }

  void _duplicate() {
    final box = _c.selectionBounds;
    if (box == null) return;
    _c.copySelection();
    _c.paste(box.center + const Offset(28, 28));
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Borrar toda la pizarra?')),
        content: Text(tr('Puedes recuperarla con Deshacer.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Borrar'))),
        ],
      ),
    );
    if (ok == true) _c.clearAll();
  }

  void _resetView() {
    _offset = Offset.zero;
    _scale = 1;
    _repaint();
  }

  Future<void> _menu(Offset local, Offset global) async {
    final at = _world(local);
    final selected = _c.hasSelection;
    final choice = await showContextMenu(context, position: global, entries: [
      if (!widget.readOnly) ...[
        if (selected) ...[
          MenuEntry('copiar', Icons.content_copy_rounded, tr('Copiar'),
              hint: 'Ctrl+C'),
          MenuEntry('cortar', Icons.content_cut_rounded, tr('Cortar'),
              hint: 'Ctrl+X'),
          MenuEntry('duplicar', Icons.library_add_outlined, tr('Duplicar'),
              hint: 'Ctrl+D'),
          MenuEntry('quitar', Icons.delete_outline_rounded, tr('Eliminar'),
              danger: true),
          null,
        ],
        MenuEntry('pegar', Icons.content_paste_rounded, tr('Pegar'),
            hint: 'Ctrl+V'),
        MenuEntry('imagen', Icons.add_photo_alternate_outlined,
            tr('Insertar imagen')),
        MenuEntry('todo', Icons.select_all_rounded, tr('Seleccionar todo'),
            hint: 'Ctrl+A'),
        null,
      ],
      MenuEntry(
          'vista', Icons.center_focus_strong_rounded, tr('Restablecer vista')),
      if (!widget.readOnly && !_c.isEmpty)
        MenuEntry('limpiar', Icons.delete_sweep_outlined, tr('Borrar pizarra'),
            danger: true),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'copiar':
        _copy();
      case 'cortar':
        _copy();
        _c.deleteSelection();
      case 'duplicar':
        _duplicate();
      case 'quitar':
        _c.deleteSelection();
      case 'pegar':
        await _paste(at);
      case 'imagen':
        final picked = await pickImageBytes(context);
        for (final (i, b) in picked.indexed) {
          await _addImage(b, at + Offset(24.0 * i, 24.0 * i));
        }
      case 'todo':
        _c.selectAll();
      case 'vista':
        _resetView();
      case 'limpiar':
        await _confirmClear();
    }
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    SingleActivator ctrl(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, control: true, shift: shift);
    final center = _world(_size.center(Offset.zero));
    if (widget.readOnly) return const {};
    return {
      ctrl(LogicalKeyboardKey.keyZ): _c.undo,
      ctrl(LogicalKeyboardKey.keyY): _c.redo,
      ctrl(LogicalKeyboardKey.keyZ, shift: true): _c.redo,
      ctrl(LogicalKeyboardKey.keyC): _copy,
      ctrl(LogicalKeyboardKey.keyX): () {
        _copy();
        _c.deleteSelection();
      },
      ctrl(LogicalKeyboardKey.keyV): () => _paste(center),
      ctrl(LogicalKeyboardKey.keyD): _duplicate,
      ctrl(LogicalKeyboardKey.keyA): _c.selectAll,
      const SingleActivator(LogicalKeyboardKey.delete): _c.deleteSelection,
      const SingleActivator(LogicalKeyboardKey.backspace): _c.deleteSelection,
      const SingleActivator(LogicalKeyboardKey.escape): _c.clearSelection,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    return ColoredBox(
      color: p.card,
      child: LayoutBuilder(builder: (context, box) {
        _size = box.biggest;
        return ListenableBuilder(
          listenable: _c,
          builder: (context, _) => CallbackShortcuts(
            bindings: _shortcuts,
            child: Focus(
              focusNode: _focus,
              child: MouseRegion(
                cursor: _c.tool == BoardTool.eraser
                    ? SystemMouseCursors.none
                    : SystemMouseCursors.precise,
                onHover: (e) {
                  _hover = e.localPosition;
                  if (_c.tool == BoardTool.eraser) _repaint();
                },
                onExit: (_) {
                  _hover = null;
                  _repaint();
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onDown,
                  onPointerMove: (e) {
                    _hover = e.localPosition;
                    _onMove(e);
                  },
                  onPointerUp: _onUp,
                  onPointerCancel: _onCancel,
                  onPointerSignal: _onSignal,
                  child: ClipRect(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('pizarra'),
                        size: Size.infinite,
                        painter: _BoardPainter(this, ink, p),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.s, this.ink, this.colors)
      : super(repaint: Listenable.merge([s._live, s._c]));
  final _WhiteboardState s;
  final Color ink;
  final NotasColors colors;

  void _paintDots(Canvas canvas, Size size) {
    var step = 26.0;
    while (step * s._scale < 14) {
      step *= 2;
    }
    final gap = step * s._scale;
    final dx = s._offset.dx % gap, dy = s._offset.dy % gap;
    final dots = <Offset>[];
    for (var x = dx; x < size.width; x += gap) {
      for (var y = dy; y < size.height; y += gap) {
        dots.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
        ui.PointMode.points,
        dots,
        Paint()
          ..color = colors.secondary.withValues(alpha: 0.42)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash * 2;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintDots(canvas, size);
    final c = s._c;
    final frame = colors.separator;
    final fixed = s._fixedPicture(ink, frame);
    canvas.save();
    canvas.translate(s._offset.dx, s._offset.dy);
    canvas.scale(s._scale);
    canvas.drawPicture(fixed);

    canvas.save();
    canvas.translate(s._moveBy.dx, s._moveBy.dy);
    for (final i in c.selectedImages) {
      if (i < c.images.length) s._paintImage(canvas, c.images[i], frame);
    }
    for (final i in c.selectedStrokes) {
      if (i < c.strokes.length) paintBoardStroke(canvas, c.strokes[i], ink);
    }
    canvas.restore();

    if (s._points != null) {
      paintBoardStroke(canvas,
          BoardStroke(c.color, c.penWidth, s._points!, s._factors!), ink);
    }
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / s._scale
      ..color = colors.accent;
    if (s._lasso != null && s._lasso!.length > 1) {
      final l = s._lasso!;
      final path = Path()..moveTo(l.first.dx, l.first.dy);
      for (final q in l.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      path.close();
      canvas.drawPath(
          path, Paint()..color = colors.accent.withValues(alpha: 0.08));
      _dashed(canvas, path, dash, 6 / s._scale);
    }
    final box = c.selectionBounds?.shift(s._moveBy).inflate(8);
    if (box != null) {
      final r = RRect.fromRectAndRadius(box, Radius.circular(8 / s._scale));
      canvas.drawRRect(
          r, Paint()..color = colors.accent.withValues(alpha: 0.07));
      _dashed(canvas, Path()..addRRect(r), dash, 6 / s._scale);
    }
    canvas.restore();

    final hover = s._hover;
    if (hover != null && c.tool == BoardTool.eraser) {
      canvas.drawCircle(
          hover,
          c.eraserWidth / 2 * s._scale,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = colors.secondary);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter o) => o.ink != ink || o.colors != colors;
}

// -------------------------------------------------- vista previa en la nota

/// Tarjeta de la pizarra dentro de la nota en modo texto.
class NoteBoardEmbedBuilder extends EmbedBuilder {
  const NoteBoardEmbedBuilder({required this.onOpen});
  final VoidCallback onOpen;

  @override
  String get key => BoardData.embedType;

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext e) {
    final data = BoardData.decode(e.node.value.data);
    if (data == null) return const SizedBox.shrink();
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: p.background,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: SizedBox(
            height: 170,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PreviewPainter(
                        data, Theme.of(context).colorScheme.onSurface),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 8,
                  child: Row(
                    children: [
                      Icon(Icons.gesture_rounded, size: 16, color: p.accent),
                      const SizedBox(width: 6),
                      Text(tr('Nota de pizarra'),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: p.secondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.data, this.ink);
  final BoardData data;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    Rect? box;
    for (final s in data.strokes) {
      box = box?.expandToInclude(s.bounds) ?? s.bounds;
    }
    for (final i in data.images) {
      box = box?.expandToInclude(i.rect) ?? i.rect;
    }
    if (box == null) return;
    final k = math.min(
        1.0,
        math.min(
            (size.width - 24) / box.width, (size.height - 40) / box.height));
    canvas.translate(size.width / 2, (size.height - 16) / 2);
    canvas.scale(k);
    canvas.translate(-box.center.dx, -box.center.dy);
    for (final i in data.images) {
      canvas.drawRect(i.rect, Paint()..color = ink.withValues(alpha: 0.12));
    }
    for (final s in data.strokes) {
      paintBoardStroke(canvas, s, ink);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter o) => o.data != data || o.ink != ink;
}

// ------------------------------------------------------ panel de herramienta

const boardColors = <int>[
  0, // tinta automática
  0xFF8E8E93,
  0xFFE5484D,
  0xFFF76B15,
  0xFFF5A524,
  0xFF30A46C,
  0xFF12A594,
  0xFF3E8BFF,
  0xFF3358D4,
  0xFF8E4EC6,
  0xFFE93D82,
  0xFF8D6E63,
];

/// Colores, tamaño y fuerza del boli, o tamaño y fuerza de la goma.
Future<void> showBoardToolPanel(
    BuildContext context, BoardController c, Offset anchor) {
  final pen = c.tool == BoardTool.pen;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Cerrar'),
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) {
      final media = MediaQuery.sizeOf(ctx);
      const width = 280.0;
      return Stack(
        children: [
          Positioned(
            left: (anchor.dx - width / 2).clamp(8.0, media.width - width - 8),
            top: anchor.dy + 6,
            width: width,
            child: _ToolPanel(controller: c, pen: pen),
          ),
        ],
      );
    },
    transitionBuilder: (_, a, __, child) {
      final curved = CurvedAnimation(parent: a, curve: Anim.curve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          alignment: Alignment.topCenter,
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.controller, required this.pen});
  final BoardController controller;
  final bool pen;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: p.card,
      elevation: 14,
      shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.separator),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final c = controller;
            final width = pen ? c.penWidth : c.eraserWidth;
            final force = pen ? c.penForce : c.eraserForce;
            final shown = c.color == 0 ? ink : Color(c.color);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pen) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in boardColors)
                        Semantics(
                          button: true,
                          selected: v == c.color,
                          label: tr('Color'),
                          child: GestureDetector(
                            onTap: () => c.setPen(color: v),
                            child: AnimatedContainer(
                              duration: Anim.fast,
                              curve: Anim.curve,
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: v == 0 ? ink : Color(v),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: v == c.color ? p.accent : p.separator,
                                  width: v == c.color ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _SliderRow(
                  label: tr('Tamaño'),
                  value: width,
                  min: pen ? 1 : 6,
                  max: pen ? 24 : 80,
                  text: width.round().toString(),
                  onChanged: (v) =>
                      pen ? c.setPen(width: v) : c.setEraser(width: v),
                ),
                _SliderRow(
                  label: tr('Fuerza'),
                  value: force,
                  min: 0,
                  max: 1,
                  text: '${(force * 100).round()}%',
                  onChanged: (v) =>
                      pen ? c.setPen(force: v) : c.setEraser(force: v),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: Center(
                    child: pen
                        ? CustomPaint(
                            size: const Size(200, 30),
                            painter: _PenPreview(shown, width, force),
                          )
                        : Container(
                            width: math.min(width, 32),
                            height: math.min(width, 32),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: p.secondary),
                            ),
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
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.text,
    required this.onChanged,
  });
  final String label;
  final double value, min, max;
  final String text;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      children: [
        SizedBox(
            width: 56,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: p.secondary))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            semanticFormatterCallback: (_) => text,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
            width: 38,
            child: Text(text,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontFeatures: [ui.FontFeature.tabularFigures()]))),
      ],
    );
  }
}

/// Muestra del trazo: con más fuerza, más diferencia entre fino y grueso.
class _PenPreview extends CustomPainter {
  _PenPreview(this.color, this.width, this.force);
  final Color color;
  final double width, force;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 36;
    final pts = <Offset>[];
    final f = <double>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      pts.add(Offset(t * size.width,
          size.height / 2 + math.sin(t * math.pi * 2) * size.height * 0.22));
      f.add((1 - force) + force * (0.35 + 1.3 * math.sin(t * math.pi)));
    }
    paintBoardStroke(
        canvas, BoardStroke(0, math.min(width, 16), pts, f), color);
  }

  @override
  bool shouldRepaint(_PenPreview o) =>
      o.color != color || o.width != width || o.force != force;
}

/// Goma de borrar: Material no trae este icono.
class EraserIcon extends StatelessWidget {
  const EraserIcon({super.key, required this.color, this.size = 21});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _EraserPainter(color));
}

class _EraserPainter extends CustomPainter {
  _EraserPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(9 * u, 21 * u), Offset(21 * u, 21 * u), line);
    canvas.save();
    canvas.translate(12 * u, 11.5 * u);
    canvas.rotate(-math.pi / 4);
    final body =
        Rect.fromCenter(center: Offset.zero, width: 19 * u, height: 10.5 * u);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(2.4 * u)), line);
    canvas.drawLine(
        Offset(-2 * u, body.top), Offset(-2 * u, body.bottom), line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EraserPainter o) => o.color != color;
}
