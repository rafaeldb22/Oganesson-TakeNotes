import 'dart:convert';

import 'note_factory.dart';
import 'note_files.dart';
import 'note_images.dart';
import 'notes_repository.dart';

enum MediaKind { image, audio, file }

/// Una imagen, nota de voz o archivo dentro del Delta de una nota.
class MediaItem {
  const MediaItem(this.kind, this.path, this.name, this.embed, this.inGraph);
  final MediaKind kind;

  /// Ruta en Storage: identifica el archivo aunque esté en varias notas.
  final String path;
  final String name;

  /// Valor de `insert` en el Delta.
  final Map<String, dynamic> embed;

  /// Conectado a mano en la red de notas: se ve como una bola propia.
  final bool inGraph;

  NoteFile? get file =>
      kind == MediaKind.image ? null : NoteFile.parse(_fileData(embed));
  String? get imageSrc => embed['image'] as String?;
}

String? _fileData(Map embed) {
  final custom = embed['custom'];
  if (custom is! String || !custom.contains(NoteFiles.embedType)) return null;
  try {
    final m = jsonDecode(custom);
    return m is Map ? m[NoteFiles.embedType] as String? : null;
  } catch (_) {
    return null;
  }
}

bool _srcInGraph(String src) {
  final q = src.indexOf('?');
  return q != -1 && Uri.splitQueryString(src.substring(q + 1))['net'] == '1';
}

String _srcWithGraph(String src, bool on) {
  final q = src.indexOf('?');
  final base = q == -1 ? src : src.substring(0, q);
  final params = q == -1
      ? <String, String>{}
      : Map.of(Uri.splitQueryString(src.substring(q + 1)));
  params.remove('net');
  if (on) params['net'] = '1';
  if (params.isEmpty) return base;
  return '$base?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
}

/// El mismo embed, marcado o no como conectado en la red.
Map<String, dynamic> embedWithGraph(Map<String, dynamic> embed, bool on) {
  final src = embed['image'];
  if (src is String) return {'image': _srcWithGraph(src, on)};
  final data = _fileData(embed);
  if (data == null) return embed;
  final m = Map<String, dynamic>.from(jsonDecode(data) as Map);
  if (on) {
    m['net'] = true;
  } else {
    m.remove('net');
  }
  return {
    'custom': jsonEncode({NoteFiles.embedType: jsonEncode(m)})
  };
}

/// Embed de un adjunto recién subido.
Map<String, dynamic> fileEmbed(NoteFile f) => {
      'custom': jsonEncode({NoteFiles.embedType: f.toJsonString()})
    };

MediaItem? _itemOf(Object? op) {
  if (op is! Map || op['insert'] is! Map) return null;
  final embed = Map<String, dynamic>.from(op['insert'] as Map);
  final src = embed['image'];
  if (src is String) {
    if (!NoteImages.isOurs(src)) return null;
    return MediaItem(MediaKind.image, NoteImages.pathOf(src), 'Imagen', embed,
        _srcInGraph(src));
  }
  final data = _fileData(embed);
  final f = data == null ? null : NoteFile.parse(data);
  if (f == null) return null;
  return MediaItem(f.isAudio ? MediaKind.audio : MediaKind.file, f.path, f.name,
      embed, (jsonDecode(data!) as Map)['net'] == true);
}

List<Object?> _ops(String content, String? rich) {
  if (rich != null) {
    try {
      final d = jsonDecode(rich);
      if (d is List && d.isNotEmpty) return List<Object?>.of(d);
    } catch (_) {}
  }
  // Nota de texto plano: su primera línea se conserva como título.
  return List<Object?>.of(jsonDecode(richFor(content)) as List);
}

(String, String) _result(List<Object?> ops) {
  final plain = StringBuffer();
  for (final o in ops) {
    final v = o is Map ? o['insert'] : null;
    plain.write(v is String ? v : '￼');
  }
  final text = plain.toString();
  return (
    text.endsWith('\n') ? text.substring(0, text.length - 1) : text,
    jsonEncode(ops),
  );
}

/// Imágenes, notas de voz y archivos de una nota, en orden.
List<MediaItem> mediaIn(String? rich) {
  if (rich == null ||
      (!rich.contains(NoteImages.scheme) && !rich.contains(NoteFiles.scheme))) {
    return const [];
  }
  try {
    return [
      for (final op in jsonDecode(rich) as List)
        if (_itemOf(op) case final item?) item,
    ];
  } catch (_) {
    return const [];
  }
}

/// Añade embeds al final, cada uno en su línea, sin tocar el formato de la
/// última línea (un título sigue siendo título).
(String content, String rich) withEmbeds(
    String content, String? rich, List<Map<String, dynamic>> embeds) {
  final ops = _ops(content, rich);
  for (final e in embeds) {
    ops
      ..add({'insert': e})
      ..add({'insert': '\n'});
  }
  return _result(ops);
}

/// Añade texto normal al final, sin heredar el formato de la última línea.
(String content, String rich) withText(
    String content, String? rich, String text) {
  final ops = _ops(content, rich)..add({'insert': '${text.trimRight()}\n'});
  return _result(ops);
}

/// Conecta un adjunto nuevo a una nota de la red.
void connectMedia(
    NotesRepository repo, String noteId, Map<String, dynamic> embed) {
  final n = repo.byId(noteId);
  if (n == null) return;
  final (content, rich) =
      withEmbeds(n.content, n.rich, [embedWithGraph(embed, true)]);
  repo.updateContent(noteId, content, rich: rich);
}

/// Quita la bola de la red; el adjunto sigue dentro de la nota.
void disconnectMedia(NotesRepository repo, String noteId, String path) {
  final n = repo.byId(noteId);
  if (n == null) return;
  final ops = _ops(n.content, n.rich);
  for (var i = 0; i < ops.length; i++) {
    final item = _itemOf(ops[i]);
    if (item != null && item.path == path && item.inGraph) {
      ops[i] = {'insert': embedWithGraph(item.embed, false)};
    }
  }
  final (content, rich) = _result(ops);
  repo.updateContent(noteId, content, rich: rich);
}
