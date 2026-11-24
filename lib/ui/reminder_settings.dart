import 'package:flutter/material.dart';

import '../data/reminders.dart';
import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';
import 'toast.dart';

/// Elegir cuándo avisar de las tareas. Cada cambio se guarda al momento.
Future<void> showReminderSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => const _ReminderSheet(),
    );

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet();

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  ReminderPrefs _p = Reminders.instance.prefs;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    Reminders.instance.loadPrefs().then((p) {
      if (mounted) setState(() => _p = p);
    });
  }

  void _set(ReminderPrefs next) {
    setState(() => _p = next);
    Reminders.instance.savePrefs(next);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _p.hour, minute: _p.minute),
      helpText: tr('Hora de los avisos'),
    );
    if (t != null && mounted) _set(_p.copyWith(hour: t.hour, minute: t.minute));
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final ok = await Reminders.instance.sendTest();
    if (!mounted) return;
    setState(() => _testing = false);
    showToast(
      context,
      ok
          ? tr('Aviso enviado')
          : tr('El sistema tiene los avisos desactivados para la app'),
      icon: ok
          ? Icons.notifications_active_outlined
          : Icons.notifications_off_outlined,
    );
  }

  String get _time => '${_p.hour}:${_p.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Avisos'),
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(tr('Elige cuándo quieres que te recordemos tus tareas.'),
                style: TextStyle(color: p.secondary, fontSize: 13)),
            const SizedBox(height: 14),
            _MasterCard(
              on: _p.enabled,
              onChanged: (v) => _set(_p.copyWith(enabled: v)),
            ),
            AnimatedOpacity(
              duration: Anim.medium,
              opacity: _p.enabled ? 1 : 0.38,
              child: IgnorePointer(
                ignoring: !_p.enabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Heading(tr('Antes de la fecha límite')),
                    Row(
                      children: [
                        for (final (i, (days, label, on, change)) in [
                          (
                            7,
                            tr('una semana antes'),
                            _p.week,
                            (bool v) => _p.copyWith(week: v)
                          ),
                          (
                            3,
                            tr('tres días antes'),
                            _p.three,
                            (bool v) => _p.copyWith(three: v)
                          ),
                          (
                            1,
                            tr('el día de antes'),
                            _p.day,
                            (bool v) => _p.copyWith(day: v)
                          ),
                        ].indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _DayCard(
                              days: days,
                              label: label,
                              on: on,
                              onTap: () => _set(change(!on)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    _Heading(tr('Mientras dure la tarea')),
                    _RepeatTile(
                      icon: Icons.today_rounded,
                      title: tr('Cada día'),
                      subtitle: tr('Un aviso diario hasta que venza'),
                      on: _p.daily,
                      onTap: () => _set(_p.copyWith(daily: !_p.daily)),
                    ),
                    const SizedBox(height: 8),
                    _RepeatTile(
                      icon: Icons.date_range_rounded,
                      title: tr('Cada semana'),
                      subtitle: tr('Un aviso cada 7 días hasta que venza'),
                      on: _p.weekly,
                      onTap: () => _set(_p.copyWith(weekly: !_p.weekly)),
                    ),
                    _Heading(tr('A qué hora')),
                    _TimeTile(time: _time, onTap: _pickTime),
                    const SizedBox(height: 14),
                    _Preview(prefs: _p),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: const Icon(Icons.notifications_outlined, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(tr('Probar aviso')),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Listo')),
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Palette.secondary(context))),
      );
}

class _MasterCard extends StatelessWidget {
  const _MasterCard({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AnimatedContainer(
      duration: Anim.medium,
      curve: Anim.curve,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: on ? p.accent.withValues(alpha: 0.14) : p.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
              on
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_outlined,
              color: on ? p.accent : p.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(on ? tr('Avisos activados') : tr('Avisos desactivados'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Switch(value: on, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.days,
    required this.label,
    required this.on,
    required this.onTap,
  });
  final int days;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: Anim.fast,
            curve: Anim.curve,
            constraints: const BoxConstraints(minHeight: 104),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            decoration: BoxDecoration(
              color: on ? p.accent : p.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    on ? Icons.check_circle : Icons.circle_outlined,
                    size: 16,
                    color: on ? p.onAccent : p.secondary,
                  ),
                ),
                Text('$days',
                    style: TextStyle(
                        fontSize: 28,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: on ? p.onAccent : null)),
                const SizedBox(height: 2),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        color: on ? p.onAccent : p.secondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RepeatTile extends StatelessWidget {
  const _RepeatTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      toggled: on,
      label: title,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: Anim.fast,
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            decoration: BoxDecoration(
              color: on ? p.accent.withValues(alpha: 0.14) : p.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(icon, size: 21, color: on ? p.accent : p.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(subtitle,
                          style: TextStyle(fontSize: 12, color: p.secondary)),
                    ],
                  ),
                ),
                Icon(on ? Icons.check_circle : Icons.circle_outlined,
                    size: 21, color: on ? p.accent : p.secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.time, required this.onTap});
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 21, color: p.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr('Hora de los avisos'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(time,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: p.accent)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, color: p.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Las dos últimas semanas de una tarea, con los días en que sonaría.
class _Preview extends StatelessWidget {
  const _Preview({required this.prefs});
  final ReminderPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const span = 14;
    final days = reminderDays(prefs, span, span);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            days.isEmpty
                ? tr('Con esta selección no recibirás avisos')
                : days.length == 1
                    ? tr('En una tarea de 2 semanas recibirás 1 aviso')
                    : trf('En una tarea de 2 semanas recibirás {0} avisos',
                        [days.length]),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var d = span; d >= 0; d--)
                Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: Anim.fast,
                      width: d == 0 ? 12 : 9,
                      height: d == 0 ? 12 : 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: days.contains(d)
                            ? p.accent
                            : p.secondary.withValues(alpha: 0.25),
                        border: d == 0
                            ? Border.all(color: p.secondary, width: 1.5)
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(tr('Hace 2 semanas'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.secondary)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(tr('Fecha límite'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.secondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
