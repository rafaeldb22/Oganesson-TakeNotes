import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/ai_assistant.dart';
import '../data/notes_repository.dart';
import 'anim.dart';
import 'i18n.dart';
import 'text_menu.dart';
import 'theme.dart';
import 'toast.dart';
import 'update_dialog.dart' show openLink;

/// Abre el asistente: panel a la derecha en pantallas anchas, hoja desde
/// abajo en el móvil.
Future<void> openAssistant(
  BuildContext context,
  AiSession session, {
  required void Function(String id) onOpenNote,
}) async {
  await AiSettings.instance.load();
  if (!context.mounted) return;
  final wide = MediaQuery.sizeOf(context).width >= 700;
  if (wide) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('Cerrar'),
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: Anim.slow,
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
          child: SizedBox(
            width: 430,
            child: Material(
              color: Palette.card(ctx),
              elevation: 18,
              shadowColor: Colors.black54,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: AssistantPanel(
                session: session,
                onOpenNote: (id) {
                  Navigator.of(ctx).pop();
                  onOpenNote(id);
                },
                onClose: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, a, _, child) {
        final c = CurvedAnimation(
            parent: a, curve: Anim.curve, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.12, 0), end: Offset.zero)
                .animate(c),
            child: child,
          ),
        );
      },
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Palette.card(context),
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.88,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: AssistantPanel(
            session: session,
            onOpenNote: (id) {
              Navigator.of(ctx).pop();
              onOpenNote(id);
            },
            onClose: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }
}

/// Icono degradado del asistente (✨).
class AiBadge extends StatelessWidget {
  const AiBadge({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = Palette.accent(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, Color.lerp(a, const Color(0xFF8E4EC6), 0.55)!],
        ),
        boxShadow: [
          BoxShadow(color: a.withValues(alpha: 0.35), blurRadius: 12),
        ],
      ),
      child: Icon(Icons.auto_awesome_rounded,
          size: size * 0.52, color: Colors.white),
    );
  }
}

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.session,
    required this.onOpenNote,
    required this.onClose,
  });

  final AiSession session;
  final void Function(String id) onOpenNote;
  final VoidCallback onClose;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _settings = false;

  AiSession get s => widget.session;
  AiSettings get settings => AiSettings.instance;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
    settings.addListener(_changed);
    s.confirm = _confirm;
    // La conversación de la última vez sigue ahí.
    s.load();
    _settings = !settings.configured;
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    settings.removeListener(_changed);
    s.confirm = (_) async => false;
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: Anim.medium, curve: Anim.curve);
      }
    });
  }

  Future<bool> _confirm(String q) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const AiBadge(size: 40),
          content: Text(q, textAlign: TextAlign.center),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('No'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Sí'))),
          ],
        ),
      ) ==
      true;

  void _send([String? text]) {
    final t = text ?? _input.text;
    if (t.trim().isEmpty || s.busy) return;
    _input.clear();
    s.send(t);
    _focus.requestFocus();
  }

  String get _modelLabel {
    for (final m in settings.provider.models) {
      if (m.id == settings.model) return m.label;
    }
    return '${settings.provider.label} · ${settings.model}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      children: [
        // Cabecera.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const AiBadge(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Asistente'),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(
                        settings.configured
                            ? trf('{0} · tu clave', [_modelLabel])
                            : tr('Con tu propia clave de IA'),
                        style: TextStyle(fontSize: 12, color: p.secondary)),
                  ],
                ),
              ),
              if (settings.configured && !_settings && s.messages.isNotEmpty)
                IconButton(
                  tooltip: tr('Nueva conversación'),
                  onPressed: s.busy ? null : s.clear,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              if (settings.configured)
                IconButton(
                  tooltip: _settings ? tr('Volver al chat') : tr('Ajustes'),
                  onPressed: () => setState(() => _settings = !_settings),
                  icon: AnimatedSwitcher(
                    duration: Anim.medium,
                    transitionBuilder: (c, a) => RotationTransition(
                        turns: Tween(begin: 0.75, end: 1.0).animate(a),
                        child: FadeTransition(opacity: a, child: c)),
                    child: Icon(
                      _settings
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.tune_rounded,
                      key: ValueKey(_settings),
                    ),
                  ),
                ),
              IconButton(
                tooltip: tr('Cerrar'),
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.separator),
        Expanded(
          child: AnimatedSwitcher(
            duration: Anim.medium,
            transitionBuilder: fadeThrough,
            child: _settings
                ? _KeySetup(
                    key: const ValueKey('ajustes'),
                    onSaved: () => setState(() => _settings = false),
                  )
                : _chat(context),
          ),
        ),
      ],
    );
  }

  Widget _chat(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      key: const ValueKey('chat'),
      children: [
        Expanded(
          child: s.messages.isEmpty
              ? _Welcome(onPick: _send)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  itemCount: s.messages.length + (s.busy ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == s.messages.length) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // La respuesta aparece mientras se escribe.
                          if (s.streaming.trim().isNotEmpty)
                            Container(
                              constraints: const BoxConstraints(maxWidth: 340),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: p.background,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: _RichText(s.streaming.trimRight()),
                            ),
                          _Thinking(text: s.activity ?? tr('Pensando…')),
                        ],
                      );
                    }
                    final last = i == s.messages.length - 1;
                    return _Bubble(
                      key: ObjectKey(s.messages[i]),
                      message: s.messages[i],
                      repo: s.repo,
                      onOpenNote: widget.onOpenNote,
                      onChanged: () => setState(() {}),
                      // Solo el último error se puede reintentar.
                      onRetry:
                          last && s.messages[i].role == AiRole.error && !s.busy
                              ? s.retryLast
                              : null,
                    );
                  },
                ),
        ),
        // Caja de texto.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Container(
            decoration: BoxDecoration(
              color: p.searchFill,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.separator),
            ),
            padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      // Intro envía; Mayús+Intro, salto de línea.
                      const SingleActivator(LogicalKeyboardKey.enter): _send,
                    },
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      autofocus: autoKeyboard,
                      minLines: 1,
                      maxLines: 5,
                      contextMenuBuilder: textFieldMenu,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: tr('Pregunta o pide algo…'),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  // Mientras responde, el botón detiene la respuesta.
                  child: AnimatedScale(
                    scale: _input.text.trim().isEmpty && !s.busy ? 0.85 : 1,
                    duration: Anim.medium,
                    curve: Curves.easeOutBack,
                    child: AnimatedSwitcher(
                      duration: Anim.fast,
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: s.busy
                          ? IconButton.filledTonal(
                              key: const ValueKey('detener'),
                              tooltip: tr('Detener'),
                              onPressed: s.cancel,
                              icon: const Icon(Icons.stop_rounded),
                            )
                          : IconButton.filled(
                              key: const ValueKey('enviar'),
                              tooltip: tr('Enviar'),
                              onPressed:
                                  _input.text.trim().isEmpty ? null : _send,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- bienvenida

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ideas = [
      (Icons.event_note_outlined, tr('¿Qué tengo pendiente esta semana?')),
      (Icons.warning_amber_rounded, tr('¿Tengo alguna tarea vencida?')),
      (
        Icons.note_add_outlined,
        tr('Crea una nota con la lista de la compra: leche, pan y huevos')
      ),
      (Icons.summarize_outlined, tr('Resume mis notas más recientes')),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      children: [
        const Center(child: AiBadge(size: 58))
            .animate()
            .scale(
                begin: const Offset(0.7, 0.7),
                curve: Curves.easeOutBack,
                duration: Anim.slow)
            .fadeIn(),
        const SizedBox(height: 16),
        Text(tr('¿En qué te ayudo?'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
            tr('Puedo ver tus notas y tareas (nunca las del Vault), crear '
                'notas, poner fechas, moverlas de carpeta y más.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.secondary, height: 1.4)),
        const SizedBox(height: 22),
        for (final (i, (icon, text)) in ideas.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Bouncy(
              pressedScale: 0.97,
              child: Material(
                color: p.background,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onPick(text),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Icon(icon, size: 19, color: p.accent),
                      const SizedBox(width: 12),
                      Expanded(child: Text(text)),
                      Icon(Icons.north_east_rounded,
                          size: 16, color: p.secondary),
                    ]),
                  ),
                ),
              ),
            )
                .animate(delay: (80 + 60 * i).ms)
                .fadeIn(duration: Anim.medium)
                .slideY(begin: 0.25, curve: Anim.curve),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- burbujas

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.repo,
    required this.onOpenNote,
    required this.onChanged,
    this.onRetry,
  });

  final AiMessage message;
  final NotesRepository repo;
  final void Function(String id) onOpenNote;
  final VoidCallback onChanged;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final user = message.role == AiRole.user;
    final error = message.role == AiRole.error;
    final err = Theme.of(context).colorScheme.error;
    final fg = user
        ? (ThemeData.estimateBrightnessForColor(p.accent) == Brightness.dark
            ? Colors.white
            : Colors.black)
        : null;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: user
            ? p.accent
            : error
                ? err.withValues(alpha: 0.1)
                : p.background,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(user ? 18 : 6),
          bottomRight: Radius.circular(user ? 6 : 18),
        ),
        border: error ? Border.all(color: err.withValues(alpha: 0.4)) : null,
      ),
      child: error
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline_rounded, size: 18, color: err),
              const SizedBox(width: 8),
              Expanded(child: SelectableText(message.text)),
            ])
          : _RichText(message.text, color: fg),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.text.isNotEmpty) bubble,
          // Debajo: reintentar (errores) o copiar (respuestas).
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: onRetry,
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(tr('Reintentar')),
              ),
            )
          else if (message.role == AiRole.assistant && message.text.isNotEmpty)
            IconButton(
              tooltip: tr('Copiar'),
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: p.secondary,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: message.text));
                showToast(context, tr('Respuesta copiada'),
                    icon: Icons.content_copy_rounded);
              },
              icon: const Icon(Icons.content_copy_rounded),
            ),
          if (message.sources.any((id) => repo.byId(id) != null))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final id in message.sources)
                    if (repo.byId(id) case final src?)
                      if (!src.deleted && !src.vault)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar:
                              const Icon(Icons.description_outlined, size: 15),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(src.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                          onPressed: () => onOpenNote(id),
                        ),
                ],
              ),
            ),
          for (final a in message.actions)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _ActionChip(
                action: a,
                exists: a.noteId != null && repo.byId(a.noteId!) != null,
                onOpen: a.noteId == null ? null : () => onOpenNote(a.noteId!),
                onUndo: a.undo == null || a.undone
                    ? null
                    : () {
                        a.undo!();
                        a.undone = true;
                        onChanged();
                        showToast(context, tr('Cambio deshecho'),
                            icon: Icons.undo_rounded);
                      },
              ),
            ),
        ],
      )
          .animate()
          .fadeIn(duration: Anim.medium)
          .slideY(begin: 0.15, curve: Anim.curve, duration: Anim.medium),
    );
  }
}

/// Texto con un Markdown mínimo: **negrita**, `código`, listas con "-",
/// "*" o numeradas, y títulos (#) en negrita.
class _RichText extends StatelessWidget {
  const _RichText(this.text, {this.color});
  final String text;
  final Color? color;

  List<InlineSpan> _inline(String line) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
    var last = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > last) {
        spans.add(TextSpan(text: line.substring(last, m.start)));
      }
      spans.add(m.group(1) != null
          ? TextSpan(
              text: m.group(1),
              style: const TextStyle(fontWeight: FontWeight.w700))
          : TextSpan(
              text: m.group(2),
              style: TextStyle(
                  fontFamily: 'monospace',
                  backgroundColor:
                      (color ?? Colors.grey).withValues(alpha: 0.15))));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context)
        .style
        .copyWith(color: color, height: 1.4, fontSize: 14.5);
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final raw in lines)
          if (raw.trim().isEmpty)
            const SizedBox(height: 6)
          else if (RegExp(r'^\s*\d+[.)]\s+').hasMatch(raw))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${RegExp(r'^\s*(\d+)').firstMatch(raw)!.group(1)}.  ',
                      style: style.copyWith(fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Text.rich(
                        TextSpan(
                            children: _inline(raw.replaceFirst(
                                RegExp(r'^\s*\d+[.)]\s+'), ''))),
                        style: style),
                  ),
                ],
              ),
            )
          else if (RegExp(r'^#+\s').hasMatch(raw))
            Text.rich(
                TextSpan(
                    children: _inline(raw.replaceFirst(RegExp(r'^#+\s*'), ''))),
                style: style.copyWith(fontWeight: FontWeight.w800))
          else if (RegExp(r'^\s*[-*•]\s+').hasMatch(raw))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: style),
                  Expanded(
                    child: Text.rich(
                        TextSpan(
                            children: _inline(
                                raw.replaceFirst(RegExp(r'^\s*[-*•]\s+'), ''))),
                        style: style),
                  ),
                ],
              ),
            )
          else
            Text.rich(
                TextSpan(
                    children: _inline(raw.replaceFirst(RegExp(r'^#+\s*'), ''))),
                style: style),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.action,
    required this.exists,
    this.onOpen,
    this.onUndo,
  });

  final AiAction action;
  final bool exists;
  final VoidCallback? onOpen;
  final VoidCallback? onUndo;

  static const _icons = <String, IconData>{
    'note_add': Icons.note_add_outlined,
    'attach_file': Icons.attach_file_rounded,
    'edit': Icons.edit_note_rounded,
    'alarm': Icons.alarm_on_rounded,
    'event_busy': Icons.event_busy_outlined,
    'task_alt': Icons.task_alt_rounded,
    'folder': Icons.drive_file_move_outline,
    'push_pin': Icons.push_pin_outlined,
    'archive': Icons.archive_outlined,
    'delete': Icons.delete_outline_rounded,
    'palette': Icons.palette_outlined,
    'link': Icons.hub_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AnimatedOpacity(
      duration: Anim.medium,
      opacity: action.undone ? 0.5 : 1,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(
          color: p.accent.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icons[action.icon] ?? Icons.check_rounded,
                size: 16, color: p.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                action.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration:
                        action.undone ? TextDecoration.lineThrough : null),
              ),
            ),
            if (onOpen != null && exists && !action.undone)
              TextButton(
                onPressed: onOpen,
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: Text(tr('Abrir')),
              ),
            if (onUndo != null)
              TextButton(
                onPressed: onUndo,
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: Text(tr('Deshacer')),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Pensando…" con tres puntos que laten.
class _Thinking extends StatelessWidget {
  const _Thinking({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: p.background,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration:
                        BoxDecoration(color: p.accent, shape: BoxShape.circle),
                  )
                      .animate(
                          onPlay: (c) => c.repeat(reverse: true),
                          delay: (150 * i).ms)
                      .scale(
                          begin: const Offset(0.6, 0.6),
                          end: const Offset(1.1, 1.1),
                          duration: 450.ms,
                          curve: Curves.easeInOut)
                      .fade(begin: 0.4, end: 1),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: AnimatedSwitcher(
              duration: Anim.fast,
              child: Text(text,
                  key: ValueKey(text),
                  style: TextStyle(fontSize: 13, color: p.secondary)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: Anim.fast);
  }
}

// -------------------------------------------------- configurar la clave

class _KeySetup extends StatefulWidget {
  const _KeySetup({super.key, required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<_KeySetup> createState() => _KeySetupState();
}

class _KeySetupState extends State<_KeySetup> {
  final settings = AiSettings.instance;
  late AiProvider _provider = settings.provider;
  late final _key = TextEditingController(text: settings.apiKey ?? '');
  late String _model = settings.model;
  late final _custom = TextEditingController(
      text: _provider.models.any((m) => m.id == _model) ? '' : _model);
  bool _show = false;
  bool _busy = false;
  String? _error;

  bool get _isCustom => !_provider.models.any((m) => m.id == _model);

  /// Cambiar de proveedor: cada uno guarda su propia clave y su modelo.
  void _pick(AiProvider p) {
    if (p == _provider || _busy) return;
    setState(() {
      _provider = p;
      _key.text = settings.keyFor(p) ?? '';
      _model = settings.modelFor(p);
      _custom.text = p.models.any((m) => m.id == _model) ? '' : _model;
      _error = null;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    final model = _isCustom ? _custom.text.trim() : _model;
    if (key.isEmpty) {
      setState(() => _error = trf('Pega tu clave de {0}.', [_provider.label]));
      return;
    }
    if (model.isEmpty) {
      setState(() => _error = tr('Escribe el nombre del modelo.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Si el modelo elegido no tiene cuota gratis en el proyecto de la
      // clave, se prueban los demás y se usa el primero que funcione.
      final working =
          await AiClient.forProvider(_provider).findWorkingModel(key, model);
      await settings.save(provider: _provider, apiKey: key, model: working);
      if (!mounted) return;
      showToast(
          context,
          working == model
              ? tr('Clave guardada. ¡Listo!')
              : trf('Clave guardada. {0} no funciona con tu clave: uso {1}.',
                  [model, working]),
          icon: Icons.check_circle_outline_rounded,
          duration: Duration(seconds: working == model ? 3 : 6));
      widget.onSaved();
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    await settings.forget(_provider);
    _key.clear();
    if (mounted) {
      setState(() {});
      showToast(context, tr('Clave borrada de este dispositivo'),
          icon: Icons.key_off_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget step(int n, String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: Text('$n',
                    style: TextStyle(
                        color: p.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    child,
                  ],
                ),
              ),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      children: [
        // Proveedor: Gemini (gratis), ChatGPT o Claude (de pago).
        SegmentedButton<AiProvider>(
          segments: [
            for (final pr in AiProvider.values)
              ButtonSegment(value: pr, label: Text(pr.label)),
          ],
          selected: {_provider},
          showSelectedIcon: false,
          onSelectionChanged: (v) => _pick(v.first),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: Anim.medium,
          child: Text(
            _provider.free
                ? tr('El asistente usa tu propia clave de la API de Gemini '
                    '(gratis con una cuenta de Google). Se guarda cifrada solo '
                    'en este dispositivo.')
                : trf(
                    'El asistente usa tu propia clave de la API de {0}. Es de '
                    'pago: necesitas saldo en tu cuenta (cada pregunta cuesta '
                    'muy poco). Se guarda cifrada solo en este dispositivo.',
                    [_provider.label]),
            key: ValueKey(_provider),
            style: TextStyle(color: p.secondary, height: 1.4),
          ),
        ),
        const SizedBox(height: 18),
        step(
          1,
          trf('Crea tu clave en {0}', [_provider.keySite]),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => openLink(context, _provider.keyUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(trf('Abrir {0}', [_provider.keySite])),
            ),
          ),
        ),
        step(
          2,
          tr('Pega la clave aquí'),
          TextField(
            controller: _key,
            obscureText: !_show,
            enabled: !_busy,
            contextMenuBuilder: textFieldMenu,
            decoration: InputDecoration(
              hintText: _provider.keyHint,
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                tooltip: _show ? tr('Ocultar') : tr('Mostrar'),
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
              ),
            ),
          ),
        ),
        step(
          3,
          tr('Elige el modelo'),
          Column(
            children: [
              for (final m in _provider.models)
                _ModelTile(
                  title: m.label,
                  subtitle: tr(m.hint),
                  selected: _model == m.id,
                  onTap: () => setState(() => _model = m.id),
                ),
              _ModelTile(
                title: tr('Otro modelo'),
                subtitle: trf('Escribe su nombre (p. ej. {0})',
                    [_provider.fallbackModels.last]),
                selected: _isCustom,
                onTap: () => setState(() => _model =
                    _custom.text.trim().isEmpty ? '_' : _custom.text.trim()),
              ),
              AnimatedSize(
                duration: Anim.medium,
                curve: Anim.curve,
                child: _isCustom
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextField(
                          controller: _custom,
                          contextMenuBuilder: textFieldMenu,
                          onChanged: (v) => setState(
                              () => _model = v.trim().isEmpty ? '_' : v.trim()),
                          decoration: InputDecoration(
                              hintText: _provider.fallbackModels.first,
                              isDense: true),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        // Privacidad y límites.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, size: 18, color: p.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _provider.free
                      ? tr('Para responder, la IA recibe el texto de las notas '
                          'que consulta (nunca las del Vault). En el plan '
                          'gratuito, Google puede usar esos datos para mejorar '
                          'sus productos. El plan gratis tiene un límite de '
                          'peticiones por minuto y por día (se ve en Google AI '
                          'Studio).')
                      : trf(
                          'Para responder, la IA recibe el texto de las notas '
                          'que consulta (nunca las del Vault), y {0} cobra a tu '
                          'cuenta según lo que se use.',
                          [_provider.label]),
                  style: TextStyle(
                      fontSize: 12.5, color: p.secondary, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: Anim.fast,
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ).animate().shakeX(hz: 5, amount: 3),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (settings.configured)
              TextButton.icon(
                onPressed: _busy ? null : _forget,
                icon: const Icon(Icons.key_off_rounded, size: 18),
                label: Text(tr('Borrar clave')),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(tr('Probar y guardar')),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? p.accent.withValues(alpha: 0.1) : p.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: selected ? p.accent : Colors.transparent, width: 1.4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: Anim.fast,
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    key: ValueKey(selected),
                    size: 20,
                    color: selected ? p.accent : p.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          style: TextStyle(fontSize: 12, color: p.secondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
