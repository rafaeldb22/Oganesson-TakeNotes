import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/notes_repository.dart';
import '../data/reminders.dart';
import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';

// ---------------------------------------------------------------- pomodoro

enum PomodoroPhase { focus, rest }

/// Pomodoro: 25 min de concentración y 5 de descanso (largo cada 4). Sigue
/// contando aunque se cierre la hoja, y suma los minutos de cada día para
/// las estadísticas.
class Pomodoro extends ChangeNotifier {
  Pomodoro._();
  static final instance = Pomodoro._();

  static const focusMinutes = 25, restMinutes = 5, longRestMinutes = 15;
  static const _kMinutes = 'pomodoro_minutos';

  PomodoroPhase phase = PomodoroPhase.focus;
  int rounds = 0; // pomodoros acabados en esta sesión
  Duration left = const Duration(minutes: focusMinutes);
  DateTime? _endsAt;
  Timer? _timer;

  bool get running => _endsAt != null;
  Duration get total => Duration(
      minutes: phase == PomodoroPhase.focus
          ? focusMinutes
          : (rounds % 4 == 0 && rounds > 0 ? longRestMinutes : restMinutes));
  double get progress =>
      1 - left.inMilliseconds / total.inMilliseconds.clamp(1, 1 << 31);

  void start() {
    if (running) return;
    _endsAt = DateTime.now().add(left);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    _tick();
    _timer?.cancel();
    _endsAt = null;
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _endsAt = null;
    phase = PomodoroPhase.focus;
    left = total;
    notifyListeners();
  }

  /// Salta a la siguiente fase (o la termina antes de tiempo).
  void skip() => _finish(early: true);

  void _tick() {
    final end = _endsAt;
    if (end == null) return;
    left = end.difference(DateTime.now());
    if (left <= Duration.zero) {
      _finish();
    } else {
      notifyListeners();
    }
  }

  void _finish({bool early = false}) {
    final wasFocus = phase == PomodoroPhase.focus;
    if (wasFocus) {
      final minutes =
          (total - (left.isNegative ? Duration.zero : left)).inMinutes;
      if (minutes > 0) unawaited(_addMinutes(minutes));
      if (!early) rounds++;
    }
    final keepRunning = running;
    _timer?.cancel();
    _endsAt = null;
    phase = wasFocus ? PomodoroPhase.rest : PomodoroPhase.focus;
    left = total;
    if (!early) {
      unawaited(Reminders.instance.notify(
          wasFocus ? tr('¡Pomodoro terminado!') : tr('Descanso terminado'),
          wasFocus
              ? tr('Tómate un descanso.')
              : tr('A por el siguiente pomodoro.')));
    }
    notifyListeners();
    if (keepRunning) start();
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<Map<String, int>> minutesByDay() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kMinutes);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry('$k', (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _addMinutes(int m) async {
    final all = await minutesByDay();
    final k = _day(DateTime.now());
    all[k] = (all[k] ?? 0) + m;
    // Solo los últimos 120 días.
    final keep = all.keys.toList()..sort();
    for (final old in keep.take(math.max(0, keep.length - 120))) {
      all.remove(old);
    }
    await (await SharedPreferences.getInstance())
        .setString(_kMinutes, jsonEncode(all));
  }
}

String _mmss(Duration d) {
  final s = d.inSeconds.clamp(0, 1 << 31);
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

Future<void> showPomodoro(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => const _PomodoroSheet(),
    );

class _PomodoroSheet extends StatelessWidget {
  const _PomodoroSheet();

  @override
  Widget build(BuildContext context) {
    final pomo = Pomodoro.instance;
    return ListenableBuilder(
      listenable: pomo,
      builder: (context, _) {
        final p = Palette.of(context);
        final focus = pomo.phase == PomodoroPhase.focus;
        final color = focus ? p.accent : const Color(0xFF2DD4A7);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Pomodoro'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: Anim.medium,
                child: Text(
                  focus ? tr('Concentración') : tr('Descanso'),
                  key: ValueKey(focus),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 210,
                height: 210,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: pomo.progress),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, v, _) => CustomPaint(
                    painter: _Ring(v, color, p.separator),
                    child: Center(
                      child: Text(_mmss(pomo.left),
                          style: const TextStyle(
                              fontSize: 46,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ),
                ),
              ).animate().scale(
                  begin: const Offset(0.85, 0.85),
                  curve: Curves.easeOutBack,
                  duration: Anim.slow),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: Anim.medium,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < pomo.rounds % 4 ||
                                (pomo.rounds > 0 && pomo.rounds % 4 == 0)
                            ? color
                            : p.separator,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: tr('Reiniciar'),
                    onPressed: pomo.reset,
                    icon: const Icon(Icons.replay_rounded),
                  ),
                  const SizedBox(width: 12),
                  Bouncy(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: pomo.running ? pomo.pause : pomo.start,
                      icon: Icon(pomo.running
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                      label: Text(pomo.running ? tr('Pausar') : tr('Empezar'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: tr('Saltar'),
                    onPressed: pomo.skip,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                  trf('{0} min de concentración · {1} de descanso',
                      [Pomodoro.focusMinutes, Pomodoro.restMinutes]),
                  style: TextStyle(color: p.secondary, fontSize: 12.5)),
            ],
          ),
        );
      },
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring(this.value, this.color, this.track);
  final double value;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, base..color = track);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value.clamp(0.0, 1.0), false,
        base..color = color);
  }

  @override
  bool shouldRepaint(_Ring old) => old.value != value || old.color != color;
}

// ------------------------------------------------------------ estadísticas

/// Datos de productividad de los últimos [days] días (hoy el último).
class ProductivityStats {
  ProductivityStats(this.days, this.done, this.created, this.focus);
  final List<DateTime> days;
  final List<int> done, created, focus;

  static Future<ProductivityStats> of(NotesRepository repo,
      {int days = 7, DateTime? now}) async {
    final today = now ?? DateTime.now();
    final list = [
      for (var i = days - 1; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i)
    ];
    int at(DateTime utc) {
      final l = utc.toLocal();
      return list.indexOf(DateTime(l.year, l.month, l.day));
    }

    final done = List.filled(days, 0), created = List.filled(days, 0);
    for (final n in [...repo.notes, ...repo.completed]) {
      if (n.vault) continue;
      final c = at(n.createdAt);
      if (c >= 0) created[c]++;
      final d = n.doneAt;
      if (n.done && d != null && at(d) >= 0) done[at(d)]++;
    }
    final minutes = await Pomodoro.minutesByDay();
    final focus = [for (final d in list) minutes[Pomodoro._day(d)] ?? 0];
    return ProductivityStats(list, done, created, focus);
  }
}

Future<void> showProductivity(BuildContext context, NotesRepository repo) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => _StatsSheet(repo: repo),
    );

class _StatsSheet extends StatefulWidget {
  const _StatsSheet({required this.repo});
  final NotesRepository repo;

  @override
  State<_StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<_StatsSheet> {
  int _days = 7;
  ProductivityStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ProductivityStats.of(widget.repo, days: _days);
    if (mounted) setState(() => _stats = s);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = _stats;
    int sum(List<int> l) => l.fold(0, (a, b) => a + b);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(tr('Productividad'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 7, label: Text(tr('Semana'))),
                ButtonSegment(value: 30, label: Text(tr('Mes'))),
              ],
              selected: {_days},
              onSelectionChanged: (v) {
                setState(() => _days = v.first);
                _load();
              },
            ),
          ]),
          const SizedBox(height: 16),
          if (s == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Row(children: [
              _Tile(Icons.task_alt_rounded, tr('Tareas hechas'),
                  '${sum(s.done)}', p.accent),
              const SizedBox(width: 10),
              _Tile(Icons.note_add_outlined, tr('Notas creadas'),
                  '${sum(s.created)}', const Color(0xFFFF8A3D)),
              const SizedBox(width: 10),
              _Tile(Icons.timer_outlined, tr('Concentración'),
                  _hours(sum(s.focus)), const Color(0xFF2DD4A7)),
            ]),
            const SizedBox(height: 22),
            _Bars(tr('Tareas hechas'), s.days, s.done, p.accent),
            _Bars(tr('Notas creadas'), s.days, s.created,
                const Color(0xFFFF8A3D)),
            _Bars(tr('Minutos de concentración'), s.days, s.focus,
                const Color(0xFF2DD4A7)),
          ],
        ],
      ),
    );
  }

  static String _hours(int minutes) => minutes < 60
      ? '$minutes min'
      : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: Palette.secondary(context))),
            ],
          ),
        ).animate().fadeIn(duration: Anim.medium).slideY(begin: 0.15),
      );
}

/// Barras por día, que crecen al aparecer.
class _Bars extends StatelessWidget {
  const _Bars(this.title, this.days, this.values, this.color);
  final String title;
  final List<DateTime> days;
  final List<int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = values.fold(0, math.max).clamp(1, 1 << 31);
    final p = Palette.of(context);
    final few = days.length <= 7;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: p.secondary)),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Tooltip(
                      message: '${days[i].day}/${days[i].month}: ${values[i]}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: values[i] / top),
                            duration: Anim.slow,
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => Container(
                              height: 4 + 70 * v,
                              margin: EdgeInsets.symmetric(
                                  horizontal: few ? 8 : 1.5),
                              decoration: BoxDecoration(
                                color: values[i] == 0
                                    ? p.separator
                                    : color.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          if (few) ...[
                            const SizedBox(height: 4),
                            Text(diaCorto(days[i]),
                                style: TextStyle(
                                    fontSize: 11, color: p.secondary)),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "L", "M"… del día.
String diaCorto(DateTime d) {
  const es = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  const en = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return (appLanguage.code == 'en' ? en : es)[d.weekday - 1];
}
