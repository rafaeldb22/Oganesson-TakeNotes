import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/note.dart';
import 'note_board.dart';
import 'note_images.dart';

/// Copia completa de notas y carpetas. Nunca incluye el Vault, porque el
/// archivo queda sin cifrar fuera de la app.
class Backup {
  Backup(this.notes, this.folders);
  final List<Note> notes;
  final List<Folder> folders;

  static const format = 'oganesson-backup';

  String encode() => const JsonEncoder.withIndent(' ').convert({
        'format': format,
        'version': 1,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'folders': [for (final f in folders) f.toRow()],
        'notes': [
          for (final n in notes)
            if (!n.vault) n.toRow()
        ],
      });

  /// Lanza [FormatException] si el archivo no es una copia válida.
  static Backup decode(String text) {
    final Object? data;
    try {
      data = jsonDecode(text);
    } catch (_) {
      throw const FormatException('not json');
    }
    if (data is! Map || data['format'] != format) {
      throw const FormatException('not a backup');
    }
    try {
      return Backup(
        [
          for (final r in (data['notes'] as List? ?? const []))
            Note.fromRow(Map<String, dynamic>.from(r as Map))
        ],
        [
          for (final r in (data['folders'] as List? ?? const []))
            Folder.fromRow(Map<String, dynamic>.from(r as Map))
        ],
      );
    } catch (_) {
      throw const FormatException('damaged');
    }
  }
}

/// Nombre de archivo seguro a partir del título.
String safeFileName(String title, String ext) {
  final base = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '')
      .replaceAll('\uFFFC', '')
      .trim();
  final cut = base.length > 60 ? base.substring(0, 60).trim() : base;
  return '${cut.isEmpty ? 'nota' : cut}.$ext';
}

String _inline(String text, Map? a) {
  if (a == null || text.trim().isEmpty) return text;
  var t = text;
  if (a['code'] == true) t = '`$t`';
  if (a['bold'] == true) t = '**$t**';
  if (a['italic'] == true) t = '*$t*';
  if (a['strike'] == true) t = '~~$t~~';
  if (a['link'] is String) t = '[$t](${a['link']})';
  return t;
}

String _blockPrefix(Map? a, int number) {
  if (a == null) return '';
  final indent = '  ' * ((a['indent'] as num?)?.toInt() ?? 0);
  if (a['header'] is num) return '${'#' * (a['header'] as num).toInt()} ';
  if (a['blockquote'] == true) return '> ';
  return switch (a['list']) {
    'bullet' => '$indent- ',
    'ordered' => '$indent$number. ',
    'checked' => '$indent- [x] ',
    'unchecked' => '$indent- [ ] ',
    _ => indent,
  };
}

/// Convierte una nota a Markdown, con su formato si lo tiene.
String noteToMarkdown(Note n) {
  final out = StringBuffer();
  final rich = n.rich;
  List? ops;
  if (rich != null) {
    try {
      final d = jsonDecode(rich);
      ops = d is List ? d : (d is Map ? d['ops'] as List? : null);
    } catch (_) {}
  }
  if (ops == null) {
    out.write(n.content.replaceAll('\uFFFC', '').trimRight());
  } else {
    var line = StringBuffer();
    var number = 0;
    var inCode = false;
    void endLine(Map? a) {
      final isCode = a?['code-block'] == true;
      if (isCode != inCode) {
        out.writeln('```');
        inCode = isCode;
      }
      number = a?['list'] == 'ordered' ? number + 1 : 0;
      out.writeln(isCode ? '$line' : '${_blockPrefix(a, number)}$line');
      line = StringBuffer();
    }

    for (final op in ops) {
      if (op is! Map) continue;
      final ins = op['insert'];
      final a = op['attributes'] as Map?;
      if (ins is Map) {
        if (ins.containsKey('image')) {
          line.write('*[imagen]*');
        } else if (ins['custom'] is String) {
          final name = RegExp(r'name\\*":\\*"([^"\\]+)')
              .firstMatch(ins['custom'] as String)
              ?.group(1);
          line.write('*[adjunto${name == null ? '' : ': $name'}]*');
        }
      } else if (ins is String) {
        final parts = ins.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) line.write(_inline(parts[i], a));
          if (i < parts.length - 1) endLine(a);
        }
      }
    }
    if (line.isNotEmpty) endLine(null);
    if (inCode) out.writeln('```');
  }
  final text = out.toString().trimRight();
  return '$text\n';
}

/// Fuentes de las imágenes de una nota, en orden.
List<String> _imageSources(Note n) {
  try {
    final d = jsonDecode(n.rich ?? '[]');
    return [
      for (final op in d is List ? d : const [])
        if (op is Map &&
            op['insert'] is Map &&
            (op['insert'] as Map)['image'] is String)
          (op['insert'] as Map)['image'] as String,
    ];
  } catch (_) {
    return const [];
  }
}

Future<Uint8List?> _loadImage(
    String src, Future<Uint8List?> Function(String path) load) async {
  try {
    return NoteImages.isOurs(src) ? await load(NoteImages.pathOf(src)) : null;
  } catch (_) {
    return null;
  }
}

/// Markdown con las fotos y las pizarras dentro (como imágenes en base64,
/// así es un solo archivo que se ve en cualquier visor).
Future<String> noteToMarkdownWithMedia(Note n,
    {Future<Uint8List?> Function(String path)? load}) async {
  final get = load ?? NoteImages.instance.load;
  var md = noteToMarkdown(n);
  for (final src in _imageSources(n)) {
    final bytes = await _loadImage(src, get);
    final at = md.indexOf('*[imagen]*');
    if (at == -1) break;
    final img = bytes == null
        ? '*[imagen]*'
        : '![](data:${NoteImages.mimeOf(bytes)};base64,${base64Encode(bytes)})';
    md = md.replaceRange(at, at + '*[imagen]*'.length, img);
  }
  final boards = await boardImages(n, load: get);
  for (final (i, png) in boards.indexed) {
    md += '\n![${boards.length == 1 ? 'Pizarra' : 'Pizarra ${i + 1}'}]'
        '(data:image/png;base64,${base64Encode(png)})\n';
  }
  return md;
}

/// Todas las notas en un solo Markdown, para leer o pasar a otra app.
String notesToMarkdown(Iterable<Note> notes) => notes
    .where((n) => !n.vault && !n.isEmpty)
    .map(noteToMarkdown)
    .join('\n---\n\n');

Future<pw.Font?> _systemFont(List<String> paths) async {
  for (final p in paths) {
    try {
      final f = File(p);
      if (await f.exists()) {
        return pw.Font.ttf(ByteData.sublistView(await f.readAsBytes()));
      }
    } catch (_) {}
  }
  return null;
}

/// PDF de una o varias notas. Usa la fuente del sistema para que salgan bien
/// las tildes; si no la encuentra, usa Helvetica y sustituye lo que no tenga.
/// Las pizarras de una nota como PNG (las vacías no salen).
Future<List<Uint8List>> boardImages(Note n,
    {Future<Uint8List?> Function(String path)? load}) async {
  final out = <Uint8List>[];
  for (final b in BoardData.all(n.rich)) {
    final png = await renderBoardPng(b, load ?? NoteImages.instance.load,
        maxSide: 2400);
    if (png != null) out.add(png);
  }
  return out;
}

/// ¿La nota no tiene más texto que el título automático de la pizarra?
bool isBoardOnly(Note n) =>
    BoardData.all(n.rich).isNotEmpty &&
    n.content
        .split('\n')
        .map((l) => l.replaceAll('\uFFFC', '').trim())
        .where((l) => l.isNotEmpty)
        .isEmpty;

/// Las líneas de una nota para el PDF, con sus fotos en su sitio.
List<pw.Widget> _body(
    Note n, List<Uint8List?> photos, String Function(String) clean) {
  final out = <pw.Widget>[];
  var next = 0;
  final imageCount = photos.length;
  // Los U+FFFC del texto son embeds: las imágenes van en orden; los demás
  // (archivos, pizarras) no ocupan foto.
  final kinds = <bool>[];
  try {
    final d = jsonDecode(n.rich ?? '[]');
    for (final op in d is List ? d : const []) {
      if (op is Map && op['insert'] is Map) {
        kinds.add((op['insert'] as Map)['image'] is String);
      }
    }
  } catch (_) {}
  var embed = 0;
  for (final line in n.content.split('\n').skip(1)) {
    final text = line.replaceAll('\uFFFC', '').trim();
    if (text.isNotEmpty) {
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(clean(line),
            style: const pw.TextStyle(fontSize: 11.5, lineSpacing: 2)),
      ));
    }
    for (final _ in '\uFFFC'.allMatches(line)) {
      final isImage = embed < kinds.length ? kinds[embed] : false;
      embed++;
      if (!isImage || next >= imageCount) continue;
      final bytes = photos[next++];
      if (bytes == null) continue;
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Center(
            child: pw.Image(pw.MemoryImage(bytes),
                fit: pw.BoxFit.contain, height: 320)),
      ));
    }
  }
  return out;
}

Future<Uint8List> notesToPdf(List<Note> notes,
    {Future<Uint8List?> Function(String path)? load}) async {
  final boards = {
    for (final n in notes)
      if (!n.vault) n.id: await boardImages(n, load: load)
  };
  // Fotos de cada nota, en orden (salen donde estaban en el texto).
  final photos = <String, List<Uint8List?>>{
    for (final n in notes)
      if (!n.vault)
        n.id: [
          for (final src in _imageSources(n))
            await _loadImage(src, load ?? NoteImages.instance.load)
        ]
  };
  final regular = await _systemFont(const [
    r'C:\Windows\Fonts\segoeui.ttf',
    '/system/fonts/NotoSans-Regular.ttf',
    '/system/fonts/Roboto-Regular.ttf',
  ]);
  final bold = await _systemFont(const [
    r'C:\Windows\Fonts\segoeuib.ttf',
    '/system/fonts/NotoSans-Bold.ttf',
    '/system/fonts/Roboto-Bold.ttf',
  ]);
  String clean(String s) {
    final t = s.replaceAll('\uFFFC', '');
    return regular != null
        ? t
        : t.replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]'), '?');
  }

  final doc = pw.Document();
  final list = notes.where((n) => !n.vault && !n.isEmpty).toList();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(48),
    theme: regular == null
        ? null
        : pw.ThemeData.withFont(base: regular, bold: bold ?? regular),
    build: (_) => [
      for (final (i, n) in list.indexed) ...[
        if (i > 0) pw.Divider(height: 32, color: PdfColors.grey400),
        pw.Text(clean(n.title),
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        ..._body(n, photos[n.id] ?? const [], clean),
        // Las pizarras de la nota, cada una como imagen.
        for (final png in boards[n.id] ?? const <Uint8List>[])
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Center(
              child: pw.Image(pw.MemoryImage(png),
                  fit: pw.BoxFit.contain, height: 420),
            ),
          ),
      ],
      if (list.isEmpty) pw.SizedBox(),
    ],
  ));
  return doc.save();
}
