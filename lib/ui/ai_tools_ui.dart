import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/ai_actions.dart';
import '../data/ai_assistant.dart';
import '../data/note_attachments.dart';
import '../data/note_board.dart';
import '../data/note_factory.dart';
import '../data/note_images.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
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
    builder: (_) => AiWorkingDialog(label: label),
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
  final hasFiles = allMediaOf(n).isNotEmpty;
  if (n.content.replaceAll('￼', '').trim().isEmpty &&
      !n.hasImages &&
      !hasFiles &&
      !(n.rich?.contains(BoardData.embedType) ?? false)) {
    showToast(context, tr('La nota no tiene texto'),
        icon: Icons.info_outline_rounded);
    return;
  }
  final picked = await showModalBottomSheet<(NoteAiAction, String?)>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 540, maxHeight: MediaQuery.sizeOf(context).height * 0.88),
    builder: (_) => _AiActionsSheet(title: n.title, hasFiles: hasFiles),
  );
  if (picked == null || !context.mounted) return;
  final (action, language) = picked;

  final reply = await _withProgress(
      context,
      action == NoteAiAction.analyze
          ? tr('Leyendo los archivos…')
          : tr('La IA está trabajando…'),
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
      canReplace:
          action == NoteAiAction.fix || action == NoteAiAction.translate);
}

/// Esfera de la IA: un anillo de luz que gira alrededor del destello.
class AiOrb extends StatefulWidget {
  const AiOrb({super.key, this.size = 46});
  final double size;

  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hsl = HSLColor.fromColor(p.accent);
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _spin,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  p.accent,
                  hsl.withHue((hsl.hue + 45) % 360).toColor(),
                  hsl.withHue((hsl.hue + 315) % 360).toColor(),
                  p.accent,
                ]),
                boxShadow: [
                  BoxShadow(
                      color: p.accent.withValues(alpha: 0.35),
                      blurRadius: s * 0.32),
                ],
              ),
              child: SizedBox.square(dimension: s),
            ),
          ),
          Container(
            width: s - 5,
            height: s - 5,
            decoration: BoxDecoration(color: p.card, shape: BoxShape.circle),
            child: Icon(Icons.auto_awesome_rounded,
                size: s * 0.46, color: p.accent),
          ),
        ],
      ),
    );
  }
}

/// Espera mientras trabaja la IA.
class AiWorkingDialog extends StatelessWidget {
  const AiWorkingDialog({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AiOrb(size: 58)
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                      begin: const Offset(0.94, 0.94),
                      end: const Offset(1.05, 1.05),
                      duration: 900.ms,
                      curve: Curves.easeInOut),
              const SizedBox(height: 18),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  color: p.accent,
                  backgroundColor: p.accent.withValues(alpha: 0.14),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: Anim.fast).scale(
        begin: const Offset(0.92, 0.92),
        duration: Anim.medium,
        curve: Curves.easeOutBack);
  }
}

/// Panel de acciones de la IA sobre una nota.
class _AiActionsSheet extends StatefulWidget {
  const _AiActionsSheet({required this.title, required this.hasFiles});
  final String title;
  final bool hasFiles;

  @override
  State<_AiActionsSheet> createState() => _AiActionsSheetState();
}

class _AiActionsSheetState extends State<_AiActionsSheet> {
  bool _translating = false;
  final _question = TextEditingController();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  void _ask() {
    final q = _question.text.trim();
    if (q.isNotEmpty) Navigator.pop(context, (NoteAiAction.ask, q));
  }

  static const _languages = [
    ('Español', 'Spanish'),
    ('English', 'English'),
    ('Français', 'French'),
    ('Deutsch', 'German'),
    ('Italiano', 'Italian'),
    ('Português', 'Portuguese'),
  ];

  void _pick(NoteAiAction a) {
    if (a == NoteAiAction.translate) {
      setState(() => _translating = !_translating);
    } else {
      Navigator.pop(context, (a, null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final actions = [
      if (widget.hasFiles)
        (
          NoteAiAction.analyze,
          Icons.plagiarism_outlined,
          tr('Analizar archivos'),
          tr('PDF, documentos, audio e imágenes')
        ),
      (
        NoteAiAction.summarize,
        Icons.short_text_rounded,
        tr('Resumir'),
        tr('Las ideas clave')
      ),
      (
        NoteAiAction.fix,
        Icons.spellcheck_rounded,
        tr('Corregir'),
        tr('Ortografía y gramática')
      ),
      (
        NoteAiAction.translate,
        Icons.translate_rounded,
        tr('Traducir'),
        tr('A otro idioma')
      ),
      (
        NoteAiAction.tasks,
        Icons.checklist_rounded,
        tr('Convertir en tareas'),
        tr('Lo que hay que hacer')
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AiOrb(),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Asistente de la nota'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 1),
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.secondary, fontSize: 13)),
                  ],
                ),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: Anim.medium)
              .slideY(begin: 0.2, duration: Anim.medium, curve: Anim.curve),
          const SizedBox(height: 14),
          // Pregunta libre sobre la nota.
          TextField(
            controller: _question,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _ask(),
            decoration: InputDecoration(
              hintText: tr('Pregunta algo sobre esta nota…'),
              filled: true,
              fillColor: p.background,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              suffixIcon: ListenableBuilder(
                listenable: _question,
                builder: (_, __) => IconButton(
                  tooltip: tr('Preguntar'),
                  onPressed: _question.text.trim().isEmpty ? null : _ask,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ),
          ).animate().fadeIn(duration: Anim.medium, delay: 40.ms),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final columns = c.maxWidth < 340 ? 1 : 2;
            final width = (c.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, (a, icon, label, hint)) in actions.indexed)
                  SizedBox(
                    width: a == NoteAiAction.analyze ? c.maxWidth : width,
                    child: _AiActionCard(
                      icon: icon,
                      label: label,
                      hint: hint,
                      active: a == NoteAiAction.translate && _translating,
                      onTap: () => _pick(a),
                    )
                        .animate(delay: (45 * i + 50).ms)
                        .fadeIn(duration: Anim.medium)
                        .slideY(
                            begin: 0.22,
                            duration: Anim.slow,
                            curve: Curves.easeOutBack),
                  ),
              ],
            );
          }),
          AnimatedSize(
            duration: Anim.medium,
            curve: Anim.curve,
            alignment: Alignment.topCenter,
            child: !_translating
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('¿A qué idioma?'),
                            style: TextStyle(
                                color: p.secondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final (i, (name, api)) in _languages.indexed)
                              ActionChip(
                                label: Text(name),
                                onPressed: () => Navigator.pop(
                                    context, (NoteAiAction.translate, api)),
                              )
                                  .animate(delay: (25 * i).ms)
                                  .fadeIn(duration: Anim.fast)
                                  .scale(
                                      begin: const Offset(0.85, 0.85),
                                      duration: Anim.medium,
                                      curve: Curves.easeOutBack),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AiActionCard extends StatefulWidget {
  const _AiActionCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label, hint;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_AiActionCard> createState() => _AiActionCardState();
}

class _AiActionCardState extends State<_AiActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lit = _hover || widget.active;
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Bouncy(
          pressedScale: 0.96,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Anim.medium,
              curve: Anim.curve,
              padding: const EdgeInsets.all(12),
              transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
              decoration: BoxDecoration(
                color: lit
                    ? Color.alphaBlend(
                        p.accent.withValues(alpha: 0.1), p.background)
                    : p.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: lit
                        ? p.accent.withValues(alpha: 0.6)
                        : p.separator.withValues(alpha: 0.65)),
                boxShadow: [
                  BoxShadow(
                    color: p.accent.withValues(alpha: _hover ? 0.16 : 0),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: Anim.medium,
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: lit ? 0.24 : 0.13),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: AnimatedScale(
                      scale: lit ? 1.12 : 1,
                      duration: Anim.medium,
                      curve: Curves.easeOutBack,
                      child: Icon(widget.icon, size: 20, color: p.accent),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(widget.hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 11.5, color: p.secondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
              // Reemplazar reescribe el Delta: borraría adjuntos y pizarra.
              if (canReplace &&
                  !n.hasImages &&
                  !n.hasFiles &&
                  !(n.rich?.contains(BoardData.embedType) ?? false))
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
