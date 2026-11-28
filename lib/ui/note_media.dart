import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/ai_assistant.dart';
import '../data/note_attachments.dart';
import '../data/note_files.dart';
import '../data/note_images.dart';
import 'ai_tools_ui.dart';
import 'anim.dart';
import 'context_menu.dart';
import 'i18n.dart';
import 'image_tools.dart';
import 'pdf_viewer.dart';
import 'theme.dart';
import 'toast.dart';

/// Datos de la nota para sus adjuntos. En las notas del Vault no se ofrece
/// nada que envíe el contenido a un proveedor de IA.
class NoteMediaScope extends InheritedWidget {
  const NoteMediaScope(
      {super.key, required this.allowAi, required super.child});
  final bool allowAi;

  static bool aiAllowed(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoteMediaScope>()?.allowAi ??
      false;

  @override
  bool updateShouldNotify(NoteMediaScope old) => old.allowAi != allowAi;
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _clock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

// ----------------------------------------------------------------- insertar

/// Un adjunto va al final de la nota, en su propia línea (luego se puede
/// mover manteniéndolo pulsado, como las fotos).
void insertFileBlock(QuillController c, NoteFile f) {
  final at = insertEmbedBlock(c, c.document.length - 1, fileBlockEmbed(f));
  c.moveCursorToPosition(min(at + 2, c.document.length - 1));
}

BlockEmbed fileBlockEmbed(NoteFile f) =>
    BlockEmbed.custom(CustomBlockEmbed(NoteFiles.embedType, f.toJsonString()));

void _insertTextAtCursor(QuillController c, String text) {
  final sel = c.selection;
  final index = sel.isValid
      ? max(sel.baseOffset, sel.extentOffset)
      : c.document.length - 1;
  c.replaceText(index, 0, '$text\n',
      TextSelection.collapsed(offset: index + text.length + 1));
}

Future<void> pickAndAttachFiles(BuildContext context, QuillController c) =>
    pickNoteFiles(context, (f) => insertFileBlock(c, f));

/// Elige archivos, los sube y llama a [onFile] con cada uno.
Future<void> pickNoteFiles(
    BuildContext context, void Function(NoteFile) onFile) async {
  try {
    final files = await openFiles();
    for (final x in files) {
      final size = await x.length();
      if (size > NoteFiles.maxBytes) {
        if (context.mounted) {
          showToast(context, tr('El archivo pasa de 25 MB'),
              icon: Icons.error_outline_rounded);
        }
        continue;
      }
      final f = await NoteFiles.instance.add(await x.readAsBytes(), x.name);
      if (f != null) onFile(f);
    }
  } catch (_) {
    if (context.mounted) {
      showToast(context, tr('No se pudo adjuntar el archivo'),
          icon: Icons.error_outline_rounded);
    }
  }
}

/// Abre un adjunto: los PDF en el lector de la app y el resto con su programa.
Future<void> openNoteFile(BuildContext context, NoteFile file) async {
  if (!file.isPdf) return openFileExternally(context, file);
  final local = await NoteFiles.instance.local(file.path);
  if (!context.mounted) return;
  if (local == null) {
    showToast(context, tr('No se pudo abrir el archivo'),
        icon: Icons.error_outline_rounded);
    return;
  }
  await openPdfViewer(context, local.path, file.name,
      onExternal: () => openFileExternally(context, file));
}

/// Abre un archivo con su programa (en Android, con el menú de compartir).
Future<void> openFileExternally(BuildContext context, NoteFile file) async {
  void missing() {
    if (context.mounted) {
      showToast(context, tr('No se pudo abrir el archivo'),
          icon: Icons.error_outline_rounded);
    }
  }

  final local = await NoteFiles.instance.local(file.path);
  if (local == null) return missing();
  try {
    if (Platform.isAndroid) {
      await SharePlus.instance.share(ShareParams(
          files: [XFile(local.path, mimeType: file.mime, name: file.name)],
          fileNameOverrides: [file.name]));
    } else {
      // Copia temporal con su nombre real, para abrirla con su programa.
      final dir = await getTemporaryDirectory();
      final safe = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final copy =
          await local.copy('${dir.path}${Platform.pathSeparator}$safe');
      if (!await launchUrl(Uri.file(copy.path))) missing();
    }
  } catch (_) {
    missing();
  }
}

// ------------------------------------------------------- leer con la IA

/// Enseña lo que ha leído la IA, para copiarlo o añadirlo a la nota.
Future<void> _showReadResult(
    BuildContext context, QuillController? c, String title, String text,
    {void Function(String text)? onInsert}) {
  final edit = TextEditingController(text: text);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Flexible(
            child: TextField(
              controller: edit,
              maxLines: null,
              decoration: InputDecoration(
                  filled: true,
                  fillColor: Palette.background(ctx),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: edit.text));
                  Navigator.pop(ctx);
                  showToast(context, tr('Copiado'),
                      icon: Icons.content_copy_rounded);
                },
                child: Text(tr('Copiar')),
              ),
              if (c != null || onInsert != null) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (onInsert != null) {
                      onInsert(edit.text.trim());
                    } else {
                      _insertTextAtCursor(c!, edit.text.trim());
                    }
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('Añadir a la nota')),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

Future<void> _readWithAi(BuildContext context, QuillController? c,
    Uint8List bytes, String mime, String prompt, String title,
    {void Function(String text)? onInsert,
    void Function(String text)? onResult}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  var open = true;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AiWorkingDialog(label: tr('Leyendo con la IA…')),
  ).whenComplete(() => open = false));
  try {
    final text = await aiReadMedia(bytes, mime, prompt);
    if (open) nav.pop();
    if (!context.mounted) return;
    if (text.trim().isEmpty) {
      showToast(context, tr('No se ha encontrado texto'),
          icon: Icons.info_outline_rounded);
      return;
    }
    onResult?.call(text.trim());
    await _showReadResult(context, c, title, text.trim(), onInsert: onInsert);
  } on AiException catch (e) {
    if (open) nav.pop();
    if (context.mounted) {
      showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  } catch (_) {
    if (open) nav.pop();
    if (context.mounted) {
      showToast(context, tr('No se ha podido leer'),
          icon: Icons.error_outline_rounded);
    }
  }
}

/// OCR: saca el texto de una imagen con la IA del usuario.
Future<void> readImageText(
        BuildContext context, QuillController? c, Uint8List bytes) =>
    _readWithAi(
        context,
        c,
        bytes,
        switch (NoteImages.extensionOf(bytes)) {
          'png' => 'image/png',
          'gif' => 'image/gif',
          'webp' => 'image/webp',
          _ => 'image/jpeg',
        },
        aiOcrPrompt,
        tr('Texto de la imagen'));

/// Lee lo nuevo de una pizarra. [onRead] guarda lo leído y [onInsert] lo
/// añade a la nota.
Future<void> readBoardText(BuildContext context, Uint8List png,
        {required String previous,
        required void Function(String text) onRead,
        required void Function(String text) onInsert}) =>
    _readWithAi(context, null, png, 'image/png', boardTextPrompt(previous),
        tr('Texto de la pizarra'),
        onInsert: onInsert, onResult: onRead);

/// Enseña lo ya leído de una pizarra, sin volver a llamar a la IA.
Future<void> showBoardText(BuildContext context, String text,
        {required void Function(String text) onInsert}) =>
    _showReadResult(context, null, tr('Texto de la pizarra'), text,
        onInsert: onInsert);

// ------------------------------------------------------------- nota de voz

/// Graba una nota de voz y la añade a la nota.
Future<void> showVoiceRecorder(BuildContext context, QuillController c) async {
  final f = await recordVoiceFile(context);
  if (f != null) insertFileBlock(c, f);
}

/// Graba una nota de voz y la sube. null si se cancela o falla.
Future<NoteFile?> recordVoiceFile(BuildContext context) async {
  final bytes = await showModalBottomSheet<Uint8List>(
    context: context,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => const _Recorder(),
  );
  if (bytes == null) return null;
  final stamp = DateTime.now();
  final name = '${tr('Nota de voz')} '
      '${stamp.day}-${stamp.month} ${stamp.hour}.'
      '${stamp.minute.toString().padLeft(2, '0')}.m4a';
  final f = await NoteFiles.instance.add(bytes, name, mime: 'audio/mp4');
  if (f == null && context.mounted) {
    showToast(context, tr('No se pudo guardar la grabación'),
        icon: Icons.error_outline_rounded);
  }
  return f;
}

class _Recorder extends StatefulWidget {
  const _Recorder();

  @override
  State<_Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<_Recorder> {
  static const _limit = Duration(minutes: 15);
  final _rec = AudioRecorder();
  Timer? _timer;
  Duration _time = Duration.zero;
  String? _path;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error = tr('Oganesson no tiene permiso de micrófono.'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}${Platform.pathSeparator}'
          'voz-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
          const RecordConfig(
              encoder: AudioEncoder.aacLc, bitRate: 64000, numChannels: 1),
          path: path);
      if (!mounted) return;
      _path = path;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _time += const Duration(seconds: 1));
        if (_time >= _limit) _finish();
      });
      setState(() {});
    } catch (_) {
      if (mounted)
        setState(() => _error = tr('No se pudo iniciar la grabación.'));
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    _busy = true;
    _timer?.cancel();
    try {
      final path = await _rec.stop() ?? _path;
      if (path == null) throw StateError('sin archivo');
      final f = File(path);
      final bytes = await f.readAsBytes();
      await f.delete().catchError((_) => f);
      if (mounted) Navigator.pop(context, bytes);
    } catch (_) {
      _busy = false;
      if (mounted)
        setState(() => _error = tr('No se pudo guardar la grabación'));
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    try {
      await _rec.cancel();
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Nota de voz'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            if (_error != null)
              Text(_error!, textAlign: TextAlign.center)
            else ...[
              Icon(Icons.mic_rounded, size: 40, color: p.accent),
              const SizedBox(height: 8),
              Text(_clock(_time),
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: _cancel, child: Text(tr('Cancelar'))),
                if (_error == null) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _path == null ? null : _finish,
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(tr('Terminar')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------- tarjeta del embed

class NoteFileEmbedBuilder extends EmbedBuilder {
  const NoteFileEmbedBuilder();

  @override
  String get key => NoteFiles.embedType;

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext e) {
    final file = NoteFile.parse(e.node.value.data);
    if (file == null) return const SizedBox.shrink();
    final controller = e.controller;
    final card = NoteFileCard(
      file: file,
      controller: controller,
      allowAi: NoteMediaScope.aiAllowed(context),
      onDelete: e.readOnly
          ? null
          : () {
              final o = fileEmbedOffset(controller.document, file.path);
              if (o != null) removeEmbedLine(controller, o);
            },
    );
    if (e.readOnly) return card;
    // Mantener pulsado y arrastrar: se mueve entre el texto, como las fotos.
    return LongPressDraggable<ImageMovePayload>(
      data: ImageMovePayload(file.path,
          () => fileEmbedOffset(controller.document, file.path) ?? -1,
          embed: fileBlockEmbed(file)),
      delay: const Duration(milliseconds: 300),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        mediaDragActive.value = true;
        HapticFeedback.mediumImpact();
      },
      onDragEnd: (_) => mediaDragActive.value = false,
      onDraggableCanceled: (_, __) => mediaDragActive.value = false,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(width: 280, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

/// Posición de un adjunto en el documento. Quill pasa a los embeds propios
/// una copia suelta del nodo, cuyo `documentOffset` siempre es 0.
int? fileEmbedOffset(Document doc, String path) {
  var at = 0;
  for (final op in doc.toDelta().toList()) {
    final v = op.data;
    if (v is Map &&
        mediaIn(jsonEncode([
              {'insert': v}
            ])).firstOrNull?.path ==
            path) {
      return at;
    }
    at += op.length ?? 0;
  }
  return null;
}

class NoteFileCard extends StatefulWidget {
  const NoteFileCard({
    super.key,
    required this.file,
    this.controller,
    this.allowAi = false,
    this.onDelete,
    this.autoplay = false,
  });
  final NoteFile file;
  final QuillController? controller;
  final bool allowAi;
  final VoidCallback? onDelete;

  /// Empieza a sonar al aparecer (al abrirla desde la red de notas).
  final bool autoplay;

  @override
  State<NoteFileCard> createState() => _NoteFileCardState();
}

class _NoteFileCardState extends State<NoteFileCard> {
  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];
  bool _playing = false;
  bool _ended = false;
  bool _loading = false;
  Duration _pos = Duration.zero;
  Duration _total = Duration.zero;

  NoteFile get _f => widget.file;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay && _f.isAudio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _togglePlay();
      });
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  void _missing() {
    if (mounted) {
      showToast(context, tr('No se pudo abrir el archivo'),
          icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _togglePlay() async {
    if (_loading) return;
    var player = _player;
    if (player == null) {
      setState(() => _loading = true);
      final local = await NoteFiles.instance.local(_f.path);
      if (!mounted) return;
      if (local == null) {
        setState(() => _loading = false);
        return _missing();
      }
      try {
        player = _player = AudioPlayer();
        // Por defecto libera el audio al acabar y ya no se puede repetir.
        await player.setReleaseMode(ReleaseMode.stop);
        _subs
          ..add(player.onPositionChanged.listen((d) {
            if (mounted) setState(() => _pos = d);
          }))
          ..add(player.onDurationChanged.listen((d) {
            if (mounted) setState(() => _total = d);
          }))
          ..add(player.onPlayerComplete.listen((_) {
            if (mounted) {
              setState(() {
                _playing = false;
                _ended = true;
                _pos = Duration.zero;
              });
            }
          }));
        await player.setSource(DeviceFileSource(local.path, mimeType: _f.mime));
      } catch (_) {
        _player = null;
        if (mounted) setState(() => _loading = false);
        return _missing();
      }
      if (!mounted) return;
      setState(() => _loading = false);
    }
    try {
      if (_playing) {
        await player.pause();
      } else {
        if (_ended) {
          _ended = false;
          await player.seek(Duration.zero);
        }
        await player.resume();
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      _missing();
    }
  }

  Future<void> _seekTo(Duration d) async {
    final p = _player;
    if (p == null) return;
    final to = d < Duration.zero ? Duration.zero : (d > _total ? _total : d);
    setState(() {
      _pos = to;
      _ended = false;
    });
    try {
      await p.seek(to);
    } catch (_) {}
  }

  Future<void> _openFile() => openNoteFile(context, _f);

  Future<void> _saveAs() async {
    final local = await NoteFiles.instance.local(_f.path);
    if (local == null) return _missing();
    try {
      final to = await getSaveLocation(suggestedName: _f.name);
      if (to == null) return;
      await local.copy(to.path);
      if (mounted) {
        showToast(context, tr('Guardado'), icon: Icons.download_done_rounded);
      }
    } catch (_) {
      _missing();
    }
  }

  Future<void> _transcribe() async {
    final local = await NoteFiles.instance.local(_f.path);
    if (local == null) return _missing();
    final bytes = await local.readAsBytes();
    if (!mounted) return;
    await _readWithAi(context, widget.controller, bytes, _f.mime,
        aiTranscribePrompt, tr('Transcripción'));
  }

  Future<void> _menu(Offset at) async {
    final choice =
        await showContextMenu(context, position: at, title: _f.name, entries: [
      MenuEntry('abrir', Icons.open_in_new_rounded,
          Platform.isAndroid ? tr('Abrir o compartir') : tr('Abrir')),
      if (!Platform.isAndroid)
        MenuEntry('guardar', Icons.download_rounded, tr('Guardar como…')),
      if (_f.isAudio && widget.allowAi)
        MenuEntry('transcribir', Icons.subtitles_outlined, tr('Transcribir')),
      if (widget.onDelete != null)
        MenuEntry('quitar', Icons.delete_outline_rounded, tr('Quitar'),
            danger: true),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'abrir':
        await _openFile();
      case 'guardar':
        await _saveAs();
      case 'transcribir':
        await _transcribe();
      case 'quitar':
        widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final audio = _f.isAudio;
    final progress = _total.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: p.background,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: audio ? _togglePlay : _openFile,
          onSecondaryTapUp: (d) => _menu(d.globalPosition),
          onLongPress: () {
            final box = context.findRenderObject() as RenderBox;
            _menu(box.localToGlobal(box.size.center(Offset.zero)));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: Anim.fast,
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: _playing ? 0.24 : 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: _loading
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: p.accent))
                      : Icon(
                          audio
                              ? (_playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded)
                              : (_f.isPdf
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.insert_drive_file_outlined),
                          size: 21,
                          color: p.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      if (audio && _player != null)
                        // Barra que se arrastra para ir a cualquier punto.
                        SizedBox(
                          height: 18,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              activeTrackColor: p.accent,
                              inactiveTrackColor: p.separator,
                              thumbColor: p.accent,
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12),
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              padding: EdgeInsets.zero,
                            ),
                            child: Slider(
                              value: progress,
                              onChanged: _total == Duration.zero
                                  ? null
                                  : (v) => _seekTo(_total * v),
                            ),
                          ),
                        )
                      else
                        Text(formatBytes(_f.size),
                            style:
                                TextStyle(fontSize: 12.5, color: p.secondary)),
                    ],
                  ),
                ),
                if (audio && _player != null) ...[
                  IconButton(
                    tooltip: tr('Atrás 10 s'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.replay_10_rounded, size: 19),
                    onPressed: () =>
                        _seekTo(_pos - const Duration(seconds: 10)),
                  ),
                  IconButton(
                    tooltip: tr('Adelante 10 s'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.forward_10_rounded, size: 19),
                    onPressed: () =>
                        _seekTo(_pos + const Duration(seconds: 10)),
                  ),
                ],
                if (audio && _player != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                        _clock(
                            _playing || _pos > Duration.zero ? _pos : _total),
                        style: TextStyle(fontSize: 12, color: p.secondary)),
                  ),
                Builder(
                  builder: (b) => IconButton(
                    tooltip: tr('Opciones'),
                    icon: const Icon(Icons.more_vert_rounded, size: 19),
                    onPressed: () {
                      final box = b.findRenderObject() as RenderBox;
                      _menu(box.localToGlobal(box.size.center(Offset.zero)));
                    },
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
