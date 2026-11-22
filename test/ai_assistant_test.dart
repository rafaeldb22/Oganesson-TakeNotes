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

  Future<(int, Map<String, dynamic>)> call(
      String method, Uri url, String key, Map<String, dynamic>? body) async {
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
    await AiSettings.instance.save(apiKey: 'AIza-prueba', model: 'm');
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
    final s = AiSession(repo, client: GeminiClient(transport: api.call));
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
    await AiSettings.instance.save(apiKey: 'AIza-prueba', model: 'm');
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
    final s = AiSession(repo, client: GeminiClient(transport: api.call));
    await s.send('hola');
    expect(s.messages.last.role, AiRole.error);
    expect(s.messages.last.text, contains('límite'));
    await s.send('hola otra vez');
    expect(s.messages.last.text, 'Hola');
    // La pregunta fallida no se reenvía.
    expect((api.sent[1]['contents'] as List).length, 1);
    repo.dispose();
  });

  testWidgets('el panel pide la clave y, con clave, propone ideas',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
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

    await AiSettings.instance.save(apiKey: 'AIza-prueba', model: 'm');
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
