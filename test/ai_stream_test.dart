import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Servidor simulado: cada petición devuelve su lista de eventos.
class _FakeStream {
  _FakeStream(this.turns);
  final List<List<Map<String, dynamic>>> turns;
  final sent = <Map<String, dynamic>>[];
  final urls = <Uri>[];

  Future<AiStreamResponse> call(
      Uri url, Map<String, String> h, Map<String, dynamic> body) async {
    urls.add(url);
    sent.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
    return AiStreamResponse(
        200, const {}, Stream.fromIterable(turns.removeAt(0)));
  }
}

Future<(int, Map<String, dynamic>)> _noHttp(String m, Uri u,
        Map<String, String> h, Map<String, dynamic>? b) async =>
    throw StateError('debía ir en directo');

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('SSE: lee los datos e ignora el resto', () async {
    final events = await parseSse(Stream.fromIterable([
      'event: ping',
      'data: {"a":1}',
      '',
      'data: no-json',
      'data: [DONE]',
    ])).toList();
    expect(events, [
      {'a': 1}
    ]);
  });

  test('Gemini en directo: une el texto y conserva la firma', () async {
    final repo = _repo();
    await AiSettings.instance
        .save(provider: AiProvider.gemini, apiKey: 'k', model: 'm');
    Map<String, dynamic> part(Map<String, dynamic> p) => {
          'candidates': [
            {
              'content': {
                'parts': [p]
              }
            }
          ]
        };
    final api = _FakeStream([
      [
        part({
          'functionCall': {'name': 'list_folders', 'args': {}},
          'thoughtSignature': 'firma-1',
        })
      ],
      [
        part({'text': 'Tienes '}),
        part({'text': '2 carpetas'}),
      ],
    ]);
    final s = AiSession(repo, transport: _noHttp, stream: api.call);
    await s.send('¿carpetas?');
    expect(s.messages.last.text, 'Tienes 2 carpetas');
    expect(s.streaming, '');
    expect(api.urls.first.toString(), contains('streamGenerateContent'));
    expect(api.urls.first.queryParameters['alt'], 'sse');
    expect(jsonEncode(api.sent[1]), contains('firma-1'));
    repo.dispose();
  });

  test('ChatGPT en directo: reconstruye una función partida', () async {
    final repo = _repo();
    await AiSettings.instance
        .save(provider: AiProvider.openai, apiKey: 'k', model: 'gpt-5-mini');
    Map<String, dynamic> d(Map<String, dynamic> delta) => {
          'choices': [
            {'delta': delta}
          ]
        };
    final api = _FakeStream([
      [
        d({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'list_tasks', 'arguments': '{"sta'}
            }
          ]
        }),
        d({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': 'tus":"pending"}'}
            }
          ]
        }),
      ],
      [
        d({'content': 'Nada '}),
        d({'content': 'pendiente'}),
      ],
    ]);
    final s = AiSession(repo, transport: _noHttp, stream: api.call);
    await s.send('¿pendiente?');
    expect(s.messages.last.text, 'Nada pendiente');
    expect(api.sent.first['stream'], true);
    final msgs = api.sent[1]['messages'] as List;
    final call = msgs[msgs.length - 2]['tool_calls'][0]['function'];
    expect(call['arguments'], '{"status":"pending"}');
    expect(msgs.last['tool_call_id'], 'call_1');
    repo.dispose();
  });

  test('Claude en directo: razonamiento y función intactos', () async {
    final repo = _repo();
    await AiSettings.instance.save(
        provider: AiProvider.claude, apiKey: 'k', model: 'claude-opus-5-5');
    final api = _FakeStream([
      [
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'thinking', 'thinking': ''}
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'sig-9'}
        },
        {'type': 'content_block_stop', 'index': 0},
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'list_tasks',
            'input': {}
          }
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': '{"status":"all"}'
          }
        },
        {'type': 'content_block_stop', 'index': 1},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'}
        },
      ],
      [
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''}
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Listo'}
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'}
        },
      ],
    ]);
    final s = AiSession(repo, transport: _noHttp, stream: api.call);
    await s.send('tareas');
    expect(s.messages.last.text, 'Listo');
    final msgs = api.sent[1]['messages'] as List;
    expect(jsonEncode(msgs[1]), contains('sig-9'));
    expect(msgs[1]['content'][1]['input'], {'status': 'all'});
    expect(msgs[2]['content'][0]['tool_use_id'], 'toolu_1');
    repo.dispose();
  });

  test('detener a mitad: conserva el texto y el historial sigue válido',
      () async {
    final repo = _repo();
    await AiSettings.instance
        .save(provider: AiProvider.openai, apiKey: 'k', model: 'gpt-5-mini');
    final events = StreamController<Map<String, dynamic>>();
    final sent = <Map<String, dynamic>>[];
    var calls = 0;
    Future<AiStreamResponse> api(
        Uri u, Map<String, String> h, Map<String, dynamic> b) async {
      sent.add(jsonDecode(jsonEncode(b)) as Map<String, dynamic>);
      if (calls++ == 0) return AiStreamResponse(200, const {}, events.stream);
      return AiStreamResponse(
          200,
          const {},
          Stream.value({
            'choices': [
              {
                'delta': {'content': 'Segunda'}
              }
            ]
          }));
    }

    final s = AiSession(repo, transport: _noHttp, stream: api);
    final pending = s.send('primera');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    events.add({
      'choices': [
        {
          'delta': {'content': 'A medias'}
        }
      ]
    });
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(s.streaming, 'A medias');
    s.cancel();
    await events.close();
    await pending;
    expect(s.messages.map((m) => m.text),
        ['primera', 'A medias', 'Respuesta detenida.']);

    await s.send('otra');
    expect(s.messages.last.text, 'Segunda');
    // La pregunta detenida no queda colgando en el historial.
    final msgs = sent[1]['messages'] as List;
    expect(msgs.where((m) => m['role'] == 'user').length, 1);
    repo.dispose();
  });

  test('detener mientras pide confirmación: no hace más cambios', () async {
    final repo = _repo();
    await AiSettings.instance
        .save(provider: AiProvider.openai, apiKey: 'k', model: 'gpt-5-mini');
    final ids = repo.notes.where((n) => !n.isEmpty).map((n) => n.id).toList();
    Map<String, dynamic> tool(int i, String id) => {
          'index': i,
          'id': 'call_$i',
          'function': {
            'name': 'set_pinned',
            'arguments': jsonEncode({'id': id, 'pinned': true})
          }
        };
    final notPinned = repo.notes.where((n) => !n.pinned && !n.isEmpty).first.id;
    final api = _FakeStream([
      [
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_a',
                    'function': {
                      'name': 'delete_note',
                      'arguments': jsonEncode({'id': ids.first})
                    }
                  },
                  tool(1, notPinned),
                ]
              }
            }
          ]
        }
      ],
    ]);
    final gate = Completer<bool>();
    final s = AiSession(repo, transport: _noHttp, stream: api.call)
      ..confirm = (_) => gate.future;
    final pending = s.send('borra y fija');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    s.cancel();
    gate.complete(false);
    await pending;
    expect(repo.byId(notPinned)!.pinned, isFalse);
    repo.dispose();
  });
}
