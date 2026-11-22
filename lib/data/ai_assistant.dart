import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart' show Attribute, Document;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../ui/i18n.dart';
import 'notes_repository.dart';

// ===================================================================
// Ajustes: cada usuario usa SU clave de la API de Gemini.
// ===================================================================

/// Modelo de Gemini que se puede elegir en los ajustes.
class AiModel {
  const AiModel(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;
}

/// Ajustes del asistente. La clave se guarda cifrada y SOLO en este
/// dispositivo (nunca se sube a Supabase).
class AiSettings extends ChangeNotifier {
  AiSettings._();
  static final instance = AiSettings._();

  static const models = [
    AiModel('gemini-3.5-flash-lite', 'Gemini Flash-Lite',
        'Rápido y con más peticiones gratis al día'),
    AiModel('gemini-3.8-flash', 'Gemini Flash',
        'Más listo, pero con pocas peticiones gratis al día'),
  ];

  static const _kKey = 'gemini_api_key';
  static const _kModel = 'gemini_model';
  static const _storage = FlutterSecureStorage();

  String? _apiKey;
  String model = models.first.id;
  bool loaded = false;

  String? get apiKey => _apiKey;
  bool get configured => (_apiKey ?? '').isNotEmpty;

  Future<void> load() async {
    if (loaded) return;
    try {
      _apiKey = await _storage.read(key: _kKey);
    } catch (e) {
      debugPrint('IA: no se pudo leer la clave ($e)');
    }
    try {
      final p = await SharedPreferences.getInstance();
      model = p.getString(_kModel) ?? model;
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  Future<void> save({required String apiKey, required String model}) async {
    _apiKey = apiKey.trim();
    this.model = model.trim();
    await _storage.write(key: _kKey, value: _apiKey);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kModel, this.model);
    notifyListeners();
  }

  Future<void> forget() async {
    _apiKey = null;
    try {
      await _storage.delete(key: _kKey);
    } catch (_) {}
    notifyListeners();
  }
}

// ===================================================================
// Cliente de la API de Gemini (REST, con llamada a funciones).
// ===================================================================

/// Error de la API explicado para el usuario.
class AiException implements Exception {
  AiException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

/// Envía una petición POST/GET y devuelve (código, cuerpo JSON). Se puede
/// sustituir en los tests.
typedef AiTransport = Future<(int, Map<String, dynamic>)> Function(
    String method, Uri url, String apiKey, Map<String, dynamic>? body);

Future<(int, Map<String, dynamic>)> _httpTransport(
    String method, Uri url, String apiKey, Map<String, dynamic>? body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.openUrl(method, url);
    req.headers
      ..set('x-goog-api-key', apiKey)
      ..contentType = ContentType.json;
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(const Duration(seconds: 90));
    final text = await res.transform(utf8.decoder).join();
    Map<String, dynamic> json = {};
    try {
      final d = jsonDecode(text);
      if (d is Map<String, dynamic>) json = d;
    } catch (_) {}
    return (res.statusCode, json);
  } finally {
    client.close();
  }
}

class GeminiClient {
  GeminiClient({AiTransport? transport})
      : _transport = transport ?? _httpTransport;
  final AiTransport _transport;

  static final _base =
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/');

  /// Comprueba que la clave y el modelo existen (sin gastar una petición de
  /// generación).
  Future<void> check(String apiKey, String model) async {
    final (code, json) =
        await _call('GET', _base.resolve('models/$model'), apiKey, null);
    if (code != 200) throw _error(code, json);
  }

  Future<Map<String, dynamic>> generate({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> contents,
    required String system,
    required List<Map<String, dynamic>> functions,
  }) async {
    final (code, json) = await _call(
      'POST',
      _base.resolve('models/$model:generateContent'),
      apiKey,
      {
        'systemInstruction': {
          'parts': [
            {'text': system}
          ]
        },
        'contents': contents,
        'tools': [
          {'functionDeclarations': functions}
        ],
      },
    );
    if (code != 200) throw _error(code, json);
    return json;
  }

  Future<(int, Map<String, dynamic>)> _call(
      String method, Uri url, String apiKey, Map<String, dynamic>? body) async {
    try {
      return await _transport(method, url, apiKey, body);
    } on SocketException {
      throw AiException(tr('Sin conexión. Revisa internet y vuelve a probar.'));
    } on TimeoutException {
      throw AiException(tr('La IA ha tardado demasiado. Vuelve a probar.'));
    } on HandshakeException {
      throw AiException(tr('Sin conexión. Revisa internet y vuelve a probar.'));
    }
  }

  static AiException _error(int code, Map<String, dynamic> json) {
    final err = json['error'];
    final msg = err is Map ? '${err['message'] ?? ''}' : '';
    final status = err is Map ? '${err['status'] ?? ''}' : '';
    if (code == 429 || status == 'RESOURCE_EXHAUSTED') {
      return AiException(
          tr('Has llegado al límite de peticiones gratis de tu clave. '
              'El límite diario se reinicia a medianoche (hora del Pacífico, '
              'las 9:00 en España). Prueba más tarde o cambia al modelo '
              'Flash-Lite en los ajustes.'),
          code: 429);
    }
    if (msg.contains('API key not valid') ||
        msg.contains('API_KEY_INVALID') ||
        code == 401) {
      return AiException(tr('La clave no es válida. Revísala en los ajustes.'),
          code: code);
    }
    if (code == 404) {
      return AiException(
          tr('Ese modelo no existe o tu clave no tiene acceso. Elige otro en '
              'los ajustes.'),
          code: code);
    }
    if (code == 403) {
      return AiException(
          tr('Tu clave no tiene permiso para usar la API de Gemini.'),
          code: code);
    }
    return AiException(
        trf('La IA respondió con un error ({0}). {1}', [code, msg]).trim(),
        code: code);
  }
}

// ===================================================================
// Herramientas: lo que la IA puede hacer con las notas.
// ===================================================================

/// Algo que ha hecho la IA (se ve en el chat, con Abrir / Deshacer).
class AiAction {
  AiAction({
    required this.icon,
    required this.label,
    this.noteId,
    this.undo,
  });

  /// Nombre del icono (ver el panel).
  final String icon;
  final String label;
  final String? noteId;
  VoidCallback? undo;
  bool undone = false;
}

/// Pide confirmación al usuario (archivar, borrar).
typedef AiConfirm = Future<bool> Function(String question);

/// Ejecuta las funciones que pide la IA sobre el repositorio. Las notas del
/// Vault no existen para el asistente: `repo.notes` nunca las contiene.
class AiTools {
  AiTools(this.repo, {required this.confirm});
  final NotesRepository repo;
  final AiConfirm confirm;

  /// Acciones de la última respuesta (para enseñarlas en el chat).
  final List<AiAction> actions = [];

  static Map<String, dynamic> _obj(Map<String, dynamic> props,
          [List<String> required = const []]) =>
      {
        'type': 'OBJECT',
        'properties': props,
        if (required.isNotEmpty) 'required': required,
      };
  static Map<String, dynamic> _s(String d, {List<String>? enumValues}) => {
        'type': 'STRING',
        'description': d,
        if (enumValues != null) 'enum': enumValues,
      };

  static final declarations = <Map<String, dynamic>>[
    {
      'name': 'list_notes',
      'description': 'Lista las notas del usuario (nunca las del Vault). '
          'Opcionalmente filtra por texto o carpeta.',
      'parameters': _obj({
        'query': _s('Texto a buscar en las notas (opcional).'),
        'folder': _s('Nombre de la carpeta (opcional).'),
        'limit': {'type': 'INTEGER', 'description': 'Máximo (por defecto 30).'},
      }),
    },
    {
      'name': 'read_note',
      'description': 'Lee el texto completo de una nota por su id.',
      'parameters': _obj({'id': _s('Id de la nota.')}, ['id']),
    },
    {
      'name': 'list_tasks',
      'description': 'Lista las tareas (notas con fecha límite) con su '
          'inicio, fecha límite y estado.',
      'parameters': _obj({
        'status': _s('Qué tareas.',
            enumValues: ['pending', 'overdue', 'done', 'all']),
      }),
    },
    {
      'name': 'list_folders',
      // Sin parámetros: Gemini no acepta un objeto vacío.
      'description': 'Lista las carpetas y cuántas notas tiene cada una.',
    },
    {
      'name': 'create_note',
      'description': 'Crea una nota. La primera línea es el título. Si tiene '
          'fecha límite, es una tarea.',
      'parameters': _obj({
        'title': _s('Título de la nota.'),
        'body': _s('Texto de la nota, debajo del título (opcional).'),
        'folder': _s('Carpeta (se crea si no existe, opcional).'),
        'due': _s('Fecha límite, ISO 8601 en hora local, p. ej. '
            '2026-11-28T20:00 (opcional).'),
        'start': _s('Inicio del periodo de la tarea, ISO 8601 (opcional).'),
        'pinned': {'type': 'BOOLEAN', 'description': 'Fijarla arriba.'},
      }, [
        'title'
      ]),
    },
    {
      'name': 'append_to_note',
      'description': 'Añade texto al final de una nota existente.',
      'parameters': _obj({
        'id': _s('Id de la nota.'),
        'text': _s('Texto a añadir.'),
      }, [
        'id',
        'text'
      ]),
    },
    {
      'name': 'set_dates',
      'description': 'Pone, cambia o quita la fecha límite y el inicio de una '
          'nota (con fecha límite pasa a ser una tarea).',
      'parameters': _obj({
        'id': _s('Id de la nota.'),
        'due': _s('Fecha límite ISO 8601 en hora local.'),
        'start': _s('Inicio ISO 8601 en hora local (opcional).'),
        'clear': {
          'type': 'BOOLEAN',
          'description': 'true para quitar las fechas.'
        },
      }, [
        'id'
      ]),
    },
    {
      'name': 'set_done',
      'description': 'Marca una tarea como hecha o pendiente.',
      'parameters': _obj({
        'id': _s('Id de la nota.'),
        'done': {'type': 'BOOLEAN', 'description': 'Hecha (true) o no.'},
      }, [
        'id',
        'done'
      ]),
    },
    {
      'name': 'move_to_folder',
      'description': 'Mueve una nota a una carpeta (se crea si no existe). '
          'Carpeta vacía = sin carpeta.',
      'parameters': _obj({
        'id': _s('Id de la nota.'),
        'folder': _s('Nombre de la carpeta.'),
      }, [
        'id',
        'folder'
      ]),
    },
    {
      'name': 'set_pinned',
      'description': 'Fija o desfija una nota arriba de la lista.',
      'parameters': _obj({
        'id': _s('Id de la nota.'),
        'pinned': {'type': 'BOOLEAN', 'description': 'Fijada o no.'},
      }, [
        'id',
        'pinned'
      ]),
    },
    {
      'name': 'archive_note',
      'description': 'Archiva una nota (el usuario debe confirmarlo).',
      'parameters': _obj({'id': _s('Id de la nota.')}, ['id']),
    },
    {
      'name': 'delete_note',
      'description': 'Mueve una nota a la papelera (el usuario debe '
          'confirmarlo; se puede recuperar 3 días).',
      'parameters': _obj({'id': _s('Id de la nota.')}, ['id']),
    },
  ];

  // ----------------------------------------------------------- utilidades

  Note? _note(Object? id) {
    final n = repo.byId('$id');
    // Fuera del alcance: borradas, archivadas o del Vault.
    if (n == null || n.deleted || n.vault) return null;
    return n;
  }

  static String _iso(DateTime? d) =>
      d == null ? '' : d.toLocal().toIso8601String().substring(0, 16);

  static DateTime? _date(Object? v) {
    if (v is! String || v.trim().isEmpty) return null;
    return DateTime.tryParse(v.trim());
  }

  String _folderName(String? id) => repo.folderById(id)?.name ?? '';

  String? _folderId(String name, {bool create = true}) {
    final n = name.trim();
    if (n.isEmpty) return null;
    for (final f in repo.folders) {
      if (f.name.toLowerCase() == n.toLowerCase()) return f.id;
    }
    return create ? repo.createFolder(n).id : null;
  }

  Map<String, dynamic> _summary(Note n) => {
        'id': n.id,
        'title': n.title,
        'preview': n.hasPreview ? n.preview : '',
        if (n.folderId != null) 'folder': _folderName(n.folderId),
        if (n.pinned) 'pinned': true,
        'updated': _iso(n.updatedAt),
        if (n.dueAt != null) 'due': _iso(n.dueAt),
        if (n.remindAt != null && n.dueAt != null) 'start': _iso(n.remindAt),
        if (n.dueAt != null) 'done': n.done,
        if (n.hasImages) 'has_images': true,
      };

  /// Copia del estado de una nota (para Deshacer).
  static Note _snapshot(Note n) => Note(
        id: n.id,
        content: n.content,
        rich: n.rich,
        createdAt: n.createdAt,
        updatedAt: n.updatedAt,
        folderId: n.folderId,
        remindAt: n.remindAt,
        dueAt: n.dueAt,
        done: n.done,
        color: n.color,
        pinned: n.pinned,
        deleted: n.deleted,
        archived: n.archived,
        doneAt: n.doneAt,
        links: List.of(n.links),
      );

  void _record(String icon, String label, Note before, {String? noteId}) {
    final snap = _snapshot(before);
    actions.add(AiAction(
      icon: icon,
      label: label,
      noteId: noteId ?? before.id,
      undo: () => repo.restoreState(snap),
    ));
  }

  // ------------------------------------------------------------ ejecutar

  /// Ejecuta una función pedida por la IA y devuelve la respuesta para ella.
  Future<Map<String, dynamic>> run(
      String name, Map<String, dynamic> args) async {
    try {
      return await _run(name, args);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> _run(String name, Map<String, dynamic> a) async {
    switch (name) {
      case 'list_notes':
        final q = '${a['query'] ?? ''}'.toLowerCase().trim();
        final folder = '${a['folder'] ?? ''}'.trim();
        final fid = folder.isEmpty ? null : _folderId(folder, create: false);
        if (folder.isNotEmpty && fid == null) {
          return {'notes': [], 'note': 'No existe la carpeta "$folder".'};
        }
        final limit = (a['limit'] is num ? (a['limit'] as num).toInt() : 30)
            .clamp(1, 100);
        final list = repo.notes
            .where((n) => !n.isEmpty)
            .where((n) => q.isEmpty || n.content.toLowerCase().contains(q))
            .where((n) => fid == null || n.folderId == fid)
            .take(limit)
            .map(_summary)
            .toList();
        return {'count': list.length, 'notes': list};

      case 'read_note':
        final n = _note(a['id']);
        if (n == null) return {'error': 'No existe esa nota.'};
        final text = n.content.replaceAll('￼', '[imagen]');
        return {
          ..._summary(n),
          'text': text.length > 6000 ? '${text.substring(0, 6000)}…' : text,
        };

      case 'list_tasks':
        final status = '${a['status'] ?? 'pending'}';
        final now = DateTime.now().toUtc();
        final all = [
          ...repo.temporales,
          ...repo.completed.where((n) => n.isTemporal),
        ];
        final list = all
            .where((n) => switch (status) {
                  'pending' => !n.done,
                  'overdue' => !n.done && n.dueAt!.isBefore(now),
                  'done' => n.done,
                  _ => true,
                })
            .map(_summary)
            .toList();
        return {'count': list.length, 'tasks': list};

      case 'list_folders':
        return {
          'folders': [
            for (final f in repo.folders)
              {'name': f.name, 'notes': repo.countIn(f.id)},
          ],
        };

      case 'create_note':
        final title = '${a['title'] ?? ''}'.trim();
        if (title.isEmpty) return {'error': 'Falta el título.'};
        final body = '${a['body'] ?? ''}'.trim();
        final due = _date(a['due']);
        final start = _date(a['start']);
        final folder = '${a['folder'] ?? ''}'.trim();
        final n = repo.createNote(
          folderId: folder.isEmpty ? null : _folderId(folder),
          dueAt: due?.toUtc(),
          remindAt: due == null
              ? null
              : (start ?? DateTime.now()).toUtc().isBefore(due.toUtc())
                  ? (start ?? DateTime.now()).toUtc()
                  : due.toUtc(),
        );
        final doc = Document()..insert(0, title);
        doc.format(0, title.length, Attribute.h1);
        if (body.isNotEmpty) doc.insert(title.length, '\n$body');
        final plain = doc.toPlainText();
        repo.updateContent(
          n.id,
          plain.endsWith('\n') ? plain.substring(0, plain.length - 1) : plain,
          rich: jsonEncode(doc.toDelta().toJson()),
        );
        if (a['pinned'] == true) repo.togglePin(n.id);
        actions.add(AiAction(
          icon: 'note_add',
          label: trf('Nota creada: {0}', [title]),
          noteId: n.id,
          undo: () => repo.delete(n.id),
        ));
        return {'ok': true, 'id': n.id, 'title': title};

      case 'append_to_note':
        final n = _note(a['id']);
        if (n == null) return {'error': 'No existe esa nota.'};
        final text = '${a['text'] ?? ''}';
        if (text.trim().isEmpty) return {'error': 'Falta el texto.'};
        _record('edit', trf('Texto añadido a «{0}»', [n.title]), n);
        Document doc;
        try {
          doc = n.rich == null
              ? (Document()..insert(0, n.content))
              : Document.fromJson(jsonDecode(n.rich!) as List);
        } catch (_) {
          doc = Document()..insert(0, n.content);
        }
        doc.insert(doc.length - 1, '\n$text');
        final plain = doc.toPlainText();
        repo.updateContent(
          n.id,
          plain.endsWith('\n') ? plain.substring(0, plain.length - 1) : plain,
          rich: jsonEncode(doc.toDelta().toJson()),
        );
        return {'ok': true};

      case 'set_dates':
        final n = _note(a['id']);
        if (n == null) return {'error': 'No existe esa nota.'};
        if (a['clear'] == true) {
          _record('event_busy', trf('Fechas quitadas de «{0}»', [n.title]), n);
          repo.setSchedule(n.id);
          return {'ok': true};
        }
        final due = _date(a['due']);
        if (due == null) return {'error': 'Falta una fecha límite válida.'};
        final start = _date(a['start']) ?? n.remindAt?.toLocal();
        _record(
            'alarm',
            trf('Fecha límite de «{0}»: {1}', [n.title, _iso(due)])
                .replaceAll('T', ' '),
            n);
        repo.setSchedule(n.id,
            dueAt: due,
            remindAt: start == null || !start.isBefore(due)
                ? (DateTime.now().isBefore(due) ? DateTime.now() : due)
                : start);
        return {'ok': true};

      case 'set_done':
        final n = _note(a['id']);
        if (n == null) return {'error': 'No existe esa nota.'};
        if (!n.isTemporal) return {'error': 'Esa nota no es una tarea.'};
        final done = a['done'] == true;
        if (n.done != done) {
          _record(
              'task_alt',
              done
                  ? trf('Tarea hecha: {0}', [n.title])
                  : trf('Tarea pendiente: {0}', [n.title]),
              n);
          repo.toggleDone(n.id);
        }
        return {'ok': true};

      case 'move_to_folder':
        final n = _note(a['id']);
        if (n == null) return {'error': 'No existe esa nota.'};
        final folder = '${a['folder'] ?? ''}'.trim();
        _record(
            'folder',
            folder.isEmpty
                ? trf('«{0}» sin carpeta', [n.title])
                : trf('«{0}» movida a {1}', [n.title, folder]),
            n);
        repo.moveToFolder(n.id, folder.isEmpty ? null : _folderId(folder));
        return {'ok': true};

      case 'set_pinned':
        final n = _note(a['id']);
        if (n == null) return {'error': 'No existe esa nota.'};
        final pinned = a['pinned'] == true;
        if (n.pinned != pinned) {
          _record(
              'push_pin',
              pinned
                  ? trf('Fijada: {0}', [n.title])
                  : trf('Desfijada: {0}', [n.title]),
              n);
          repo.togglePin(n.id);
        }
        return {'ok': true};

      case 'archive_note':
      case 'delete_note':
        final n = _note(a['id']);
        if (n == null) return {'error': 'No existe esa nota.'};
        final archive = name == 'archive_note';
        final ok = await confirm(archive
            ? trf('La IA quiere archivar «{0}». ¿Archivarla?', [n.title])
            : trf('La IA quiere mover «{0}» a la papelera. ¿Eliminarla?',
                [n.title]));
        if (!ok) {
          return {'ok': false, 'reason': 'El usuario no lo ha permitido.'};
        }
        _record(
            archive ? 'archive' : 'delete',
            archive
                ? trf('Archivada: {0}', [n.title])
                : trf('A la papelera: {0}', [n.title]),
            n);
        archive ? repo.setArchived(n.id, true) : repo.delete(n.id);
        return {'ok': true};
    }
    return {'error': 'Función desconocida: $name'};
  }
}

// ===================================================================
// Conversación.
// ===================================================================

enum AiRole { user, assistant, error }

class AiMessage {
  AiMessage(this.role, this.text, {List<AiAction>? actions})
      : actions = actions ?? [];
  final AiRole role;
  final String text;
  final List<AiAction> actions;
}

/// Conversación con el asistente (se mantiene mientras la app está abierta).
class AiSession extends ChangeNotifier {
  AiSession(this.repo, {GeminiClient? client, AiSettings? settings})
      : client = client ?? GeminiClient(),
        settings = settings ?? AiSettings.instance;

  final NotesRepository repo;
  final GeminiClient client;
  final AiSettings settings;

  final List<AiMessage> messages = [];

  /// Historial en el formato de la API (las respuestas del modelo se guardan
  /// tal cual: Gemini necesita recibir de vuelta sus firmas de razonamiento).
  final List<Map<String, dynamic>> _contents = [];
  bool busy = false;

  /// Qué está haciendo ahora (p. ej. "Buscando tareas…").
  String? activity;

  /// La pone el panel para pedir confirmaciones.
  AiConfirm confirm = (_) async => false;

  static const _maxSteps = 8;

  void clear() {
    messages.clear();
    _contents.clear();
    notifyListeners();
  }

  String _system() {
    final now = DateTime.now();
    final off = now.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final hh = off.inHours.abs().toString().padLeft(2, '0');
    final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final english = appLanguage.code == 'en';
    const days = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo'
    ];
    return '''
Eres el asistente de Oganesson TakeNotes, una app de notas y tareas.
Ahora es ${now.toIso8601String().substring(0, 16)} (${days[now.weekday - 1]}), zona horaria UTC$sign$hh:$mm.
Responde SIEMPRE en ${english ? 'inglés' : 'español'}, de forma breve, clara y amable.
- Usa las funciones para consultar y cambiar notas y tareas. No inventes ids: búscalos con list_notes o list_tasks.
- Las fechas que envíes van en ISO 8601 en hora local (sin zona). Calcula "mañana", "el viernes"… a partir de la fecha de arriba.
- Una tarea es una nota con fecha límite ("due"); "start" es el inicio de su periodo.
- Las notas del Vault son privadas: no puedes verlas ni cambiarlas. Si te preguntan por ellas, dilo.
- Para archivar o borrar, la app pide confirmación al usuario.
- Cuando cambies algo, dilo en una frase. Usa listas cortas con guiones cuando ayuden.
''';
  }

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || busy) return;
    await settings.load();
    if (!settings.configured) {
      messages
          .add(AiMessage(AiRole.error, tr('Primero pon tu clave de Gemini.')));
      notifyListeners();
      return;
    }
    messages.add(AiMessage(AiRole.user, t));
    final start = _contents.length;
    _contents.add({
      'role': 'user',
      'parts': [
        {'text': t}
      ],
    });
    busy = true;
    activity = tr('Pensando…');
    notifyListeners();

    final tools = AiTools(repo, confirm: confirm);
    final reply = StringBuffer();
    try {
      for (var step = 0; step < _maxSteps; step++) {
        final res = await client.generate(
          apiKey: settings.apiKey!,
          model: settings.model,
          contents: _contents,
          system: _system(),
          functions: AiTools.declarations,
        );
        final cands = res['candidates'];
        final content = cands is List && cands.isNotEmpty
            ? (cands.first as Map)['content']
            : null;
        if (content is! Map) {
          final reason = res['promptFeedback'] is Map
              ? '${(res['promptFeedback'] as Map)['blockReason'] ?? ''}'
              : '';
          throw AiException(reason.isEmpty
              ? tr('La IA no ha devuelto respuesta. Vuelve a probar.')
              : tr('La IA no ha querido responder a eso.'));
        }
        final modelContent = Map<String, dynamic>.from(content)
          ..['role'] = 'model';
        _contents.add(modelContent);
        final parts = (modelContent['parts'] as List?) ?? const [];
        final calls = <Map>[];
        for (final p in parts) {
          if (p is! Map) continue;
          if (p['functionCall'] is Map) {
            calls.add(p['functionCall'] as Map);
          } else if (p['text'] is String && p['thought'] != true) {
            reply.write(p['text']);
          }
        }
        if (calls.isEmpty) break;
        final responses = <Map<String, dynamic>>[];
        for (final c in calls) {
          final name = '${c['name']}';
          activity = _activityFor(name);
          notifyListeners();
          final args = c['args'] is Map
              ? Map<String, dynamic>.from(c['args'] as Map)
              : <String, dynamic>{};
          final result = await tools.run(name, args);
          responses.add({
            'functionResponse': {
              'name': name,
              if (c['id'] != null) 'id': c['id'],
              'response': result,
            }
          });
        }
        _contents.add({'role': 'user', 'parts': responses});
        activity = tr('Pensando…');
        notifyListeners();
      }
      final text = reply.toString().trim();
      messages.add(AiMessage(
        AiRole.assistant,
        text.isEmpty && tools.actions.isNotEmpty ? tr('Hecho.') : text,
        actions: List.of(tools.actions),
      ));
    } on AiException catch (e) {
      // La pregunta que ha fallado no se queda en el historial.
      _contents.removeRange(start, _contents.length);
      messages.add(
          AiMessage(AiRole.error, e.message, actions: List.of(tools.actions)));
    } finally {
      busy = false;
      activity = null;
      notifyListeners();
    }
  }

  static String _activityFor(String fn) => switch (fn) {
        'list_notes' => tr('Buscando notas…'),
        'read_note' => tr('Leyendo la nota…'),
        'list_tasks' => tr('Mirando tus tareas…'),
        'list_folders' => tr('Mirando las carpetas…'),
        'create_note' => tr('Creando la nota…'),
        'append_to_note' => tr('Escribiendo en la nota…'),
        'set_dates' => tr('Poniendo fechas…'),
        _ => tr('Haciendo cambios…'),
      };
}
