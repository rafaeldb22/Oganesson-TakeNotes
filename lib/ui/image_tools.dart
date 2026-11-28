import 'dart:async';
import 'dart:math';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image/image.dart' as img;

import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';

// ------------------------------------------------- mover una imagen

/// Lo que se arrastra al mover una imagen dentro de la nota.
/// true mientras se arrastra una foto o un archivo para moverlo: el editor
/// no debe seleccionar texto a la vez.
final mediaDragActive = ValueNotifier<bool>(false);

class ImageMovePayload {
  const ImageMovePayload(this.src, this.offsetOf, {this.embed});
  final String src;

  /// Lo que se vuelve a insertar (una imagen si es null; si no, p. ej. el
  /// embed de un archivo adjunto).
  final Embeddable? embed;

  /// Posición actual de la imagen en el documento.
  final int Function() offsetOf;
}

/// Texto plano del documento (las imágenes son U+FFFC, un carácter, igual
/// que en los offsets de Quill).
String _plain(QuillController c) => c.document.toPlainText();

/// Inicio de la línea que contiene [offset].
int _lineStart(String t, int offset) =>
    offset <= 0 ? 0 : t.lastIndexOf('\n', offset - 1) + 1;

/// ¿El cursor (sin selección) está justo antes o después de una imagen?
bool caretNextToImage(QuillController c) {
  final sel = c.selection;
  if (!sel.isValid || !sel.isCollapsed) return false;
  // Solo los dos caracteres de alrededor (no todo el texto en cada
  // movimiento del cursor).
  final len = c.document.length;
  final o = sel.baseOffset;
  final from = max(0, o - 1);
  final n = min(2, len - from);
  if (n <= 0) return false;
  return c.document.getPlainText(from, n).contains('\uFFFC');
}

/// Quita el embed de [offset] y su línea, sin dejar un hueco en la nota.
void removeEmbedLine(QuillController c, int offset) {
  final t = _plain(c);
  final len = offset + 2 < t.length && t[offset + 1] == '\n' ? 2 : 1;
  c.replaceText(offset, len, '', TextSelection.collapsed(offset: offset));
}

/// Inserta una imagen en [index] SIEMPRE en su propia línea (Quill solo
/// separa así los vídeos: una imagen pegada en mitad de una frase quedaría
/// mezclada con el texto). Devuelve la posición de la imagen.
int insertImageBlock(QuillController c, int index, String src) =>
    insertEmbedBlock(c, index, BlockEmbed.image(src));

/// Igual que [insertImageBlock] para cualquier embed de bloque (archivos).
int insertEmbedBlock(QuillController c, int index, Embeddable embed) {
  final t = _plain(c);
  index = index.clamp(0, max(0, t.length - 1));
  var at = index;
  if (at > 0 && t[at - 1] != '\n') {
    c.replaceText(at, 0, '\n', null);
    at++;
  }
  c.replaceText(at, 0, embed, null);
  final after = _plain(c);
  if (at + 1 >= after.length || after[at + 1] != '\n') {
    c.replaceText(at + 1, 0, '\n', null);
  }
  return at;
}

/// Mueve la imagen que está en [from] para que empiece en [target] (un
/// inicio de línea del documento actual). Devuelve false si no hay que
/// moverla.
bool moveImageTo(QuillController c, int from, String src, int target,
    {Embeddable? embed}) {
  final t = _plain(c);
  if (from < 0 || from >= t.length) return false;
  // La imagen ocupa su propia línea: imagen + salto de línea.
  final hasBreak = from + 1 < t.length && t[from + 1] == '\n';
  final len = hasBreak ? 2 : 1;
  if (target == from || target == from + len) return false;
  c.replaceText(from, len, '', null);
  final at = insertEmbedBlock(
      c, target > from ? target - len : target, embed ?? BlockEmbed.image(src));
  c.updateSelection(
      TextSelection.collapsed(offset: at + 1), ChangeSource.local);
  HapticFeedback.selectionClick();
  return true;
}

/// Sube la imagen por encima de la línea anterior.
bool moveImageUp(QuillController c, int from, String src) {
  if (from <= 0) return false;
  final t = _plain(c);
  return moveImageTo(c, from, src, _lineStart(t, from - 1));
}

/// Baja la imagen por debajo de la línea siguiente.
bool moveImageDown(QuillController c, int from, String src) {
  final t = _plain(c);
  final nextStart = from + 2; // tras la imagen y su salto de línea
  if (nextStart >= t.length) return false;
  final nextEnd = t.indexOf('\n', nextStart);
  if (nextEnd == -1 || nextEnd + 1 >= t.length) {
    // Siguiente línea = la última: la imagen pasa al final.
    return moveImageTo(c, from, src, t.length - 1);
  }
  return moveImageTo(c, from, src, nextEnd + 1);
}

/// Zona del editor donde se sueltan las imágenes que se están moviendo:
/// una línea con el color del acento marca dónde caerá.
class ImageMoveTarget extends StatefulWidget {
  const ImageMoveTarget({
    super.key,
    required this.controller,
    required this.editorKey,
    required this.child,
  });

  final QuillController controller;
  final GlobalKey<EditorState> editorKey;
  final Widget child;

  @override
  State<ImageMoveTarget> createState() => _ImageMoveTargetState();
}

class _ImageMoveTargetState extends State<ImageMoveTarget> {
  int? _target; // inicio de línea donde caería
  double? _lineY; // altura de la línea indicadora (local)

  /// Calcula el destino para la posición global [g].
  void _update(Offset g) {
    final editor = widget.editorKey.currentState?.renderEditor;
    final box = context.findRenderObject() as RenderBox?;
    if (editor == null || box == null) return;
    final t = _plain(widget.controller);
    final pos = editor.getPositionForOffset(g).offset.clamp(0, t.length - 1);
    final start = _lineStart(t, pos);
    var end = t.indexOf('\n', pos);
    if (end == -1) end = t.length - 1;
    final top = editor.getLocalRectForCaret(TextPosition(offset: start));
    final bottom = editor.getLocalRectForCaret(TextPosition(offset: end));
    final local = editor.globalToLocal(g);
    final upper = local.dy < (top.top + bottom.bottom) / 2;
    final target = upper ? start : min(end + 1, t.length - 1);
    final y = upper ? top.top : bottom.bottom;
    final ly = box.globalToLocal(editor.localToGlobal(Offset(0, y))).dy;
    if (target != _target || ly != _lineY) {
      setState(() {
        _target = target;
        _lineY = ly;
      });
    }
  }

  void _clear() {
    if (_target != null || _lineY != null) {
      setState(() {
        _target = null;
        _lineY = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    return DragTarget<ImageMovePayload>(
      onMove: (d) => _update(d.offset),
      onLeave: (_) => _clear(),
      onAcceptWithDetails: (d) {
        final target = _target;
        _clear();
        if (target == null) return;
        moveImageTo(widget.controller, d.data.offsetOf(), d.data.src, target,
            embed: d.data.embed);
      },
      builder: (context, candidates, _) => Stack(
        children: [
          widget.child,
          if (candidates.isNotEmpty && _lineY != null)
            AnimatedPositioned(
              duration: Anim.fast,
              curve: Anim.curve,
              left: 12,
              right: 12,
              top: _lineY! - 1.5,
              child: IgnorePointer(
                child: Row(children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                              color: accent.withValues(alpha: 0.5),
                              blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ]),
              ).animate().fadeIn(duration: Anim.fast),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- recortar

/// Gira una imagen 90° (en un isolate) y la devuelve en PNG.
Uint8List _rotate90(Uint8List bytes) {
  final i = img.decodeImage(bytes);
  if (i == null) return bytes;
  return img.encodePng(img.copyRotate(img.bakeOrientation(i), angle: 90));
}

/// Abre el editor de recorte a pantalla completa. Devuelve la imagen
/// recortada o null si se cancela.
Future<Uint8List?> openImageCropper(BuildContext context, Uint8List bytes) =>
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<Uint8List>(
      opaque: false,
      transitionDuration: Anim.slow,
      reverseTransitionDuration: Anim.medium,
      pageBuilder: (_, __, ___) => _Cropper(bytes: bytes),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Anim.curve),
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0)
              .animate(CurvedAnimation(parent: a, curve: Anim.curve)),
          child: child,
        ),
      ),
    ));

class _Cropper extends StatefulWidget {
  const _Cropper({required this.bytes});
  final Uint8List bytes;

  @override
  State<_Cropper> createState() => _CropperState();
}

class _CropperState extends State<_Cropper> {
  final _crop = CropController();
  late Uint8List _image = widget.bytes;
  double? _ratio; // null = libre
  bool _busy = false;
  bool _ready = false;
  bool _canUndo = false, _canRedo = false;
  int _version = 0; // al girar se vuelve a montar el recorte

  static const _ratios = <(String, double?)>[
    ('Libre', null),
    ('1:1', 1),
    ('4:3', 4 / 3),
    ('16:9', 16 / 9),
    ('3:4', 3 / 4),
  ];

  void _done() {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    _crop.crop();
  }

  Future<void> _rotate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await compute(_rotate90, _image);
    if (!mounted) return;
    setState(() {
      _image = r;
      _busy = false;
      _ready = false;
      _version++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    Widget roundBtn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: Bouncy(
            pressedScale: 0.88,
            child: IconButton(
              onPressed: onTap,
              icon: Icon(icon),
              color: Colors.white,
              disabledColor: Colors.white30,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.enter): _done,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: const Color(0xF20B0B0F),
          child: Padding(
            padding: EdgeInsets.only(top: top + 8, bottom: bottom + 12),
            child: Column(
              children: [
                // Barra de arriba: cancelar · título · hecho.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      roundBtn(Icons.close_rounded, tr('Cancelar'),
                          () => Navigator.of(context).maybePop()),
                      const Spacer(),
                      Text(tr('Recortar'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Bouncy(
                        child: FilledButton.icon(
                          onPressed: _busy || !_ready ? null : _done,
                          style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor:
                                  ThemeData.estimateBrightnessForColor(
                                              accent) ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black),
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded),
                          label: Text(tr('Hecho')),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Área de recorte.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: AnimatedSwitcher(
                      duration: Anim.medium,
                      child: Crop(
                        key: ValueKey(_version),
                        image: _image,
                        controller: _crop,
                        aspectRatio: _ratio,
                        baseColor: Colors.transparent,
                        maskColor: Colors.black.withValues(alpha: 0.62),
                        interactive: false,
                        filterQuality: FilterQuality.high,
                        progressIndicator: const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white)),
                        initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                            size: 0.9, aspectRatio: _ratio),
                        cornerDotBuilder: (size, edge) =>
                            _Corner(size: size, edge: edge),
                        onStatusChanged: (s) {
                          final ready = s == CropStatus.ready;
                          if (ready != _ready && mounted) {
                            setState(() => _ready = ready);
                          }
                        },
                        onHistoryChanged: (h) => setState(() {
                          _canUndo = h.undoCount > 0;
                          _canRedo = h.redoCount > 0;
                        }),
                        onCropped: (r) {
                          switch (r) {
                            case CropSuccess(:final croppedImage):
                              Navigator.of(context).pop(croppedImage);
                            case CropFailure():
                              setState(() => _busy = false);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Proporciones.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final (label, value) in _ratios)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _RatioChip(
                            label: label == 'Libre' ? tr('Libre') : label,
                            selected: _ratio == value,
                            // Hasta que la imagen está lista, la
                            // librería no acepta cambios de proporción.
                            onTap: () {
                              if (!_ready || _busy) return;
                              setState(() => _ratio = value);
                              _crop.aspectRatio = value;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Girar · deshacer · rehacer.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    roundBtn(Icons.rotate_90_degrees_ccw_rounded,
                        tr('Girar 90°'), _busy ? null : _rotate),
                    const SizedBox(width: 14),
                    roundBtn(Icons.undo_rounded, tr('Deshacer'),
                        _canUndo ? _crop.undo : null),
                    const SizedBox(width: 14),
                    roundBtn(Icons.redo_rounded, tr('Rehacer'),
                        _canRedo ? _crop.redo : null),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Esquina del recorte en forma de L (como en las fotos del móvil).
class _Corner extends StatelessWidget {
  const _Corner({required this.size, required this.edge});
  final double size;
  final EdgeAlignment edge;

  @override
  Widget build(BuildContext context) {
    final left =
        edge == EdgeAlignment.topLeft || edge == EdgeAlignment.bottomLeft;
    final topSide =
        edge == EdgeAlignment.topLeft || edge == EdgeAlignment.topRight;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CornerPainter(left: left, top: topSide)),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.left, required this.top});
  final bool left, top;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final c = size.center(Offset.zero);
    const l = 14.0;
    final dx = left ? l : -l;
    final dy = top ? l : -l;
    canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(c.dx + dx, c.dy),
        p);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.left != left || old.top != top;
}

class _RatioChip extends StatelessWidget {
  const _RatioChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    return Bouncy(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Anim.medium,
          curve: Anim.curve,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: AnimatedDefaultTextStyle(
            duration: Anim.medium,
            style: TextStyle(
              color: selected
                  ? (ThemeData.estimateBrightnessForColor(accent) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black)
                  : Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
