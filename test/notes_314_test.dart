import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notas/data/desktop_integration.dart';
import 'package:notas/data/note_export.dart';
import 'package:notas/data/note_factory.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/urgency.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'k',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  test('Markdown export carries the photos inside', () async {
    final r = _repo();
    final n = r.createNote();
    final png =
        Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
    r.updateContent(n.id, 'Viaje\n\uFFFC',
        rich: jsonEncode([
          {'insert': 'Viaje'},
          {
            'insert': '\n',
            'attributes': {'header': 1}
          },
          {
            'insert': {'image': 'sb://demo/foto?w=2&h=2'}
          },
          {'insert': '\n'},
        ]));
    final md = await noteToMarkdownWithMedia(r.byId(n.id)!,
        load: (path) async => path == 'demo/foto' ? png : null);
    expect(md, contains('![](data:image/png;base64,'));
    expect(md, isNot(contains('*[imagen]*')));
    r.dispose();
  });

  test('a .md file opened with the app becomes a formatted note', () {
    final r = _repo();
    final n = noteFromMarkdown(r, '# Lista\n- [ ] pan\n- **leche**');
    expect(n.title, 'Lista');
    expect(n.content, 'Lista\npan\nleche');
    expect(n.rich, contains('unchecked'));
    expect(DesktopIntegration.markdownIn(['--x', r'C:\a\b.MD']), r'C:\a\b.MD');
    expect(DesktopIntegration.markdownIn(['--new-note']), isNull);
    r.dispose();
  });

  test('calendar-only notes go to Completed 5 minutes after ending', () {
    final r = _repo();
    final ended = r.createNote(
        dueAt: DateTime.now().subtract(const Duration(minutes: 6)).toUtc(),
        remindAt: DateTime.now().subtract(const Duration(hours: 2)).toUtc());
    r.updateContent(ended.id, 'Reunión');
    final fresh = r.createNote(
        dueAt: DateTime.now().subtract(const Duration(minutes: 2)).toUtc(),
        remindAt: DateTime.now().subtract(const Duration(hours: 2)).toUtc());
    r.updateContent(fresh.id, 'Clase');
    expect(r.completed.map((n) => n.id), [ended.id]);
    expect(r.notes.map((n) => n.id), contains(fresh.id));
    r.dispose();
  });

  test('the calendar reaches three years ahead', () {
    final range = calendarRange(DateTime(2026, 12, 15));
    expect(range.last.year, 2029);
    expect(range.last.month, 12);
  });
}
