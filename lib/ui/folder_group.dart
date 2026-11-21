import 'package:flutter/material.dart';

import '../models/note.dart';
import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';

/// Carpeta desplegable dentro de la lista de notas (como las carpetas de
/// pestañas de Zen): cabecera con flecha, icono, nombre y nº de notas; al
/// abrirla, sus notas aparecen debajo, sangradas y con una línea guía.
class FolderGroup extends StatefulWidget {
  const FolderGroup({
    super.key,
    required this.folder,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.onNewNote,
    required this.onOptions,
    this.child,
  });

  final Folder folder;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onNewNote;

  /// Opciones de la carpeta: con posición = clic derecho.
  final void Function(Offset? at) onOptions;

  /// Notas de la carpeta (null = vacía).
  final Widget? child;

  @override
  State<FolderGroup> createState() => _FolderGroupState();
}

class _FolderGroupState extends State<FolderGroup> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color =
        widget.folder.color == null ? p.accent : Color(widget.folder.color!);
    final open = widget.expanded;

    final header = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        onLongPress: () => widget.onOptions(null),
        onSecondaryTapUp: (d) => widget.onOptions(d.globalPosition),
        child: AnimatedContainer(
          duration: Anim.fast,
          curve: Anim.curve,
          height: 40,
          padding: const EdgeInsets.only(left: 4, right: 4),
          decoration: BoxDecoration(
            color: _hover ? p.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: Anim.medium,
                curve: Anim.curve,
                child: Icon(Icons.chevron_right_rounded,
                    size: 20, color: p.secondary),
              ),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: Anim.fast,
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: Icon(
                  open ? Icons.folder_open_rounded : Icons.folder_rounded,
                  key: ValueKey(open),
                  size: 19,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              // Al pasar el ratón: crear una nota dentro.
              AnimatedOpacity(
                duration: Anim.fast,
                opacity: _hover ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_hover,
                  child: IconButton(
                    tooltip: tr('Nueva nota aquí'),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(Icons.add_rounded, color: p.secondary),
                    onPressed: widget.onNewNote,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${widget.count}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );

    final body = widget.child == null
        ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 8),
            child: Text(tr('Carpeta vacía'),
                style: TextStyle(color: p.secondary, fontSize: 13)),
          )
        : widget.child!;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          // Contenido con línea guía a la izquierda; se despliega animado.
          ClipRect(
            child: AnimatedSize(
              duration: Anim.medium,
              curve: Anim.curve,
              alignment: Alignment.topCenter,
              child: open
                  ? Container(
                      margin: const EdgeInsets.only(left: 13, top: 4),
                      padding: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                              color: color.withValues(alpha: 0.45), width: 2),
                        ),
                      ),
                      child: body,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}
