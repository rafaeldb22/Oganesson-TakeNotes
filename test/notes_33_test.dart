import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_board.dart';
import 'package:notas/data/reminders.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/reminder_settings.dart';
import 'package:notas/ui/theme.dart';
import 'package:notas/ui/whiteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

Note _task(DateTime start, DateTime due) => Note(
    id: 'n',
    content: 'Tarea',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    remindAt: start.toUtc(),
    dueAt: due.toUtc());

void main() {
  setUp(() => appLanguage.code = 'es');

  group('avisos', () {
    final now = DateTime(2026, 12, 1, 8);
    final due = Note.dayEnd(DateTime(2026, 12, 15));
    const none = ReminderPrefs(week: false, three: false, day: false);

    List<int> daysOf(ReminderPrefs p) => [
          for (final (at, _) in reminderTimes(_task(now, due), p, now))
            DateTime.utc(2026, 12, 15)
                .difference(DateTime.utc(
                    at.toLocal().year, at.toLocal().month, at.toLocal().day))
                .inDays,
        ];

    test('solo suenan las casillas marcadas', () {
      expect(daysOf(const ReminderPrefs()), [7, 3, 1]);
      expect(daysOf(none.copyWith(three: true)), [3]);
      expect(daysOf(none), isEmpty);
      expect(daysOf(const ReminderPrefs(enabled: false)), isEmpty);
    });

    test('cada día y cada semana hasta la fecha límite', () {
      expect(daysOf(none.copyWith(weekly: true)), [14, 7]);
      expect(daysOf(none.copyWith(daily: true)),
          [for (var d = 14; d >= 0; d--) d]);
    });

    test('a la hora elegida y nunca en el pasado', () {
      final late = reminderTimes(_task(now, due),
          none.copyWith(daily: true, hour: 7, minute: 30), now);
      expect(late.first.$1.toLocal(), DateTime(2026, 12, 2, 7, 30));
    });

    test('si vence antes de la hora de avisar, avisa antes de que venza', () {
      final morning = DateTime(2026, 12, 2, 8);
      final out = reminderTimes(
          _task(DateTime(2026, 12, 2), morning), const ReminderPrefs(), now);
      expect(out.last.$1.toLocal(), DateTime(2026, 12, 2, 7));
    });

    test('la selección se guarda', () {
      const p = ReminderPrefs(daily: true, week: false, hour: 18, minute: 45);
      final back = ReminderPrefs.decode(p.encode());
      expect(back.daily, isTrue);
      expect(back.week, isFalse);
      expect(back.hour, 18);
      expect(back.minute, 45);
      expect(ReminderPrefs.decode('no es json').week, isTrue);
    });

    for (final size in const [Size(320, 568), Size(800, 700)]) {
      testWidgets('la pantalla cabe y guarda en $size', (t) async {
        SharedPreferences.setMockInitialValues({});
        await Reminders.instance.savePrefs(const ReminderPrefs());
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          theme: buildTheme(themeById(''), Brightness.dark),
          home: Scaffold(
            body: Builder(
                builder: (c) => TextButton(
                    onPressed: () => showReminderSettings(c),
                    child: const Text('abrir'))),
          ),
        ));
        await t.tap(find.text('abrir'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(find.text('tres días antes'));
        await t.pumpAndSettle();
        expect(Reminders.instance.prefs.three, isFalse);
      });
    }
  });

  test('el garabato borra también la tinta entre sus pasadas', () {
    // Pasadas separadas 16 unidades, con trazos justo en medio.
    final path = <Offset>[];
    for (var row = 0; row < 8; row++) {
      final y = row * 16.0;
      for (var x = 0.0; x <= 120; x += 4) {
        path.add(Offset(row.isEven ? x : 120 - x, y));
      }
    }
    expect(isScribble(path), isTrue);
    final ink = BoardStroke(0, 2, [
      for (var x = 10.0; x <= 110; x += 2) Offset(x, 40)
    ], [
      for (var x = 10.0; x <= 110; x += 2) 1,
    ]);
    final c = BoardController(BoardData(strokes: [ink]), onChanged: () {});
    expect(c.eraseScribble(path, scribbleReach(path, 6)), isTrue);
    expect(c.strokes, isEmpty);
  });
}
