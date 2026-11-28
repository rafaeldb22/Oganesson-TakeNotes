import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/note.dart';
import '../ui/urgency.dart' show calendarRange;
import 'note_ics.dart';
import 'notes_repository.dart';

/// Peticiones HTTP (inyectables en las pruebas): método, URL, cabeceras y
/// cuerpo; devuelve el código y el JSON.
typedef GoogleTransport = Future<(int, Map<String, dynamic>)> Function(
    String method, Uri url, Map<String, String> headers, Object? body);

/// Google Calendar: conectar la cuenta (OAuth en el navegador) y sincronizar
/// en los dos sentidos.
/// - Las notas con fecha de Oganesson se crean en Google (y se actualizan o
///   se borran con ellas).
/// - Los eventos de Google salen en el calendario de Oganesson como los de
///   un .ics (no cuentan como notas).
class GoogleCalendar extends ChangeNotifier {
  GoogleCalendar._();
  static final instance = GoogleCalendar._();

  /// Cliente OAuth "de escritorio" del proyecto de Google Cloud. El secreto
  /// de un cliente de escritorio no es confidencial para Google, pero no va
  /// en el repositorio: llega con --dart-define (secreto de GitHub Actions).
  static const clientId =
      '898073060855-0elfqpfverfof1sesdt4q3ia5b4cvu5l.apps.googleusercontent.com';
  static const clientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');
  static const _scope = 'https://www.googleapis.com/auth/calendar';
  static final _api = Uri.parse('https://www.googleapis.com/calendar/v3/');

  /// En Android hará falta su propio cliente (paquete + SHA-1).
  static bool get supported =>
      !kIsWeb && Platform.isWindows && clientSecret.isNotEmpty;

  static const _storage = FlutterSecureStorage();
  GoogleTransport transport = _http;

  String? _userId;
  String? _refresh;
  String? _access;
  DateTime _expires = DateTime(2000);
  Timer? _timer;
  bool busy = false;
  String? email;
  String? error;
  DateTime? lastSync;

  /// nota → evento de Google (lo que hemos subido) y su firma.
  Map<String, String> _pushed = {};
  Map<String, String> _signatures = {};

  /// Ids de las notas que vienen de Google.
  Set<String> _imported = {};

  bool get connected => _refresh != null;

  String get _kRefresh => 'google_refresh_$_userId';
  String get _kState => 'google_estado_$_userId';

  /// Al abrir sesión: lee el token guardado y sincroniza si está conectado.
  Future<void> attach(NotesRepository repo) async {
    _userId = repo.userId;
    try {
      _refresh = await _storage.read(key: _kRefresh);
      final raw = (await SharedPreferences.getInstance()).getString(_kState);
      if (raw != null) {
        final j = jsonDecode(raw) as Map;
        _pushed = Map<String, String>.from(j['pushed'] as Map? ?? {});
        _signatures = Map<String, String>.from(j['sig'] as Map? ?? {});
        _imported = {...((j['imported'] as List?) ?? const []).cast<String>()};
        email = j['email'] as String?;
        final last = j['last'] as String?;
        lastSync = last == null ? null : DateTime.tryParse(last);
      }
    } catch (_) {}
    notifyListeners();
    _timer?.cancel();
    if (connected) {
      unawaited(sync(repo));
      _timer = Timer.periodic(
          const Duration(minutes: 10), (_) => unawaited(sync(repo)));
    }
  }

  Future<void> _saveState() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
          _kState,
          jsonEncode({
            'pushed': _pushed,
            'sig': _signatures,
            'imported': _imported.toList(),
            'email': email,
            'last': lastSync?.toIso8601String(),
          }));
    } catch (_) {}
  }

  // ------------------------------------------------------------- conexión

  /// Abre el navegador para dar permiso y espera la vuelta (localhost).
  Future<bool> connect(NotesRepository repo) async {
    if (!supported) return false;
    error = null;
    final verifier = _random(64);
    final challenge = base64Url
        .encode(const DartSha256().hashSync(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final state = _random(16);
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': '$_scope email',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
    });
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      final req = await server.first.timeout(const Duration(minutes: 5));
      final q = req.uri.queryParameters;
      final ok = q['state'] == state && q['code'] != null;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_page(ok));
      await req.response.close();
      if (!ok) throw StateError(q['error'] ?? 'sin código');
      final (code, res) = await transport(
          'POST', Uri.parse('https://oauth2.googleapis.com/token'), const {}, {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': q['code'],
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirect,
      });
      if (code != 200 || res['refresh_token'] == null) {
        throw StateError('${res['error_description'] ?? res['error']}');
      }
      _refresh = res['refresh_token'] as String;
      _access = res['access_token'] as String?;
      _expires = DateTime.now().add(
          Duration(seconds: (res['expires_in'] as num? ?? 0).toInt() - 60));
      await _storage.write(key: _kRefresh, value: _refresh);
      await attach(repo);
      return true;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    } finally {
      await server.close(force: true);
    }
  }

  /// Desconecta: borra el permiso guardado. Los eventos ya creados en Google
  /// se quedan; los de Google desaparecen de Oganesson.
  Future<void> disconnect(NotesRepository repo) async {
    _timer?.cancel();
    final token = _refresh;
    _refresh = null;
    _access = null;
    try {
      await _storage.delete(key: _kRefresh);
      if (token != null) {
        await transport(
            'POST',
            Uri.parse('https://oauth2.googleapis.com/revoke?token=$token'),
            const {},
            null);
      }
    } catch (_) {}
    repo.removeGoogleEvents(_imported);
    _imported = {};
    _pushed = {};
    _signatures = {};
    email = null;
    lastSync = null;
    await _saveState();
    notifyListeners();
  }

  Future<String> _token() async {
    if (_access != null && DateTime.now().isBefore(_expires)) return _access!;
    final (code, res) = await transport(
        'POST', Uri.parse('https://oauth2.googleapis.com/token'), const {}, {
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': _refresh,
      'grant_type': 'refresh_token',
    });
    if (code != 200) {
      throw StateError('${res['error_description'] ?? res['error'] ?? code}');
    }
    _access = res['access_token'] as String;
    _expires = DateTime.now()
        .add(Duration(seconds: (res['expires_in'] as num? ?? 0).toInt() - 60));
    return _access!;
  }

  Future<(int, Map<String, dynamic>)> _call(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final url = _api.resolve(path).replace(queryParameters: query);
    return transport(
        method, url, {'Authorization': 'Bearer ${await _token()}'}, body);
  }

  // ---------------------------------------------------------- sincronizar

  /// Sube las notas con fecha y trae los eventos de Google.
  Future<void> sync(NotesRepository repo) async {
    if (!connected || busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _push(repo);
      await _pull(repo);
      lastSync = DateTime.now();
      await _saveState();
    } catch (e) {
      error = '$e';
      debugPrint('Google Calendar: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Firma de lo que se sube: si no cambia, no se vuelve a enviar.
  static String signatureOf(Note n) =>
      '${n.title}|${n.remindAt?.toIso8601String()}|${n.dueAt}|${n.done}|${n.repeat}';

  /// Una nota como evento de Google.
  static Map<String, dynamic> eventOf(Note n) {
    final due = n.dueAt!.toLocal();
    final start = (n.remindAt ?? n.dueAt!).toLocal();
    final Map<String, dynamic> s, e;
    if (n.isAllDay) {
      String day(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      s = {'date': day(start)};
      e = {'date': day(DateTime(due.year, due.month, due.day + 1))};
    } else {
      final from = start.isBefore(due) ? start : due;
      s = {'dateTime': from.toUtc().toIso8601String()};
      e = {'dateTime': due.toUtc().toIso8601String()};
    }
    final preview = n.preview;
    return {
      'summary': n.done ? '✓ ${n.title}' : n.title,
      if (preview.isNotEmpty)
        'description':
            preview.length > 800 ? preview.substring(0, 800) : preview,
      'start': s,
      'end': e,
      'extendedProperties': {
        'private': {'oganesson': n.id}
      },
    };
  }

  Future<void> _push(NotesRepository repo) async {
    final mine = {
      for (final n in repo.calendarItems)
        if (!n.isCalendarEvent && !n.vault && !repo.isForeign(n)) n.id: n
    };
    // Borradas o sin fecha: fuera de Google.
    for (final id in _pushed.keys.toList()) {
      if (mine.containsKey(id)) continue;
      final (code, _) =
          await _call('DELETE', 'calendars/primary/events/${_pushed[id]}');
      if (code == 204 || code == 404 || code == 410 || code == 200) {
        _pushed.remove(id);
        _signatures.remove(id);
      }
    }
    for (final n in mine.values) {
      final sig = signatureOf(n);
      if (_signatures[n.id] == sig && _pushed.containsKey(n.id)) continue;
      final ev = _pushed[n.id];
      final (code, res) = ev == null
          ? await _call('POST', 'calendars/primary/events', body: eventOf(n))
          : await _call('PATCH', 'calendars/primary/events/$ev',
              body: eventOf(n));
      if (code == 404 || code == 410) {
        // Lo borraron en Google: se vuelve a crear la próxima vez.
        _pushed.remove(n.id);
        _signatures.remove(n.id);
        continue;
      }
      if (code != 200) continue;
      _pushed[n.id] = res['id'] as String;
      _signatures[n.id] = sig;
    }
  }

  /// Un evento de Google como evento de calendario de Oganesson.
  static IcsEvent? eventToIcs(Map<String, dynamic> e) {
    if (e['status'] == 'cancelled') return null;
    final s = e['start'] as Map?, en = e['end'] as Map?;
    if (s == null || en == null) return null;
    final title = '${e['summary'] ?? ''}'.trim();
    final desc = '${e['description'] ?? ''}'.trim();
    final content = [
      if (title.isNotEmpty) title else 'Evento',
      if (desc.isNotEmpty) desc.replaceAll(RegExp(r'<[^>]+>'), ''),
    ].join('\n');
    if (s['date'] != null) {
      final a = DateTime.parse('${s['date']}');
      final b =
          DateTime.parse('${en['date']}').subtract(const Duration(days: 1));
      return IcsEvent(
          uid: 'google:${e['id']}',
          content: content,
          remindAt: Note.dayStart(a).toUtc(),
          dueAt: Note.dayEnd(b.isBefore(a) ? a : b).toUtc());
    }
    final a = DateTime.tryParse('${s['dateTime']}');
    final b = DateTime.tryParse('${en['dateTime']}');
    if (a == null || b == null) return null;
    return IcsEvent(
        uid: 'google:${e['id']}',
        content: content,
        remindAt: a.toUtc(),
        dueAt: b.toUtc());
  }

  Future<void> _pull(NotesRepository repo) async {
    final range = calendarRange();
    final events = <IcsEvent>[];
    String? page;
    do {
      final (code, res) =
          await _call('GET', 'calendars/primary/events', query: {
        'timeMin': range.first.toUtc().toIso8601String(),
        'timeMax': range.last.toUtc().toIso8601String(),
        'singleEvents': 'true',
        'maxResults': '2500',
        if (page != null) 'pageToken': page,
      });
      if (code != 200) {
        throw StateError('${(res['error'] as Map?)?['message'] ?? code}');
      }
      email ??= res['summary'] as String?;
      for (final e in (res['items'] as List? ?? const []).whereType<Map>()) {
        final ev = Map<String, dynamic>.from(e);
        // Las que subimos nosotros ya son notas.
        final own = ((ev['extendedProperties'] as Map?)?['private']
            as Map?)?['oganesson'];
        if (own != null) continue;
        final i = eventToIcs(ev);
        if (i != null) events.add(i);
      }
      page = res['nextPageToken'] as String?;
    } while (page != null);
    _imported = repo.syncGoogleEvents(events, _imported);
  }

  // ------------------------------------------------------------ utilidades

  static String _random(int n) {
    final r = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String _page(bool ok) => '''<!doctype html><meta charset="utf-8">
<title>Oganesson</title><body style="font-family:Segoe UI,sans-serif;background:#141826;color:#f5e9c8;display:grid;place-items:center;height:100vh;margin:0">
<div style="text-align:center"><h1>${ok ? 'Google Calendar conectado' : 'No se pudo conectar'}</h1>
<p>${ok ? 'Ya puedes cerrar esta pestaña y volver a Oganesson.' : 'Vuelve a Oganesson e inténtalo otra vez.'}</p></div>''';

  static Future<(int, Map<String, dynamic>)> _http(
      String method, Uri url, Map<String, String> headers, Object? body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.openUrl(method, url);
      headers.forEach(req.headers.set);
      if (body is Map && url.host == 'oauth2.googleapis.com') {
        req.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded');
        req.write(Uri(queryParameters: {
          for (final e in body.entries)
            if (e.value != null) '${e.key}': '${e.value}'
        }).query);
      } else if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> json = {};
      if (text.isNotEmpty) {
        try {
          final d = jsonDecode(text);
          if (d is Map<String, dynamic>) json = d;
        } catch (_) {}
      }
      return (res.statusCode, json);
    } finally {
      client.close();
    }
  }
}
