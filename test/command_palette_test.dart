import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show QuillEditor;
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/command_palette.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('la búsqueda ignora tildes, mayúsculas y orden de palabras', () {
    expect(paletteMatches('cafe', 'Lista: Café y pan'), isTrue);
    expect(paletteMatches('PAN cafe', 'Café y pan'), isTrue);
    expect(paletteMatches('té', 'Café'), isFalse);
    expect(paletteMatches('', 'lo que sea'), isTrue);
  });

  testWidgets('busca una nota, la elige con Intro y nunca muestra el Vault',
      (tester) async {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        'demo')
      ..loaded = true
      ..seedDemo();
    final secret = repo.createNote();
    repo.updateContent(secret.id, 'Historia secreta\nclave');
    repo.setVault(secret.id, true);
    final target =
        repo.notes.firstWhere((n) => n.title == 'Examen de historia');

    String? opened;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showCommandPalette(
              context,
              repo: repo,
              commands: [
                PaletteCommand(Icons.edit_note, 'Nueva nota', () {}),
              ],
              onOpenNote: (id) => opened = id,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nueva nota'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'historia');
    await tester.pump();
    expect(find.text('Examen de historia'), findsOneWidget);
    expect(find.text('Historia secreta'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, target.id);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('Ctrl+K abre la paleta también escribiendo en una nota',
      (tester) async {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
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
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Pelis pendientes').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(QuillEditor));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Busca notas o escribe una acción…'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
