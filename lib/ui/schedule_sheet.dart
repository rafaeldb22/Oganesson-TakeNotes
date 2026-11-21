import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../data/reminders.dart';
import 'anim.dart';
import 'format.dart';
import 'theme.dart';
import 'urgency.dart';

/// Hoja para convertir una nota en temporal: fecha límite, desde cuándo
/// avisar y atajos rápidos. Los avisos se programan solos al guardar.
Future<void> showScheduleSheet(
    BuildContext context, NotesRepository repo, String noteId,
    {DateTime? initialDue}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) =>
        _ScheduleSheet(repo: repo, noteId: noteId, initialDue: initialDue),
  );
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet(
      {required this.repo, required this.noteId, this.initialDue});
  final NotesRepository repo;
  final String noteId;
  final DateTime? initialDue;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  DateTime? _start; // local
  DateTime? _due; // local

  @override
  void initState() {
    super.initState();
    final n = widget.repo.byId(widget.noteId);
    _start = n?.remindAt?.toLocal();
    _due = n?.dueAt?.toLocal() ?? widget.initialDue;
    if (_due != null && _start == null && n?.dueAt == null) {
      _start = DateTime.now();
    }
  }

  DateTime _at(DateTime day, int h, [int m = 0]) =>
      DateTime(day.year, day.month, day.day, h, m);

  void _preset(Duration offset, {int? hour}) {
    final now = DateTime.now();
    var d = now.add(offset);
    if (hour != null) d = _at(d, hour);
    setState(() {
      _due = d;
      _start ??= now;
    });
  }

  Future<DateTime?> _pick(DateTime? current) async {
    final range = calendarRange();
    final now = DateTime.now();
    var initial = current ?? now;
    if (initial.isBefore(range.first)) initial = range.first;
    if (initial.isAfter(range.last)) initial = range.last;
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: range.first,
      lastDate: range.last,
      helpText: 'Elige el día',
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? _at(now, 20)),
      helpText: 'Elige la hora',
    );
    if (!mounted) return null;
    final t = time ?? const TimeOfDay(hour: 20, minute: 0);
    return _at(day, t.hour, t.minute);
  }

  void _save() {
    var start = _start;
    final due = _due;
    if (due != null && start != null && start.isAfter(due)) start = due;
    widget.repo.setSchedule(widget.noteId, remindAt: start, dueAt: due);
    if (due != null) Reminders.instance.askPermission();
    Navigator.pop(context);
  }

  void _clear() {
    widget.repo.setSchedule(widget.noteId, remindAt: null, dueAt: null);
    Navigator.pop(context);
  }

  Widget _row({
    required IconData icon,
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final accent = Palette.accent(context);
    return Bouncy(
      pressedScale: 0.98,
      child: Material(
        color: Palette.background(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 12, color: Palette.secondary(context))),
                      AnimatedSwitcher(
                        duration: Anim.fast,
                        child: Text(
                          value == null
                              ? 'Sin fecha'
                              : fechaLarga(value.toUtc()),
                          key: ValueKey(value),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                if (value != null && onClear != null)
                  IconButton(
                      tooltip: 'Quitar',
                      onPressed: onClear,
                      icon: const Icon(Icons.close, size: 18)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hadSchedule = widget.repo.byId(widget.noteId)?.dueAt != null;
    final presets = <(String, VoidCallback)>[
      ('Hoy 20:00', () => _preset(Duration.zero, hour: 20)),
      ('Mañana 9:00', () => _preset(const Duration(days: 1), hour: 9)),
      ('En 3 días', () => _preset(const Duration(days: 3), hour: 20)),
      ('En 1 semana', () => _preset(const Duration(days: 7), hour: 20)),
      ('En 1 mes', () => _preset(const Duration(days: 30), hour: 20)),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nota temporal',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Te aviso al empezar, 1 hora antes y cuando se acabe el tiempo.',
              style: TextStyle(color: Palette.secondary(context)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < presets.length; i++)
                  ActionChip(
                    label: Text(presets[i].$1),
                    avatar: const Icon(Icons.bolt, size: 16),
                    onPressed: presets[i].$2,
                  )
                      .animate(delay: (40 * i).ms)
                      .fadeIn(duration: Anim.medium)
                      .slideX(begin: 0.2, curve: Anim.curve),
              ],
            ),
            const SizedBox(height: 16),
            _row(
              icon: Icons.flag_outlined,
              label: 'Fecha límite',
              value: _due,
              onTap: () async {
                final d = await _pick(_due);
                if (d != null) {
                  setState(() {
                    _due = d;
                    _start ??= DateTime.now();
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            _row(
              icon: Icons.notifications_active_outlined,
              label: 'Empieza / avisar desde',
              value: _start,
              onTap: () async {
                final d = await _pick(_start);
                if (d != null) setState(() => _start = d);
              },
              onClear: () => setState(() => _start = null),
            ),
            const SizedBox(height: 14),
            AnimatedSize(
              duration: Anim.medium,
              curve: Anim.curve,
              child: _due == null
                  ? const SizedBox(width: double.infinity)
                  : _Preview(start: _start, due: _due!),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (hadSchedule)
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('Quitar fechas'),
                  ),
                const Spacer(),
                Bouncy(
                  child: FilledButton.icon(
                    onPressed: _due == null ? null : _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Vista previa de la barra de tiempo con las fechas elegidas.
class _Preview extends StatelessWidget {
  const _Preview({required this.start, required this.due});
  final DateTime? start;
  final DateTime due;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final s = start ?? now;
    final total = due.difference(s).inSeconds;
    final p = total <= 0
        ? 1.0
        : (now.difference(s).inSeconds / total).clamp(0.0, 1.0);
    final color = p >= 1
        ? const Color(0xFFE5484D)
        : (p < 0.5
            ? const Color(0xFF30A46C)
            : (p < 0.8 ? const Color(0xFFF5A524) : const Color(0xFFF76B15)));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tiempoRestante(due.toUtc()),
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}
