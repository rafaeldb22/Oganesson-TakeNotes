import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note.dart';

/// Un adjunto de una nota: PDF, archivo o nota de voz.
class NoteFile {
  const NoteFile(
      {required this.src,
      required this.name,
      required this.size,
      required this.mime});

  /// `ogf://<usuario>/<id>`.
  final String src;
  final String name;
  final int size;
  final String mime;

  String get path => src.substring(NoteFiles.scheme.length);
  bool get isAudio => mime.startsWith('audio/');
  bool get isPdf => mime == 'application/pdf';

  String toJsonString() =>
      jsonEncode({'src': src, 'name': name, 'size': size, 'mime': mime});

  static NoteFile? parse(Object? data) {
    try {
      final m = jsonDecode('$data');
      if (m is! Map || m['src'] is! String) return null;
      final src = m['src'] as String;
      if (!src.startsWith(NoteFiles.scheme)) return null;
      return NoteFile(
        src: src,
        name: (m['name'] as String?) ?? 'archivo',
        size: (m['size'] as num?)?.toInt() ?? 0,
        mime: (m['mime'] as String?) ?? 'application/octet-stream',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Tipo MIME según la extensión del archivo.
String mimeForName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  return const {
        'pdf': 'application/pdf',
        'txt': 'text/plain',
        'md': 'text/markdown',
        'csv': 'text/csv',
        'json': 'application/json',
        'doc': 'application/msword',
        'docx':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx':
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'zip': 'application/zip',
        'm4a': 'audio/mp4',
        'mp3': 'audio/mpeg',
        'wav': 'audio/wav',
        'ogg': 'audio/ogg',
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
      }[ext] ??
      'application/octet-stream';
}

/// Adjuntos: disco local + bucket privado `note-files` (migración 009). Sin
/// conexión o sin migración quedan en una cola y se reintentan.
class NoteFiles extends ChangeNotifier {
  NoteFiles._();
  static final instance = NoteFiles._();

  static const bucket = 'note-files';
  static const scheme = 'ogf://';
  static const embedType = 'oga-file';
  static const maxBytes = 25 * 1024 * 1024;

  SupabaseClient? _client;
  String _userId = 'local';
  Directory? _dir;
  final Set<String> _pending = {};
  final Set<String> _uploading = {};
  final Map<String, String> _mimes = {};
  String get _pendingKey => 'archivos_pendientes_$_userId';

  /// Carpeta de pruebas (sin path_provider).
  @visibleForTesting
  set directory(Directory d) => _dir = d;

  Future<void> attach(SupabaseClient? client, String userId) async {
    _client = client;
    _userId = userId;
    _pending.clear();
    try {
      final p = await SharedPreferences.getInstance();
      for (final e in p.getStringList(_pendingKey) ?? const <String>[]) {
        final cut = e.indexOf('|');
        if (cut == -1) continue;
        _mimes[e.substring(cut + 1)] = e.substring(0, cut);
        _pending.add(e.substring(cut + 1));
      }
    } catch (_) {}
    unawaited(retryPending());
  }

  bool isPending(String path) => _pending.contains(path);

  /// Rutas de los adjuntos de una nota.
  static Set<String> pathsIn(String? rich) {
    if (rich == null || !rich.contains(scheme)) return const {};
    return {
      for (final m in RegExp(r'ogf://([^"\\]+)').allMatches(rich)) m.group(1)!,
    };
  }

  /// Guarda y sube. null si el archivo pasa del límite o está vacío.
  Future<NoteFile?> add(Uint8List bytes, String name, {String? mime}) async {
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    final path = '$_userId/${newNoteId()}';
    final type = mime ?? mimeForName(name);
    final f = await _file(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    _pending.add(path);
    _mimes[path] = type;
    await _savePending();
    notifyListeners();
    unawaited(_upload(path, bytes));
    return NoteFile(
        src: '$scheme$path', name: name, size: bytes.length, mime: type);
  }

  Future<void> _upload(String path, Uint8List bytes) async {
    final client = _client;
    if (client == null) {
      _pending.remove(path);
      await _savePending();
      notifyListeners();
      return;
    }
    if (!_uploading.add(path)) return;
    try {
      await client.storage.from(bucket).uploadBinary(path, bytes,
          fileOptions: FileOptions(
              contentType: _mimes[path], upsert: true, cacheControl: '3600'));
      _pending.remove(path);
      await _savePending();
    } catch (e) {
      debugPrint('Adjunto: subida pendiente ($e)');
    } finally {
      _uploading.remove(path);
      notifyListeners();
    }
  }

  Future<void> retryPending() async {
    for (final path in _pending.toList()) {
      final f = await _file(path);
      if (!await f.exists()) {
        _pending.remove(path);
        continue;
      }
      await _upload(path, await f.readAsBytes());
    }
    await _savePending();
  }

  Future<void> _savePending() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(
          _pendingKey, [for (final x in _pending) '${_mimes[x] ?? ''}|$x']);
    } catch (_) {}
  }

  /// Archivo en disco, descargándolo si hace falta. null si no se puede.
  Future<File?> local(String path) async {
    try {
      final f = await _file(path);
      if (await f.exists()) return f;
      final client = _client;
      if (client == null) return null;
      final bytes = await client.storage.from(bucket).download(path);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
      return f;
    } catch (e) {
      debugPrint('Adjunto: no se pudo descargar ($e)');
      return null;
    }
  }

  /// Borra adjuntos que ya no usa ninguna nota.
  Future<void> remove(Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return;
    for (final p in list) {
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
      debugPrint('Adjunto: no se pudo borrar de la nube ($e)');
    }
  }

  Future<File> _file(String path) async {
    _dir ??= Directory('${(await getApplicationSupportDirectory()).path}'
        '${Platform.pathSeparator}adjuntos');
    return File('${_dir!.path}${Platform.pathSeparator}'
        '${path.replaceAll('/', '_')}');
  }
}
