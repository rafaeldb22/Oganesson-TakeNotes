import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/note_attachments.dart';
import 'package:notas/data/note_files.dart';
import 'package:notas/data/note_ics.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'k',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

String _ymd(DateTime d) => '${d.year}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

String _importEvent(NotesRepository r) {
  final day = _ymd(DateTime.now().add(const Duration(days: 2)));
  final f = parseIcs('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n'
      'UID:clase\r\nDTSTART:${day}T100000\r\nDTEND:${day}T110000\r\n'
      'SUMMARY:Clase de física\r\nDESCRIPTION:Aula 12\r\n'
      'END:VEVENT\r\nEND:VCALENDAR\r\n');
  r.importEvents(f.events);
  return icsNoteId(r.userId, 'clase');
}

Map<String, dynamic> _reply(List<Map<String, dynamic>> parts) => {
      'candidates': [
        {
          'content': {'role': 'model', 'parts': parts}
        }
      ]
    };

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('la IA encuentra, cambia y borra los eventos .ics', () async {
    final r = _repo();
    final id = _importEvent(r);
    final tools = AiTools(r, confirm: (_) async => true);
    final found = await tools.run('list_calendar', {'query': 'fisica'});
    expect((found['items'] as List).single['id'], id);
    expect(
        (await tools
            .run('append_to_note', {'id': id, 'text': 'Traer DNI'}))['ok'],
        isTrue);
    expect(r.byId(id)!.content, contains('Traer DNI'));
    expect((await tools.run('delete_note', {'id': id}))['ok'], isTrue);
    expect(r.byId(id)!.deleted, isTrue);
    r.dispose();
  });

  test('la IA lee los eventos .ics sin contarlos como notas', () async {
    final r = _repo();
    final id = _importEvent(r);
    var asked = 0;
    final tools = AiTools(r, confirm: (_) async {
      asked++;
      return true;
    });

    final agenda = await tools.run('list_calendar', {});
    final item = (agenda['items'] as List).single as Map;
    expect(item['id'], id);
    expect(item['kind'], 'event');
    expect(item['start_day'], isNotEmpty);

    final read = await tools.run('read_note', {'id': id});
    expect(read['text'], contains('Aula 12'));
    expect(tools.sources, isEmpty);

    expect(jsonEncode(await tools.run('list_notes', {})),
        isNot(contains('Clase de física')));
    expect(asked, 0);
    r.dispose();
  });

  test('la agenda no incluye el Vault ni lo hecho', () async {
    final r = _repo();
    final due = DateTime.now().add(const Duration(days: 1)).toUtc();
    final secret = r.createNote(dueAt: due, remindAt: DateTime.now().toUtc());
    r.updateContent(secret.id, 'Secreto');
    secret.vault = true;
    final done = r.createNote(dueAt: due, remindAt: DateTime.now().toUtc());
    r.updateContent(done.id, 'Terminada');
    r.toggleDone(done.id);
    final tools = AiTools(r, confirm: (_) async => true);
    final out = jsonEncode(await tools.run('list_calendar', {}));
    expect(out, isNot(contains('Secreto')));
    expect(out, isNot(contains('Terminada')));
    r.dispose();
  });

  test('busca sin acentos, por palabras y con el título primero', () async {
    final r = _repo();
    final body = r.createNote(), title = r.createNote(), other = r.createNote();
    r.updateContent(body.id, 'Ideas\nEl presupuesto de la reforma');
    r.updateContent(title.id, 'Presupuesto reforma\nCocina');
    r.updateContent(other.id, 'Lista de la compra');
    final tools = AiTools(r, confirm: (_) async => true);
    final out =
        await tools.run('list_notes', {'query': 'reformá de PRESUPUESTO'});
    final ids = [for (final n in out['notes'] as List) n['id']];
    expect(ids, [title.id, body.id]);
    r.dispose();
  });

  test('una nota larga se puede seguir leyendo', () async {
    final r = _repo();
    final n = r.createNote();
    r.updateContent(n.id, 'Largo\n${'x' * 9000}FIN');
    final tools = AiTools(r, confirm: (_) async => true);
    final first = await tools.run('read_note', {'id': n.id});
    expect(first['text'], isNot(contains('FIN')));
    final next = await tools
        .run('read_note', {'id': n.id, 'offset': first['next_offset']});
    expect(next['text'], endsWith('FIN'));
    expect(next.containsKey('next_offset'), isFalse);
    r.dispose();
  });

  test('no vuelve a analizar un archivo ya leído', () async {
    final r = _repo();
    final n = r.createNote();
    r.updateContent(n.id, 'Con PDF');
    connectMedia(
        r,
        n.id,
        fileEmbed(const NoteFile(
            src: 'ogf://demo/a',
            name: 'a.pdf',
            size: 9,
            mime: 'application/pdf')));
    var reads = 0;
    final cache = <String, String>{};
    AiTools tools() => AiTools(r,
        confirm: (_) async => true,
        readCache: cache,
        readFile: (_) async {
          reads++;
          return 'contenido';
        });
    await tools().run('read_note_files', {'id': n.id});
    final again = await tools().run('read_note_files', {'id': n.id});
    expect(reads, 1);
    expect(jsonEncode(again), contains('contenido'));
    r.dispose();
  });

  group('conversación', () {
    Future<void> key() => AiSettings.instance
        .save(provider: AiProvider.gemini, apiKey: 'k', model: 'm');

    test('recorta lo antiguo sin romper el orden', () async {
      final r = _repo();
      await key();
      final sent = <Map<String, dynamic>>[];
      final s = AiSession(r, transport: (m, u, h, b) async {
        if (b != null) sent.add(jsonDecode(jsonEncode(b)));
        return (
          200,
          _reply([
            {'text': 'ok'}
          ])
        );
      });
      for (var i = 0; i < 45; i++) {
        await s.send('pregunta $i');
      }
      final contents = sent.last['contents'] as List;
      expect(contents.length, lessThanOrEqualTo(61));
      expect(contents.first['role'], 'user');
      expect(jsonEncode(contents.first), contains('pregunta'));
      expect(jsonEncode(contents.last), contains('pregunta 44'));
      r.dispose();
    });

    test('las lecturas van a la vez y los cambios de uno en uno', () async {
      final r = _repo();
      final a = r.createNote(), b = r.createNote();
      r.updateContent(a.id, 'A');
      r.updateContent(b.id, 'B');
      await key();
      final replies = [
        _reply([
          {
            'functionCall': {
              'name': 'read_note',
              'args': {'id': a.id}
            }
          },
          {
            'functionCall': {
              'name': 'read_note',
              'args': {'id': b.id}
            }
          },
          {
            'functionCall': {
              'name': 'set_pinned',
              'args': {'id': a.id, 'pinned': true}
            }
          },
          {
            'functionCall': {
              'name': 'set_pinned',
              'args': {'id': b.id, 'pinned': true}
            }
          },
        ]),
        _reply([
          {'text': 'Listo'}
        ]),
      ];
      final s = AiSession(r, transport: (m, u, h, x) async {
        return (200, replies.removeAt(0));
      });
      final gates = <Completer<bool>>[];
      s.confirm = (_) {
        final c = Completer<bool>();
        gates.add(c);
        return c.future;
      };
      final done = s.send('fija las dos');
      await pumpEventQueue();
      expect(gates.length, 1);
      gates[0].complete(true);
      await pumpEventQueue();
      expect(gates.length, 2);
      gates[1].complete(false);
      await done;
      expect(a.pinned, isTrue);
      expect(b.pinned, isFalse);
      expect(s.messages.last.text, 'Listo');
      r.dispose();
    });

    test('nunca deja una respuesta en blanco', () async {
      final r = _repo();
      await key();
      final s = AiSession(r, transport: (m, u, h, b) async {
        return (
          200,
          _reply([
            {'text': ' '}
          ])
        );
      });
      await s.send('hola');
      expect(s.messages.last.text, contains('No he podido'));
      r.dispose();
    });

    test('no repite el índice de archivos si no cambia', () async {
      final r = _repo();
      final n = r.createNote();
      r.updateContent(n.id, 'Con PDF');
      connectMedia(
          r,
          n.id,
          fileEmbed(const NoteFile(
              src: 'ogf://demo/a',
              name: 'informe.pdf',
              size: 9,
              mime: 'application/pdf')));
      await key();
      final sent = <Map<String, dynamic>>[];
      final s = AiSession(r, transport: (m, u, h, b) async {
        if (b != null) sent.add(jsonDecode(jsonEncode(b)));
        return (
          200,
          _reply([
            {'text': 'ok'}
          ])
        );
      });
      await s.send('uno');
      await s.send('dos');
      final contents = sent.last['contents'] as List;
      expect(jsonEncode(contents.first), contains('informe.pdf'));
      expect(jsonEncode(contents.last), contains('los mismos de antes'));
      r.dispose();
    });
  });
}
