import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'anim.dart';
import 'theme.dart';

/// Una opción del menú contextual. `null` en la lista = separador.
class MenuEntry {
  const MenuEntry(this.value, this.icon, this.label,
      {this.danger = false, this.hint, this.subtitle, this.badge})
      : section = false;

  /// Título de sección (no se puede pulsar).
  const MenuEntry.section(this.label)
      : value = '',
        icon = Icons.circle,
        danger = false,
        hint = null,
        subtitle = null,
        badge = null,
        section = true;

  final String value;
  final IconData icon;
  final String label;
  final bool danger;
  final bool section;

  /// Texto pequeño a la derecha (p. ej. un atajo de teclado).
  final String? hint;

  /// Segunda línea bajo el texto.
  final String? subtitle;

  /// Contador en una pastilla a la derecha.
  final String? badge;
}

/// Menú contextual (clic derecho) con cabecera opcional, iconos, separadores,
/// resaltado al pasar el ratón y animación de entrada y salida desde el
/// punto del clic. Devuelve el `value` elegido o null.
///
/// [alignRight]: el borde derecho del menú queda en [position] (para menús
/// que salen de un botón). [header]: cabecera propia (p. ej. la cuenta).
Future<String?> showContextMenu(
  BuildContext context, {
  required Offset position,
  required List<MenuEntry?> entries,
  String? title,
  Widget? header,
  bool alignRight = false,
  double width = 250,
}) {
  return Navigator.of(context).push<String>(_ContextMenuRoute(
    position: position,
    entries: entries,
    title: title,
    header: header,
    alignRight: alignRight,
    width: width,
    capturedTheme: Theme.of(context),
  ));
}

class _ContextMenuRoute extends PopupRoute<String> {
  _ContextMenuRoute({
    required this.position,
    required this.entries,
    required this.title,
    required this.header,
    required this.alignRight,
    required this.width,
    required this.capturedTheme,
  });

  final Offset position;
  final List<MenuEntry?> entries;
  final String? title;
  final Widget? header;
  final bool alignRight;
  final double width;
  final ThemeData capturedTheme;

  @override
  Color? get barrierColor => Colors.transparent;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'menu';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return Theme(
      data: capturedTheme,
      child: _ContextMenuLayout(
        position: position,
        animation: animation,
        alignRight: alignRight,
        width: width,
        child:
            _ContextMenuPanel(entries: entries, title: title, header: header),
      ),
    );
  }
}

/// Coloca el panel junto al cursor sin salirse de la pantalla y lo anima
/// desde la esquina más cercana al clic.
class _ContextMenuLayout extends StatelessWidget {
  const _ContextMenuLayout({
    required this.position,
    required this.animation,
    required this.child,
    required this.alignRight,
    required this.width,
  });
  final Offset position;
  final Animation<double> animation;
  final Widget child;
  final bool alignRight;
  final double width;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = c.biggest;
      // Si no cabe a la derecha o abajo, se abre hacia el otro lado.
      final openLeft = alignRight || position.dx + width + 8 > size.width;
      final openUp = position.dy > size.height * 0.6;
      final left = openLeft ? position.dx - width : position.dx;
      final origin = Alignment(openLeft ? 1 : -1, openUp ? 1 : -1);
      final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic);
      return Stack(
        children: [
          Positioned(
            left: left.clamp(8.0, size.width - width - 8),
            top: openUp ? null : position.dy.clamp(8.0, size.height - 60),
            bottom: openUp
                ? (size.height - position.dy).clamp(8.0, size.height - 60)
                : null,
            width: width,
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
  const _ContextMenuPanel({required this.entries, this.title, this.header});
  final List<MenuEntry?> entries;
  final String? title;
  final Widget? header;

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
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 32),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (header != null) header!,
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
              // Entrada escalonada: cada opción aparece un poco después.
              for (final (i, e) in entries.indexed)
                (e == null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            child: Divider(height: 1, color: p.separator),
                          )
                        : e.section
                            ? Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 4),
                                child: Text(e.label.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                        color: p.secondary)),
                              )
                            : _MenuItem(entry: e))
                    .animate(delay: (14 * i).ms)
                    .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                    .slideX(begin: 0.04, duration: 220.ms, curve: Anim.curve),
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
                    size: 16,
                    color: e.danger ? error : (_hover ? tint : p.secondary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: fg)),
                    if (e.subtitle != null)
                      Text(e.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: p.secondary)),
                  ],
                ),
              ),
              if (e.badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(e.badge!,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: tint)),
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
