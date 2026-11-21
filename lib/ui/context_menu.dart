import 'package:flutter/material.dart';

import 'anim.dart';
import 'theme.dart';

/// Una opción del menú contextual. `null` en la lista = separador.
class MenuEntry {
  const MenuEntry(this.value, this.icon, this.label,
      {this.danger = false, this.hint});
  final String value;
  final IconData icon;
  final String label;
  final bool danger;

  /// Texto pequeño a la derecha (p. ej. un atajo de teclado).
  final String? hint;
}

/// Menú contextual (clic derecho) con cabecera opcional, iconos, separadores,
/// resaltado al pasar el ratón y animación de entrada y salida desde el
/// punto del clic. Devuelve el `value` elegido o null.
Future<String?> showContextMenu(
  BuildContext context, {
  required Offset position,
  required List<MenuEntry?> entries,
  String? title,
}) {
  return Navigator.of(context).push<String>(_ContextMenuRoute(
    position: position,
    entries: entries,
    title: title,
    capturedTheme: Theme.of(context),
  ));
}

class _ContextMenuRoute extends PopupRoute<String> {
  _ContextMenuRoute({
    required this.position,
    required this.entries,
    required this.title,
    required this.capturedTheme,
  });

  final Offset position;
  final List<MenuEntry?> entries;
  final String? title;
  final ThemeData capturedTheme;

  @override
  Color? get barrierColor => Colors.transparent;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'menu';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return Theme(
      data: capturedTheme,
      child: _ContextMenuLayout(
        position: position,
        animation: animation,
        child: _ContextMenuPanel(entries: entries, title: title),
      ),
    );
  }
}

/// Coloca el panel junto al cursor sin salirse de la pantalla y lo anima
/// desde la esquina más cercana al clic.
class _ContextMenuLayout extends StatelessWidget {
  const _ContextMenuLayout(
      {required this.position, required this.animation, required this.child});
  final Offset position;
  final Animation<double> animation;
  final Widget child;

  static const _width = 250.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = c.biggest;
      // Si no cabe a la derecha o abajo, se abre hacia el otro lado.
      final openLeft = position.dx + _width + 8 > size.width;
      final openUp = position.dy > size.height * 0.6;
      final left = openLeft ? position.dx - _width : position.dx;
      final origin = Alignment(openLeft ? 1 : -1, openUp ? 1 : -1);
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic);
      return Stack(
        children: [
          Positioned(
            left: left.clamp(8.0, size.width - _width - 8),
            top: openUp ? null : position.dy.clamp(8.0, size.height - 60),
            bottom: openUp
                ? (size.height - position.dy).clamp(8.0, size.height - 60)
                : null,
            width: _width,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                alignment: origin,
                scale: Tween(begin: 0.9, end: 1.0).animate(curved),
                child: SlideTransition(
                  position: Tween(
                    begin: Offset(0, openUp ? 0.03 : -0.03),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _ContextMenuPanel extends StatelessWidget {
  const _ContextMenuPanel({required this.entries, this.title});
  final List<MenuEntry?> entries;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.card,
      elevation: 12,
      shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height - 32),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Text(title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: p.secondary)),
                ),
              for (final e in entries)
                if (e == null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Divider(height: 1, color: p.separator),
                  )
                else
                  _MenuItem(entry: e),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({required this.entry});
  final MenuEntry entry;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final e = widget.entry;
    final error = Theme.of(context).colorScheme.error;
    final fg = e.danger ? error : Theme.of(context).colorScheme.onSurface;
    final tint = e.danger ? error : p.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(e.value),
        child: AnimatedContainer(
          duration: Anim.fast,
          curve: Anim.curve,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: _hover ? tint.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: Anim.fast,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: _hover ? 0.18 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(e.icon,
                    size: 16, color: e.danger ? error : (_hover ? tint : p.secondary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(e.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: fg)),
              ),
              if (e.hint != null)
                Text(e.hint!,
                    style: TextStyle(fontSize: 11.5, color: p.secondary)),
            ],
          ),
        ),
      ),
    );
  }
}
