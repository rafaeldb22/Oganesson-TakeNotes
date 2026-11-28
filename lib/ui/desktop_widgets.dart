import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:window_manager/window_manager.dart';

import '../data/desktop_integration.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'calendar_views.dart' show calendarColor;
import 'focus_tools.dart';
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';

/// Las notas de la sesión abierta (las pone la pantalla principal), para
/// los widgets de escritorio.
NotesRepository? activeRepo;

/// Widgets de escritorio: la app se convierte en una ventanita flotante,
/// siempre visible, con el widget elegido. (Los widgets del panel de
/// Windows 11 solo existen para apps empaquetadas para la Store.)
const desktopWidgets = <(String, IconData, String, String)>[
  (
    'tareas',
    Icons.checklist_rounded,
    'Próximas tareas',
    'Lo que vence antes, siempre a la vista'
  ),
  (
    'calendario',
    Icons.calendar_month_rounded,
    'Calendario del mes',
    'El mes con un punto en los días con tareas'
  ),
  ('pomodoro', Icons.timer_outlined, 'Pomodoro', 'El tomate y sus botones'),
  (
    'fijada',
    Icons.push_pin_outlined,
    'Nota fijada',
    'Tu primera nota fijada, para leerla de un vistazo'
  ),
];

Future<void> showWidgetsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (ctx) {
        final p = Palette.of(ctx);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(children: [
              Icon(Icons.widgets_outlined, color: p.accent),
              const SizedBox(width: 10),
              Text(tr('Widgets de escritorio'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            Text(
                tr('Oganesson se convierte en una ventanita siempre visible '
                    'en el escritorio. Arrástrala donde quieras; el botón de '
                    'abrir la devuelve a su tamaño.'),
                style: TextStyle(color: p.secondary, fontSize: 13)),
            const SizedBox(height: 14),
            for (final (i, (id, icon, name, hint)) in desktopWidgets.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: p.background,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    leading: CircleAvatar(
                      backgroundColor: p.accent.withValues(alpha: 0.15),
                      child: Icon(icon, color: p.accent),
                    ),
                    title: Text(tr(name)),
                    subtitle: Text(tr(hint)),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () {
                      Navigator.pop(ctx);
                      DesktopIntegration.instance.enterWidget(id);
                    },
                  ),
                ),
              )
                  .animate(delay: (40 * i).ms)
                  .fadeIn(duration: Anim.medium)
                  .slideY(begin: 0.15, curve: Anim.curve),
          ],
        );
      },
    );

/// La ventanita del widget elegido.
class DesktopWidgetView extends StatelessWidget {
  const DesktopWidgetView({super.key, required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (_, icon, name, _) = desktopWidgets.firstWhere((w) => w.$1 == kind,
        orElse: () => desktopWidgets.first);
    final repo = activeRepo;
    return Material(
      color: p.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra para arrastrar la ventana.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              color: p.accent.withValues(alpha: 0.10),
              child: Row(children: [
                Icon(icon, size: 17, color: p.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: tr('Abrir Oganesson'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_full_rounded, size: 17),
                  onPressed: DesktopIntegration.instance.exitWidget,
                ),
                IconButton(
                  tooltip: tr('Cerrar widget'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () =>
                      DesktopIntegration.instance.exitWidget(hide: true),
                ),
              ]),
            ),
          ),
          Expanded(
            child: repo == null
                ? Center(
                    child: Text(tr('Inicia sesión en Oganesson'),
                        style: TextStyle(color: p.secondary)))
                : ListenableBuilder(
                    listenable: repo,
                    builder: (context, _) => switch (kind) {
                      'calendario' => _MonthWidget(repo: repo),
                      'pomodoro' => const _PomodoroWidget(),
                      'fijada' => _PinnedWidget(repo: repo),
                      _ => _TasksWidget(repo: repo),
                    },
                  ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: Anim.medium);
  }
}

class _TasksWidget extends StatelessWidget {
  const _TasksWidget({required this.repo});
  final NotesRepository repo;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tasks = repo.temporales.where((n) => !n.done && !n.isPast()).take(8);
    if (tasks.isEmpty) {
      return Center(
          child:
              Text(tr('Nada pendiente'), style: TextStyle(color: p.secondary)));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final n in tasks)
          ListTile(
            dense: true,
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: calendarColor(context, n), shape: BoxShape.circle),
            ),
            title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(tiempoNota(n),
                style: TextStyle(fontSize: 12, color: p.secondary)),
          ),
      ],
    );
  }
}

class _MonthWidget extends StatelessWidget {
  const _MonthWidget({required this.repo});
  final NotesRepository repo;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final start = DateTime(now.year, now.month, 1 - (first.weekday - 1));
    final items = repo.calendarItems;
    bool busy(DateTime d) => items.any((n) {
          final s = n.periodStart.toLocal(), e = n.dueAt!.toLocal();
          final a = DateTime(s.year, s.month, s.day),
              b = DateTime(e.year, e.month, e.day);
          return !d.isBefore(a) && !d.isAfter(b);
        });
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(children: [
        Text(nombreMes(now.month, now.year),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        Row(children: [
          for (final d in diasIniciales)
            Expanded(
                child: Center(
                    child: Text(d,
                        style: TextStyle(
                            fontSize: 11,
                            color: p.secondary,
                            fontWeight: FontWeight.w700)))),
        ]),
        for (var w = 0; w < 6; w++)
          Expanded(
            child: Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(builder: (_) {
                    final d = DateTime(
                        start.year, start.month, start.day + w * 7 + i);
                    final today = d.year == now.year &&
                        d.month == now.month &&
                        d.day == now.day;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: today ? p.accent : null,
                              shape: BoxShape.circle),
                          child: Text('${d.day}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight:
                                      today ? FontWeight.w800 : FontWeight.w500,
                                  color: today
                                      ? p.onAccent
                                      : d.month != now.month
                                          ? p.secondary.withValues(alpha: 0.4)
                                          : null)),
                        ),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                              color: d.month == now.month && busy(d)
                                  ? p.accent
                                  : Colors.transparent,
                              shape: BoxShape.circle),
                        ),
                      ],
                    );
                  }),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _PomodoroWidget extends StatelessWidget {
  const _PomodoroWidget();

  @override
  Widget build(BuildContext context) {
    final pomo = Pomodoro.instance;
    return ListenableBuilder(
      listenable: pomo,
      builder: (context, _) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
              scale: 1.4,
              child: PomodoroTomato(onTap: () {}, alwaysVisible: true)),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: tr('Reiniciar'),
                onPressed: pomo.reset,
                icon: const Icon(Icons.replay_rounded)),
            IconButton.filled(
              tooltip: pomo.running ? tr('Pausar') : tr('Empezar'),
              onPressed: pomo.running ? pomo.pause : pomo.start,
              icon: Icon(pomo.running
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
            ),
            IconButton(
                tooltip: tr('Saltar'),
                onPressed: pomo.skip,
                icon: const Icon(Icons.skip_next_rounded)),
          ]),
        ],
      ),
    );
  }
}

class _PinnedWidget extends StatelessWidget {
  const _PinnedWidget({required this.repo});
  final NotesRepository repo;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final Note? n = repo.notes.where((n) => n.pinned).firstOrNull;
    if (n == null) {
      return Center(
          child: Text(tr('Fija una nota para verla aquí'),
              style: TextStyle(color: p.secondary)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n.title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
              n.content
                  .split('\n')
                  .skip(1)
                  .map((l) => l.replaceAll('￼', ''))
                  .join('\n')
                  .trim(),
              style: const TextStyle(height: 1.45)),
        ],
      ),
    );
  }
}
