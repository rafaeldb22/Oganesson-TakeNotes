import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note.dart';

/// Imágenes de las notas.
///
/// Cada imagen es un embed de Quill cuya fuente es `sb://<usuario>/<id>?w=&h=`
/// (ancho y alto originales, para reservar el hueco antes de cargarla). Los
/// bytes viven en Supabase Storage (bucket privado [bucket], una carpeta por
/// usuario, migración 007) y en una caché local en disco.
///
/// Al añadir una imagen se ve al instante (bytes en memoria), se comprime en
/// segundo plano y se sube. Si no hay conexión (o aún falta la migración)
/// queda en una cola persistente y se reintenta más tarde.
class NoteImages extends ChangeNotifier {
  NoteImages._();
  static final instance = NoteImages._();

  static const bucket = 'note-images';
  static const scheme = 'sb://';

  /// Lado mayor máximo tras comprimir.
  static const maxSide = 2048;

  SupabaseClient? _client;
  String _userId = 'local';
  Directory? _dir;

  /// Imágenes recientes en memoria (las que se acaban de pegar o ver).
  final _mem = <String, Uint8List>{};
  static const _memMax = 24;

  /// Subidas en curso y pendientes (sin conexión o con error).
  final Set<String> _uploading = {};
  final Set<String> _pending = {};
  final Map<String, Future<Uint8List?>> _loading = {};
  String get _pendingKey => 'imagenes_pendientes_$_userId';

  /// Se llama al entrar en la cuenta (sin [client] en el modo demo).
  Future<void> attach(SupabaseClient? client, String userId) async {
    _client = client;
    _userId = userId;
    _pending.clear();
    try {
      final p = await SharedPreferences.getInstance();
      _pending.addAll(p.getStringList(_pendingKey) ?? const []);
    } catch (_) {}
    unawaited(retryPending());
  }

  // ------------------------------------------------------------ fuentes

  static bool isOurs(String src) => src.startsWith(scheme);

  /// `usuario/id` de una fuente `sb://…`.
  static String pathOf(String src) {
    final s = src.substring(scheme.length);
    final q = s.indexOf('?');
    return q == -1 ? s : s.substring(0, q);
  }

  /// Tamaño original guardado en la fuente (para reservar el hueco).
  static ui.Size? sizeOf(String src) {
    final q = src.indexOf('?');
    if (q == -1) return null;
    final params = Uri.splitQueryString(src.substring(q + 1));
    final w = double.tryParse(params['w'] ?? '');
    final h = double.tryParse(params['h'] ?? '');
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return ui.Size(w, h);
  }

  /// Rutas de todas las imágenes de una nota (su Delta en JSON).
  static Set<String> pathsIn(String? rich) {
    if (rich == null || !rich.contains(scheme)) return const {};
    return {
      for (final m in RegExp(r'sb://([^"?\\]+)').allMatches(rich)) m.group(1)!,
    };
  }

  // -------------------------------------------------------------- estado

  bool isUploading(String path) => _uploading.contains(path);
  bool isPending(String path) =>
      _pending.contains(path) && !_uploading.contains(path);

  // ------------------------------------------------------------- añadir

  /// Añade una imagen (bytes de un archivo, del portapapeles o de la
  /// cámara) y devuelve la fuente para el embed. null si no es una imagen.
  Future<String?> add(Uint8List raw) async {
    final size = await _decodeSize(raw);
    if (size == null) return null;
    final path = '$_userId/${newNoteId()}';
    _remember(path, raw);
    _pending.add(path);
    _uploading.add(path);
    notifyListeners();
    unawaited(_process(path, raw));
    return '$scheme$path?w=${size.width.round()}&h=${size.height.round()}';
  }

  /// Comprime (en un isolate), guarda en disco y sube.
  Future<void> _process(String path, Uint8List raw) async {
    Uint8List bytes = raw;
    try {
      bytes = await compute(compressImage, raw);
    } catch (e) {
      debugPrint('Imagen: no se pudo comprimir ($e), se sube tal cual');
    }
    _remember(path, bytes);
    await _writeLocal(path, bytes);
    await _savePending();
    await _upload(path, bytes);
  }

  Future<void> _upload(String path, Uint8List bytes) async {
    final client = _client;
    if (client == null) {
      // Modo demo: solo local.
      _pending.remove(path);
      _uploading.remove(path);
      notifyListeners();
      return;
    }
    _uploading.add(path);
    notifyListeners();
    try {
      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
                contentType: _mime(bytes),
                upsert: true,
                cacheControl: '31536000'),
          );
      _pending.remove(path);
      await _savePending();
    } catch (e) {
      debugPrint('Imagen: subida pendiente ($e)');
    } finally {
      _uploading.remove(path);
      notifyListeners();
    }
  }

  /// Reintenta las subidas que quedaron pendientes.
  Future<void> retryPending() async {
    for (final path in _pending.toList()) {
      if (_uploading.contains(path)) continue;
      final bytes = _mem[path] ?? await _readLocal(path);
      if (bytes == null) {
        _pending.remove(path); // ya no está en este dispositivo
        continue;
      }
      await _upload(path, bytes);
    }
    await _savePending();
  }

  Future<void> _savePending() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_pendingKey, _pending.toList());
    } catch (_) {}
  }

  // -------------------------------------------------------------- cargar

  /// Bytes de una imagen: memoria → disco → nube (y se guarda en disco).
  Future<Uint8List?> load(String path) {
    final m = _mem[path];
    if (m != null) return SynchronousFuture(m);
    return _loading[path] ??= _loadSlow(path).whenComplete(() {
      _loading.remove(path);
    });
  }

  /// Bytes ya en memoria (para pintar sin esperar un frame).
  Uint8List? cached(String path) => _mem[path];

  Future<Uint8List?> _loadSlow(String path) async {
    final local = await _readLocal(path);
    if (local != null) {
      _remember(path, local);
      return local;
    }
    final client = _client;
    if (client == null) return null;
    try {
      final bytes = await client.storage.from(bucket).download(path);
      _remember(path, bytes);
      await _writeLocal(path, bytes);
      return bytes;
    } catch (e) {
      debugPrint('Imagen: no se pudo descargar $path ($e)');
      return null;
    }
  }

  // -------------------------------------------------------------- borrar

  /// Borra imágenes que ya no usa ninguna nota (de la nube y del disco).
  Future<void> remove(Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return;
    for (final p in list) {
      _mem.remove(p);
      _pending.remove(p);
      try {
        final f = await _file(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _savePending();
    try {
      await _client?.storage.from(bucket).remove(list);
    } catch (e) {
      debugPrint('Imagen: no se pudo borrar de la nube ($e)');
    }
  }

  // ----------------------------------------------------------- utilidades

  void _remember(String path, Uint8List bytes) {
    _mem.remove(path);
    _mem[path] = bytes;
    while (_mem.length > _memMax) {
      _mem.remove(_mem.keys.first);
    }
  }

  Future<File> _file(String path) async {
    _dir ??= Directory(
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}imagenes');
    return File('${_dir!.path}${Platform.pathSeparator}'
        '${path.replaceAll('/', '_')}');
  }

  Future<void> _writeLocal(String path, Uint8List bytes) async {
    try {
      final f = await _file(path);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('Imagen: no se pudo guardar en disco ($e)');
    }
  }

  Future<Uint8List?> _readLocal(String path) async {
    try {
      final f = await _file(path);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }

  /// Ancho y alto sin decodificar la imagen entera (motor nativo).
  static Future<ui.Size?> _decodeSize(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final size = ui.Size(desc.width.toDouble(), desc.height.toDouble());
      desc.dispose();
      buffer.dispose();
      return size.isEmpty ? null : size;
    } catch (_) {
      return null;
    }
  }

  /// Extensión según los primeros bytes (para guardar o copiar).
  static String extensionOf(Uint8List b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
    if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
    return 'jpg';
  }

  static String _mime(Uint8List b) => switch (extensionOf(b)) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}

/// Comprime una imagen para subirla (se ejecuta en un isolate con
/// `compute`). Las capturas pequeñas se quedan en PNG para que el texto se
/// vea nítido; las fotos se reducen a [NoteImages.maxSide] y pasan a JPEG.
/// Los GIF se dejan tal cual (pueden ser animados).
Uint8List compressImage(Uint8List raw) {
  final ext = NoteImages.extensionOf(raw);
  if (ext == 'gif') return raw;
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  var image = img.bakeOrientation(decoded); // fotos giradas (EXIF)
  final big =
      image.width > NoteImages.maxSide || image.height > NoteImages.maxSide;
  if (ext == 'png' && !big && raw.length <= 1600 * 1024) return raw;
  if (big) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: NoteImages.maxSide, interpolation: img.Interpolation.cubic)
        : img.copyResize(image,
            height: NoteImages.maxSide, interpolation: img.Interpolation.cubic);
  }
  if (ext == 'png') {
    final png = img.encodePng(image, level: 6);
    if (png.length <= 1600 * 1024) return png;
  }
  // JPEG no tiene transparencia: se pinta sobre blanco.
  if (image.hasAlpha) {
    final bg = img.Image(width: image.width, height: image.height)
      ..clear(img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(bg, image);
  }
  final jpg = img.encodeJpg(image, quality: 86);
  return jpg.length < raw.length || big ? jpg : raw;
}
