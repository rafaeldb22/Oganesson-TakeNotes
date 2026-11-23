import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import '../ui/i18n.dart';
import 'ai_assistant.dart';
import 'note_attachments.dart';
import 'note_files.dart';
import 'note_images.dart';

/// Texto máximo de un archivo que se envía a la IA.
const maxFileChars = 12000;

/// Páginas de un PDF escaneado que se miran como imagen.
const _maxScannedPages = 5;

/// Tamaño máximo descomprimido de un Word, Excel o PowerPoint.
const _maxOfficeBytes = 40 * 1024 * 1024;

const _textTypes = {'application/json', 'application/xml'};
const _textExtensions = {
  'txt', 'md', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml', 'log', 'ini', 'html',
  'htm', 'css', 'js', 'ts', 'dart', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'cs',
  'sql', 'sh', 'ps1', 'rtf', //
};

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
}

String _unescapeXml(String s) => s.replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#\d+|lt|gt|amp|quot|apos);'),
      (m) {
        final e = m.group(1)!;
        final code = e.startsWith('#x')
            ? int.tryParse(e.substring(2), radix: 16)
            : e.startsWith('#')
                ? int.tryParse(e.substring(1))
                : null;
        if (code != null) {
          return code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : '';
        }
        return const {
          'lt': '<',
          'gt': '>',
          'amp': '&',
          'quot': '"',
          'apos': "'",
        }[e]!;
      },
    );

/// Une los trozos de texto de un XML, con un salto en cada fin de párrafo.
String _xmlParagraphs(String xml, String textTag, String paragraphTag) {
  final out = StringBuffer();
  final re = RegExp('<$textTag(?: [^>]*)?>([^<]*)</$textTag>|</$paragraphTag>');
  for (final m in re.allMatches(xml)) {
    final t = m.group(1);
    out.write(t == null ? '\n' : _unescapeXml(t));
  }
  return out.toString();
}

int _trailingNumber(String name) =>
    int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(name)?.group(1) ?? '') ?? 0;

String _sheetText(String xml, List<String> shared) {
  final rows = <String>[];
  for (final row
      in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true).allMatches(xml)) {
    final cells = <String>[];
    for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
        .allMatches(row.group(1)!)) {
      final body = c.group(2) ?? '';
      final v = RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1);
      if (c.group(1)!.contains('t="s"')) {
        final i = int.tryParse(v ?? '');
        cells.add(i != null && i >= 0 && i < shared.length ? shared[i] : '');
      } else if (v != null) {
        cells.add(_unescapeXml(v));
      } else {
        cells.add(_unescapeXml(
            RegExp(r'<t(?: [^>]*)?>([^<]*)</t>').firstMatch(body)?.group(1) ??
                ''));
      }
    }
    if (cells.any((x) => x.isNotEmpty)) rows.add(cells.join('\t'));
  }
  return rows.join('\n');
}

/// Texto de un .docx, .xlsx o .pptx. null si el archivo no es válido.
String? officeText(Uint8List bytes, String extension) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  // Un zip diminuto puede descomprimirse en gigas: se mira antes de leerlo.
  if (zip.files.fold<int>(0, (n, f) => n + f.size) > _maxOfficeBytes) {
    return null;
  }
  String? read(String name) {
    final f = zip.findFile(name);
    if (f == null) return null;
    return utf8.decode(f.content, allowMalformed: true);
  }

  List<String> parts(String prefix) => zip.files
      .where((f) => f.name.startsWith(prefix) && f.name.endsWith('.xml'))
      .map((f) => f.name)
      .toList()
    ..sort((a, b) => _trailingNumber(a).compareTo(_trailingNumber(b)));

  switch (extension) {
    case 'docx':
      final doc = read('word/document.xml');
      return doc == null ? null : _xmlParagraphs(doc, 'w:t', 'w:p');
    case 'pptx':
      final slides = parts('ppt/slides/slide');
      if (slides.isEmpty) return null;
      return [
        for (final (i, s) in slides.indexed)
          '[${i + 1}]\n${_xmlParagraphs(read(s)!, 'a:t', 'a:p').trim()}',
      ].join('\n\n');
    case 'xlsx':
      final sheets = parts('xl/worksheets/sheet');
      if (sheets.isEmpty) return null;
      final sharedXml = read('xl/sharedStrings.xml') ?? '';
      final shared = [
        for (final si
            in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(sharedXml))
          RegExp(r'<t(?: [^>]*)?>([^<]*)</t>')
              .allMatches(si.group(1)!)
              .map((t) => _unescapeXml(t.group(1)!))
              .join(),
      ];
      return [
        for (final (i, s) in sheets.indexed)
          '[${i + 1}]\n${_sheetText(read(s)!, shared)}',
      ].join('\n\n');
  }
  return null;
}

Future<PdfDocument?> _openPdf(Uint8List bytes) async {
  try {
    await pdfrxFlutterInitialize();
    return await PdfDocument.openData(bytes);
  } catch (_) {
    return null; // Dañado o protegido con contraseña.
  }
}

/// Texto de un PDF. Vacío si es escaneado; null si no se puede abrir.
Future<String?> pdfText(Uint8List bytes) async {
  final doc = await _openPdf(bytes);
  if (doc == null) return null;
  try {
    final out = StringBuffer();
    for (final page in doc.pages) {
      final t = await page.loadText();
      if (t != null) out.writeln(t.fullText);
      if (out.length > maxFileChars) break;
    }
    return out.toString().trim();
  } finally {
    await doc.dispose();
  }
}

/// Primeras páginas de un PDF escaneado, como PNG.
Future<List<Uint8List>> _pdfPages(Uint8List bytes) async {
  final doc = await _openPdf(bytes);
  if (doc == null) return const [];
  try {
    final out = <Uint8List>[];
    for (final page in doc.pages.take(_maxScannedPages)) {
      final k = 1600 / math.max(page.width, page.height);
      final w = (page.width * k).round(), h = (page.height * k).round();
      final image = await page.render(
          width: w,
          height: h,
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
          backgroundColor: 0xFFFFFFFF);
      if (image == null) continue;
      final frame = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.pixels.buffer,
          bytesOffset: image.pixels.offsetInBytes,
          numChannels: 4,
          order: img.ChannelOrder.bgra);
      out.add(img.encodePng(frame, level: 3));
      image.dispose();
    }
    return out;
  } finally {
    await doc.dispose();
  }
}

/// Texto de un documento sin usar la IA. null si hay que mirarlo de otra forma.
Future<String?> documentText(Uint8List bytes, NoteFile f) async {
  final ext = _extension(f.name);
  if (f.isPdf) return pdfText(bytes);
  if (const {'docx', 'xlsx', 'pptx'}.contains(ext)) {
    return officeText(bytes, ext);
  }
  if (f.mime.startsWith('text/') ||
      _textTypes.contains(f.mime) ||
      _textExtensions.contains(ext)) {
    final t = utf8.decode(bytes, allowMalformed: true);
    return t.contains('\u0000') ? null : t;
  }
  return null;
}

String _limit(String t) {
  final s = t.trim();
  return s.length <= maxFileChars
      ? s
      : '${s.substring(0, maxFileChars)}\n[… recortado]';
}

// Los archivos no cambian: así la misma pregunta no se paga dos veces.
final _cache = <String, String>{};

/// Lee cualquier adjunto para la IA. Lanza [AiException] si no se puede.
Future<String> readMediaItem(MediaItem m,
    {AiSettings? settings, AiClient? client}) async {
  final cached = _cache[m.path];
  if (cached != null) return cached;

  Future<String> ask(Uint8List bytes, String mime, String prompt) =>
      aiReadMedia(bytes, mime, prompt, settings: settings, client: client);

  final String result;
  if (m.kind == MediaKind.image) {
    final bytes = await NoteImages.instance.load(m.path);
    if (bytes == null) throw AiException(tr('No se pudo abrir el archivo'));
    result = await ask(bytes, NoteImages.mimeOf(bytes), aiImagePrompt);
  } else {
    final f = m.file;
    final local = f == null ? null : await NoteFiles.instance.local(f.path);
    if (f == null || local == null) {
      throw AiException(tr('No se pudo abrir el archivo'));
    }
    final bytes = await local.readAsBytes();
    if (f.isAudio) {
      result = await ask(bytes, f.mime, aiTranscribePrompt);
    } else {
      final text = await documentText(bytes, f);
      if (text == null) {
        throw AiException(tr('No se puede leer este tipo de archivo.'));
      }
      if (f.isPdf && text.replaceAll(RegExp(r'\s'), '').length < 40) {
        final pages = await _pdfPages(bytes);
        if (pages.isEmpty) {
          throw AiException(tr('No se pudo abrir el archivo'));
        }
        final read = <String>[];
        for (final p in pages) {
          read.add((await ask(p, 'image/png', aiImagePrompt)).trim());
        }
        result = read.join('\n\n');
      } else {
        result = text;
      }
    }
  }
  return _cache[m.path] = _limit(result);
}
