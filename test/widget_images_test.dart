import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/calendar_widget_image.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/theme.dart';
import 'package:notas/ui/widget_images.dart';

/// Dibuja todas las imágenes de los widgets de Android (con datos y vacías,
/// en claro y oscuro) y falla si algo se desborda.
void main() {
  setUp(() => appLanguage.code = 'es');
  final now = DateTime.now();
  final tasks = [
    for (var i = 0; i < 7; i++)
      Note(
        id: 't$i',
        content: 'Tarea larga número $i para probar\nDetalle',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now,
        remindAt: i.isEven
            ? now.subtract(const Duration(days: 1))
            : now.add(Duration(days: 1 + i)),
        dueAt: now.add(Duration(days: 2 + i, hours: 3)),
        color: i == 2 ? 0xFFB197FC : null,
      ),
  ];
  final notes = [
    for (var i = 0; i < 9; i++)
      Note(
          id: 'n$i',
          content: 'Nota fijada $i\nCon una vista previa algo larga',
          createdAt: now,
          updatedAt: now.subtract(Duration(hours: i * 5)),
          pinned: true),
  ];

  Future<void> render(WidgetTester tester, Size size, Widget w) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(Center(child: SizedBox.fromSize(size: size, child: w)));
    expect(tester.takeException(), isNull);
  }

  for (final dark in [true, false]) {
    final colors = dark ? appThemes.first.dark : appThemes.first.lightSoft;
    final m = dark ? 'oscuro' : 'claro';

    for (final size in CalendarWidgetSize.values) {
      testWidgets('calendario ${size.name} $m', (t) async {
        for (final list in [tasks, <Note>[]]) {
          await render(
              t,
              size.logicalSize,
              CalendarWidgetImage(
                  notes: list, colors: colors, dark: dark, size: size));
        }
      });
    }
    for (final spec in [
      WidgetSpecs.tareasS,
      WidgetSpecs.tareasM,
      WidgetSpecs.tareasL
    ]) {
      testWidgets('${spec.key} $m', (t) async {
        for (final list in [tasks, <Note>[]]) {
          await render(t, spec.size,
              TasksWidgetImage(notes: list, colors: colors, dark: dark));
        }
      });
    }
    for (final spec in [WidgetSpecs.proximaW, WidgetSpecs.proximaS]) {
      testWidgets('${spec.key} $m', (t) async {
        for (final note in [tasks.first, null]) {
          await render(
              t,
              spec.size,
              NextTaskWidgetImage(
                  note: note,
                  colors: colors,
                  dark: dark,
                  wide: spec == WidgetSpecs.proximaW));
        }
      });
    }
    for (final spec in [WidgetSpecs.fijadasM, WidgetSpecs.fijadasL]) {
      testWidgets('${spec.key} $m', (t) async {
        await render(
            t,
            spec.size,
            PinnedWidgetImage(
                notes: notes, pinned: true, colors: colors, dark: dark));
        await render(
            t,
            spec.size,
            PinnedWidgetImage(
                notes: const [], pinned: false, colors: colors, dark: dark));
      });
    }
  }
}
