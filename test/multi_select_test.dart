import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<NotesRepository> _pump(WidgetTester tester) async {
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
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return repo;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _ctrlTap(WidgetTester tester, String text) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.tap(find.text(text).first);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _settle(tester);
}

void main() {
  testWidgets('Ctrl+clic selecciona, borra varias y Deshacer las recupera',
      (tester) async {
    final repo = await _pump(tester);
    final a = repo.notes.firstWhere((n) => n.title == 'Ideas para el proyecto');
    final b = repo.notes.firstWhere((n) => n.title == 'Pelis pendientes');

    await _ctrlTap(tester, a.title);
    expect(find.text('1 seleccionada'), findsOneWidget);
    // Con selección activa, un toque normal marca en vez de abrir.
    await tester.tap(find.text(b.title).first);
    await _settle(tester);
    expect(find.text('2 seleccionadas'), findsOneWidget);

    await tester.tap(find.byTooltip('Eliminar'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await _settle(tester);
    expect(repo.byId(a.id)!.deleted, isTrue);
    expect(repo.byId(b.id)!.deleted, isTrue);
    expect(find.text('2 seleccionadas'), findsNothing);

    await tester.tap(find.text('Deshacer'));
    await _settle(tester);
    expect(repo.byId(a.id)!.deleted, isFalse);
    expect(repo.byId(b.id)!.deleted, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('Esc quita la selección y fijar actúa sobre todas',
      (tester) async {
    final repo = await _pump(tester);
    final a = repo.notes.firstWhere((n) => n.title == 'Ideas para el proyecto');
    await _ctrlTap(tester, a.title);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('1 seleccionada'), findsNothing);

    await _ctrlTap(tester, a.title);
    await tester.tap(find.byTooltip('Fijar arriba'));
    await _settle(tester);
    expect(repo.byId(a.id)!.pinned, isTrue);
    expect(find.text('1 seleccionada'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
