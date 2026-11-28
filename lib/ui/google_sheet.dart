import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/google_calendar.dart';
import '../data/notes_repository.dart';
import 'anim.dart';
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';
import 'toast.dart';

/// Ajustes → Google Calendar: conectar, ver el estado, sincronizar o
/// desconectar.
Future<void> showGoogleCalendarSheet(
        BuildContext context, NotesRepository repo) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (_) => _GoogleSheet(repo: repo),
    );

class _GoogleSheet extends StatelessWidget {
  const _GoogleSheet({required this.repo});
  final NotesRepository repo;

  @override
  Widget build(BuildContext context) {
    final g = GoogleCalendar.instance;
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) {
        final p = Palette.of(context);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.event_note_rounded,
                    color: Color(0xFF4285F4)),
              ).animate().scale(
                  begin: const Offset(0.8, 0.8),
                  curve: Curves.easeOutBack,
                  duration: Anim.slow),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Google Calendar'),
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800)),
                    Text(
                        g.connected
                            ? (g.email == null
                                ? tr('Conectado')
                                : trf('Conectado como {0}', [g.email]))
                            : tr('Sin conectar'),
                        style: TextStyle(color: p.secondary, fontSize: 13)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Text(
                tr('Tus notas con fecha aparecen en tu Google Calendar, y los '
                    'eventos de Google en el calendario de Oganesson. Se '
                    'sincroniza al abrir la app y cada 10 minutos.'),
                style: TextStyle(color: p.secondary, height: 1.4)),
            const SizedBox(height: 16),
            if (!GoogleCalendar.supported)
              _Info(
                  icon: Icons.info_outline_rounded,
                  text: Platform.isAndroid
                      ? tr(
                          'En el móvil llegará en la próxima versión. Mientras, conéctalo en el PC: los eventos se ven también aquí.')
                      : tr('Esta versión no trae la clave de Google Calendar.'))
            else if (!g.connected)
              FilledButton.icon(
                onPressed: g.busy
                    ? null
                    : () async {
                        final ok = await g.connect(repo);
                        if (context.mounted) {
                          showToast(
                              context,
                              ok
                                  ? tr('Google Calendar conectado')
                                  : tr('No se pudo conectar con Google'),
                              icon: ok
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.error_outline_rounded);
                        }
                      },
                icon: const Icon(Icons.link_rounded),
                label: Text(tr('Conectar con Google')),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              )
            else ...[
              _Info(
                  icon: g.busy
                      ? Icons.sync_rounded
                      : Icons.check_circle_outline_rounded,
                  text: g.busy
                      ? tr('Sincronizando…')
                      : g.lastSync == null
                          ? tr('Aún sin sincronizar')
                          : trf('Última sincronización: {0}',
                              [fechaMedia(g.lastSync!.toUtc())])),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: g.busy ? null : () => g.sync(repo),
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(tr('Sincronizar ahora')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: g.busy ? null : () => g.disconnect(repo),
                    icon: const Icon(Icons.link_off_rounded),
                    label: Text(tr('Desconectar')),
                  ),
                ),
              ]),
            ],
            if (g.error != null) ...[
              const SizedBox(height: 10),
              Text(g.error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12.5)),
            ],
          ],
        );
      },
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: p.background, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, size: 20, color: p.accent),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
