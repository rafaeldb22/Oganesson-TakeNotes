import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';

/// Programa los avisos de las notas temporales en el propio dispositivo
/// (Android y Windows). Cada dispositivo programa los suyos a partir de las
/// notas sincronizadas, así que el aviso llega aunque la nota se creara
/// en el otro.
///
/// Avisos por nota: al empezar el periodo (si se puso "avisar desde"),
/// 1 hora antes de la fecha límite y a la hora límite.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;
  String _lastSignature = '';
  Timer? _debounce;

  bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Notas',
          appUserModelId: 'Rafa.Notas',
          guid: '6f1c3a52-8e4b-4f6a-9d2e-7c5b1a9e3f40',
        ),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }
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
    final relevant = notes
        .where((n) => n.isTemporal && !n.done && !n.deleted && !n.isEmpty)
        .toList();
    final sig = relevant
        .map((n) => '${n.id}|${n.remindAt}|${n.dueAt}|${n.title}')
        .join(';');
    if (sig == _lastSignature) return;
    _lastSignature = sig;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => _apply(relevant));
  }

  Future<void> _apply(List<Note> notes) async {
    await init();
    if (!_ready) return;
    if (notes.isNotEmpty) await askPermission();
    try {
      await _plugin.cancelAll();
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

    for (final n in notes) {
      final base = (n.id.hashCode & 0x0fffffff) * 4;
      final due = n.dueAt!;
      final avisos = <(int, DateTime, String)>[
        if (n.remindAt != null) (base, n.remindAt!, 'Empieza: ${n.title}'),
        (base + 1, due.subtract(const Duration(hours: 1)), 'Queda 1 hora: ${n.title}'),
        (base + 2, due, 'Se acaba el tiempo: ${n.title}'),
      ];
      for (final (id, when, title) in avisos) {
        if (!when.isAfter(now)) continue;
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            n.preview == 'Sin texto adicional' ? null : n.preview,
            tz.TZDateTime.from(when, tz.UTC),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'recordatorios',
                'Recordatorios',
                channelDescription: 'Avisos de las notas temporales',
                importance: Importance.high,
                priority: Priority.high,
              ),
              windows: WindowsNotificationDetails(),
            ),
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
}
