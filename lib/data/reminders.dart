import 'dart:async';
import 'dart:convert';
import '../ui/format.dart' show duracionTexto, fechaMedia;
import '../ui/i18n.dart';
import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';

/// Cuándo avisar de las tareas. Se guarda en cada dispositivo, igual que los
/// avisos, que también se programan en cada uno.
@immutable
class ReminderPrefs {
  const ReminderPrefs({
    this.enabled = true,
    this.daily = false,
    this.weekly = false,
    this.week = true,
    this.three = true,
    this.day = true,
    this.leads = const {60},
    this.hour = 9,
    this.minute = 0,
  });

  /// Opciones de "el mismo día": minutos antes de la hora en que acaba.
  static const leadOptions = [0, 10, 30, 60, 120];

  final bool enabled, daily, weekly, week, three, day;

  /// Minutos antes de que acabe una tarea con hora.
  final Set<int> leads;

  /// Hora de los avisos de las tareas de todo el día, que no tienen hora.
  final int hour, minute;

  ReminderPrefs copyWith({
    bool? enabled,
    bool? daily,
    bool? weekly,
    bool? week,
    bool? three,
    bool? day,
    Set<int>? leads,
    int? hour,
    int? minute,
  }) =>
      ReminderPrefs(
        enabled: enabled ?? this.enabled,
        daily: daily ?? this.daily,
        weekly: weekly ?? this.weekly,
        week: week ?? this.week,
        three: three ?? this.three,
        day: day ?? this.day,
        leads: leads ?? this.leads,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  String encode() => jsonEncode({
        'on': enabled,
        'daily': daily,
        'weekly': weekly,
        'week': week,
        'three': three,
        'day': day,
        'leads': leads.toList()..sort(),
        'h': hour,
        'm': minute,
      });

  static ReminderPrefs decode(String? raw) {
    const d = ReminderPrefs();
    if (raw == null) return d;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      bool flag(String k, bool fallback) =>
          j[k] is bool ? j[k] as bool : fallback;
      return ReminderPrefs(
        enabled: flag('on', d.enabled),
        daily: flag('daily', d.daily),
        weekly: flag('weekly', d.weekly),
        week: flag('week', d.week),
        three: flag('three', d.three),
        day: flag('day', d.day),
        leads: j['leads'] is List
            ? {
                for (final v in j['leads'] as List)
                  if (leadOptions.contains(v)) v as int
              }
            : d.leads,
        hour: j['h'] is int ? (j['h'] as int).clamp(0, 23) : d.hour,
        minute: j['m'] is int ? (j['m'] as int).clamp(0, 59) : d.minute,
      );
    } catch (_) {
      return d;
    }
  }
}

/// Días antes de la fecha límite en los que toca avisar. [daysLeft] son los
/// que faltan y [activeDays] los que dura la tarea.
Set<int> reminderDays(ReminderPrefs p, int daysLeft, int activeDays,
    {bool singleDay = false}) {
  if (!p.enabled || daysLeft < 0) return const {};
  final span = activeDays < daysLeft ? activeDays : daysLeft;
  return {
    if (singleDay || p.leads.isNotEmpty) 0,
    if (p.week && daysLeft >= 7) 7,
    if (p.three && daysLeft >= 3) 3,
    if (p.day && daysLeft >= 1) 1,
    if (p.daily)
      for (var d = 0; d <= span; d++) d,
    if (p.weekly)
      for (var d = 7; d <= span; d += 7) d,
  };
}

String _clock(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

/// "Vence mañana a las 20:00", "Vence el 28 nov · todo el día"…
String _dueText(DateTime due, int daysBefore, bool allDay) {
  final date = fechaMedia(due.toUtc()).split(',').first;
  if (allDay) {
    return switch (daysBefore) {
      0 => tr('Vence hoy · todo el día'),
      1 => tr('Vence mañana · todo el día'),
      _ => trf('Vence el {0} · todo el día', [date]),
    };
  }
  final at = _clock(due);
  return switch (daysBefore) {
    0 => trf('Vence hoy a las {0}', [at]),
    1 => trf('Vence mañana a las {0}', [at]),
    _ => trf('Vence el {0} a las {1}', [date, at]),
  };
}

/// Avisos pendientes de una nota, del más cercano al más lejano. Con hora:
/// una hora antes de la hora en que acaba, en cada día elegido, y el último
/// día los minutos de [ReminderPrefs.leads]. Sin hora: a la hora elegida.
List<(DateTime, String)> reminderTimes(Note n, ReminderPrefs p, DateTime now) {
  final due = n.dueAt?.toLocal();
  if (due == null) return const [];
  final local = now.toLocal();
  // En UTC para que un cambio de hora no descuente un día.
  int daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;
  final daysLeft = daysBetween(local, due);
  final activeDays = daysBetween(n.periodStart.toLocal(), due);
  final days = reminderDays(p, daysLeft, activeDays < 0 ? 0 : activeDays,
      singleDay: n.isSingleDay);
  final allDay = n.isAllDay;
  final found = <DateTime, String>{};
  void add(DateTime at, String body) {
    if (at.isAfter(local)) found.putIfAbsent(at, () => body);
  }

  for (final d in days) {
    if (allDay) {
      add(DateTime(due.year, due.month, due.day - d, p.hour, p.minute),
          _dueText(due, d, true));
    } else if (d > 0) {
      add(DateTime(due.year, due.month, due.day - d, due.hour - 1, due.minute),
          _dueText(due, d, false));
    } else {
      for (final lead in p.leads.isEmpty ? const {60} : p.leads) {
        add(
            due.subtract(Duration(minutes: lead)),
            lead == 0
                ? tr('Vence ahora')
                : trf('Vence en {0} · a las {1}',
                    [duracionTexto(Duration(minutes: lead)), _clock(due)]));
      }
    }
  }
  final times = found.keys.toList()..sort();
  return [
    for (final at in times.take(Reminders.maxPerNote)) (at.toUtc(), found[at]!),
  ];
}

/// Avisos de las notas temporales en el propio dispositivo, a partir de las
/// notas sincronizadas: el aviso llega aunque la nota se creara en el otro.
/// En Android los programa el sistema. En Windows los lanza la app, que sigue
/// en la bandeja, y al abrirse recupera los que se perdió estando cerrada.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  static const _kPrefs = 'avisos_v1';
  static const _kLastTick = 'avisos_ultimo';
  static const _kSnoozes = 'avisos_pospuestos';
  static const _snooze = Duration(minutes: 10);

  /// Android admite unas 500 alarmas por app: se programan las más cercanas
  /// y el resto al volver a abrir la app.
  static const maxScheduled = 300;
  static const maxPerNote = 21;

  /// Tras un rato cerrada, no se dispara una avalancha de avisos antiguos.
  static const _maxCatchUp = 5;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;
  bool _prefsLoaded = false;
  bool _windowsCleaned = false;
  String _lastSignature = '';
  List<Note>? _lastNotes;
  List<Note> _active = const [];
  Timer? _debounce;
  Timer? _ticker;
  int _nextShownId = 1;
  Map<String, DateTime> _snoozes = {};

  void Function(String noteId)? _onOpen;
  void Function(String noteId)? _onDone;
  NotificationResponse? _waiting;

  ReminderPrefs prefs = const ReminderPrefs();

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  /// Botones del aviso. En Windows cada botón lleva su orden y la nota.
  NotificationDetails _details(String noteId) => NotificationDetails(
        android: AndroidNotificationDetails(
          'recordatorios',
          'Recordatorios',
          channelDescription: 'Avisos de las notas temporales',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: [
            AndroidNotificationAction('done', tr('Hecha'),
                showsUserInterface: true, cancelNotification: true),
            AndroidNotificationAction('snooze', tr('Posponer 10 min'),
                showsUserInterface: true, cancelNotification: true),
          ],
        ),
        windows: WindowsNotificationDetails(
          actions: [
            WindowsAction(content: tr('Hecha'), arguments: 'done|$noteId'),
            WindowsAction(
                content: tr('Posponer 10 min'), arguments: 'snooze|$noteId'),
          ],
        ),
      );

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Oganesson',
          appUserModelId: 'Rafa.Oganesson',
          guid: '6f1c3a52-8e4b-4f6a-9d2e-7c5b1a9e3f40',
        ),
      );
      await _plugin.initialize(settings,
          onDidReceiveNotificationResponse: _onResponse);
      _ready = true;
      // La app se abrió al pulsar un aviso.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true &&
          launch!.notificationResponse != null) {
        _onResponse(launch.notificationResponse!);
      }
    } catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }
  }

  /// La pantalla principal dice qué hacer al pulsar un aviso.
  void attach(
      {required void Function(String noteId) onOpen,
      required void Function(String noteId) onDone}) {
    _onOpen = onOpen;
    _onDone = onDone;
    final w = _waiting;
    _waiting = null;
    if (w != null) _onResponse(w);
  }

  void detach() {
    _onOpen = null;
    _onDone = null;
  }

  void _onResponse(NotificationResponse r) {
    final (action, id) = parseReminderResponse(r.actionId, r.payload);
    if (id == null) return;
    if (action == 'snooze') {
      unawaited(_addSnooze(id));
      return;
    }
    if (_onOpen == null) {
      _waiting = r;
      return;
    }
    action == 'done' ? _onDone?.call(id) : _onOpen?.call(id);
  }

  Future<void> _addSnooze(String id) async {
    await _loadSnoozes();
    _snoozes[id] = DateTime.now().toUtc().add(_snooze);
    await _saveSnoozes();
    _lastSignature = '';
    final notes = _lastNotes;
    if (notes != null) schedule(notes);
  }

  bool _snoozesLoaded = false;

  Future<void> _loadSnoozes() async {
    if (_snoozesLoaded) return;
    _snoozesLoaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kSnoozes);
      if (raw == null) return;
      _snoozes = {
        for (final e in (jsonDecode(raw) as Map).entries)
          '${e.key}': DateTime.parse('${e.value}'),
      };
    } catch (_) {}
  }

  Future<void> _saveSnoozes() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
          _kSnoozes,
          jsonEncode({
            for (final e in _snoozes.entries) e.key: e.value.toIso8601String(),
          }));
    } catch (_) {}
  }

  Future<ReminderPrefs> loadPrefs() async {
    if (_prefsLoaded) return prefs;
    try {
      final sp = await SharedPreferences.getInstance();
      prefs = ReminderPrefs.decode(sp.getString(_kPrefs));
      _prefsLoaded = true;
    } catch (e) {
      debugPrint('Avisos: no se pudo leer la configuración ($e)');
    }
    return prefs;
  }

  /// Guarda las casillas y vuelve a programar los avisos con ellas.
  Future<void> savePrefs(ReminderPrefs next) async {
    prefs = next;
    _prefsLoaded = true;
    try {
      await (await SharedPreferences.getInstance())
          .setString(_kPrefs, next.encode());
    } catch (e) {
      debugPrint('Avisos: no se pudo guardar la configuración ($e)');
    }
    if (next.enabled) await askPermission();
    final notes = _lastNotes;
    if (notes != null) schedule(notes);
  }

  /// ¿Windows tiene apagadas las notificaciones de todas las apps?
  Future<bool> windowsToastsOff() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final r = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications',
        '/v',
        'ToastEnabled',
      ]);
      return r.exitCode == 0 && RegExp(r'0x0\b').hasMatch('${r.stdout}');
    } catch (_) {
      return false;
    }
  }

  /// Lanza un aviso ahora. false si el sistema los tiene desactivados.
  Future<bool> sendTest() async {
    await init();
    if (!_ready || await windowsToastsOff()) return false;
    await askPermission();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.areNotificationsEnabled() == false) return false;
    }
    try {
      await _plugin.show(
          0x7ffffffe,
          tr('Los avisos funcionan'),
          tr('Así te recordaremos tus tareas.'),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'recordatorios',
              'Recordatorios',
              importance: Importance.high,
              priority: Priority.high,
            ),
            windows: WindowsNotificationDetails(),
          ));
      return true;
    } catch (e) {
      debugPrint('Aviso de prueba: $e');
      return false;
    }
  }

  /// Solo para pruebas (`--dart-define=TEST_TOAST=true`): programa un aviso
  /// dentro de [delay] para comprobar si llega con la app cerrada.
  /// Usa un id fuera del rango de los avisos reales y se vuelve a programar
  /// cada vez que [schedule] reprograma (porque hace cancelAll).
  Future<void> scheduleTest(Duration delay) async {
    await init();
    if (!_ready) return;
    await askPermission();
    _testAt = DateTime.now().toUtc().add(delay);
    await _scheduleTest();
  }

  DateTime? _testAt;

  Future<void> _scheduleTest() async {
    final at = _testAt;
    if (at == null || !at.isAfter(DateTime.now().toUtc())) return;
    await _plugin.zonedSchedule(
      0x7fffffff,
      'Prueba de Oganesson',
      'Aviso programado a las ${at.toLocal().toIso8601String().substring(11, 19)}',
      tz.TZDateTime.from(at, tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails('recordatorios', 'Recordatorios'),
        windows: WindowsNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    debugPrint('TEST_TOAST programado para ${at.toLocal()}');
  }

  /// Pide permiso de notificaciones (Android 13+) y de alarmas exactas.
  Future<void> askPermission() async {
    if (!_ready || _permissionAsked) return;
    _permissionAsked = true;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        await android?.requestNotificationsPermission();
        await android?.requestExactAlarmsPermission();
      } catch (e) {
        debugPrint('Permisos: $e');
      }
    }
  }

  /// Reprograma todos los avisos si ha cambiado algo relevante.
  void schedule(List<Note> notes) {
    if (!supported) return;
    _lastNotes = notes;
    final relevant = notes
        .where((n) => n.isTemporal && !n.done && !n.deleted && !n.isEmpty)
        .toList();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final sig = '${prefs.encode()}|$today|${relevant.map((n) => '${n.id}|'
        '${n.dueAt}|${n.remindAt}|${n.isSingleDay}|${n.title}|${n.vault}').join(';')}';
    if (sig == _lastSignature) return;
    _lastSignature = sig;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => _apply(relevant));
  }

  String _titleOf(Note n) => n.vault ? tr('Nota del Vault') : n.title;

  Future<void> _apply(List<Note> notes) async {
    await init();
    if (!_ready) return;
    final wasLoaded = _prefsLoaded;
    final p = await loadPrefs();
    await _loadSnoozes();
    // La firma se calculó con los valores por defecto: se actualiza.
    if (!wasLoaded && _lastNotes != null) {
      _lastSignature = '';
    }
    if (notes.isNotEmpty && p.enabled) await askPermission();

    if (Platform.isWindows) {
      _active = notes;
      // Quita los que programaban las versiones anteriores, una sola vez:
      // cancelAll también borraría los avisos ya visibles.
      if (!_windowsCleaned) {
        _windowsCleaned = true;
        try {
          await _plugin.cancelAll();
          await _scheduleTest();
        } catch (_) {}
      }
      _ticker ??= Timer.periodic(
          const Duration(seconds: 30), (_) => unawaited(_tick()));
      await _tick();
      return;
    }

    try {
      await _plugin.cancelAll();
      await _scheduleTest();
    } catch (_) {}

    final now = DateTime.now().toUtc();
    var exact = true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      exact = await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      exact = false;
    }

    final pending = <(DateTime, String, Note)>[
      for (final n in notes) ...[
        for (final (at, body) in reminderTimes(n, p, now)) (at, body, n),
        if (_snoozes[n.id]?.isAfter(now) ?? false)
          (_snoozes[n.id]!, _dueText(n.dueAt!.toLocal(), 0, n.isAllDay), n),
      ],
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    // Ids seguidos: con el hash de la nota, dos notas podían pisarse.
    for (final (i, (at, body, n)) in pending.take(maxScheduled).indexed) {
      try {
        await _plugin.zonedSchedule(
          i + 1,
          _titleOf(n),
          body,
          tz.TZDateTime.from(at, tz.UTC),
          _details(n.id),
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'open|${n.id}',
        );
      } catch (e) {
        debugPrint('No se pudo programar aviso: $e');
      }
    }
  }

  bool _ticking = false;

  /// Windows: lanza lo que ha vencido desde la última comprobación.
  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final now = DateTime.now().toUtc();
      final stored = DateTime.tryParse(sp.getString(_kLastTick) ?? '');
      final oldest = now.subtract(const Duration(hours: 24));
      final since =
          stored == null ? now : (stored.isBefore(oldest) ? oldest : stored);
      final due = remindersBetween(_active, prefs, since, now);
      for (final (_, body, n) in due.reversed.take(_maxCatchUp)) {
        await _showNow(n, body);
      }
      var changed = false;
      for (final n in _active) {
        final at = _snoozes[n.id];
        if (at != null && !at.isAfter(now)) {
          await _showNow(n, _dueText(n.dueAt!.toLocal(), 0, n.isAllDay));
          _snoozes.remove(n.id);
          changed = true;
        }
      }
      if (changed) await _saveSnoozes();
      await sp.setString(_kLastTick, now.toIso8601String());
    } catch (e) {
      debugPrint('Avisos: $e');
    } finally {
      _ticking = false;
    }
  }

  Future<void> _showNow(Note n, String body) async {
    final id = _nextShownId;
    _nextShownId = id >= 100000 ? 1 : id + 1;
    await _plugin.show(id, _titleOf(n), body, _details(n.id),
        payload: 'open|${n.id}');
  }
}

/// Avisos con hora en el tramo (from, to], del más antiguo al más reciente.
List<(DateTime, String, Note)> remindersBetween(
    List<Note> notes, ReminderPrefs p, DateTime from, DateTime to) {
  final out = <(DateTime, String, Note)>[
    for (final n in notes)
      if (!n.done && !n.deleted)
        for (final (at, body) in reminderTimes(n, p, from))
          if (!at.isAfter(to)) (at, body, n),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// Qué se ha pulsado en un aviso. En Android el botón llega en `actionId`; en
/// Windows, tanto el botón como el aviso llegan como `orden|nota`.
(String, String?) parseReminderResponse(String? actionId, String? payload) {
  final raw = payload ?? '';
  final bar = raw.indexOf('|');
  final verb = bar < 0 ? 'open' : raw.substring(0, bar);
  final id = bar < 0 ? raw : raw.substring(bar + 1);
  if (id.isEmpty) return ('open', null);
  final action = actionId == 'done' || actionId == 'snooze' ? actionId! : verb;
  return (action, id);
}
