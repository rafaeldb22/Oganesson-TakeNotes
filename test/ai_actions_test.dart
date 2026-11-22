import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_actions.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true
  ..seedDemo();

void main() {
  setUp(() async {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AiSettings.instance
        .save(provider: AiProvider.openai, apiKey: 'k', model: 'gpt-5-mini');
  });

  group('parseTasks', () {
    test('JSON, con bloque de código, sin duplicados', () {
      expect(parseTasks('```json\n["Uno","uno"," Dos "]\n```'), ['Uno', 'Dos']);
    });
    test('lista si no viene JSON', () {
      expect(parseTasks('Aquí van:\n- Uno\n2. Dos\nnada'), ['Uno', 'Dos']);
    });
    test('vacío y límite', () {
      expect(parseTasks('[]'), isEmpty);
      final many = jsonEncode([for (var i = 0; i < 50; i++) 't$i']);
      expect(parseTasks(many).length, 30);
    });
  });

  test('una acción no envía funciones y marca la nota como datos', () async {
    final repo = _repo();
    final n = repo.notes.firstWhere((x) => !x.isEmpty);
    Map<String, dynamic>? sent;
    final client = OpenAiClient(transport: (m, u, h, b) async {
      sent = b;
      return (
        200,
        {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': ' Resumen '}
            }
          ]
        }
      );
    });
    final r = await runNoteAction(n, NoteAiAction.summarize, client: client);
    expect(r, 'Resumen');
    expect(sent!.containsKey('tools'), isFalse);
    expect(jsonEncode(sent), contains('<nota>'));
    repo.dispose();
  });

  test('las acciones nunca envían una nota del Vault', () async {
    final repo = _repo();
    final n = repo.notes.firstWhere((x) => !x.isEmpty)..vault = true;
    var called = false;
    final client = OpenAiClient(transport: (m, u, h, b) async {
      called = true;
      return (200, <String, dynamic>{});
    });
    expect(() => runNoteAction(n, NoteAiAction.fix, client: client),
        throwsA(isA<AiException>()));
    expect(called, isFalse);
    repo.dispose();
  });

  test('el resumen diario excluye el Vault', () {
    final repo = _repo();
    final tareas = repo.temporales;
    final oculta = tareas.first;
    final visible = tareas.last;
    final titulo = oculta.title;
    oculta.vault = true;
    repo.vaultChanged();
    final data = dailyBriefData(repo);
    expect(data, isNot(contains(titulo)));
    expect(data, contains(visible.title));
    repo.dispose();
  });

  test('list_tasks no enseña completadas del Vault con el Vault abierto',
      () async {
    final repo = _repo()..vaultUnlocked = () => true;
    final n = repo.temporales.first;
    const titulo = 'SECRETO-DEL-VAULT';
    repo.updateContent(n.id, '$titulo\nprivado');
    repo.toggleDone(n.id);
    n
      ..vault = true
      ..doneAt = DateTime.now().toUtc().subtract(const Duration(days: 9));
    repo.vaultChanged();
    expect(repo.completed.any((x) => x.id == n.id), isTrue);
    final tools = AiTools(repo, confirm: (_) async => true);
    final out = await tools.run('list_tasks', {'status': 'all'});
    expect(jsonEncode(out), isNot(contains(titulo)));
    repo.dispose();
  });

  test('las fuentes se guardan con el mensaje', () {
    final m = AiMessage(AiRole.assistant, 'hola', sources: ['a', 'b']);
    final back = AiMessage.fromJson(jsonDecode(jsonEncode(m.toJson())))!;
    expect(back.sources, ['a', 'b']);
  });

  test('preguntar a las notas enlaza las que ha leído', () async {
    final repo = _repo();
    final n = repo.notes.firstWhere((x) => x.title == 'Pelis pendientes');
    var turn = 0;
    final session = AiSession(repo, transport: (m, u, h, b) async {
      turn++;
      return (
        200,
        turn == 1
            ? {
                'choices': [
                  {
                    'message': {
                      'role': 'assistant',
                      'content': null,
                      'tool_calls': [
                        {
                          'id': 'c1',
                          'type': 'function',
                          'function': {
                            'name': 'read_note',
                            'arguments': jsonEncode({'id': n.id}),
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            : {
                'choices': [
                  {
                    'message': {'role': 'assistant', 'content': 'Dune 2'}
                  }
                ]
              }
      );
    });
    await session.send('¿qué peli tengo pendiente?');
    expect(session.messages.last.text, 'Dune 2');
    expect(session.messages.last.sources, [n.id]);
    repo.dispose();
  });

  test('añadir al final conserva el formato', () {
    final repo = _repo();
    final n = repo.createNote();
    final rich = jsonEncode([
      {
        'insert': 'Hola',
        'attributes': {'bold': true}
      },
      {'insert': '\n'}
    ]);
    repo.updateContent(n.id, 'Hola\n', rich: rich);
    appendToNote(repo, n, 'Fin');
    expect(n.content, contains('Fin'));
    expect(n.rich, contains('"bold":true'));
    expect(n.rich, contains('Fin'));
    repo.dispose();
  });
}
