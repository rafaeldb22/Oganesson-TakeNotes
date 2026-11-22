import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_files.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/note_media.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('una nota con adjunto se abre en el editor real', (tester) async {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        'demo')
      ..loaded = true
      ..seedDemo();
    const f = NoteFile(
        src: 'ogf://u/a',
        name: 'informe.pdf',
        size: 2048,
        mime: 'application/pdf');
    final n = repo.createNote();
    repo.updateContent(n.id, 'Con adjunto\n\uFFFC',
        rich: jsonEncode([
          {'insert': 'Con adjunto\n'},
          {
            'insert': {
              'custom': jsonEncode({NoteFiles.embedType: f.toJsonString()})
            }
          },
          {'insert': '\n'},
        ]));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.dark),
      home: NotesHome(repo: repo),
    ));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Con adjunto').first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(QuillEditor), findsOneWidget);
    final card = tester.widget<NoteFileCard>(find.byType(NoteFileCard));
    expect(card.file.name, 'informe.pdf');
    expect(card.allowAi, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
