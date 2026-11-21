import 'package:flutter/material.dart';

import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';

/// Menú de clic derecho sobre texto (cortar, copiar, pegar, seleccionar
/// todo) con el estilo de la app: iconos, atajos, resaltado al pasar el
/// ratón y entrada animada. Sustituye a la barra por defecto de Flutter.
Widget buildTextMenu(BuildContext context, List<ContextMenuButtonItem> items,
    TextSelectionToolbarAnchors anchors) {
  if (items.isEmpty) return const SizedBox.shrink();
  return TextFieldTapRegion(
    child: _TextMenu(items: items, anchor: anchors.primaryAnchor),
  );
}

/// Para `TextField(contextMenuBuilder: textFieldMenu)`.
Widget textFieldMenu(BuildContext context, EditableTextState state) =>
    buildTextMenu(
        context, state.contextMenuButtonItems, state.contextMenuAnchors);

class _TextMenu extends StatelessWidget {
  const _TextMenu({required this.items, required this.anchor});
  final List<ContextMenuButtonItem> items;
  final Offset anchor;

  static const _width = 210.0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final size = c.biggest;
      final left = anchor.dx.clamp(8.0, size.width - _width - 8);
      final openUp = anchor.dy > size.height - 220;
      return Stack(
        children: [
          Positioned(
            left: left,
            top: openUp ? null : anchor.dy + 4,
            bottom: openUp ? size.height - anchor.dy + 4 : null,
            width: _width,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: 0.92 + 0.08 * t,
                  alignment: openUp ? Alignment.bottomLeft : Alignment.topLeft,
                  child: child,
                ),
              ),
              child: Material(
                color: p.card,
                elevation: 10,
                shadowColor:
                    Theme.of(context).shadowColor.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: p.separator),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in items) _TextMenuItem(item: item),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _TextMenuItem extends StatefulWidget {
  const _TextMenuItem({required this.item});
  final ContextMenuButtonItem item;

  @override
  State<_TextMenuItem> createState() => _TextMenuItemState();
}

class _TextMenuItemState extends State<_TextMenuItem> {
  bool _hover = false;

  (IconData, String, String?) get _look => switch (widget.item.type) {
        ContextMenuButtonType.cut => (
            Icons.content_cut_rounded,
            tr('Cortar'),
            'Ctrl+X'
          ),
        ContextMenuButtonType.copy => (
            Icons.content_copy_rounded,
            tr('Copiar'),
            'Ctrl+C'
          ),
        ContextMenuButtonType.paste => (
            Icons.content_paste_rounded,
            tr('Pegar'),
            'Ctrl+V'
          ),
        ContextMenuButtonType.selectAll => (
            Icons.select_all_rounded,
            tr('Seleccionar todo'),
            'Ctrl+A'
          ),
        ContextMenuButtonType.delete => (
            Icons.backspace_outlined,
            tr('Eliminar'),
            null
          ),
        ContextMenuButtonType.lookUp => (
            Icons.search_rounded,
            tr('Buscar'),
            null
          ),
        _ => (
            Icons.more_horiz_rounded,
            widget.item.label ?? '',
            null,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (icon, label, hint) = _look;
    final fg = Theme.of(context).colorScheme.onSurface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.item.onPressed,
        child: AnimatedContainer(
          duration: Anim.fast,
          curve: Anim.curve,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color:
                _hover ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: _hover ? p.accent : p.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: fg)),
              ),
              if (hint != null)
                Text(hint,
                    style: TextStyle(fontSize: 11.5, color: p.secondary)),
            ],
          ),
        ),
      ),
    );
  }
}
