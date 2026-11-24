import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/new_note_icon.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final wide in [true, false]) {
    testWidgets(
        '${wide ? 'PC' : 'móvil'}: la primera línea de una nota nueva es título '
        'aunque el repositorio avise de cambios antes de escribir',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize =
          wide ? const Size(1400, 900) : const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = wide ? 1 : 3;
      addTearDown(tester.view.reset);
      final repo = NotesRepository(
          SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
              authOptions: const AuthClientOptions(autoRefreshToken: false)),
          'demo')
        ..loaded = true
        ..seedDemo();
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(themeById(''), Brightness.dark),
        home: NotesHome(repo: repo),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byType(NewNoteIcon).first);
      await tester.pump(const Duration(milliseconds: 400));

      // Un aviso cualquiera del repositorio (como un cambio de estado de la
      // sincronización) antes de empezar a escribir.
      repo.togglePin(repo.notes.firstWhere((n) => !n.isEmpty).id);
      await tester.pump(const Duration(milliseconds: 100));

      // Escribir "Hola" letra a letra, como hace el editor.
      final c = tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
      for (final ch in 'Hola'.split('')) {
        final o = c.selection.baseOffset;
        c.replaceText(o, 0, ch, TextSelection.collapsed(offset: o + 1));
        await tester.pump(const Duration(milliseconds: 120));
      }
      await tester.pump(const Duration(seconds: 3));

      final note = repo.notes.firstWhere((n) => n.content == 'Hola');
      expect(note.rich, contains('"header":1'));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      repo.dispose();
      await tester.pump(const Duration(minutes: 5));
    });
  }
}
