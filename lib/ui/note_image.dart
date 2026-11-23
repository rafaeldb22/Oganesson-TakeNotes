import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:quill_native_bridge/quill_native_bridge.dart';

import '../data/note_images.dart';
import 'anim.dart';
import 'drawing_pad.dart';
import 'image_tools.dart';
import 'note_media.dart';
import 'context_menu.dart';
import 'i18n.dart';
import 'theme.dart';
import 'title_bar.dart';
import 'toast.dart';

const _imageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif'
};

bool _isImagePath(String path) {
  final dot = path.lastIndexOf('.');
  return dot != -1 &&
      _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
}

// ------------------------------------------------------------- insertar

/// Inserta imágenes en la posición del cursor (una debajo de otra).
/// Devuelve cuántas se han añadido.
Future<int> insertImages(BuildContext context, QuillController controller,
    List<Uint8List> images) async {
  var added = 0;
  for (final bytes in images) {
    final src = await NoteImages.instance.add(bytes);
    if (src == null) continue;
    final sel = controller.selection;
    final index = sel.isValid
        ? min(sel.baseOffset, sel.extentOffset)
        : controller.document.length - 1;
    final length = sel.isValid ? (sel.extentOffset - sel.baseOffset).abs() : 0;
    if (length > 0) controller.replaceText(index, length, '', null);
    final at = insertImageBlock(controller, index, src);
    // El cursor queda en la línea de debajo, listo para seguir escribiendo.
    controller.moveCursorToPosition(at + 2);
    added++;
  }
  if (added < images.length && context.mounted) {
    showToast(context, tr('Algún archivo no es una imagen'),
        icon: Icons.broken_image_outlined);
  }
  if (added > 0) HapticFeedback.lightImpact();
  return added;
}

/// Ctrl+V: si el portapapeles tiene una imagen (una captura, una imagen
/// copiada o archivos de imagen copiados en el Explorador), la pega en la
/// nota. Devuelve false para que el texto se pegue como siempre.
Future<bool> pasteImagesFromClipboard(
    BuildContext context, QuillController controller) async {
  try {
    if (await Clipboard.hasStrings()) return false;
  } catch (_) {}
  final images = <Uint8List>[];
  try {
    final b = await Pasteboard.image;
    if (b != null && b.isNotEmpty) images.add(b);
  } catch (_) {}
  if (images.isEmpty && isDesktopWindows) {
    try {
      for (final f in (await Pasteboard.files()).where(_isImagePath)) {
        images.add(await File(f).readAsBytes());
      }
    } catch (_) {}
  }
  if (images.isEmpty || !context.mounted) return false;
  await insertImages(context, controller, images);
  return true;
}

/// Botón de imagen: en Android elige entre galería y cámara; en Windows
/// abre el selector de archivos (varias a la vez).
Future<void> pickAndInsertImages(
    BuildContext context, QuillController controller) async {
  final picker = ImagePicker();
  var files = <XFile>[];
  try {
    if (Platform.isAndroid) {
      final source = await _chooseSource(context);
      if (source == null) return;
      // En Android la reducción la hace el sistema (rápido y sin memoria).
      if (source == ImageSource.camera) {
        final f = await picker.pickImage(
            source: source,
            maxWidth: NoteImages.maxSide.toDouble(),
            maxHeight: NoteImages.maxSide.toDouble(),
            imageQuality: 88);
        if (f != null) files = [f];
      } else {
        files = await picker.pickMultiImage(
            maxWidth: NoteImages.maxSide.toDouble(),
            maxHeight: NoteImages.maxSide.toDouble(),
            imageQuality: 88);
      }
    } else {
      files = await picker.pickMultiImage();
    }
  } catch (e) {
    debugPrint('Imagen: selector ($e)');
    if (context.mounted) {
      showToast(context, tr('No se pudo abrir la imagen'),
          icon: Icons.error_outline_rounded);
    }
    return;
  }
  if (files.isEmpty) return;
  final bytes = [for (final f in files) await f.readAsBytes()];
  if (context.mounted) await insertImages(context, controller, bytes);
}

Future<ImageSource?> _chooseSource(BuildContext context) =>
    showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        Widget tile(int i, IconData icon, String label, ImageSource s) =>
            Expanded(
              child: Bouncy(
                child: Material(
                  color: Palette.accent(ctx).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.pop(ctx, s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Column(
                        children: [
                          Icon(icon, size: 30, color: Palette.accent(ctx)),
                          const SizedBox(height: 10),
                          Text(label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
              )
                  .animate(delay: (60 * i).ms)
                  .fadeIn(duration: Anim.medium)
                  .slideY(begin: 0.3, curve: Anim.curve),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 14),
                  child: Text(tr('Añadir imagen'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                Row(children: [
                  tile(0, Icons.photo_library_outlined, tr('Galería'),
                      ImageSource.gallery),
                  const SizedBox(width: 12),
                  tile(1, Icons.photo_camera_outlined, tr('Cámara'),
                      ImageSource.camera),
                ]),
              ],
            ),
          ),
        );
      },
    );

// --------------------------------------------------- copiar y guardar

Future<void> copyImageBytes(BuildContext context, Uint8List bytes) async {
  try {
    await Pasteboard.writeImage(bytes);
    if (context.mounted) {
      showToast(context, tr('Imagen copiada'),
          icon: Icons.content_copy_rounded);
    }
  } catch (_) {
    if (context.mounted) {
      showToast(context, tr('No se pudo copiar la imagen'),
          icon: Icons.error_outline_rounded);
    }
  }
}

Future<void> saveImageBytes(BuildContext context, Uint8List bytes) async {
  final ext = NoteImages.extensionOf(bytes);
  final name = 'oganesson-${DateTime.now().millisecondsSinceEpoch}';
  final bridge = QuillNativeBridge();
  try {
    if (Platform.isAndroid) {
      await bridge.saveImageToGallery(bytes,
          options: GalleryImageSaveOptions(
              name: name, fileExtension: ext, albumName: 'Oganesson'));
      if (context.mounted) {
        showToast(context, tr('Guardada en la galería'),
            icon: Icons.download_done_rounded);
      }
    } else {
      final r = await bridge.saveImage(bytes,
          options: ImageSaveOptions(name: name, fileExtension: ext));
      if (r.filePath != null && context.mounted) {
        showToast(context, tr('Imagen guardada'),
            icon: Icons.download_done_rounded);
      }
    }
  } catch (e) {
    debugPrint('Imagen: no se pudo guardar ($e)');
    if (context.mounted) {
      showToast(context, tr('No se pudo guardar la imagen'),
          icon: Icons.error_outline_rounded);
    }
  }
}

// ------------------------------------------------------- embed de Quill

/// Dibuja las imágenes de las notas dentro del editor.
class NoteImageEmbedBuilder extends EmbedBuilder {
  const NoteImageEmbedBuilder();

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final node = embedContext.node;
    final controller = embedContext.controller;
    final src = '${node.value.data}';
    final editable = !embedContext.readOnly;
    return NoteImageView(
      src: src,
      controller: controller,
      offsetOf: () => node.documentOffset,
      onDelete: !editable
          ? null
          : () {
              final o = node.documentOffset;
              controller.replaceText(
                  o, 1, '', TextSelection.collapsed(offset: o));
            },
      // Recortada: se guarda como imagen nueva y ocupa el mismo sitio.
      onCropped: !editable
          ? null
          : (bytes) async {
              final newSrc = await NoteImages.instance.add(bytes);
              if (newSrc == null) return;
              final o = node.documentOffset;
              final sized =
                  NoteImages.withScale(newSrc, NoteImages.scaleOf(src));
              controller.replaceText(o, 1, BlockEmbed.image(sized), null);
            },
      onResize: !editable || !NoteImages.isOurs(src)
          ? null
          : (percent) {
              final o = node.documentOffset;
              controller.replaceText(o, 1,
                  BlockEmbed.image(NoteImages.withScale(src, percent)), null);
            },
      onMoveUp: !editable
          ? null
          : () => moveImageUp(controller, node.documentOffset, src),
      onMoveDown: !editable
          ? null
          : () => moveImageDown(controller, node.documentOffset, src),
    );
  }
}

/// Una imagen dentro de la nota: hueco con brillo mientras carga, aparece
/// con un fundido, muestra si se está subiendo y al pasar el ratón ofrece
/// ver, copiar, guardar y quitar. Al tocarla se abre a pantalla completa.
class NoteImageView extends StatefulWidget {
  const NoteImageView({
    super.key,
    required this.src,
    this.controller,
    this.offsetOf,
    this.onDelete,
    this.onCropped,
    this.onResize,
    this.onMoveUp,
    this.onMoveDown,
  });

  final String src;
  final QuillController? controller;
  final int Function()? offsetOf;
  final VoidCallback? onDelete;
  final Future<void> Function(Uint8List cropped)? onCropped;
  final void Function(int percent)? onResize;
  final bool Function()? onMoveUp;
  final bool Function()? onMoveDown;

  @override
  State<NoteImageView> createState() => _NoteImageViewState();
}

class _NoteImageViewState extends State<NoteImageView> {
  /// Imágenes que ya han hecho su animación de entrada (al reconstruir el
  /// editor no se vuelven a animar).
  static final _seen = <String>{};

  final _heroTag = Object();
  Uint8List? _bytes;
  bool _failed = false;
  bool _hover = false;
  late bool _animateIn;

  /// Tamaño mientras se mueve el control (aún sin guardar en la nota).
  int? _liveScale;

  bool get _ours => NoteImages.isOurs(widget.src);
  String get _path => NoteImages.pathOf(widget.src);

  @override
  void initState() {
    super.initState();
    // Por ruta: cambiar el tamaño no debe repetir la animación de entrada.
    _animateIn = _seen.add(_ours ? _path : widget.src);
    NoteImages.instance.addListener(_onImages);
    widget.controller?.addListener(_onSelection);
    _load();
  }

  @override
  void didUpdateWidget(NoteImageView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onSelection);
      widget.controller?.addListener(_onSelection);
    }
    final sameImage = NoteImages.isOurs(old.src) &&
        _ours &&
        NoteImages.pathOf(old.src) == _path;
    if (old.src != widget.src && !sameImage) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  @override
  void dispose() {
    NoteImages.instance.removeListener(_onImages);
    widget.controller?.removeListener(_onSelection);
    super.dispose();
  }

  bool _wasSelected = false;
  void _onSelection() {
    // Solo se redibuja cuando la imagen entra o sale de la selección.
    if (_selected != _wasSelected && mounted) setState(() {});
  }

  void _onImages() {
    if (mounted) setState(() {});
  }

  void _load() {
    if (!_ours) return; // http(s): lo carga Image.network
    final cached = NoteImages.instance.cached(_path);
    if (cached != null) {
      _bytes = cached;
      return;
    }
    NoteImages.instance.load(_path).then((b) {
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _failed = b == null;
      });
    });
  }

  /// ¿La selección del editor incluye esta imagen? (marco con el acento)
  bool get _selected {
    final c = widget.controller;
    if (c == null || widget.offsetOf == null) return false;
    final int off;
    try {
      off = widget.offsetOf!(); // el nodo puede estar ya fuera del documento
    } catch (_) {
      return false;
    }
    final sel = c.selection;
    return !sel.isCollapsed && sel.start <= off && sel.end > off;
  }

  ImageProvider? get _provider {
    if (_ours) return _bytes == null ? null : MemoryImage(_bytes!);
    if (widget.src.startsWith('http')) return NetworkImage(widget.src);
    return null;
  }

  Future<Uint8List?> _currentBytes() async {
    if (_bytes != null) return _bytes;
    if (!widget.src.startsWith('http')) return null;
    try {
      final r = await HttpClient().getUrl(Uri.parse(widget.src));
      final res = await r.close();
      final chunks = <int>[];
      await for (final c in res) {
        chunks.addAll(c);
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
    }
  }

  void _open() {
    final p = _provider;
    if (p == null) return;
    openImageViewer(
      context,
      image: p,
      heroTag: _heroTag,
      bytes: _currentBytes,
      onDelete: widget.onDelete,
      onCropped: widget.onCropped,
    );
  }

  Future<void> _crop() async {
    final b = await _currentBytes();
    if (b == null || !mounted || widget.onCropped == null) return;
    final cropped = await openImageCropper(context, b);
    if (cropped != null) await widget.onCropped!(cropped);
  }

  /// Control de tamaño: la imagen cambia en directo y se guarda al cerrar.
  Future<void> _pickSize() async {
    final start = NoteImages.scaleOf(widget.src);
    var value = start;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      barrierColor: Colors.black12,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void pick(int v) {
          setSheet(() => value = v);
          if (mounted) setState(() => _liveScale = v);
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Text(tr('Tamaño de la imagen'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                AnimatedSwitcher(
                  duration: Anim.fast,
                  child: Text('$value %',
                      key: ValueKey(value),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Palette.accent(ctx))),
                ),
              ]),
              Slider(
                min: 20,
                max: 100,
                divisions: 16,
                value: value.toDouble(),
                label: '$value %',
                onChanged: (v) => pick(v.round()),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in const [25, 50, 75, 100])
                    ChoiceChip(
                      label: Text('$p %'),
                      selected: value == p,
                      showCheckmark: false,
                      onSelected: (_) => pick(p),
                    ),
                ],
              ),
            ],
          ),
        );
      }),
    );
    if (!mounted) return;
    if (value != start) widget.onResize?.call(value);
    setState(() => _liveScale = null);
  }

  /// Miniatura que sigue al dedo / al ratón al mover la imagen.
  Widget _dragFeedback() {
    final p = _provider;
    final natural = NoteImages.sizeOf(widget.src) ?? const Size(4, 3);
    const w = 150.0;
    return Transform.translate(
      offset: const Offset(-24, -24),
      child: Transform.rotate(
        angle: -0.04,
        child: Material(
          color: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: w,
              height: w * natural.height / natural.width,
              child: p == null
                  ? ColoredBox(color: Palette.hover(context))
                  : Image(image: p, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }

  ImageMovePayload get _payload =>
      ImageMovePayload(widget.src, widget.offsetOf ?? () => -1);

  // Pulsación larga en Android: si se suelta sin moverla, abre el menú.
  Offset? _downAt;
  Offset? _upAt;

  Future<void> _menu(Offset? at) async {
    final entries = [
      MenuEntry('ver', Icons.open_in_full_rounded, tr('Ver imagen')),
      if (widget.onCropped != null)
        MenuEntry('recortar', Icons.crop_rounded, tr('Recortar')),
      if (widget.onResize != null)
        MenuEntry('tamano', Icons.photo_size_select_large_rounded,
            tr('Cambiar tamaño')),
      if (widget.onCropped != null)
        MenuEntry('dibujar', Icons.draw_outlined, tr('Dibujar encima')),
      if (NoteMediaScope.aiAllowed(context))
        MenuEntry(
            'ocr', Icons.document_scanner_outlined, tr('Sacar el texto (OCR)')),
      if (widget.onMoveUp != null)
        MenuEntry('subir', Icons.arrow_upward_rounded, tr('Subir')),
      if (widget.onMoveDown != null)
        MenuEntry('bajar', Icons.arrow_downward_rounded, tr('Bajar')),
      MenuEntry('copiar', Icons.content_copy_rounded, tr('Copiar imagen')),
      MenuEntry(
          'guardar',
          Icons.download_rounded,
          Platform.isAndroid
              ? tr('Guardar en la galería')
              : tr('Guardar como…')),
      if (widget.onDelete != null)
        MenuEntry('quitar', Icons.delete_outline_rounded, tr('Quitar imagen'),
            danger: true),
    ];
    String? choice;
    if (at != null) {
      choice = await showContextMenu(context,
          position: at, title: tr('Imagen'), entries: entries);
    } else {
      choice = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in entries)
              ListTile(
                leading: Icon(e.icon,
                    color: e.danger ? Theme.of(ctx).colorScheme.error : null),
                title: Text(e.label,
                    style: TextStyle(
                        color:
                            e.danger ? Theme.of(ctx).colorScheme.error : null)),
                onTap: () => Navigator.pop(ctx, e.value),
              ),
          ]),
        ),
      );
    }
    if (!mounted || choice == null) return;
    await _action(choice);
  }

  Future<void> _action(String a) async {
    switch (a) {
      case 'ver':
        _open();
      case 'recortar':
        await _crop();
      case 'tamano':
        await _pickSize();
      case 'dibujar':
        final b = await _currentBytes();
        if (b == null || !mounted) return;
        final drawn = await showDrawingPad(context, background: b);
        if (drawn != null) await widget.onCropped?.call(drawn);
      case 'ocr':
        final b = await _currentBytes();
        if (b != null && mounted) {
          await readImageText(context, widget.controller, b);
        }
      case 'subir':
        widget.onMoveUp?.call();
      case 'bajar':
        widget.onMoveDown?.call();
      case 'copiar':
        final b = await _currentBytes();
        if (b != null && mounted) await copyImageBytes(context, b);
      case 'guardar':
        final b = await _currentBytes();
        if (b != null && mounted) await saveImageBytes(context, b);
      case 'quitar':
        widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final natural = NoteImages.sizeOf(widget.src) ?? const Size(1200, 900);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final selected = _wasSelected = _selected;
    final uploading = _ours && NoteImages.instance.isUploading(_path);
    final pending = _ours && NoteImages.instance.isPending(_path);
    final accent = Palette.accent(context);

    Widget content = LayoutBuilder(builder: (context, c) {
      // Tamaño en pantalla: el natural (en píxeles lógicos), sin pasar del
      // ancho de la nota ni de una altura cómoda.
      var w = min(c.maxWidth, max(160.0, natural.width / max(1.0, dpr)));
      w = max(72.0, w * (_liveScale ?? NoteImages.scaleOf(widget.src)) / 100);
      var h = w * natural.height / natural.width;
      const maxH = 560.0;
      if (h > maxH) {
        h = maxH;
        w = h * natural.width / natural.height;
      }
      final provider = _provider;
      final radius = BorderRadius.circular(14);

      final image = Stack(
        fit: StackFit.expand,
        children: [
          // Hueco con brillo mientras carga.
          if (provider == null && !_failed)
            DecoratedBox(
              decoration: BoxDecoration(color: Palette.hover(context)),
            ).animate(onPlay: (c) => c.repeat()).shimmer(
                duration: 1400.ms,
                color: Palette.card(context).withValues(alpha: 0.6)),
          if (_failed)
            _Unavailable(onRetry: () {
              setState(() => _failed = false);
              _load();
            }),
          if (provider != null)
            Hero(
              tag: _heroTag,
              child: Image(
                image: provider,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _Unavailable(onRetry: null),
                frameBuilder: (context, child, frame, sync) => sync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: Anim.slow,
                        curve: Anim.curve,
                        child: child,
                      ),
              ),
            ),
          // Subiendo / pendiente de subir.
          Positioned(
            left: 10,
            bottom: 10,
            child: AnimatedSwitcher(
              duration: Anim.medium,
              transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                      scale: Tween(begin: 0.8, end: 1.0).animate(
                          CurvedAnimation(
                              parent: a, curve: Curves.easeOutBack)),
                      child: c)),
              child: uploading
                  ? _Pill(
                      key: const ValueKey('subiendo'),
                      leading: const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.8, color: Colors.white)),
                      label: tr('Subiendo…'))
                  : pending
                      ? _Pill(
                          key: const ValueKey('pendiente'),
                          leading: const Icon(Icons.cloud_off_rounded,
                              size: 14, color: Colors.white),
                          label: tr('Pendiente de subir'))
                      : const SizedBox.shrink(key: ValueKey('nada')),
            ),
          ),
          // Acciones al pasar el ratón (escritorio).
          if (isDesktopWindows && provider != null)
            Positioned(
              top: 8,
              right: 8,
              child: IgnorePointer(
                ignoring: !_hover,
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: Anim.fast,
                  child: AnimatedSlide(
                    offset: _hover ? Offset.zero : const Offset(0, -0.2),
                    duration: Anim.medium,
                    curve: Anim.curve,
                    child: _Frosted(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        // Asa para mover la imagen entre el texto.
                        if (widget.onMoveUp != null)
                          Draggable<ImageMovePayload>(
                            data: _payload,
                            dragAnchorStrategy: pointerDragAnchorStrategy,
                            feedback: _dragFeedback(),
                            onDragStarted: HapticFeedback.selectionClick,
                            child: Tooltip(
                              message: tr('Arrastra para moverla'),
                              child: const MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_indicator_rounded,
                                      size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        _HoverBtn(Icons.open_in_full_rounded, tr('Ver imagen'),
                            () => _action('ver')),
                        if (widget.onCropped != null)
                          _HoverBtn(Icons.crop_rounded, tr('Recortar'),
                              () => _action('recortar')),
                        if (widget.onResize != null)
                          _HoverBtn(Icons.photo_size_select_large_rounded,
                              tr('Cambiar tamaño'), () => _action('tamano')),
                        _HoverBtn(Icons.content_copy_rounded,
                            tr('Copiar imagen'), () => _action('copiar')),
                        _HoverBtn(Icons.download_rounded, tr('Guardar como…'),
                            () => _action('guardar')),
                        if (widget.onDelete != null)
                          _HoverBtn(Icons.delete_outline_rounded,
                              tr('Quitar imagen'), () => _action('quitar')),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

      return Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: Anim.medium,
          curve: Anim.curve,
          width: w,
          height: h,
          margin: const EdgeInsets.symmetric(vertical: 6),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? accent : Palette.separator(context),
              width: selected ? 2.5 : 1,
            ),
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.16 : 0.08),
                blurRadius: _hover ? 18 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(borderRadius: radius, child: image),
        ),
      );
    });

    content = MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _open,
        onSecondaryTapUp: (d) => _menu(d.globalPosition),
        child: content,
      ),
    );

    // Android: mantener pulsada y arrastrar mueve la imagen entre el texto;
    // mantener pulsada y soltar sin moverla abre el menú.
    if (!isDesktopWindows) {
      content = Listener(
        onPointerDown: (e) => _downAt = e.position,
        onPointerUp: (e) => _upAt = e.position,
        child: LongPressDraggable<ImageMovePayload>(
          data: _payload,
          maxSimultaneousDrags: widget.onMoveUp == null ? 0 : 1,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _dragFeedback(),
          childWhenDragging: Opacity(opacity: 0.35, child: content),
          onDragStarted: HapticFeedback.mediumImpact,
          onDraggableCanceled: (_, __) {
            final a = _downAt, b = _upAt;
            if (a != null && b != null && (a - b).distance < 14) _menu(null);
          },
          child: content,
        ),
      );
      if (widget.onMoveUp == null) {
        content =
            GestureDetector(onLongPress: () => _menu(null), child: content);
      }
    }

    if (_animateIn) {
      content = content.animate().fadeIn(duration: Anim.medium).scale(
          begin: const Offset(0.94, 0.94),
          alignment: Alignment.centerLeft,
          curve: Curves.easeOutBack,
          duration: Anim.slow);
    }
    return content;
  }
}

/// Miniatura cuadrada de una imagen (filas de la lista de notas).
class NoteThumb extends StatefulWidget {
  const NoteThumb({super.key, required this.path, this.size = 42});
  final String path;
  final double size;

  @override
  State<NoteThumb> createState() => _NoteThumbState();
}

class _NoteThumbState extends State<NoteThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NoteThumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  void _load() {
    _bytes = NoteImages.instance.cached(widget.path);
    if (_bytes != null) return;
    NoteImages.instance.load(widget.path).then((b) {
      if (mounted && b != null) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedSwitcher(
              duration: Anim.medium,
              child: _bytes == null
                  ? ColoredBox(
                      key: const ValueKey('vacia'),
                      color: Palette.hover(context),
                      child: Icon(Icons.image_outlined,
                          size: 18, color: Palette.secondary(context)),
                    )
                  : Image.memory(
                      _bytes!,
                      key: ValueKey(widget.path),
                      fit: BoxFit.cover,
                      cacheWidth: (widget.size *
                              MediaQuery.devicePixelRatioOf(context) *
                              2)
                          .round(),
                      gaplessPlayback: true,
                    ),
            ),
          ),
        ),
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Palette.hover(context),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined,
                  color: Palette.secondary(context), size: 28),
              const SizedBox(height: 6),
              Text(tr('Imagen no disponible'),
                  style: TextStyle(
                      color: Palette.secondary(context), fontSize: 13)),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: Text(tr('Reintentar'))),
            ],
          ),
        ),
      );
}

/// Fondo esmerilado oscuro para controles encima de una imagen.
class _Frosted extends StatelessWidget {
  const _Frosted({required this.child, this.radius = 12});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: child,
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.leading, required this.label});
  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) => _Frosted(
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            leading,
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _HoverBtn extends StatelessWidget {
  const _HoverBtn(this.icon, this.tooltip, this.onTap);
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Bouncy(
        pressedScale: 0.85,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          color: Colors.white,
          icon: Icon(icon),
        ),
      );
}

// ----------------------------------------------------------- visor

/// Abre una imagen a pantalla completa: sale de su sitio en la nota (Hero),
/// se amplía con los dedos, la rueda o doble toque, y se cierra
/// arrastrándola hacia abajo, con Esc o con la ✕.
Future<void> openImageViewer(
  BuildContext context, {
  required ImageProvider image,
  required Object heroTag,
  required Future<Uint8List?> Function() bytes,
  VoidCallback? onDelete,
  Future<void> Function(Uint8List cropped)? onCropped,
}) =>
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Anim.slow,
      reverseTransitionDuration: Anim.medium,
      pageBuilder: (context, animation, _) => _ImageViewer(
        image: image,
        heroTag: heroTag,
        bytes: bytes,
        onDelete: onDelete,
        onCropped: onCropped,
        animation: animation,
      ),
    ));

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({
    required this.image,
    required this.heroTag,
    required this.bytes,
    required this.animation,
    this.onDelete,
    this.onCropped,
  });

  final ImageProvider image;
  final Object heroTag;
  final Future<Uint8List?> Function() bytes;
  final Animation<double> animation;
  final VoidCallback? onDelete;
  final Future<void> Function(Uint8List cropped)? onCropped;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _zoomAnim =
      AnimationController(vsync: this, duration: Anim.medium)
        ..addListener(() {
          final m = _zoomTween
              ?.evaluate(CurvedAnimation(parent: _zoomAnim, curve: Anim.curve));
          if (m != null) _transform.value = m;
        });
  Matrix4Tween? _zoomTween;
  Offset _doubleTapAt = Offset.zero;
  double _drag = 0; // arrastre vertical para cerrar
  bool _dragging = false;
  bool _zoomed = false;

  @override
  void dispose() {
    _zoomAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target);
    _zoomAnim.forward(from: 0);
    setState(() => _zoomed = target.getMaxScaleOnAxis() > 1.01);
  }

  void _onDoubleTap() {
    if (_zoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    const s = 2.6;
    final p = _doubleTapAt;
    _animateTo(Matrix4.identity()
      ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
      ..scaleByDouble(s, s, 1, 1));
  }

  Future<void> _act(String a) async {
    switch (a) {
      case 'recortar':
        final b = await widget.bytes();
        if (b == null || !mounted) return;
        final cropped = await openImageCropper(context, b);
        if (cropped == null || !mounted) return;
        final save = widget.onCropped;
        _close();
        await save?.call(cropped);
      case 'copiar':
        final b = await widget.bytes();
        if (b != null && mounted) await copyImageBytes(context, b);
      case 'guardar':
        final b = await widget.bytes();
        if (b != null && mounted) await saveImageBytes(context, b);
      case 'quitar':
        // Primero se cierra el visor (la imagen vuelve a su sitio) y luego
        // se quita de la nota.
        final remove = widget.onDelete;
        _close();
        Future.delayed(Anim.medium, () => remove?.call());
    }
  }

  @override
  Widget build(BuildContext context) {
    final dragFade = (1 - (_drag.abs() / 320)).clamp(0.0, 1.0);
    final top = MediaQuery.paddingOf(context).top;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        // Ctrl+C copia la imagen y Ctrl+S la guarda.
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            _act('copiar'),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _act('guardar'),
      },
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, child) => ColoredBox(
            color: Colors.black.withValues(
                alpha: 0.94 *
                    Curves.easeOut.transform(widget.animation.value) *
                    dragFade),
            child: child,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                  onDoubleTap: _onDoubleTap,
                  onVerticalDragStart:
                      _zoomed ? null : (_) => setState(() => _dragging = true),
                  onVerticalDragUpdate: _zoomed
                      ? null
                      : (d) => setState(() => _drag += d.delta.dy),
                  onVerticalDragEnd: _zoomed
                      ? null
                      : (d) {
                          if (_drag.abs() > 120 ||
                              d.velocity.pixelsPerSecond.dy.abs() > 900) {
                            _close();
                          } else {
                            setState(() {
                              _dragging = false;
                              _drag = 0;
                            });
                          }
                        },
                  child: AnimatedContainer(
                    duration: _dragging ? Duration.zero : Anim.medium,
                    curve: Anim.curve,
                    transform: Matrix4.translationValues(0, _drag, 0)
                      ..scaleByDouble(1 - (_drag.abs() / 2400),
                          1 - (_drag.abs() / 2400), 1, 1),
                    transformAlignment: Alignment.center,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 6,
                      panEnabled: _zoomed,
                      clipBehavior: Clip.none,
                      onInteractionEnd: (_) {
                        final z = _transform.value.getMaxScaleOnAxis() > 1.01;
                        if (z != _zoomed) setState(() => _zoomed = z);
                      },
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Hero(
                            tag: widget.heroTag,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image(
                                image: widget.image,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Barra superior: cerrar y acciones.
              Positioned(
                left: 12,
                right: 12,
                top: top + 10,
                // Los botones se ven siempre (también al ampliar o
                // arrastrar la imagen).
                child: FadeTransition(
                  opacity: widget.animation,
                  child: Row(
                    children: [
                      _Frosted(
                        radius: 22,
                        child: _HoverBtn(
                            Icons.close_rounded, tr('Cerrar'), _close),
                      ),
                      const Spacer(),
                      _Frosted(
                        radius: 22,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (widget.onCropped != null)
                            _HoverBtn(Icons.crop_rounded, tr('Recortar'),
                                () => _act('recortar')),
                          _HoverBtn(
                              Icons.content_copy_rounded,
                              isDesktopWindows
                                  ? '${tr('Copiar imagen')}  (Ctrl+C)'
                                  : tr('Copiar imagen'),
                              () => _act('copiar')),
                          _HoverBtn(
                              Icons.download_rounded,
                              Platform.isAndroid
                                  ? tr('Guardar en la galería')
                                  : '${tr('Guardar como…')}  (Ctrl+S)',
                              () => _act('guardar')),
                          if (widget.onDelete != null)
                            _HoverBtn(Icons.delete_outline_rounded,
                                tr('Quitar imagen'), () => _act('quitar')),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------- soltar archivos (PC)

/// Zona del editor donde se pueden soltar imágenes arrastradas desde el
/// Explorador: muestra un marco discontinuo animado mientras se arrastra.
class ImageDropZone extends StatefulWidget {
  const ImageDropZone({super.key, required this.child, required this.onImages});
  final Widget child;
  final void Function(List<Uint8List> images) onImages;

  @override
  State<ImageDropZone> createState() => _ImageDropZoneState();
}

class _ImageDropZoneState extends State<ImageDropZone> {
  bool _over = false;

  Future<void> _done(DropDoneDetails d) async {
    setState(() => _over = false);
    final files = d.files.where((f) => _isImagePath(f.name)).toList();
    if (files.isEmpty) {
      if (d.files.isNotEmpty && mounted) {
        showToast(context, tr('Solo se pueden añadir imágenes'),
            icon: Icons.broken_image_outlined);
      }
      return;
    }
    final bytes = [for (final f in files) await f.readAsBytes()];
    widget.onImages(bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopWindows) return widget.child;
    final accent = Palette.accent(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: _done,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _over ? 1 : 0,
                duration: Anim.fast,
                child: AnimatedScale(
                  scale: _over ? 1 : 0.97,
                  duration: Anim.medium,
                  curve: Anim.curve,
                  child: Container(
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: CustomPaint(
                      painter: _DashedBorder(accent),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                    size: 44, color: accent)
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .moveY(
                                    begin: 0,
                                    end: -6,
                                    duration: 900.ms,
                                    curve: Curves.easeInOut),
                            const SizedBox(height: 10),
                            Text(tr('Suelta para añadir las imágenes'),
                                style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(18)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 10), paint);
        d += 17;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
