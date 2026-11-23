import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/note_attachments.dart';
import 'package:notas/data/note_factory.dart';
import 'package:notas/data/note_file_reader.dart';
import 'package:notas/data/note_files.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, text) {
    final b = utf8.encode(text);
    a.addFile(ArchiveFile(name, b.length, b));
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

NoteFile _file(String name, String mime) =>
    NoteFile(src: 'ogf://demo/$name', name: name, size: 1, mime: mime);

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'k',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lee un Word', () {
    final docx = _zip({
      'word/document.xml': '<w:body><w:p><w:r><w:t>Hola </w:t></w:r>'
          '<w:r><w:t xml:space="preserve">R&amp;D</w:t></w:r></w:p>'
          '<w:tbl/><w:p><w:r><w:t>Segunda</w:t></w:r></w:p></w:body>',
    });
    expect(officeText(docx, 'docx')!.trim(), 'Hola R&D\nSegunda');
  });

  test('lee un Excel con textos compartidos y números', () {
    final xlsx = _zip({
      'xl/sharedStrings.xml': '<sst><si><t>Total</t></si></sst>',
      'xl/worksheets/sheet1.xml': '<sheetData><row r="1">'
          '<c r="A1" t="s"><v>0</v></c><c r="B1"><v>42</v></c>'
          '</row></sheetData>',
    });
    expect(officeText(xlsx, 'xlsx'), contains('Total\t42'));
  });

  test('lee las diapositivas en orden', () {
    final pptx = _zip({
      'ppt/slides/slide10.xml': '<a:p><a:t>Diez</a:t></a:p>',
      'ppt/slides/slide2.xml': '<a:p><a:t>Dos</a:t></a:p>',
    });
    final t = officeText(pptx, 'pptx')!;
    expect(t.indexOf('Dos'), lessThan(t.indexOf('Diez')));
  });

  test('un archivo dañado no rompe nada', () {
    expect(officeText(Uint8List.fromList([1, 2, 3]), 'docx'), isNull);
  });

  test('lee texto y rechaza binarios', () async {
    expect(
        await documentText(
            Uint8List.fromList(utf8.encode('a,b')), _file('d.csv', 'text/csv')),
        'a,b');
    expect(
        await documentText(
            Uint8List.fromList([65, 0, 66]), _file('d.txt', 'text/plain')),
        isNull);
    expect(await documentText(Uint8List(3), _file('d.zip', 'application/zip')),
        isNull);
  });

  testWidgets('saca el texto de un PDF real', (t) async {
    final tmp = Directory.systemTemp.createTempSync('pdfrx');
    addTearDown(() => tmp.deleteSync(recursive: true));
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tmp.path);
    final text = await t.runAsync(() async {
      final doc = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Factura de marzo')));
      return pdfText(await doc.save());
    });
    expect(text, contains('Factura de marzo'));
  });

  group('la IA', () {
    Map<String, dynamic> embed(String name) =>
        fileEmbed(_file(name, mimeForName(name)));

    test('lee los archivos de dentro y los conectados', () async {
      final r = _repo();
      final n = r.createNote();
      final (c, rich) =
          withEmbeds('Nota', richFor('Nota'), [embed('informe.pdf')]);
      r.updateContent(n.id, c, rich: rich);
      connectMedia(r, n.id, embed('datos.xlsx'));
      final tools = AiTools(r,
          confirm: (_) async => false,
          readFile: (m) async => 'contenido de ${m.name}');
      final out = await tools.run('read_note_files', {'id': n.id});
      final names = [for (final f in out['files'] as List) f['content']];
      expect(names, ['contenido de informe.pdf', 'contenido de datos.xlsx']);
      r.dispose();
    });

    test('un archivo que falla no impide leer los demás', () async {
      final r = _repo();
      final n = r.createNote();
      final (c, rich) =
          withEmbeds('Nota', richFor('Nota'), [embed('a.bin'), embed('b.txt')]);
      r.updateContent(n.id, c, rich: rich);
      final tools = AiTools(r,
          confirm: (_) async => false,
          readFile: (m) async {
            if (m.name == 'a.bin') throw AiException('no');
            return 'ok';
          });
      final files =
          (await tools.run('read_note_files', {'id': n.id}))['files'] as List;
      expect(files[0]['error'], 'no');
      expect(files[1]['content'], 'ok');
      r.dispose();
    });

    test('nunca lee archivos del Vault', () async {
      final r = _repo();
      final n = r.createNote();
      final (c, rich) = withEmbeds('Nota', richFor('Nota'), [embed('x.pdf')]);
      r.updateContent(n.id, c, rich: rich);
      r.setVault(n.id, true);
      var read = false;
      final tools = AiTools(r,
          confirm: (_) async => false,
          readFile: (_) async {
            read = true;
            return 'x';
          });
      final out = await tools.run('read_note_files', {'id': n.id});
      expect(out['error'], isNotNull);
      expect(read, isFalse);
      r.dispose();
    });
  });
}
