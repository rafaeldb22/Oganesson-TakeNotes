import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/note_export.dart';
import 'package:notas/data/note_files.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/drawing_pad.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/note_media.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('oga_files');
    NoteFiles.instance.directory = dir;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('adjuntos', () {
    test('guardar, localizar, límite y borrar', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final f = (await NoteFiles.instance.add(bytes, 'informe.pdf'))!;
      expect(f.isPdf, isTrue);
      final local = await NoteFiles.instance.local(f.path);
      expect(await local!.readAsBytes(), bytes);
      expect(
          await NoteFiles.instance
              .add(Uint8List(NoteFiles.maxBytes + 1), 'grande.zip'),
          isNull);
      await NoteFiles.instance.remove([f.path]);
      expect(await NoteFiles.instance.local(f.path), isNull);
    });

    test('el embed se guarda, se recarga y se detecta en la nota', () async {
      const f = NoteFile(
          src: 'ogf://u/abc', name: 'voz.m4a', size: 2048, mime: 'audio/mp4');
      final c = QuillController.basic();
      insertFileBlock(c, f);
      final json = jsonEncode(c.document.toDelta().toJson());
      expect(NoteFiles.pathsIn(json), {'u/abc'});

      final again = Document.fromJson(jsonDecode(json) as List);
      final embed = again.toDelta().toList().first.data as Map;
      expect(embed.containsKey('custom'), isTrue);

      final n = Note(
        id: 'n',
        content: '￼',
        rich: json,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(n.hasFiles, isTrue);
      expect(n.hasImages, isFalse);
      expect(n.title, 'Adjunto');
      expect(noteToMarkdown(n), contains('[adjunto: voz.m4a]'));
    });

    testWidgets('la tarjeta dibuja nombre y tamaño', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(themeById(''), Brightness.dark),
        home: const Scaffold(
          body: NoteFileCard(
              file: NoteFile(
                  src: 'ogf://u/a',
                  name: 'informe.pdf',
                  size: 2048,
                  mime: 'application/pdf')),
        ),
      ));
      expect(find.text('informe.pdf'), findsOneWidget);
      expect(find.text('2 KB'), findsOneWidget);
    });

    test('datos dañados no rompen', () {
      expect(NoteFile.parse('no-json'), isNull);
      expect(NoteFile.parse('{"src":"http://x"}'), isNull);
    });
  });

  group('dibujo', () {
    test('la goma detecta el trazo por proximidad', () {
      final s = Stroke(Colors.red, 4, [Offset.zero, const Offset(100, 0)]);
      expect(strokeHit(s, const Offset(50, 5), 4), isTrue);
      expect(strokeHit(s, const Offset(50, 40), 4), isFalse);
    });

    testWidgets('dibujar, deshacer y rehacer', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(themeById(''), Brightness.dark),
        home: const DrawingPad(),
      ));
      await tester.pump();
      IconButton btn(String tip) =>
          tester.widget<IconButton>(find.widgetWithIcon(
              IconButton,
              {
                'u': Icons.undo_rounded,
                'r': Icons.redo_rounded,
              }[tip]!));
      expect(btn('u').onPressed, isNull);
      await tester.drag(
          find.byKey(const ValueKey('lienzo')), const Offset(120, 60));
      await tester.pump();
      expect(btn('u').onPressed, isNotNull);
      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pump();
      expect(btn('u').onPressed, isNull);
      expect(btn('r').onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('leer con la IA', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

    test('Gemini envía la imagen en línea', () async {
      Map<String, dynamic>? sent;
      final c = GeminiClient(transport: (m, u, h, b) async {
        sent = b;
        return (
          200,
          {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'pensando', 'thought': true},
                    {'text': 'Hola'},
                  ]
                }
              }
            ]
          }
        );
      });
      final t = await c.readMedia(
          apiKey: 'k',
          model: 'm',
          bytes: png,
          mime: 'image/png',
          prompt: aiOcrPrompt);
      expect(t, 'Hola');
      expect(jsonEncode(sent), contains('inline_data'));
    });

    test('ChatGPT transcribe el audio con su API', () async {
      Uri? url;
      final c = OpenAiClient(
        transport: (m, u, h, b) => throw StateError('no debía usarse'),
        multipart: (u, h, f, file, name, mime) async {
          url = u;
          return (200, {'text': 'dicho'});
        },
      );
      final t = await c.readMedia(
          apiKey: 'k',
          model: 'm',
          bytes: png,
          mime: 'audio/mp4',
          prompt: aiTranscribePrompt);
      expect(t, 'dicho');
      expect(url.toString(), endsWith('audio/transcriptions'));
    });

    test('Claude lee imágenes y avisa con audio o rechazo', () async {
      var reply = <String, dynamic>{
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': 'Leído'}
        ]
      };
      final c = ClaudeClient(transport: (m, u, h, b) async => (200, reply));
      expect(
          await c.readMedia(
              apiKey: 'k',
              model: 'claude-opus-5-5',
              bytes: png,
              mime: 'image/png',
              prompt: aiOcrPrompt),
          'Leído');
      await expectLater(
          c.readMedia(
              apiKey: 'k',
              model: 'claude-opus-5-5',
              bytes: png,
              mime: 'audio/mp4',
              prompt: aiTranscribePrompt),
          throwsA(isA<AiException>()));
      reply = {'stop_reason': 'refusal', 'content': []};
      await expectLater(
          c.readMedia(
              apiKey: 'k',
              model: 'claude-opus-5-5',
              bytes: png,
              mime: 'image/png',
              prompt: aiOcrPrompt),
          throwsA(isA<AiException>()));
    });

    test('sin clave no envía nada', () async {
      final s = AiSettings.instance;
      await s.load();
      await s.save(provider: AiProvider.gemini, apiKey: '', model: 'm');
      await expectLater(aiReadMedia(png, 'image/png', aiOcrPrompt),
          throwsA(isA<AiException>()));
    });
  });
}
