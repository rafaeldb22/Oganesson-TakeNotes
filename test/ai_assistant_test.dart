import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/assistant_panel.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true
  ..seedDemo();

/// API de Gemini simulada: responde con las respuestas preparadas en orden
/// y guarda lo que se le envía.
class _FakeApi {
  _FakeApi(this.replies);
  final List<(int, Map<String, dynamic>)> replies;
  final sent = <Map<String, dynamic>>[];
  final urls = <Uri>[];
  final headers = <Map<String, String>>[];

  Future<(int, Map<String, dynamic>)> call(String method, Uri url,
      Map<String, String> h, Map<String, dynamic>? body) async {
    urls.add(url);
    headers.add(h);
    if (body != null) sent.add(jsonDecode(jsonEncode(body)));
    return replies.removeAt(0);
  }
}

Map<String, dynamic> _model(List<Map<String, dynamic>> parts) => {
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

  test('las herramientas nunca ven las notas del Vault', () async {
    final repo = _repo();
    final secret = repo.createNote();
    repo.updateContent(secret.id, 'Contraseñas del banco\n1234');
    repo.setVault(secret.id, true);
    final tools = AiTools(repo, confirm: (_) async => true);

    final list = await tools.run('list_notes', {});
    expect(jsonEncode(list), isNot(contains('banco')));
    final search = await tools.run('list_notes', {'query': 'banco'});
    expect(search['count'], 0);
    expect(
        (await tools.run('read_note', {'id': secret.id}))['error'], isNotNull);
    expect(
        (await tools
            .run('set_pinned', {'id': secret.id, 'pinned': true}))['error'],
        isNotNull);
    repo.dispose();
  });

  test('crear una nota con título, carpeta y fecha, y deshacerlo', () async {
    final repo = _repo();
    final tools = AiTools(repo, confirm: (_) async => true);
    final r = await tools.run('create_note', {
      'title': 'Dentista',
      'body': 'Llevar la tarjeta',
      'folder': 'Salud',
      'due': '2030-05-02T10:00',
    });
    final n = repo.byId(r['id'] as String)!;
    expect(n.title, 'Dentista');
    expect(n.content, 'Dentista\nLlevar la tarjeta');
    expect(n.rich, contains('"header":1'));
    expect(repo.folderById(n.folderId)!.name, 'Salud');
    expect(n.dueAt!.toLocal(), DateTime(2030, 5, 2, 10));
    expect(tools.actions.single.label, contains('Dentista'));

    tools.actions.single.undo!();
    expect(repo.byId(n.id)!.deleted, isTrue);
    repo.dispose();
  });

  test('archivar y borrar solo con confirmación; deshacer restaura', () async {
    final repo = _repo();
    final id = repo.notes.firstWhere((n) => !n.isEmpty).id;

    final no = AiTools(repo, confirm: (_) async => false);
    expect((await no.run('delete_note', {'id': id}))['ok'], false);
    expect(repo.byId(id)!.deleted, isFalse);

    final yes = AiTools(repo, confirm: (_) async => true);
    await yes.run('archive_note', {'id': id});
    expect(repo.byId(id)!.archived, isTrue);
    yes.actions.single.undo!();
    expect(repo.byId(id)!.archived, isFalse);
    repo.dispose();
  });

  test('tareas pendientes, poner fecha y marcar como hecha', () async {
    final repo = _repo();
    final tools = AiTools(repo, confirm: (_) async => true);
    final id = repo.notes.firstWhere((n) => !n.isTemporal && !n.isEmpty).id;
    await tools.run('set_dates', {'id': id, 'due': '2030-01-10T09:00'});
    final pending = await tools.run('list_tasks', {'status': 'pending'});
    expect(jsonEncode(pending), contains(id));
    await tools.run('set_done', {'id': id, 'done': true});
    expect(repo.byId(id)!.done, isTrue);
    repo.dispose();
  });

  test('conversación: la IA llama a una función y luego responde', () async {
    final repo = _repo();
    await AiSettings.instance
        .save(provider: AiProvider.gemini, apiKey: 'AIza-prueba', model: 'm');
    final api = _FakeApi([
      (
        200,
        _model([
          {
            'functionCall': {
              'name': 'list_tasks',
              'args': {'status': 'pending'}
            },
            'thoughtSignature': 'firma-123',
          }
        ])
      ),
      (
        200,
        _model([
          {'text': 'Tienes **2 tareas** pendientes.'}
        ])
      ),
    ]);
    final s = AiSession(repo, transport: api.call);
    await s.send('¿Qué tengo pendiente?');

    expect(s.messages.last.role, AiRole.assistant);
    expect(s.messages.last.text, 'Tienes **2 tareas** pendientes.');
    // La segunda petición devuelve la respuesta de la función y conserva la
    // firma de razonamiento del modelo.
    final second = jsonEncode(api.sent[1]);
    expect(second, contains('functionResponse'));
    expect(second, contains('firma-123'));
    expect(jsonEncode(api.sent[0]['tools']), contains('create_note'));
    repo.dispose();
  });

  test('límite de peticiones: mensaje claro y el historial no se rompe',
      () async {
    final repo = _repo();
    await AiSettings.instance
        .save(provider: AiProvider.gemini, apiKey: 'AIza-prueba', model: 'm');
    final api = _FakeApi([
      (
        429,
        {
          'error': {'status': 'RESOURCE_EXHAUSTED', 'message': 'quota'}
        }
      ),
      (
        200,
        _model([
          {'text': 'Hola'}
        ])
      ),
    ]);
    final s = AiSession(repo, transport: api.call);
    await s.send('hola');
    expect(s.messages.last.role, AiRole.error);
    expect(s.messages.last.text, contains('límite'));
    await s.send('hola otra vez');
    expect(s.messages.last.text, 'Hola');
    // La pregunta fallida no se reenvía.
    expect((api.sent[1]['contents'] as List).length, 1);
    repo.dispose();
  });

  test('ChatGPT: llama a una función y responde (formato de OpenAI)', () async {
    final repo = _repo();
    await AiSettings.instance.save(
        provider: AiProvider.openai, apiKey: 'sk-prueba', model: 'gpt-5-mini');
    final api = _FakeApi([
      (
        200,
        {
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'list_tasks',
                      'arguments': '{"status":"pending"}'
                    }
                  }
                ]
              }
            }
          ]
        }
      ),
      (
        200,
        {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Nada pendiente.'}
            }
          ]
        }
      ),
    ]);
    final s = AiSession(repo, transport: api.call);
    await s.send('¿Qué tengo pendiente?');
    expect(s.messages.last.text, 'Nada pendiente.');
    expect(api.urls.first.host, 'api.openai.com');
    expect(api.headers.first['Authorization'], 'Bearer sk-prueba');
    final second = api.sent[1];
    final msgs = second['messages'] as List;
    expect(msgs.first['role'], 'system');
    expect(msgs.last['role'], 'tool');
    expect(msgs.last['tool_call_id'], 'call_1');
    // Esquema JSON estándar (tipos en minúsculas).
    expect(jsonEncode(second['tools']), contains('"type":"object"'));
    repo.dispose();
  });

  test('Claude: bloques sin cambios y respuestas de funciones juntas',
      () async {
    final repo = _repo();
    await AiSettings.instance.save(
        provider: AiProvider.claude,
        apiKey: 'sk-ant-prueba',
        model: 'claude-opus-5-5');
    final api = _FakeApi([
      (
        200,
        {
          'stop_reason': 'tool_use',
          'content': [
            {'type': 'thinking', 'thinking': '', 'signature': 'sig-1'},
            {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'list_tasks',
              'input': {'status': 'pending'}
            },
            {
              'type': 'tool_use',
              'id': 'toolu_2',
              'name': 'list_folders',
              'input': {}
            },
          ]
        }
      ),
      (
        200,
        {
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': 'Tienes 2 carpetas.'}
          ]
        }
      ),
    ]);
    final s = AiSession(repo, transport: api.call);
    await s.send('¿Qué carpetas tengo?');
    expect(s.messages.last.text, 'Tienes 2 carpetas.');
    expect(api.urls.first.toString(), 'https://api.anthropic.com/v1/messages');
    expect(api.headers.first['x-api-key'], 'sk-ant-prueba');
    expect(api.headers.first['anthropic-version'], '2026-10-21');
    final first = api.sent[0];
    expect(first['model'], 'claude-opus-5-5');
    expect(first['fallbacks'], 'default');
    expect(first.containsKey('temperature'), isFalse);
    final msgs = api.sent[1]['messages'] as List;
    // El turno del asistente vuelve tal cual (con su bloque de razonamiento).
    expect(jsonEncode(msgs[1]), contains('sig-1'));
    // Las dos respuestas, en UN solo mensaje del usuario.
    final results = (msgs[2]['content'] as List);
    expect(results.length, 2);
    expect(results.every((b) => b['type'] == 'tool_result'), isTrue);
    repo.dispose();
  });

  test('Claude: sin saldo lo explica y no prueba otros modelos', () async {
    final api = _FakeApi([
      (
        400,
        {
          'type': 'error',
          'error': {
            'type': 'invalid_request_error',
            'message': 'Your credit balance is too low to access the '
                'Anthropic API.'
          }
        }
      ),
    ]);
    try {
      await ClaudeClient(transport: api.call)
          .findWorkingModel('k', 'claude-opus-5-5');
      fail('debía fallar');
    } on AiException catch (e) {
      expect(e.message, contains('no tiene saldo'));
    }
    expect(api.sent.length, 1);
  });

  group('mejoras del asistente', () {
    Map<String, dynamic> text(String t) => _model([
          {'text': t}
        ]);

    test('instrucciones fijas (caché) y contexto en cada pregunta', () async {
      final repo = _repo();
      await AiSettings.instance
          .save(provider: AiProvider.gemini, apiKey: 'k', model: 'm');
      final api = _FakeApi([(200, text('a')), (200, text('b'))]);
      final s = AiSession(repo, transport: api.call);
      await s.send('hola');
      await s.send('¿y mañana?');
      // El inicio de la petición es idéntico: los proveedores lo cachean.
      expect(jsonEncode(api.sent[0]['systemInstruction']),
          jsonEncode(api.sent[1]['systemInstruction']));
      // Ni fecha ni hora en las instrucciones (cambiarían en cada pregunta).
      expect(jsonEncode(api.sent[0]['systemInstruction']),
          isNot(contains('Ahora:')));
      // La fecha y las carpetas van con cada pregunta.
      final last = (api.sent[1]['contents'] as List).last;
      expect(jsonEncode(last), contains('<contexto>'));
      expect(jsonEncode(last), contains('Clase'));
      // El chat solo enseña lo que escribió el usuario.
      expect(s.messages[2].text, '¿y mañana?');
      repo.dispose();
    });

    test('Claude: caché automática y esfuerzo bajo', () async {
      final repo = _repo();
      await AiSettings.instance.save(
          provider: AiProvider.claude, apiKey: 'k', model: 'claude-opus-5-5');
      final api = _FakeApi([
        (
          200,
          {
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'Hola'}
            ]
          }
        )
      ]);
      await AiSession(repo, transport: api.call).send('hola');
      expect(api.sent.single['cache_control'], {'type': 'ephemeral'});
      expect(api.sent.single['output_config'], {'effort': 'low'});
      repo.dispose();
    });

    test('servicio saturado: reintenta solo y responde', () async {
      final repo = _repo();
      await AiSettings.instance.save(
          provider: AiProvider.claude, apiKey: 'k', model: 'claude-opus-5-5');
      final api = _FakeApi([
        (
          529,
          {
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Overloaded'}
          }
        ),
        (
          200,
          {
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'Ya está'}
            ]
          }
        ),
      ]);
      final s = AiSession(repo, transport: api.call)
        ..retryDelay = (_, __) => Duration.zero;
      await s.send('hola');
      expect(s.messages.last.text, 'Ya está');
      expect(api.sent.length, 2);
      repo.dispose();
    });

    test('detener: la respuesta que llega tarde se ignora', () async {
      final repo = _repo();
      await AiSettings.instance
          .save(provider: AiProvider.gemini, apiKey: 'k', model: 'm');
      final gate = Completer<void>();
      Future<(int, Map<String, dynamic>)> slow(String m, Uri u,
          Map<String, String> h, Map<String, dynamic>? b) async {
        await gate.future;
        return (200, text('tarde'));
      }

      final s = AiSession(repo, transport: slow);
      final pending = s.send('hola');
      await Future<void>.delayed(Duration.zero);
      expect(s.busy, isTrue);
      s.cancel();
      expect(s.busy, isFalse);
      gate.complete();
      await pending;
      expect(s.messages.map((m) => m.text), isNot(contains('tarde')));
      expect(s.messages.last.text, 'Respuesta detenida.');
      repo.dispose();
    });

    test('al abrir la app empieza otra; la anterior queda en el historial',
        () async {
      final repo = _repo();
      await AiSettings.instance
          .save(provider: AiProvider.gemini, apiKey: 'k', model: 'm');
      final api = _FakeApi([(200, text('Respuesta guardada'))]);
      await AiSession(repo, transport: api.call).send('hola');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final again = AiSession(repo);
      await again.load();
      expect(again.messages, isEmpty);
      expect(again.past.single['title'], 'hola');
      again.restore(0);
      expect(again.messages.map((m) => m.text), ['hola', 'Respuesta guardada']);
      expect(again.past, isEmpty);
      // Nueva conversación: la actual vuelve al historial (máximo 3).
      again.clear();
      expect(again.past, hasLength(1));
      repo.dispose();
    });

    test('reintentar la última pregunta tras un error', () async {
      final repo = _repo();
      await AiSettings.instance
          .save(provider: AiProvider.gemini, apiKey: 'k', model: 'm');
      final api = _FakeApi([
        (
          400,
          {
            'error': {'code': 400, 'message': 'algo raro'}
          }
        ),
        (200, text('Ahora sí')),
      ]);
      final s = AiSession(repo, transport: api.call);
      await s.send('hola');
      expect(s.messages.last.role, AiRole.error);
      await s.retryLast();
      expect(s.messages.map((m) => m.text).toList(), ['hola', 'Ahora sí']);
      repo.dispose();
    });

    test('color y enlaces', () async {
      final repo = _repo();
      final tools = AiTools(repo, confirm: (_) async => true);
      final ids = repo.notes.where((n) => !n.isEmpty).map((n) => n.id).toList();
      await tools.run('set_color', {'id': ids[0], 'color': 'azul'});
      expect(repo.byId(ids[0])!.color, isNotNull);
      tools.actions.last.undo!();
      expect(repo.byId(ids[0])!.color, isNull);
      final r = await tools.run('link_notes', {
        'id': ids[0],
        'targets': [ids[1], 'no-existe'],
      });
      expect(r['linked'], 1);
      expect(repo.byId(ids[0])!.links, contains(ids[1]));
      final listed = await tools.run('list_notes', {'query': 'huevos'});
      expect(jsonEncode(listed), contains('snippet'));
      repo.dispose();
    });
  });

  group('errores 429 y elección de modelo', () {
    Map<String, dynamic> quota(String message, {String? retry}) => {
          'error': {
            'code': 429,
            'status': 'RESOURCE_EXHAUSTED',
            'message': message,
            if (retry != null)
              'details': [
                {
                  '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                  'retryDelay': retry,
                }
              ],
          }
        };

    test('modelo sin cuota gratis (limit: 0): lo dice y nombra el modelo',
        () async {
      final api = _FakeApi([
        (
          429,
          quota('You exceeded your current quota. Quota exceeded for metric: '
              'generate_content_free_tier_requests, limit: 0, model: x')
        )
      ]);
      final c = GeminiClient(transport: api.call);
      try {
        await c.check('k', 'gemini-x');
        fail('debía fallar');
      } on AiException catch (e) {
        expect(e.message, contains('gemini-x'));
        expect(e.message, contains('Google dice'));
        expect(e.modelSpecific, isTrue);
      }
    });

    test('límite por minuto: dice cuántos segundos esperar', () async {
      final api = _FakeApi(
          [(429, quota('Resource has been exhausted.', retry: '33.4s'))]);
      try {
        await GeminiClient(transport: api.call).check('k', 'm');
        fail('debía fallar');
      } on AiException catch (e) {
        expect(e.message, contains('34 s'));
      }
    });

    test('si el modelo elegido no tiene cuota, se usa otro que funcione',
        () async {
      final api = _FakeApi([
        (429, quota('Quota exceeded, limit: 0, model: a')),
        (
          404,
          {
            'error': {'code': 404, 'message': 'not found'}
          }
        ),
        (
          200,
          _model([
            {'text': 'ok'}
          ])
        ),
      ]);
      final m = await GeminiClient(transport: api.call)
          .findWorkingModel('k', 'elegido');
      expect(m, AiSettings.fallbackModels[1]);
      expect(api.sent.length, 3);
    });

    test(
        'proyecto de prepago sin créditos (402): lo explica y no prueba '
        'otros modelos', () async {
      // Respuesta real de Google para una clave de un proyecto con
      // facturación de prepago agotada.
      final api = _FakeApi([
        (
          402,
          {
            'error': {
              'code': 402,
              'status': 'RESOURCE_EXHAUSTED',
              'message': 'Your prepayment credits are depleted. Please go to '
                  'AI Studio at https://ai.studio/projects to manage your '
                  'project and billing.'
            }
          }
        ),
      ]);
      try {
        await GeminiClient(transport: api.call).findWorkingModel('k', 'm');
        fail('debía fallar');
      } on AiException catch (e) {
        expect(e.message, contains('prepago'));
        expect(e.message, contains('SIN facturación'));
        expect(e.modelSpecific, isFalse);
      }
      expect(api.sent.length, 1);
    });

    test('clave inválida: no sigue probando modelos', () async {
      final api = _FakeApi([
        (
          400,
          {
            'error': {
              'code': 400,
              'status': 'INVALID_ARGUMENT',
              'message': 'API key not valid. Please pass a valid API key.'
            }
          }
        ),
      ]);
      try {
        await GeminiClient(transport: api.call).findWorkingModel('k', 'm');
        fail('debía fallar');
      } on AiException catch (e) {
        expect(e.message, contains('clave no es válida'));
      }
      expect(api.sent.length, 1);
    });
  });

  testWidgets('el panel pide la clave y, con clave, propone ideas',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
    AiSettings.instance.provider = AiProvider.gemini;
    await AiSettings.instance.forget();
    final session = AiSession(repo);
    Widget app() => MaterialApp(
          theme: buildTheme(themeById(''), Brightness.dark),
          home: Scaffold(
            body: AssistantPanel(
                session: session, onOpenNote: (_) {}, onClose: () {}),
          ),
        );
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Abrir Google AI Studio'), findsOneWidget);
    expect(find.text('Probar y guardar', skipOffstage: false), findsOneWidget);

    await AiSettings.instance
        .save(provider: AiProvider.gemini, apiKey: 'AIza-prueba', model: 'm');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('¿En qué te ayudo?'), findsOneWidget);
    expect(find.text('¿Qué tengo pendiente esta semana?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
