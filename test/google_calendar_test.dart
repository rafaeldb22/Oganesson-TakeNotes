import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/google_calendar.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'k',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  test('notes become Google events and Google events become calendar items',
      () {
    final day = DateTime(2027, 3, 10);
    final n = Note(
        id: 'n1',
        content: 'Examen\nTema 4',
        createdAt: DateTime.utc(2027),
        updatedAt: DateTime.utc(2027),
        remindAt: Note.dayStart(day).toUtc(),
        dueAt: Note.dayEnd(day).toUtc());
    final ev = GoogleCalendar.eventOf(n);
    expect(ev['start'], {'date': '2027-03-10'});
    expect(ev['end'], {'date': '2027-03-11'});
    expect(ev['summary'], 'Examen');
    expect((ev['extendedProperties'] as Map)['private'], {'oganesson': 'n1'});

    final allDay = GoogleCalendar.eventToIcs({
      'id': 'g1',
      'summary': 'Viaje',
      'start': {'date': '2027-04-01'},
      'end': {'date': '2027-04-04'},
    })!;
    expect(allDay.uid, 'google:g1');
    expect(allDay.dueAt.toLocal().day, 3);
    final timed = GoogleCalendar.eventToIcs({
      'id': 'g2',
      'summary': 'Dentista',
      'start': {'dateTime': '2027-04-05T10:00:00Z'},
      'end': {'dateTime': '2027-04-05T11:00:00Z'},
    })!;
    expect(timed.dueAt, DateTime.utc(2027, 4, 5, 11));
    expect(GoogleCalendar.eventToIcs({'status': 'cancelled'}), isNull);
  });

  test('Google events sync in and disappear when deleted in Google', () {
    final r = _repo();
    final a = GoogleCalendar.eventToIcs({
      'id': 'a',
      'summary': 'A',
      'start': {'dateTime': '2027-05-01T10:00:00Z'},
      'end': {'dateTime': '2027-05-01T11:00:00Z'},
    })!;
    final b = GoogleCalendar.eventToIcs({
      'id': 'b',
      'summary': 'B',
      'start': {'dateTime': '2027-05-02T10:00:00Z'},
      'end': {'dateTime': '2027-05-02T11:00:00Z'},
    })!;
    var ids = r.syncGoogleEvents([a, b], {});
    expect(r.calendarItems.map((n) => n.title), containsAll(['A', 'B']));
    // "B" se borró en Google.
    ids = r.syncGoogleEvents([a], ids);
    expect(r.calendarItems.map((n) => n.title), isNot(contains('B')));
    expect(ids, hasLength(1));
    // No cuentan como notas.
    expect(r.notes.where((n) => n.title == 'A'), isEmpty);
    r.dispose();
  });
}
