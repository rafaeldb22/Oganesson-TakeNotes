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

/// Estados de toda la pantalla (para ver si algo se ha vuelto a construir).
Set<State> _states(WidgetTester tester) => {
      for (final e
          in find.byWidgetPredicate((w) => w is StatefulWidget).evaluate())
        if (e is StatefulElement) e.state
    };

Future<NotesRepository> _pumpHome(WidgetTester tester,
    {required bool wide}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize =
      wide ? const Size(1400, 900) : const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = wide ? 1 : 3;
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
  return repo;
}

Future<void> _dispose(WidgetTester tester, NotesRepository repo) async {
  await tester.pumpWidget(const SizedBox());
  repo.dispose();
  await tester.pump(const Duration(minutes: 5));
}

void main() {
  for (final wide in [false, true]) {
    testWidgets(
        '${wide ? 'PC' : 'móvil'}: una nota nueva es lo único que se anima',
        (tester) async {
      final repo = await _pumpHome(tester, wide: wide);
      final before = _states(tester);

      final n = repo.createNote();
      repo.updateContent(n.id, 'Nota nueva\nhola');
      await tester.pump(const Duration(milliseconds: 50));

      // Lo que ya estaba sigue siendo lo mismo (no se ha reconstruido).
      expect(_states(tester).containsAll(before), isTrue);
      // Y solo la fila nueva está entrando.
      expect(_playing(tester), ['Column']);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_playing(tester), isEmpty);
      expect(tester.takeException(), isNull);
      await _dispose(tester, repo);
    });
  }

  testWidgets('móvil: abrir y cerrar una nota no reconstruye la lista',
      (tester) async {
    final repo = await _pumpHome(tester, wide: false);
    final before = _states(tester);
    final note = repo.notes.where((n) => !n.isEmpty).first;
    await tester.tap(find.text(note.title).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byTooltip('Back'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_playing(tester), isEmpty);
    }
    expect(_states(tester).containsAll(before), isTrue);
    await _dispose(tester, repo);
  });

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
    // La lista sigue montada debajo de la nota.
    final listStates = _states(tester);

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
    // Nada de la lista se ha vuelto a construir (salvo la fila borrada y el
    // editor, que ya no están).
    final now = _states(tester);
    const listParts = {
      'FolderGroup',
      'WaveTitle',
      '_NoteTile',
      'Scaffold',
      'TextField',
      'SortMenu',
      'RefreshIndicator',
      'DropZone',
    };
    final rebuilt = now
        .difference(listStates)
        .where((s) => s.mounted)
        .map((s) => '${s.widget.runtimeType}')
        .where(listParts.contains)
        .toList();
    expect(rebuilt, isEmpty);
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
