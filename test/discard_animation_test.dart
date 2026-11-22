import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Animaciones de flutter_animate que se están reproduciendo (algún
/// FadeTransition suyo por debajo de 1).
List<String> _playing(WidgetTester tester) => [
      for (final e in find.byType(Animate).evaluate())
        for (final f in find
            .descendant(
                of: find.byWidget(e.widget),
                matching: find.byType(FadeTransition))
            .evaluate()
            .take(1))
          if ((f.widget as FadeTransition).opacity.value < 0.999)
            '${(e.widget as Animate).child.runtimeType}',
    ];

void main() {
  testWidgets(
      'móvil: al eliminar la nota abierta la lista no repite su animación',
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
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final note = repo.notes.where((n) => !n.isEmpty).first;
    await tester.tap(find.text(note.title).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const PageStorageKey('lista-notas')), findsNothing);

    // ⋯ → Eliminar.
    await tester.tap(find.byTooltip('More'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byIcon(Icons.delete_outline).last);

    // Mientras la nota se va, nada de la lista (ni el editor que sale) se
    // vuelve a animar desde cero.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_playing(tester), isEmpty, reason: 't=${(i + 1) * 50} ms');
    }
    expect(find.byKey(const PageStorageKey('lista-notas')), findsOneWidget);
    expect(repo.byId(note.id)!.deleted, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('PC: cambiar a la red y volver no re-anima la lista',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
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
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (final tip in [RegExp(r'^Note network'), RegExp(r'^Note network')]) {
      await tester.tap(find.byTooltip(tip));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final list = find.byKey(const PageStorageKey('lista-notas'));
        expect(list, findsOneWidget);
        final rows = _playing(tester)
            .where((t) => t == 'Column') // filas de la lista
            .toList();
        expect(rows, isEmpty);
      }
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
