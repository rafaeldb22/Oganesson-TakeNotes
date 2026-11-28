import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/notes_repository.dart';
import '../data/reminders.dart';
import '../models/note.dart';
import 'anim.dart';
import 'format.dart' show fechaMedia;
import 'i18n.dart';
import 'theme.dart';

// ---------------------------------------------------------------- pomodoro

enum PomodoroPhase { focus, rest }

/// Pomodoro: 25 min de concentración y 5 de descanso (largo cada 4). Sigue
/// contando aunque se cierre la hoja, y suma los minutos de cada día para
/// las estadísticas.
class Pomodoro extends ChangeNotifier {
  Pomodoro._() {
    loadSettings();
  }
  static final instance = Pomodoro._();

  /// Ajustes (se guardan en el dispositivo): minutos de cada fase, cada
  /// cuántos pomodoros toca el descanso largo y si la siguiente fase empieza
  /// sola.
  int focusMinutes = 25,
      restMinutes = 5,
      longRestMinutes = 15,
      roundsToLong = 4;
  bool autoStart = true;
  static const _kMinutes = 'pomodoro_minutos';
  static const _kSettings = 'pomodoro_ajustes';

  /// "Modo pomodoro" activo: desde Empezar hasta Reiniciar (el tomate de
  /// abajo a la izquierda se ve mientras tanto).
  bool active = false;

  Future<void> loadSettings() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kSettings);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      int v(String k, int d, int min, int max) =>
          ((j[k] as num?)?.toInt() ?? d).clamp(min, max);
      focusMinutes = v('f', 25, 1, 120);
      restMinutes = v('r', 5, 1, 60);
      longRestMinutes = v('l', 15, 1, 90);
      roundsToLong = v('n', 4, 2, 10);
      autoStart = j['a'] != false;
      if (!running) left = total;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    if (!running) left = total;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(
          _kSettings,
          jsonEncode({
            'f': focusMinutes,
            'r': restMinutes,
            'l': longRestMinutes,
            'n': roundsToLong,
            'a': autoStart,
          }));
    } catch (_) {}
  }

  PomodoroPhase phase = PomodoroPhase.focus;
  int rounds = 0; // pomodoros acabados en esta sesión
  Duration left = const Duration(minutes: 25);
  DateTime? _endsAt;
  Timer? _timer;

  bool get running => _endsAt != null;
  Duration get total => Duration(
      minutes: phase == PomodoroPhase.focus
          ? focusMinutes
          : (rounds % roundsToLong == 0 && rounds > 0
              ? longRestMinutes
              : restMinutes));
  double get progress =>
      1 - left.inMilliseconds / total.inMilliseconds.clamp(1, 1 << 31);

  void start() {
    if (running) return;
    active = true;
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
    active = false;
    rounds = 0;
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
    if (keepRunning && autoStart) start();
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

/// Ajustes del pomodoro, plegados bajo un botón.
class _PomodoroSettings extends StatefulWidget {
  const _PomodoroSettings();

  @override
  State<_PomodoroSettings> createState() => _PomodoroSettingsState();
}

class _PomodoroSettingsState extends State<_PomodoroSettings> {
  bool _open = false;

  Widget _stepper(String label, int value, int min, int max, int step,
      void Function(int) set) {
    final p = Palette.of(context);
    return Row(children: [
      Expanded(child: Text(label)),
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: value <= min ? null : () => set(value - step),
        icon: const Icon(Icons.remove_rounded, size: 18),
      ),
      SizedBox(
        width: 44,
        child: Text('$value',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, color: p.accent)),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: value >= max ? null : () => set(value + step),
        icon: const Icon(Icons.add_rounded, size: 18),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pomo = Pomodoro.instance;
    void edit(void Function() f) {
      setState(f);
      pomo.saveSettings();
    }

    return Column(children: [
      TextButton.icon(
        onPressed: () => setState(() => _open = !_open),
        icon: AnimatedRotation(
          turns: _open ? 0.5 : 0,
          duration: Anim.medium,
          child: const Icon(Icons.tune_rounded, size: 18),
        ),
        label: Text(tr('Ajustes del pomodoro')),
      ),
      AnimatedSize(
        duration: Anim.medium,
        curve: Anim.curve,
        child: !_open
            ? const SizedBox(width: double.infinity)
            : Column(children: [
                _stepper(tr('Concentración (min)'), pomo.focusMinutes, 5, 120,
                    5, (v) => edit(() => pomo.focusMinutes = v)),
                _stepper(tr('Descanso corto (min)'), pomo.restMinutes, 1, 30, 1,
                    (v) => edit(() => pomo.restMinutes = v)),
                _stepper(tr('Descanso largo (min)'), pomo.longRestMinutes, 5,
                    60, 5, (v) => edit(() => pomo.longRestMinutes = v)),
                _stepper(
                    tr('Pomodoros hasta el descanso largo'),
                    pomo.roundsToLong,
                    2,
                    10,
                    1,
                    (v) => edit(() => pomo.roundsToLong = v)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Empezar la siguiente fase sola')),
                  value: pomo.autoStart,
                  onChanged: (v) => edit(() => pomo.autoStart = v),
                ),
              ]),
      ),
    ]);
  }
}

/// El tomate del pomodoro (abajo a la derecha mientras está activo), como
/// el boceto: cuerpo redondo con el color del tema, dos hojas arriba y una
/// pantallita con el tiempo. Tocarlo abre el pomodoro.
class PomodoroTomato extends StatefulWidget {
  const PomodoroTomato(
      {super.key, required this.onTap, this.alwaysVisible = false});
  final VoidCallback onTap;

  /// En el widget de escritorio se ve aunque el pomodoro no haya empezado.
  final bool alwaysVisible;

  @override
  State<PomodoroTomato> createState() => _PomodoroTomatoState();
}

class _PomodoroTomatoState extends State<PomodoroTomato> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pomo = Pomodoro.instance;
    return ListenableBuilder(
      listenable: pomo,
      builder: (context, _) {
        final p = Palette.of(context);
        final focus = pomo.phase == PomodoroPhase.focus;
        // Del tema: el acento; en el descanso, el acento más suave.
        final body = focus ? p.accent : Color.lerp(p.accent, p.card, 0.45)!;
        final visible = pomo.active || widget.alwaysVisible;
        // Sin Tooltip: el tomate está por encima del Navigator (sin Overlay)
        // y un Tooltip ahí rompía la pantalla entera al pasar el ratón.
        return AnimatedSwitcher(
          duration: Anim.medium,
          transitionBuilder: (c, a) => ScaleTransition(
              scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
              child: FadeTransition(opacity: a, child: c)),
          child: !visible
              ? const SizedBox.shrink(key: ValueKey('sin-tomate'))
              : MouseRegion(
                  key: const ValueKey('tomate'),
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hover = true),
                  onExit: (_) => setState(() => _hover = false),
                  child: GestureDetector(
                    onTap: widget.onTap,
                    child: AnimatedScale(
                      duration: Anim.fast,
                      scale: _hover ? 1.06 : 1,
                      child: SizedBox(
                        width: 116,
                        height: 116,
                        child: CustomPaint(
                          painter: _Tomato(
                            body: body,
                            leaf: Color.lerp(p.accent, Colors.black, 0.35)!,
                            screen: p.card,
                            ink: p.accent,
                            progress: pomo.progress,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 22),
                            child: Center(
                              child: Text(_mmss(pomo.left),
                                  style: TextStyle(
                                      color: Color.lerp(
                                          p.accent, Colors.black, 0.25),
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Tomato extends CustomPainter {
  const _Tomato({
    required this.body,
    required this.leaf,
    required this.screen,
    required this.ink,
    required this.progress,
  });
  final Color body, leaf, screen, ink;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w / 2, h * 0.58);
    final round = Rect.fromCenter(center: c, width: w * 0.88, height: h * 0.78);
    // Sombra suave.
    canvas.drawOval(
        round.shift(const Offset(0, 4)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    // Cuerpo: el color del tema con un brillo arriba a la izquierda.
    canvas.drawOval(
        round,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            radius: 0.95,
            colors: [Color.lerp(body, Colors.white, 0.35)!, body],
          ).createShader(round));
    // Lo que queda de la fase, por dentro del borde.
    canvas.drawArc(
        round.deflate(5),
        -math.pi / 2,
        math.pi * 2 * (1 - progress.clamp(0.0, 1.0)),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.7));
    // Dos hojas y el rabito (como en el boceto).
    final top = Offset(w / 2, round.top + 3);
    final leafPaint = Paint()..color = leaf;
    void leafAt(double dir) {
      final tip = top + Offset(dir * w * 0.26, -h * 0.13);
      canvas.drawPath(
          Path()
            ..moveTo(top.dx, top.dy)
            ..quadraticBezierTo(
                top.dx + dir * w * 0.06, tip.dy - h * 0.07, tip.dx, tip.dy)
            ..quadraticBezierTo(
                top.dx + dir * w * 0.16, top.dy + h * 0.02, top.dx, top.dy)
            ..close(),
          leafPaint);
    }

    leafAt(-1);
    leafAt(1);
    canvas.drawLine(
        top,
        top + Offset(w * 0.03, -h * 0.09),
        Paint()
          ..color = leaf
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round);
    // Pantallita del tiempo.
    final display = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w / 2, c.dy + 2), width: w * 0.62, height: h * 0.26),
        const Radius.circular(9));
    canvas.drawRRect(display, Paint()..color = screen.withValues(alpha: 0.95));
    canvas.drawRRect(
        display,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Color.lerp(ink, Colors.black, 0.3)!);
  }

  @override
  bool shouldRepaint(_Tomato o) =>
      o.body != body ||
      o.progress != progress ||
      o.leaf != leaf ||
      o.screen != screen;
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
                  for (var i = 0; i < pomo.roundsToLong; i++)
                    AnimatedContainer(
                      duration: Anim.medium,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < pomo.rounds % pomo.roundsToLong ||
                                (pomo.rounds > 0 &&
                                    pomo.rounds % pomo.roundsToLong == 0)
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
                      [pomo.focusMinutes, pomo.restMinutes]),
                  style: TextStyle(color: p.secondary, fontSize: 12.5)),
              const SizedBox(height: 6),
              const _PomodoroSettings(),
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
  ProductivityStats(this.days, this.done, this.created, this.focus,
      [this.doneTasks = const []]);
  final List<DateTime> days;
  final List<int> done, created, focus;

  /// Las tareas completadas en el periodo, la última primero.
  final List<Note> doneTasks;

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
    final tasks = <Note>[];
    final seen = <String>{};
    for (final n in [...repo.notes, ...repo.completed]) {
      if (n.vault || !seen.add(n.id)) continue;
      final c = at(n.createdAt);
      if (c >= 0) created[c]++;
      final d = n.doneAt;
      if (n.done && d != null && at(d) >= 0) {
        done[at(d)]++;
        tasks.add(n);
      }
    }
    tasks.sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    final minutes = await Pomodoro.minutesByDay();
    final focus = [for (final d in list) minutes[Pomodoro._day(d)] ?? 0];
    return ProductivityStats(list, done, created, focus, tasks);
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
            Text(tr('Tareas completadas'),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: p.secondary)),
            const SizedBox(height: 6),
            if (s.doneTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(tr('Aún no has completado tareas en este periodo.'),
                    style: TextStyle(color: p.secondary)),
              )
            else
              for (final (i, n) in s.doneTasks.take(40).indexed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle_rounded, color: p.accent),
                  title: Text(n.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(fechaMedia(n.doneAt!),
                      style: TextStyle(color: p.secondary, fontSize: 12)),
                )
                    .animate(delay: (25 * i.clamp(0, 15)).ms)
                    .fadeIn(duration: Anim.medium)
                    .slideX(begin: 0.05),
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
