import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../data/note_board.dart';
import '../data/note_export.dart';
import '../data/note_images.dart';
import '../data/note_factory.dart';
import '../data/note_filters.dart';
import '../data/note_ics.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';
import 'toast.dart';

// ---------------------------------------------------------- información

/// Metadatos de la nota (como las propiedades de Obsidian).
Future<void> showNoteInfo(BuildContext context, NotesRepository repo, Note n) {
  final author = repo.isForeign(n)
      ? repo.incomingShare(n.id)?.ownerEmail
      : Supabase.instance.client.auth.currentUser?.email;
  final rows = <(IconData, String, String)>[
    (Icons.person_outline_rounded, tr('Autor'), author ?? '—'),
    (Icons.add_circle_outline_rounded, tr('Creada'), fechaLarga(n.createdAt)),
    (Icons.edit_outlined, tr('Última modificación'), fechaLarga(n.updatedAt)),
    if (n.dueAt != null)
      (Icons.event_outlined, tr('Vence'), fechaLarga(n.dueAt!)),
    (Icons.notes_rounded, tr('Texto'), textStats(n.content)),
    (
      Icons.hub_outlined,
      tr('Enlaces'),
      '${n.links.where((l) => !l.contains(':')).length}'
    ),
  ];
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
    builder: (ctx) {
      final p = Palette.of(ctx);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Información'),
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            for (final (i, (icon, label, value)) in rows.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Icon(icon, size: 19, color: p.accent),
                  const SizedBox(width: 12),
                  SizedBox(
                      width: 150,
                      child: Text(label, style: TextStyle(color: p.secondary))),
                  Expanded(
                      child: SelectableText(value,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              )
                  .animate(delay: (40 * i).ms)
                  .fadeIn(duration: Anim.medium)
                  .slideX(begin: 0.06, curve: Anim.curve),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------- historial

/// Versiones anteriores de una nota, con vista previa y restaurar.
Future<void> showHistorySheet(
    BuildContext context, NotesRepository repo, String noteId) {
  final versions = repo.history.versionsOf(noteId);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
    builder: (ctx) {
      final p = Palette.of(ctx);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Historial de versiones'),
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Se guardan en este dispositivo.'),
                style: TextStyle(color: p.secondary, fontSize: 13)),
            const SizedBox(height: 12),
            if (versions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(tr('Aún no hay versiones anteriores.'),
                      style: TextStyle(color: p.secondary)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: versions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final v = versions[i];
                    return Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: p.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(fechaLarga(v.at),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5)),
                                const SizedBox(height: 3),
                                Text(
                                    v.content
                                        .replaceAll('￼', '')
                                        .replaceAll('\n', ' ')
                                        .trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.secondary, fontSize: 13)),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              repo.restoreVersion(noteId, v);
                              Navigator.pop(ctx);
                              showToast(context, tr('Versión restaurada'),
                                  icon: Icons.history_rounded);
                            },
                            child: Text(tr('Restaurar')),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------- plantillas

class NoteTemplate {
  const NoteTemplate(this.name, this.icon, this.text,
      {this.steps = const [], this.custom = false, this.rich});
  final String name;
  final IconData icon;
  final String text;
  final List<String> steps;
  final bool custom;

  /// Formato de una plantilla propia (con sus casillas).
  final String? rich;
}

List<NoteTemplate> builtInTemplates() => [
      NoteTemplate(
          tr('Reunión'),
          Icons.groups_outlined,
          '${tr('Reunión')}\n${tr('Asistentes:')}\n\n${tr('Temas:')}\n\n'
          '${tr('Decisiones:')}\n',
          steps: [tr('Enviar el resumen')]),
      NoteTemplate(tr('Lista de la compra'), Icons.shopping_cart_outlined,
          tr('Lista de la compra'),
          steps: [tr('Fruta y verdura'), tr('Básicos'), tr('Limpieza')]),
      NoteTemplate(
          tr('Diario'),
          Icons.auto_stories_outlined,
          '${tr('Diario')}\n${tr('Cómo ha ido hoy:')}\n\n'
          '${tr('Lo mejor del día:')}\n\n${tr('Para mañana:')}\n'),
      NoteTemplate(tr('Proyecto'), Icons.rocket_launch_outlined,
          '${tr('Proyecto')}\n${tr('Objetivo:')}\n\n${tr('Notas:')}\n',
          steps: [tr('Definir el alcance'), tr('Primer paso')]),
      NoteTemplate(
          tr('Viaje'),
          Icons.luggage_outlined,
          '${tr('Viaje')}\n${tr('Destino:')}\n${tr('Fechas:')}\n\n'
          '${tr('Alojamiento:')}\n',
          steps: [tr('Documentación'), tr('Reservas'), tr('Maleta')]),
    ];

const _templatesKey = 'note_templates_v1';

Future<List<NoteTemplate>> loadCustomTemplates() async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_templatesKey);
    if (raw == null) return const [];
    return [
      for (final m in jsonDecode(raw) as List)
        NoteTemplate(
          m['name'] as String,
          Icons.bookmark_outline_rounded,
          m['text'] as String,
          steps: ((m['steps'] as List?) ?? const []).cast<String>(),
          rich: m['rich'] as String?,
          custom: true,
        )
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> _storeTemplates(List<NoteTemplate> list) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(
      _templatesKey,
      jsonEncode([
        for (final t in list)
          {'name': t.name, 'text': t.text, 'steps': t.steps, 'rich': t.rich}
      ]));
}

/// Guarda el texto y los pasos de [n] (sin marcar) como plantilla propia.
Future<void> saveAsTemplate(BuildContext context, Note n) async {
  final list = [...await loadCustomTemplates()];
  list.removeWhere((t) => t.name == n.title);
  list.add(NoteTemplate(
    n.title,
    Icons.bookmark_outline_rounded,
    n.content.replaceAll('￼', '').trim(),
    rich: n.hasImages || n.hasFiles ? null : n.rich,
    custom: true,
  ));
  await _storeTemplates(list);
  if (context.mounted) {
    showToast(context, tr('Plantilla guardada'),
        icon: Icons.bookmark_added_outlined);
  }
}

/// Elige una plantilla y devuelve la nota creada.
Future<Note?> pickTemplate(BuildContext context, NotesRepository repo) async {
  final custom = await loadCustomTemplates();
  if (!context.mounted) return null;
  final chosen = await showModalBottomSheet<NoteTemplate>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
    builder: (ctx) {
      final mine = [...custom];
      return StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(tr('Plantillas'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            for (final t in [...mine, ...builtInTemplates()])
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                leading: Icon(t.icon, color: Palette.accent(ctx)),
                title:
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: t.custom
                    ? IconButton(
                        tooltip: tr('Quitar'),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () async {
                          setSheet(() => mine.remove(t));
                          await _storeTemplates(mine);
                        },
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      );
    },
  );
  if (chosen == null) return null;
  return createFromTemplate(repo, chosen);
}

Note? createFromTemplate(NotesRepository repo, NoteTemplate t) {
  final rich = t.rich;
  if (rich != null) {
    final n = repo.createNote();
    repo.updateContent(n.id, t.text, rich: rich);
    return repo.byId(n.id);
  }
  final n = createNoteFrom(repo, text: t.text);
  if (n == null) return null;
  repo.addChecklist(n.id, t.steps);
  return n;
}

// ------------------------------------------------------------------ filtros

/// Hoja de filtros de búsqueda. Devuelve los elegidos (null = sin cambios).
Future<NoteFilters?> showFiltersSheet(
    BuildContext context, NotesRepository repo, NoteFilters current) {
  var date = current.date;
  var folder = current.folderId;
  var images = current.withImages;
  var tasks = current.withTasks;
  return showModalBottomSheet<NoteFilters>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final p = Palette.of(ctx);
      Widget label(String t) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(t,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: p.secondary)),
          );
      Widget chip(String t, bool on, VoidCallback tap) => ChoiceChip(
            label: Text(t),
            selected: on,
            showCheckmark: false,
            onSelected: (_) => set(tap),
          );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Filtros'),
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            label(tr('Modificada')),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final (d, t) in [
                (DateFilter.any, tr('Cualquier fecha')),
                (DateFilter.today, tr('Hoy')),
                (DateFilter.week, tr('Últimos 7 días')),
                (DateFilter.month, tr('Último mes')),
              ])
                chip(t, date == d, () => date = d),
            ]),
            label(tr('Carpeta')),
            Wrap(spacing: 8, runSpacing: 6, children: [
              chip(tr('Todas'), folder == null, () => folder = null),
              chip(tr('Sin carpeta'), folder == '', () => folder = ''),
              for (final f in repo.folders)
                chip(f.name, folder == f.id, () => folder = f.id),
            ]),
            label(tr('Contenido')),
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilterChip(
                  label: Text(tr('Con imágenes')),
                  selected: images,
                  onSelected: (v) => set(() => images = v)),
              FilterChip(
                  label: Text(tr('Tareas')),
                  selected: tasks,
                  onSelected: (v) => set(() => tasks = v)),
            ]),
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, const NoteFilters()),
                  child: Text(tr('Quitar filtros')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(
                      ctx,
                      NoteFilters(
                        date: date,
                        folderId: folder,
                        withImages: images,
                        withTasks: tasks,
                      )),
                  child: Text(tr('Aplicar')),
                ),
              ],
            ),
          ],
        ),
      );
    }),
  );
}

// ------------------------------------------------------- exportar e importar

/// La pizarra como PNG de alta calidad (hasta 3200 px de lado).
Future<void> exportBoardPng(BuildContext context, BoardData d) =>
    _run(context, () async {
      final png =
          await renderBoardPng(d, NoteImages.instance.load, maxSide: 3200);
      if (png == null || !context.mounted) return false;
      return _deliver(context, png, 'pizarra.png', 'image/png', 'PNG', 'png');
    });

/// En PC pregunta dónde guardar; en el móvil abre el menú de compartir.
Future<bool> _deliver(BuildContext context, Uint8List bytes, String name,
    String mime, String label, String ext) async {
  if (Platform.isAndroid) {
    final r = await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: mime, name: name)],
      fileNameOverrides: [name],
    ));
    return r.status != ShareResultStatus.dismissed;
  }
  final to = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: label, extensions: [ext])
    ],
  );
  if (to == null) return false;
  var path = to.path;
  if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}

Future<void> _run(BuildContext context, Future<bool> Function() job) async {
  try {
    if (await job() && context.mounted) {
      showToast(context, tr('Exportado'), icon: Icons.check_rounded);
    }
  } catch (_) {
    if (context.mounted) {
      showToast(context, tr('No se ha podido exportar'),
          icon: Icons.error_outline);
    }
  }
}

/// Exportar una nota: Markdown o PDF.
Future<void> showExportNote(BuildContext context, Note n) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Markdown'),
            onTap: () => Navigator.pop(ctx, 'md')),
        ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            onTap: () => Navigator.pop(ctx, 'pdf')),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (kind == null || !context.mounted) return;
  await _run(context, () async {
    if (kind == 'md') {
      return _deliver(
          context,
          Uint8List.fromList(utf8.encode(noteToMarkdown(n))),
          safeFileName(n.title, 'md'),
          'text/markdown',
          'Markdown',
          'md');
    }
    return _deliver(context, await notesToPdf([n]),
        safeFileName(n.title, 'pdf'), 'application/pdf', 'PDF', 'pdf');
  });
}

/// Exportar todo: copia para restaurar, Markdown o PDF. El Vault nunca sale.
Future<void> showExportAll(BuildContext context, NotesRepository repo) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(tr('Copia completa')),
            subtitle: Text(tr('Se puede volver a importar. Sin el Vault.')),
            onTap: () => Navigator.pop(ctx, 'json')),
        ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Markdown'),
            onTap: () => Navigator.pop(ctx, 'md')),
        ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            onTap: () => Navigator.pop(ctx, 'pdf')),
        ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(tr('Calendario (.ics)')),
            subtitle: Text(tr('Notas con fecha pendientes. Sin el Vault.')),
            onTap: () => Navigator.pop(ctx, 'ics')),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (kind == null || !context.mounted) return;
  final notes =
      repo.allActive.where((n) => !n.vault && !repo.isForeign(n)).toList();
  final day = DateTime.now().toIso8601String().substring(0, 10);
  await _run(context, () async {
    switch (kind) {
      case 'json':
        return _deliver(
            context,
            Uint8List.fromList(
                utf8.encode(Backup(notes, repo.folders).encode())),
            'oganesson-$day.json',
            'application/json',
            'JSON',
            'json');
      case 'md':
        return _deliver(
            context,
            Uint8List.fromList(utf8.encode(notesToMarkdown(notes))),
            'oganesson-$day.md',
            'text/markdown',
            'Markdown',
            'md');
      case 'ics':
        if (calendarNotes(notes).isEmpty) {
          if (context.mounted) {
            showToast(context, tr('No hay notas con fecha pendientes'),
                icon: Icons.event_busy_outlined);
          }
          return false;
        }
        return _deliver(
            context,
            Uint8List.fromList(utf8.encode(notesToIcs(notes))),
            'oganesson-$day.ics',
            'text/calendar',
            'iCalendar',
            'ics');
      default:
        return _deliver(context, await notesToPdf(notes), 'oganesson-$day.pdf',
            'application/pdf', 'PDF', 'pdf');
    }
  });
}

/// Importa un `.ics`: añade los eventos actuales y futuros sin borrar nada.
Future<void> importCalendarFile(
    BuildContext context, NotesRepository repo) async {
  try {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
          label: 'iCalendar',
          extensions: ['ics'],
          mimeTypes: ['text/calendar', 'application/ics'])
    ]);
    if (file == null) return;
    if (await file.length() > 10 * 1024 * 1024) {
      throw const FormatException('too large');
    }
    final f = parseIcs(await file.readAsString());
    final r = repo.importEvents(f.events);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ImportResult(
          added: r.added,
          existing: r.existing,
          skipped: f.skipped,
          simplified: f.simplified),
    );
  } on FormatException {
    if (context.mounted) {
      showToast(context, tr('Ese archivo no es un calendario válido'),
          icon: Icons.error_outline);
    }
  } catch (_) {
    if (context.mounted) {
      showToast(context, tr('No se ha podido importar'),
          icon: Icons.error_outline);
    }
  }
}

/// Resultado de importar un calendario, con el contador animado.
class _ImportResult extends StatelessWidget {
  const _ImportResult({
    required this.added,
    required this.existing,
    required this.skipped,
    required this.simplified,
  });

  final int added;
  final int existing;
  final int skipped;
  final int simplified;

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    final rows = [
      if (existing > 0) trf('Ya estaban: {0}', [existing]),
      if (skipped > 0) trf('Pasados u omitidos: {0}', [skipped]),
      if (simplified > 0) trf('sin repetición: {0}', [simplified]),
    ];
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_rounded, size: 52, color: accent)
              .animate()
              .scale(
                  begin: const Offset(0.3, 0.3),
                  duration: 650.ms,
                  curve: Curves.elasticOut)
              .fadeIn(duration: Anim.fast),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: added.toDouble()),
            duration: 800.ms,
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text('${v.round()}',
                style: TextStyle(
                    fontSize: 38, fontWeight: FontWeight.w800, color: accent)),
          ),
          Text(tr('eventos añadidos al calendario'),
                  textAlign: TextAlign.center)
              .animate(delay: 120.ms)
              .fadeIn(duration: Anim.medium),
          const SizedBox(height: 10),
          for (final (i, row) in rows.indexed)
            Text(row,
                    style: TextStyle(
                        color: Palette.secondary(context), fontSize: 13))
                .animate(delay: (220 + 70 * i).ms)
                .fadeIn(duration: Anim.medium)
                .slideY(begin: 0.3, curve: Anim.curve),
        ],
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context), child: Text(tr('Listo'))),
      ],
    );
  }
}

/// Importa una copia: añade lo que falta sin borrar nada.
Future<void> importBackupFile(
    BuildContext context, NotesRepository repo) async {
  try {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
          label: 'Oganesson',
          extensions: ['json'],
          mimeTypes: ['application/json'])
    ]);
    if (file == null) return;
    final r = repo.importBackup(Backup.decode(await file.readAsString()));
    if (context.mounted) {
      showToast(context,
          trf('Importadas: {0} notas, {1} carpetas', [r.notes, r.folders]),
          icon: Icons.download_done_rounded);
    }
  } on FormatException {
    if (context.mounted) {
      showToast(context, tr('Ese archivo no es una copia de Oganesson'),
          icon: Icons.error_outline);
    }
  } catch (_) {
    if (context.mounted) {
      showToast(context, tr('No se ha podido importar'),
          icon: Icons.error_outline);
    }
  }
}
