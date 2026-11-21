import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import 'anim.dart';
import 'theme.dart';
import 'urgency.dart';
import 'i18n.dart';

/// Elegir el color de una nota. Cambia también su barra de tiempo (mecha)
/// y sus barras en el calendario. Se aplica al momento.
Future<void> showNoteColorSheet(
    BuildContext context, NotesRepository repo, String noteId) {
  return showModalBottomSheet<void>(
    context: context,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final current = repo.byId(noteId)?.color;
        final options = <(String, int?)>[
          (tr('Automático'), null),
          ...noteColors
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Color de la nota'),
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(tr('También cambia su mecha de tiempo.'),
                    style: TextStyle(color: Palette.secondary(context))),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < options.length; i++)
                      _Swatch(
                        name: tr(options[i].$1),
                        color: options[i].$2,
                        selected: options[i].$2 == current,
                        onTap: () => repo.setColor(noteId, options[i].$2),
                      )
                          .animate(delay: (15 * i).ms)
                          .fadeIn(duration: Anim.medium)
                          .scale(
                              begin: const Offset(0.7, 0.7),
                              curve: Curves.easeOutBack,
                              duration: Anim.slow),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stops = fusePalette(color);
    return Tooltip(
      message: name,
      child: Bouncy(
        pressedScale: 0.85,
        hoverScale: 1.08,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Anim.medium,
            curve: Anim.curve,
            width: 44,
            height: 44,
            padding: EdgeInsets.all(selected ? 3 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: stops,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 20)
                  : (color == null
                      ? const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 16)
                      : null),
            ),
          ),
        ),
      ),
    );
  }
}
