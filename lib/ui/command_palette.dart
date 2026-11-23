import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import 'anim.dart';
import 'i18n.dart';
import 'text_menu.dart';
import 'theme.dart';

/// Una acción de la paleta de comandos.
class PaletteCommand {
  const PaletteCommand(this.icon, this.label, this.run, {this.shortcut});
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback run;
}

/// Quita tildes y mayúsculas: "cafe" encuentra "Café".
String paletteNormalize(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i == -1 ? ch : to[i]);
  }
  return b.toString();
}

/// ¿Están todas las palabras de [query] en [text]?
bool paletteMatches(String query, String text) {
  final t = paletteNormalize(text);
  return paletteNormalize(query)
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .every(t.contains);
}

/// Ctrl+K: buscar notas y lanzar cualquier acción desde el teclado.
Future<void> showCommandPalette(
  BuildContext context, {
  required NotesRepository repo,
  required List<PaletteCommand> commands,
  required void Function(String id) onOpenNote,
}) async {
  final action = await showGeneralDialog<VoidCallback>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Cerrar'),
    barrierColor: Colors.black.withValues(alpha: 0.3),
    transitionDuration: Anim.medium,
    pageBuilder: (_, __, ___) => _Palette(
      repo: repo,
      commands: commands,
      onOpenNote: onOpenNote,
    ),
    transitionBuilder: (_, a, __, child) {
      final c = CurvedAnimation(parent: a, curve: Anim.curve);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(c),
          alignment: Alignment.topCenter,
          child: child,
        ),
      );
    },
  );
  // La acción se lanza con la paleta ya cerrada.
  action?.call();
}

class _Item {
  const _Item(this.icon, this.label, this.run, {this.subtitle, this.shortcut});
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? shortcut;
  final VoidCallback run;
}

class _Palette extends StatefulWidget {
  const _Palette({
    required this.repo,
    required this.commands,
    required this.onOpenNote,
  });

  final NotesRepository repo;
  final List<PaletteCommand> commands;
  final void Function(String id) onOpenNote;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  static const _rowHeight = 54.0;
  static const _maxNotes = 30;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _index = 0;
  bool _picked = false; // Intro puede llegar por dos caminos

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Item> get _items {
    final q = _input.text.trim();
    final commands = [
      for (final c in widget.commands)
        if (q.isEmpty || paletteMatches(q, c.label))
          _Item(c.icon, c.label, c.run, shortcut: c.shortcut),
    ];
    final found = widget.repo.notes
        .where((n) => !n.isEmpty)
        .where((n) => q.isEmpty || paletteMatches(q, n.content))
        .toList();
    // Primero las que lo tienen en el título; dentro, se mantiene el orden.
    final ranked = q.isEmpty
        ? found
        : [
            ...found.where((n) => paletteMatches(q, n.title)),
            ...found.where((n) => !paletteMatches(q, n.title)),
          ];
    final notes = ranked.take(q.isEmpty ? 6 : _maxNotes).map((n) => _Item(
          n.isTemporal ? Icons.alarm_rounded : Icons.sticky_note_2_outlined,
          n.title,
          () => widget.onOpenNote(n.id),
          subtitle: n.hasPreview ? n.preview : null,
        ));
    // Al buscar, primero las notas; sin buscar, primero las acciones.
    return q.isEmpty ? [...commands, ...notes] : [...notes, ...commands];
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _index = (_index + delta) % count);
    if (!_scroll.hasClients) return;
    final top = _index * _rowHeight;
    final pos = _scroll.position;
    if (top < pos.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo(top + _rowHeight - pos.viewportDimension);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = _items;
    final selected = items.isEmpty ? 0 : _index.clamp(0, items.length - 1);
    void pick(_Item i) {
      if (_picked) return;
      _picked = true;
      Navigator.of(context).pop(i.run);
    }

    void submit() {
      if (items.isNotEmpty) pick(items[selected]);
    }

    return Align(
      alignment: const Alignment(0, -0.62),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
          child: Material(
            color: p.card,
            elevation: 18,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _move(1, items.length),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _move(-1, items.length),
                const SingleActivator(LogicalKeyboardKey.enter): submit,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): submit,
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.of(context).pop(),
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _input,
                    autofocus: autoKeyboard,
                    contextMenuBuilder: textFieldMenu,
                    textInputAction: TextInputAction.go,
                    onChanged: (_) => setState(() => _index = 0),
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      hintText: tr('Busca notas o escribe una acción…'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  Divider(height: 1, color: p.separator),
                  Flexible(
                    child: items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(tr('Sin resultados'),
                                style: TextStyle(color: p.secondary)),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemExtent: _rowHeight,
                            itemCount: items.length,
                            itemBuilder: (context, i) => _Row(
                              item: items[i],
                              selected: i == selected,
                              onTap: () => pick(items[i]),
                              onHover: () {
                                if (_index != i) setState(() => _index = i);
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ).animate().slideY(
            begin: -0.03, end: 0, duration: Anim.medium, curve: Anim.curve),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final _Item item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Anim.fast,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? p.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 19, color: p.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (item.subtitle != null)
                      Text(item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.secondary)),
                  ],
                ),
              ),
              if (item.shortcut != null)
                Text(item.shortcut!,
                    style: TextStyle(fontSize: 12, color: p.secondary)),
            ],
          ),
        ),
      ),
    );
  }
}
