import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_history.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/note_tools.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<NotesRepository> _pump(WidgetTester tester) async {
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
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(themeById(''), Brightness.dark),
    home: NotesHome(repo: repo),
  ));
  await _settle(tester, 20);
  return repo;
}

Future<void> _settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _end(WidgetTester tester, NotesRepository repo) async {
  await tester.pumpWidget(const SizedBox());
  repo.dispose();
  await tester.pump(const Duration(minutes: 5));
}

Future<void> _openTool(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Más').first);
  await _settle(tester);
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

void main() {
  testWidgets('subtareas desde el menú de la nota', (tester) async {
    final repo = await _pump(tester);
    final n = repo.notes.firstWhere((x) => x.title == 'Pelis pendientes');
    await tester.tap(find.text(n.title).first);
    await _settle(tester);
    await _openTool(tester, 'Subtareas');
    await tester.enterText(
        find.byKey(const ValueKey('nueva-subtarea')), 'Primer paso');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(n.subtasks.single.text, 'Primer paso');
    expect(find.text('0/1'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await _settle(tester);
    expect(n.subtasks.single.done, isTrue);
    expect(find.text('1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _end(tester, repo);
  });

  testWidgets('restaurar una versión cambia el editor abierto', (tester) async {
    final repo = await _pump(tester);
    final n = repo.notes.firstWhere((x) => x.title == 'Pelis pendientes');
    final original = n.content;
    repo.history
        .record(n, now: DateTime.now().toUtc().subtract(NoteHistory.gap * 2));
    await tester.tap(find.text(n.title).first);
    await _settle(tester);
    repo.updateContent(n.id, 'Texto nuevo\n');
    await _settle(tester);

    await _openTool(tester, 'Historial de versiones');
    await tester.tap(find.text('Restaurar').first);
    await _settle(tester, 12);
    expect(repo.byId(n.id)!.content, original);
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText().trim(), original.trim());
    expect(tester.takeException(), isNull);
    await _end(tester, repo);
  });

  testWidgets('los filtros reducen la lista y se pueden quitar',
      (tester) async {
    final repo = await _pump(tester);
    expect(find.text('Pelis pendientes'), findsWidgets);
    await tester.tap(find.byTooltip('Filtros'));
    await _settle(tester);
    await tester.tap(find.text('Con imágenes'));
    await _settle(tester, 3);
    await tester.tap(find.text('Aplicar'));
    await _settle(tester);
    expect(find.text('Pelis pendientes'), findsNothing);

    await tester.tap(find.byTooltip('Filtros'));
    await _settle(tester);
    await tester.tap(find.text('Quitar filtros'));
    await _settle(tester);
    expect(find.text('Pelis pendientes'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _end(tester, repo);
  });

  test('una plantilla crea la nota con sus pasos', () {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    final repo = NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        'demo')
      ..loaded = true;
    final t = builtInTemplates().firstWhere((x) => x.name == 'Viaje');
    final n = createFromTemplate(repo, t)!;
    expect(n.title, 'Viaje');
    expect(n.subtasks.length, 3);
    repo.dispose();
  });
}
