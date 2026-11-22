import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_factory.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/quick_capture.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  test('crea una nota con título, texto e imágenes válida para el editor', () {
    final repo = _repo();
    final n = createNoteFrom(repo,
        text: 'Compra\r\nleche\npan', images: ['sb://demo/a?w=4&h=3'])!;
    expect(n.title, 'Compra');
    expect(n.content, 'Compra\nleche\npan\n￼');
    expect(n.rich, contains('"header":1'));
    final doc = Document.fromJson(jsonDecode(n.rich!) as List);
    expect(doc.toPlainText(), 'Compra\nleche\npan\n￼\n');
    repo.dispose();
  });

  test('solo una imagen, o nada', () {
    final repo = _repo();
    final n = createNoteFrom(repo, text: '  ', images: ['sb://demo/a'])!;
    expect(n.title, 'Imagen');
    Document.fromJson(jsonDecode(n.rich!) as List);
    expect(createNoteFrom(repo, text: '  '), isNull);
    repo.dispose();
  });

  testWidgets('nota rápida: Ctrl+Intro guarda y Esc cancela', (tester) async {
    final repo = _repo();
    final results = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.light),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              results.add(await showQuickCapture(context, repo)),
          child: const Text('abrir'),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(results, [null]);
    expect(repo.notes, isEmpty);

    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
        find.byKey(const ValueKey('captura')), 'Llamar a Ana\nmañana');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.notes.single.title, 'Llamar a Ana');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
