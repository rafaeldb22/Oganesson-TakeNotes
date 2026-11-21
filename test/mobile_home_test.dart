import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/calendar_view.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('móvil: el botón Notas vuelve a la lista desde el calendario',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final client = SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final repo = NotesRepository(client, 'demo');
    repo.loaded = true;
    repo.seedDemo();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.dark),
      home: NotesHome(repo: repo),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    final notas = find.byTooltip('Notes');
    final calendario = find.byTooltip(RegExp(r'^Calendar'));
    expect(notas, findsOneWidget);
    expect(find.byKey(const PageStorageKey('lista-notas')), findsOneWidget);

    await tester.tap(calendario);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CalendarView), findsOneWidget);
    expect(find.byKey(const PageStorageKey('lista-notas')), findsNothing);

    await tester.tap(notas);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const PageStorageKey('lista-notas')), findsOneWidget);
    expect(find.byType(CalendarView), findsNothing);
    expect(tester.takeException(), isNull);

    // Limpieza: sin temporizadores pendientes al acabar.
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
