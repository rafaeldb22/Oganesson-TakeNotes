import 'dart:async';
import 'dart:convert';
import '../ui/i18n.dart';
import 'dart:io' show Platform;

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
    this.hour = 9,
    this.minute = 0,
  });

  final bool enabled, daily, weekly, week, three, day;
  final int hour, minute;

  ReminderPrefs copyWith({
    bool? enabled,
    bool? daily,
    bool? weekly,
    bool? week,
    bool? three,
    bool? day,
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
    if (singleDay) 0,
    if (p.week && daysLeft >= 7) 7,
    if (p.three && daysLeft >= 3) 3,
    if (p.day && daysLeft >= 1) 1,
    if (p.daily)
      for (var d = 0; d <= span; d++) d,
    if (p.weekly)
      for (var d = 7; d <= span; d += 7) d,
  };
}

/// Avisos pendientes de una nota, del más cercano al más lejano.
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
          singleDay: n.isSingleDay)
      .toList()
    ..sort((a, b) => b.compareTo(a));
  final out = <(DateTime, String)>[];
  for (final d in days) {
    var at = DateTime(due.year, due.month, due.day - d, p.hour, p.minute);
    // Si vence antes de la hora de avisar, una hora antes de que venza.
    if (d == 0 && at.isAfter(due)) at = due.subtract(const Duration(hours: 1));
    if (!at.isAfter(local)) continue;
    out.add((
      at.toUtc(),
      switch (d) {
        0 => tr('Es hoy'),
        1 => tr('Queda 1 día'),
        _ => trf('Quedan {0} días', [d]),
      }
    ));
    if (out.length >= Reminders.maxPerNote) break;
  }
  return out;
}

/// Programa los avisos de las notas temporales en el propio dispositivo
/// (Android y Windows). Cada dispositivo programa los suyos a partir de las
/// notas sincronizadas, así que el aviso llega aunque la nota se creara
/// en el otro.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  static const _kPrefs = 'avisos_v1';

  /// Android admite unas 500 alarmas por app: se programan las más cercanas
  /// y el resto al volver a abrir la app.
  static const maxScheduled = 300;
  static const maxPerNote = 21;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'recordatorios',
      'Recordatorios',
      channelDescription: 'Avisos de las notas temporales',
      importance: Importance.high,
      priority: Priority.high,
    ),
    windows: WindowsNotificationDetails(),
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;
  bool _prefsLoaded = false;
  String _lastSignature = '';
  List<Note>? _lastNotes;
  Timer? _debounce;

  ReminderPrefs prefs = const ReminderPrefs();

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isWindows);

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
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }
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

  /// Lanza un aviso ahora. false si el sistema los tiene desactivados.
  Future<bool> sendTest() async {
    await init();
    if (!_ready) return false;
    await askPermission();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.areNotificationsEnabled() == false) return false;
    }
    try {
      await _plugin.show(0x7ffffffe, tr('Los avisos funcionan'),
          tr('Así te recordaremos tus tareas.'), _details);
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

  Future<void> _apply(List<Note> notes) async {
    await init();
    if (!_ready) return;
    final wasLoaded = _prefsLoaded;
    final p = await loadPrefs();
    // La firma se calculó con los valores por defecto: se actualiza.
    if (!wasLoaded && _lastNotes != null) {
      _lastSignature = '';
    }
    if (notes.isNotEmpty && p.enabled) await askPermission();
    try {
      await _plugin.cancelAll();
      await _scheduleTest();
    } catch (_) {}

    final now = DateTime.now().toUtc();
    var exact = true;
    if (Platform.isAndroid) {
      try {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        exact = await android?.canScheduleExactNotifications() ?? false;
      } catch (_) {
        exact = false;
      }
    }

    final pending = <(DateTime, String, Note)>[
      for (final n in notes)
        for (final (at, body) in reminderTimes(n, p, now)) (at, body, n),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    // Ids seguidos: con el hash de la nota, dos notas podían pisarse.
    for (final (i, (at, body, n)) in pending.take(maxScheduled).indexed) {
      final title = n.vault ? tr('Nota del Vault') : n.title;
      try {
        await _plugin.zonedSchedule(
          i + 1,
          trf('Recordatorio: {0}', [title]),
          body,
          tz.TZDateTime.from(at, tz.UTC),
          _details,
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: n.id,
        );
      } catch (e) {
        debugPrint('No se pudo programar aviso: $e');
      }
    }
  }
}
