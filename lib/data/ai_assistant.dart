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
// Proveedores y ajustes: cada usuario usa SU clave (Gemini, ChatGPT o
// Claude).
// ===================================================================

/// Modelo que se puede elegir en los ajustes.
class AiModel {
  const AiModel(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;
}

enum AiProvider { gemini, openai, claude }

extension AiProviderInfo on AiProvider {
  String get label => switch (this) {
        AiProvider.gemini => 'Gemini',
        AiProvider.openai => 'ChatGPT',
        AiProvider.claude => 'Claude',
      };

  /// Dónde se crea la clave.
  String get keyUrl => switch (this) {
        AiProvider.gemini => 'https://aistudio.google.com/apikey',
        AiProvider.openai => 'https://platform.openai.com/api-keys',
        AiProvider.claude => 'https://console.anthropic.com/settings/keys',
      };

  String get keySite => switch (this) {
        AiProvider.gemini => 'Google AI Studio',
        AiProvider.openai => 'OpenAI Platform',
        AiProvider.claude => 'Claude Console',
      };

  String get keyHint => switch (this) {
        AiProvider.gemini => 'AIza…',
        AiProvider.openai => 'sk-…',
        AiProvider.claude => 'sk-ant-…',
      };

  /// ¿Tiene plan gratuito? (OpenAI y Anthropic cobran por uso.)
  bool get free => this == AiProvider.gemini;

  List<AiModel> get models => switch (this) {
        AiProvider.gemini => const [
            AiModel('gemini-3.5-flash-lite', 'Gemini Flash-Lite',
                'Rápido y con más peticiones gratis al día'),
            AiModel('gemini-3.8-flash', 'Gemini Flash',
                'Más listo, pero con pocas peticiones gratis al día'),
          ],
        AiProvider.openai => const [
            AiModel('gpt-5-mini', 'GPT-5 mini', 'Rápido y barato'),
            AiModel('gpt-5', 'GPT-5', 'El más listo de OpenAI (más caro)'),
          ],
        AiProvider.claude => const [
            AiModel('claude-opus-5-5', 'Claude Opus 5.5',
                'El más capaz para el día a día'),
            AiModel('claude-sonnet-5-5', 'Claude Sonnet 5.5',
                'Muy capaz y más barato'),
            AiModel('claude-haiku-5-5', 'Claude Haiku 5.5',
                'El más rápido y barato'),
          ],
      };

  /// Modelos que se prueban, en orden, si el elegido no funciona con la
  /// clave.
  List<String> get fallbackModels => switch (this) {
        AiProvider.gemini => const [
            'gemini-3.5-flash-lite',
            'gemini-3.1-flash-lite',
            'gemini-2.5-flash-lite',
            'gemini-3.6-flash',
            'gemini-3.8-flash',
          ],
        AiProvider.openai => const [
            'gpt-5-mini',
            'gpt-5',
            'gpt-4.1-mini',
            'gpt-4o-mini',
          ],
        AiProvider.claude => const [
            'claude-opus-5-5',
            'claude-sonnet-5-5',
            'claude-haiku-5-5',
          ],
      };
}

/// Ajustes del asistente. Las claves se guardan cifradas y SOLO en este
/// dispositivo (nunca se suben a Supabase), una por proveedor.
class AiSettings extends ChangeNotifier {
  AiSettings._();
  static final instance = AiSettings._();

  /// Compatibilidad: modelos de Gemini (versiones anteriores).
  static List<AiModel> get models => AiProvider.gemini.models;
  static List<String> get fallbackModels => AiProvider.gemini.fallbackModels;

  static const _storage = FlutterSecureStorage();
  static const _kProvider = 'ai_provider';
  static String _kKey(AiProvider p) => 'ai_key_${p.name}';
  static String _kModel(AiProvider p) => 'ai_model_${p.name}';

  AiProvider provider = AiProvider.gemini;
  final Map<AiProvider, String> _keys = {};
  final Map<AiProvider, String> _models = {};
  bool loaded = false;

  String? keyFor(AiProvider p) => _keys[p];
  String modelFor(AiProvider p) => _models[p] ?? p.models.first.id;

  String? get apiKey => _keys[provider];
  String get model => modelFor(provider);
  bool get configured => (apiKey ?? '').isNotEmpty;

  Future<void> load() async {
    if (loaded) return;
    try {
      for (final p in AiProvider.values) {
        final k = await _storage.read(key: _kKey(p));
        if (k != null && k.isNotEmpty) _keys[p] = k;
      }
      // Clave de Gemini de la versión 1.8.
      if (!_keys.containsKey(AiProvider.gemini)) {
        final old = await _storage.read(key: 'gemini_api_key');
        if (old != null && old.isNotEmpty) _keys[AiProvider.gemini] = old;
      }
    } catch (e) {
      debugPrint('IA: no se pudo leer la clave ($e)');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      provider = AiProvider.values.firstWhere(
          (p) => p.name == prefs.getString(_kProvider),
          orElse: () => AiProvider.gemini);
      for (final p in AiProvider.values) {
        final m = prefs.getString(_kModel(p));
        if (m != null) _models[p] = m;
      }
      final oldModel = prefs.getString('gemini_model');
      if (oldModel != null)
        _models.putIfAbsent(AiProvider.gemini, () => oldModel);
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  Future<void> save({
    AiProvider? provider,
    required String apiKey,
    required String model,
  }) async {
    final p = provider ?? this.provider;
    this.provider = p;
    _keys[p] = apiKey.trim();
    _models[p] = model.trim();
    await _storage.write(key: _kKey(p), value: _keys[p]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProvider, p.name);
    await prefs.setString(_kModel(p), _models[p]!);
    loaded = true;
    notifyListeners();
  }

  Future<void> forget([AiProvider? provider]) async {
    final p = provider ?? this.provider;
    _keys.remove(p);
    try {
      await _storage.delete(key: _kKey(p));
      if (p == AiProvider.gemini) await _storage.delete(key: 'gemini_api_key');
    } catch (_) {}
    notifyListeners();
  }
}

// ===================================================================
// Clientes de las API (REST, con llamada a funciones).
// ===================================================================

/// Error de la API explicado para el usuario.
class AiException implements Exception {
  AiException(this.message, {this.code, this.modelSpecific = false});
  final String message;
  final int? code;

  /// El problema es del modelo (no existe, o sin cuota para él): puede que
  /// otro modelo sí funcione con la misma clave.
  final bool modelSpecific;
  @override
  String toString() => message;
}

/// Envía una petición y devuelve (código, cuerpo JSON). Se puede sustituir
/// en los tests.
typedef AiTransport = Future<(int, Map<String, dynamic>)> Function(
    String method,
    Uri url,
    Map<String, String> headers,
    Map<String, dynamic>? body);

Future<(int, Map<String, dynamic>)> _httpTransport(String method, Uri url,
    Map<String, String> headers, Map<String, dynamic>? body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.openUrl(method, url);
    headers.forEach(req.headers.set);
    req.headers.contentType = ContentType.json;
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(const Duration(seconds: 120));
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

/// Una llamada a función pedida por la IA.
class AiToolCall {
  AiToolCall(this.id, this.name, this.args);
  final String? id;
  final String name;
  final Map<String, dynamic> args;
}

/// Respuesta de un paso: texto, funciones pedidas y el mensaje tal cual
/// (para devolverlo en el historial: Gemini y Claude necesitan recibir de
/// vuelta sus bloques de razonamiento sin cambios).
class AiTurn {
  AiTurn({required this.text, required this.calls, required this.raw});
  final String text;
  final List<AiToolCall> calls;
  final Map<String, dynamic> raw;
}

/// Base común de los tres proveedores.
abstract class AiClient {
  AiClient({AiTransport? transport}) : _transport = transport ?? _httpTransport;
  final AiTransport _transport;

  AiProvider get provider;

  static AiClient forProvider(AiProvider p, {AiTransport? transport}) =>
      switch (p) {
        AiProvider.gemini => GeminiClient(transport: transport),
        AiProvider.openai => OpenAiClient(transport: transport),
        AiProvider.claude => ClaudeClient(transport: transport),
      };

  /// Mensaje del usuario en el formato de la API.
  Map<String, dynamic> userMessage(String text);

  /// Respuestas de las funciones, en el formato de la API.
  List<Map<String, dynamic>> toolResults(
      List<(AiToolCall, Map<String, dynamic>)> results);

  /// Un paso de la conversación.
  Future<AiTurn> complete({
    required String apiKey,
    required String model,
    required String system,
    required List<Map<String, dynamic>> history,
    required List<Map<String, dynamic>> tools,
  });

  /// Petición mínima real: comprueba la clave, el modelo y el saldo/cuota.
  Future<void> check(String apiKey, String model);

  /// Busca un modelo que funcione: primero [preferred] y luego los de
  /// [AiProviderInfo.fallbackModels].
  Future<String> findWorkingModel(String apiKey, String preferred) async {
    AiException? first;
    for (final m in {preferred, ...provider.fallbackModels}) {
      try {
        await check(apiKey, m);
        return m;
      } on AiException catch (e) {
        first ??= e;
        // Clave mala, sin conexión, sin saldo…: probar otros no sirve.
        if (!e.modelSpecific) rethrow;
      }
    }
    throw first!;
  }

  Future<(int, Map<String, dynamic>)> call(String method, Uri url,
      Map<String, String> headers, Map<String, dynamic>? body) async {
    try {
      return await _transport(method, url, headers, body);
    } on SocketException {
      throw AiException(tr('Sin conexión. Revisa internet y vuelve a probar.'));
    } on TimeoutException {
      throw AiException(tr('La IA ha tardado demasiado. Vuelve a probar.'));
    } on HandshakeException {
      throw AiException(tr('Sin conexión. Revisa internet y vuelve a probar.'));
    }
  }

  /// "Google dice: …" / "OpenAI dice: …": el motivo exacto, primera frase.
  static String detail(String who, String msg) {
    final first = msg.split(RegExp(r'(?<=\.)\s')).first.trim();
    if (first.isEmpty) return '';
    final cut = first.length > 180 ? '${first.substring(0, 180)}…' : first;
    return '\n\n${trf('{0} dice: {1}', [who, cut])}';
  }

  /// Esquema JSON estándar (OpenAI y Claude) a partir de las declaraciones
  /// de Gemini (tipos en mayúsculas).
  static Map<String, dynamic> jsonSchema(Map<String, dynamic>? s) {
    if (s == null) return {'type': 'object', 'properties': <String, dynamic>{}};
    Object? conv(Object? v) {
      if (v is Map) {
        return {
          for (final e in v.entries)
            '${e.key}':
                e.key == 'type' ? '${e.value}'.toLowerCase() : conv(e.value)
        };
      }
      if (v is List) return v.map(conv).toList();
      return v;
    }

    return Map<String, dynamic>.from(conv(s) as Map);
  }

  static Map<String, dynamic> parseArgs(Object? a) {
    if (a is Map) return Map<String, dynamic>.from(a);
    if (a is String && a.trim().isNotEmpty) {
      try {
        final d = jsonDecode(a);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return {};
  }
}

// ------------------------------------------------------------- Gemini

class GeminiClient extends AiClient {
  GeminiClient({super.transport});

  @override
  AiProvider get provider => AiProvider.gemini;

  static final _base =
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/');

  Map<String, String> _h(String key) => {'x-goog-api-key': key};

  @override
  Map<String, dynamic> userMessage(String text) => {
        'role': 'user',
        'parts': [
          {'text': text}
        ],
      };

  @override
  List<Map<String, dynamic>> toolResults(
          List<(AiToolCall, Map<String, dynamic>)> results) =>
      [
        {
          'role': 'user',
          'parts': [
            for (final (c, r) in results)
              {
                'functionResponse': {
                  'name': c.name,
                  if (c.id != null) 'id': c.id,
                  'response': r,
                }
              }
          ],
        }
      ];

  @override
  Future<void> check(String apiKey, String model) async {
    final (code, json) = await call(
      'POST',
      _base.resolve('models/$model:generateContent'),
      _h(apiKey),
      {
        'contents': [userMessage('ok')],
        'generationConfig': {'maxOutputTokens': 8},
      },
    );
    if (code != 200) throw _error(code, json, model: model);
  }

  @override
  Future<AiTurn> complete({
    required String apiKey,
    required String model,
    required String system,
    required List<Map<String, dynamic>> history,
    required List<Map<String, dynamic>> tools,
  }) async {
    final (code, res) = await call(
      'POST',
      _base.resolve('models/$model:generateContent'),
      _h(apiKey),
      {
        'systemInstruction': {
          'parts': [
            {'text': system}
          ]
        },
        'contents': history,
        'tools': [
          {'functionDeclarations': tools}
        ],
      },
    );
    if (code != 200) throw _error(code, res, model: model);
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
    final raw = Map<String, dynamic>.from(content)..['role'] = 'model';
    final text = StringBuffer();
    final calls = <AiToolCall>[];
    for (final p in (raw['parts'] as List?) ?? const []) {
      if (p is! Map) continue;
      final fc = p['functionCall'];
      if (fc is Map) {
        calls.add(AiToolCall(fc['id'] as String?, '${fc['name']}',
            AiClient.parseArgs(fc['args'])));
      } else if (p['text'] is String && p['thought'] != true) {
        text.write(p['text']);
      }
    }
    return AiTurn(text: text.toString(), calls: calls, raw: raw);
  }

  /// Segundos que Google pide esperar (RetryInfo.retryDelay, p. ej. "34s").
  static int? _retrySeconds(Object? err) {
    if (err is! Map || err['details'] is! List) return null;
    for (final d in err['details'] as List) {
      if (d is Map && '${d['@type']}'.endsWith('RetryInfo')) {
        final v = double.tryParse('${d['retryDelay']}'.replaceAll('s', ''));
        if (v != null) return v.ceil();
      }
    }
    return null;
  }

  static AiException _error(int code, Map<String, dynamic> json,
      {String? model}) {
    final err = json['error'];
    final msg = err is Map ? '${err['message'] ?? ''}' : '';
    final status = err is Map ? '${err['status'] ?? ''}' : '';
    final google = AiClient.detail('Google', msg);
    final lower = msg.toLowerCase();
    // Proyecto con facturación de prepago y sin créditos (HTTP 402): llega
    // con el mismo estado que los límites, pero ningún modelo funcionará.
    if (code == 402 ||
        lower.contains('prepayment') ||
        lower.contains('credits are depleted')) {
      return AiException(
          '${tr('El proyecto de Google de tu clave tiene la facturación de '
              'prepago activada y se ha quedado sin créditos, así que Google '
              'rechaza todas las peticiones (con facturación no se usa el plan '
              'gratis). Para usarlo gratis, crea una clave nueva en Google AI '
              'Studio en un proyecto SIN facturación, o añade créditos a ese '
              'proyecto.')}$google',
          code: 402);
    }
    if (code == 429 || status == 'RESOURCE_EXHAUSTED') {
      final wait = _retrySeconds(err);
      final String text;
      if (lower.contains('limit: 0')) {
        text = trf(
            'Tu clave no tiene peticiones gratis para el modelo {0}. '
            'Elige otro modelo en los ajustes.',
            [model ?? '']);
      } else if (lower.contains('perday') || lower.contains('per day')) {
        text = tr('Has gastado las peticiones gratis de hoy para este modelo. '
            'Se reinician a medianoche, hora del Pacífico (las 9:00 en '
            'España). Mientras, puedes elegir otro modelo en los ajustes.');
      } else if (wait != null ||
          lower.contains('perminute') ||
          lower.contains('per minute')) {
        text = wait == null
            ? tr('Demasiadas peticiones seguidas. Espera un minuto y vuelve '
                'a probar.')
            : trf(
                'Demasiadas peticiones seguidas. Espera {0} s y vuelve a '
                'probar.',
                [wait]);
      } else {
        text = tr('Google ha limitado tu clave por ahora (límite del plan '
            'gratis). Espera un poco y vuelve a probar, o elige otro modelo.');
      }
      return AiException('$text$google', code: 429, modelSpecific: true);
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
          code: code,
          modelSpecific: true);
    }
    if (code == 403) {
      return AiException(
          tr('Tu clave no tiene permiso para usar la API de Gemini.'),
          code: code);
    }
    return AiException(
        '${trf('La IA respondió con un error ({0}).', [code])}$google',
        code: code);
  }
}

// ------------------------------------------------------- OpenAI (ChatGPT)

class OpenAiClient extends AiClient {
  OpenAiClient({super.transport});

  @override
  AiProvider get provider => AiProvider.openai;

  static final _base = Uri.parse('https://api.openai.com/v1/');

  Map<String, String> _h(String key) => {'Authorization': 'Bearer $key'};

  @override
  Map<String, dynamic> userMessage(String text) =>
      {'role': 'user', 'content': text};

  @override
  List<Map<String, dynamic>> toolResults(
          List<(AiToolCall, Map<String, dynamic>)> results) =>
      [
        for (final (c, r) in results)
          {
            'role': 'tool',
            'tool_call_id': c.id,
            'content': jsonEncode(r),
          }
      ];

  @override
  Future<void> check(String apiKey, String model) async {
    final (code, json) = await call(
      'POST',
      _base.resolve('chat/completions'),
      _h(apiKey),
      {
        'model': model,
        'messages': [userMessage('ok')],
        'max_completion_tokens': 16,
      },
    );
    if (code != 200) throw _error(code, json, model: model);
  }

  @override
  Future<String> findWorkingModel(String apiKey, String preferred) async {
    try {
      return await super.findWorkingModel(apiKey, preferred);
    } on AiException catch (e) {
      if (!e.modelSpecific) rethrow;
      // Ninguno de la lista: el primer modelo "gpt" que tenga la cuenta.
      final (code, json) =
          await call('GET', _base.resolve('models'), _h(apiKey), null);
      if (code != 200) rethrow;
      final ids = [
        for (final m in (json['data'] as List?) ?? const [])
          if (m is Map && '${m['id']}'.startsWith('gpt-')) '${m['id']}'
      ]..sort();
      for (final id in ids) {
        try {
          await check(apiKey, id);
          return id;
        } on AiException catch (_) {}
      }
      rethrow;
    }
  }

  @override
  Future<AiTurn> complete({
    required String apiKey,
    required String model,
    required String system,
    required List<Map<String, dynamic>> history,
    required List<Map<String, dynamic>> tools,
  }) async {
    final (code, res) = await call(
      'POST',
      _base.resolve('chat/completions'),
      _h(apiKey),
      {
        'model': model,
        'messages': [
          {'role': 'system', 'content': system},
          ...history,
        ],
        'tools': [
          for (final t in tools)
            {
              'type': 'function',
              'function': {
                'name': t['name'],
                'description': t['description'],
                'parameters': AiClient.jsonSchema(
                    t['parameters'] as Map<String, dynamic>?),
              }
            }
        ],
      },
    );
    if (code != 200) throw _error(code, res, model: model);
    final choices = res['choices'];
    final msg = choices is List && choices.isNotEmpty
        ? (choices.first as Map)['message']
        : null;
    if (msg is! Map) {
      throw AiException(tr('La IA no ha devuelto respuesta. Vuelve a probar.'));
    }
    if (msg['refusal'] is String && '${msg['refusal']}'.isNotEmpty) {
      throw AiException(tr('La IA no ha querido responder a eso.'));
    }
    final toolCalls = (msg['tool_calls'] as List?) ?? const [];
    final raw = <String, dynamic>{
      'role': 'assistant',
      'content': msg['content'],
      if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
    };
    return AiTurn(
      text: msg['content'] is String ? msg['content'] as String : '',
      calls: [
        for (final c in toolCalls)
          if (c is Map && c['function'] is Map)
            AiToolCall('${c['id']}', '${(c['function'] as Map)['name']}',
                AiClient.parseArgs((c['function'] as Map)['arguments']))
      ],
      raw: raw,
    );
  }

  static AiException _error(int code, Map<String, dynamic> json,
      {String? model}) {
    final err = json['error'];
    final msg = err is Map ? '${err['message'] ?? ''}' : '';
    final type = err is Map ? '${err['code'] ?? err['type'] ?? ''}' : '';
    final openai = AiClient.detail('OpenAI', msg);
    if (code == 401) {
      return AiException(tr('La clave no es válida. Revísala en los ajustes.'),
          code: code);
    }
    if (type == 'insufficient_quota') {
      return AiException(
          '${tr('Tu cuenta de OpenAI no tiene saldo. La API de OpenAI es de '
              'pago: añade saldo en platform.openai.com (Billing) y vuelve a '
              'probar.')}$openai',
          code: code);
    }
    if (code == 429) {
      return AiException(
          '${tr('Demasiadas peticiones seguidas. Espera un minuto y vuelve a '
              'probar.')}$openai',
          code: code);
    }
    if (code == 404 || type == 'model_not_found') {
      return AiException(
          '${tr('Ese modelo no existe o tu clave no tiene acceso. Elige otro '
              'en los ajustes.')}$openai',
          code: code,
          modelSpecific: true);
    }
    if (code == 400 && msg.toLowerCase().contains('model')) {
      return AiException(
          '${trf('La IA respondió con un error ({0}).', [code])}$openai',
          code: code,
          modelSpecific: true);
    }
    return AiException(
        '${trf('La IA respondió con un error ({0}).', [code])}$openai',
        code: code);
  }
}

// ---------------------------------------------------- Claude (Anthropic)

class ClaudeClient extends AiClient {
  ClaudeClient({super.transport});

  @override
  AiProvider get provider => AiProvider.claude;

  static final _url = Uri.parse('https://api.anthropic.com/v1/messages');

  /// Modelos con reintento automático en otro modelo si Claude rechaza la
  /// petición por seguridad (`fallbacks: "default"`).
  static const _withFallbacks = {'claude-opus-5-5', 'claude-sonnet-5-5'};

  Map<String, String> _h(String key, String model) => {
        'x-api-key': key,
        'anthropic-version': '2026-10-21',
        if (_withFallbacks.contains(model))
          'anthropic-beta': 'server-side-fallback-2026-07-01',
      };

  @override
  Map<String, dynamic> userMessage(String text) => {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text}
        ],
      };

  @override
  List<Map<String, dynamic>> toolResults(
          List<(AiToolCall, Map<String, dynamic>)> results) =>
      [
        {
          'role': 'user',
          // Todas las respuestas juntas, en un solo mensaje.
          'content': [
            for (final (c, r) in results)
              {
                'type': 'tool_result',
                'tool_use_id': c.id,
                'content': jsonEncode(r),
                if (r.containsKey('error')) 'is_error': true,
              }
          ],
        }
      ];

  @override
  Future<void> check(String apiKey, String model) async {
    final (code, json) = await call('POST', _url, _h(apiKey, model), {
      'model': model,
      'max_tokens': 64,
      'messages': [userMessage('ok')],
    });
    if (code != 200) throw _error(code, json, model: model);
  }

  @override
  Future<AiTurn> complete({
    required String apiKey,
    required String model,
    required String system,
    required List<Map<String, dynamic>> history,
    required List<Map<String, dynamic>> tools,
  }) async {
    final (code, res) = await call('POST', _url, _h(apiKey, model), {
      'model': model,
      'max_tokens': 16000,
      'system': system,
      'messages': history,
      'tools': [
        for (final t in tools)
          {
            'name': t['name'],
            'description': t['description'],
            'input_schema':
                AiClient.jsonSchema(t['parameters'] as Map<String, dynamic>?),
          }
      ],
      if (_withFallbacks.contains(model)) 'fallbacks': 'default',
    });
    if (code != 200) throw _error(code, res, model: model);
    if (res['stop_reason'] == 'refusal') {
      throw AiException(tr('La IA no ha querido responder a eso.'));
    }
    final content = (res['content'] as List?) ?? const [];
    final text = StringBuffer();
    final calls = <AiToolCall>[];
    for (final b in content) {
      if (b is! Map) continue;
      if (b['type'] == 'text') {
        text.write(b['text']);
      } else if (b['type'] == 'tool_use') {
        calls.add(AiToolCall(
            '${b['id']}', '${b['name']}', AiClient.parseArgs(b['input'])));
      }
    }
    // El contenido se devuelve completo y sin cambios (incluidos los
    // bloques de razonamiento).
    return AiTurn(
      text: text.toString(),
      calls: calls,
      raw: {'role': 'assistant', 'content': content},
    );
  }

  static AiException _error(int code, Map<String, dynamic> json,
      {String? model}) {
    final err = json['error'];
    final msg = err is Map ? '${err['message'] ?? ''}' : '';
    final type = err is Map ? '${err['type'] ?? ''}' : '';
    final claude = AiClient.detail('Anthropic', msg);
    final lower = msg.toLowerCase();
    if (code == 401 || type == 'authentication_error') {
      return AiException(tr('La clave no es válida. Revísala en los ajustes.'),
          code: code);
    }
    if (lower.contains('credit balance')) {
      return AiException(
          '${tr('Tu cuenta de Anthropic no tiene saldo. La API de Claude es de '
              'pago: añade saldo en la Claude Console (Billing) y vuelve a '
              'probar.')}$claude',
          code: code);
    }
    if (code == 404 || type == 'not_found_error') {
      return AiException(
          '${tr('Ese modelo no existe o tu clave no tiene acceso. Elige otro '
              'en los ajustes.')}$claude',
          code: code,
          modelSpecific: true);
    }
    if (code == 429 || type == 'rate_limit_error') {
      return AiException(
          '${tr('Demasiadas peticiones seguidas. Espera un minuto y vuelve a '
              'probar.')}$claude',
          code: code);
    }
    if (code == 529 || type == 'overloaded_error') {
      return AiException(
          tr('Claude está saturado ahora mismo. Vuelve a probar en un rato.'),
          code: code);
    }
    return AiException(
        '${trf('La IA respondió con un error ({0}).', [code])}$claude',
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
/// Funciona igual con Gemini, ChatGPT o Claude: cada cliente traduce el
/// historial y las funciones al formato de su API.
class AiSession extends ChangeNotifier {
  AiSession(this.repo, {AiTransport? transport, AiSettings? settings})
      : _transport = transport,
        settings = settings ?? AiSettings.instance;

  final NotesRepository repo;
  final AiSettings settings;
  final AiTransport? _transport;

  final List<AiMessage> messages = [];

  /// Historial en el formato de la API del proveedor con el que se empezó
  /// (si se cambia de proveedor, el historial empieza de cero).
  final List<Map<String, dynamic>> _history = [];
  AiProvider? _historyProvider;
  bool busy = false;

  /// Qué está haciendo ahora (p. ej. "Buscando tareas…").
  String? activity;

  /// La pone el panel para pedir confirmaciones.
  AiConfirm confirm = (_) async => false;

  static const _maxSteps = 8;

  void clear() {
    messages.clear();
    _history.clear();
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
      messages.add(AiMessage(AiRole.error, tr('Primero pon tu clave de IA.')));
      notifyListeners();
      return;
    }
    final provider = settings.provider;
    if (_historyProvider != provider) {
      _history.clear();
      _historyProvider = provider;
    }
    final client = AiClient.forProvider(provider, transport: _transport);

    messages.add(AiMessage(AiRole.user, t));
    final start = _history.length;
    _history.add(client.userMessage(t));
    busy = true;
    activity = tr('Pensando…');
    notifyListeners();

    final tools = AiTools(repo, confirm: confirm);
    final reply = StringBuffer();
    try {
      for (var step = 0; step < _maxSteps; step++) {
        final turn = await client.complete(
          apiKey: settings.apiKey!,
          model: settings.model,
          system: _system(),
          history: _history,
          tools: AiTools.declarations,
        );
        _history.add(turn.raw);
        if (turn.text.trim().isNotEmpty) {
          if (reply.isNotEmpty) reply.write('\n\n');
          reply.write(turn.text.trim());
        }
        if (turn.calls.isEmpty) break;
        final results = <(AiToolCall, Map<String, dynamic>)>[];
        for (final c in turn.calls) {
          activity = _activityFor(c.name);
          notifyListeners();
          results.add((c, await tools.run(c.name, c.args)));
        }
        _history.addAll(client.toolResults(results));
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
      _history.removeRange(start, _history.length);
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
