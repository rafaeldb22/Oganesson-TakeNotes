import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ai_actions.dart';
import '../data/ai_assistant.dart';
import '../data/note_factory.dart';
import '../data/note_images.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'i18n.dart';
import 'theme.dart';
import 'toast.dart';

/// Espera con un diálogo; devuelve null si falla (y lo avisa).
Future<T?> _withProgress<T>(
    BuildContext context, String label, Future<T> Function() job) async {
  final nav = Navigator.of(context, rootNavigator: true);
  var open = true;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 16),
        Expanded(child: Text(label)),
      ]),
    ),
  ).whenComplete(() => open = false));
  try {
    final r = await job();
    if (open) nav.pop();
    return r;
  } on AiException catch (e) {
    if (open) nav.pop();
    if (context.mounted) {
      showToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  } catch (_) {
    if (open) nav.pop();
    if (context.mounted) {
      showToast(context, tr('La IA no ha podido hacerlo. Vuelve a probar.'),
          icon: Icons.error_outline_rounded);
    }
  }
  return null;
}

/// Acciones de la IA sobre una nota.
Future<void> showNoteAiActions(
    BuildContext context, NotesRepository repo, String noteId) async {
  final n = repo.byId(noteId);
  if (n == null || n.vault || repo.isForeign(n)) return;
  if (n.content.replaceAll('￼', '').trim().isEmpty && !n.hasImages) {
    showToast(context, tr('La nota no tiene texto'),
        icon: Icons.info_outline_rounded);
    return;
  }
  final action = await showModalBottomSheet<NoteAiAction>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (a, icon, label) in [
          (NoteAiAction.summarize, Icons.short_text_rounded, tr('Resumir')),
          (NoteAiAction.fix, Icons.spellcheck_rounded, tr('Corregir')),
          (NoteAiAction.translate, Icons.translate_rounded, tr('Traducir')),
          (
            NoteAiAction.tasks,
            Icons.checklist_rounded,
            tr('Convertir en tareas')
          ),
        ])
          ListTile(
            leading: Icon(icon, color: Palette.accent(ctx)),
            title: Text(label),
            onTap: () => Navigator.pop(ctx, a),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (action == null || !context.mounted) return;

  String? language;
  if (action == NoteAiAction.translate) {
    language = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final (name, api) in const [
            ('Español', 'Spanish'),
            ('English', 'English'),
            ('Français', 'French'),
            ('Deutsch', 'German'),
            ('Italiano', 'Italian'),
            ('Português', 'Portuguese'),
          ])
            ListTile(title: Text(name), onTap: () => Navigator.pop(ctx, api)),
        ],
      ),
    );
    if (language == null || !context.mounted) return;
  }

  final reply = await _withProgress(context, tr('La IA está trabajando…'),
      () => runNoteAction(n, action, language: language));
  if (reply == null || !context.mounted) return;

  if (action == NoteAiAction.tasks) {
    final tasks = await _reviewTasks(context, parseTasks(reply));
    if (tasks == null) return;
    repo.addChecklist(n.id, tasks);
    if (context.mounted && tasks.isNotEmpty) {
      showToast(context, trf('{0} tareas añadidas', [tasks.length]),
          icon: Icons.checklist_rounded);
    }
    return;
  }
  await _showResult(context, repo, n, reply,
      canReplace: action != NoteAiAction.summarize);
}

Future<void> _showResult(
    BuildContext context, NotesRepository repo, Note n, String text,
    {required bool canReplace}) {
  final edit = TextEditingController(text: text);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Resultado'),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Flexible(
            child: TextField(
              key: const ValueKey('resultado-ia'),
              controller: edit,
              maxLines: null,
              decoration: InputDecoration(
                filled: true,
                fillColor: Palette.background(ctx),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: edit.text));
                  Navigator.pop(ctx);
                  showToast(context, tr('Copiado'),
                      icon: Icons.content_copy_rounded);
                },
                child: Text(tr('Copiar')),
              ),
              OutlinedButton(
                onPressed: () {
                  appendToNote(repo, n, edit.text);
                  Navigator.pop(ctx);
                },
                child: Text(tr('Añadir al final')),
              ),
              if (canReplace && !n.hasImages && !n.hasFiles)
                FilledButton(
                  onPressed: () {
                    final oldText = n.content, oldRich = n.rich;
                    repo.history.record(n, force: true);
                    final plain = edit.text.trim();
                    repo.updateContent(n.id, '$plain\n', rich: richFor(plain));
                    Navigator.pop(ctx);
                    showToast(context, tr('Nota actualizada'),
                        icon: Icons.check_rounded,
                        actionLabel: tr('Deshacer'),
                        onAction: () =>
                            repo.updateContent(n.id, oldText, rich: oldRich));
                  },
                  child: Text(tr('Reemplazar')),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Revisa las tareas antes de crearlas: nada se añade sin confirmar.
Future<List<String>?> _reviewTasks(BuildContext context, List<String> tasks) {
  if (tasks.isEmpty) {
    showToast(context, tr('No se han encontrado tareas'),
        icon: Icons.info_outline_rounded);
    return Future.value();
  }
  final on = {for (var i = 0; i < tasks.length; i++) i};
  return showModalBottomSheet<List<String>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(tr('Tareas encontradas'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < tasks.length; i++)
                    CheckboxListTile(
                      dense: true,
                      value: on.contains(i),
                      title: Text(tasks[i]),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) =>
                          set(() => v == true ? on.add(i) : on.remove(i)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: on.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, [
                          for (var i = 0; i < tasks.length; i++)
                            if (on.contains(i)) tasks[i]
                        ]),
                child: Text(trf('Añadir {0}', [on.length])),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Resumen del día a partir de tareas y notas recientes.
Future<void> showDailyBrief(BuildContext context, NotesRepository repo,
    {void Function(String id)? onOpen}) async {
  final text = await _withProgress(
      context, tr('Preparando tu resumen…'), () => runDailyBrief(repo));
  if (text == null || text.isEmpty || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Resumen de hoy'),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(text.replaceAll('**', ''),
                  style: const TextStyle(fontSize: 15, height: 1.5)),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () {
                final n = createNoteFrom(repo,
                    text: '${tr('Resumen de hoy')}\n'
                        '${text.replaceAll('**', '')}');
                Navigator.pop(ctx);
                if (n != null) onOpen?.call(n.id);
              },
              child: Text(tr('Guardar como nota')),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Crea una nota con las tareas que salgan de una foto.
Future<void> tasksFromPhoto(BuildContext context, NotesRepository repo,
    {void Function(String id)? onOpen}) async {
  final XFile? file;
  try {
    file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Imágenes',
        extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
      )
    ]);
  } catch (_) {
    if (context.mounted) {
      showToast(context, tr('No se pudo abrir la imagen'),
          icon: Icons.error_outline_rounded);
    }
    return;
  }
  if (file == null || !context.mounted) return;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return;
  final mime = switch (NoteImages.extensionOf(bytes)) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
  final reply = await _withProgress(context, tr('Leyendo con la IA…'),
      () => aiReadMedia(bytes, mime, aiTasksPrompt));
  if (reply == null || !context.mounted) return;
  final tasks = await _reviewTasks(context, parseTasks(reply));
  if (tasks == null || tasks.isEmpty) return;
  final n = createNoteFrom(repo, text: tr('Tareas de la foto'));
  if (n == null) return;
  repo.addChecklist(n.id, tasks);
  onOpen?.call(n.id);
}
