import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'anim.dart';
import 'theme.dart';
import 'i18n.dart';

/// Opciones de orden de la lista de notas.
const sortOptions = <String, (String, IconData)>{
  'modificada': ('Modificación', Icons.update_rounded),
  'creada': ('Creación', Icons.event_note_outlined),
  'nombre': ('Nombre (A–Z)', Icons.sort_by_alpha_rounded),
};

/// Selector de orden: una pastilla discreta que abre un panel flotante
/// animado (aparece con fundido y escala desde la pastilla).
class SortMenu extends StatefulWidget {
  const SortMenu({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<SortMenu> createState() => _SortMenuState();
}

class _SortMenuState extends State<SortMenu> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  bool _hover = false;

  void _toggle() => setState(_portal.toggle);

  void _close() {
    if (_portal.isShowing) setState(_portal.hide);
  }

  void _pick(String v) {
    _close();
    if (v != widget.value) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final open = _portal.isShowing;
    final (rawLabel, icon) =
        sortOptions[widget.value] ?? sortOptions.values.first;
    final label = tr(rawLabel);

    return TapRegion(
      groupId: this,
      onTapOutside: (_) => _close(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (_) => _panel(context),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: _toggle,
              child: AnimatedContainer(
                duration: Anim.fast,
                curve: Anim.curve,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: open || _hover ? p.searchFill : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: Anim.medium,
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(scale: a, child: c),
                      ),
                      child: Icon(icon,
                          key: ValueKey(icon), size: 15, color: p.secondary),
                    ),
                    const SizedBox(width: 6),
                    AnimatedSize(
                      duration: Anim.medium,
                      curve: Anim.curve,
                      child: AnimatedSwitcher(
                        duration: Anim.medium,
                        switchInCurve: Anim.curve,
                        transitionBuilder: (c, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(
                                    begin: const Offset(0, 0.4),
                                    end: Offset.zero)
                                .animate(a),
                            child: c,
                          ),
                        ),
                        child: Text(label,
                            key: ValueKey(label),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: p.secondary)),
                      ),
                    ),
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: Anim.medium,
                      curve: Anim.curve,
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 17, color: p.secondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final p = Palette.of(context);
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomRight,
      followerAnchor: Alignment.topRight,
      offset: const Offset(0, 6),
      child: Align(
        alignment: Alignment.topRight,
        child: TapRegion(
          groupId: this,
          child: Material(
            color: p.card,
            elevation: 10,
            shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: p.separator),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicWidth(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                      child: Text(tr('Ordenar por'),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              color: p.secondary)),
                    ),
                    for (final (i, e) in sortOptions.entries.indexed)
                      _Option(
                        label: tr(e.value.$1),
                        icon: e.value.$2,
                        selected: e.key == widget.value,
                        onTap: () => _pick(e.key),
                      )
                          .animate(delay: (25 * i).ms)
                          .fadeIn(duration: Anim.fast)
                          .slideY(begin: -0.15, curve: Anim.curve),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: Anim.fast, curve: Anim.curve).scale(
              begin: const Offset(0.92, 0.92),
              alignment: Alignment.topRight,
              duration: Anim.medium,
              curve: Curves.easeOutBack),
        ),
      ),
    );
  }
}

class _Option extends StatefulWidget {
  const _Option({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Option> createState() => _OptionState();
}

class _OptionState extends State<_Option> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = widget.selected ? p.accent : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Anim.fast,
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? p.accent.withValues(alpha: 0.12)
                : (_hover ? p.searchFill : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: fg ?? p.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            widget.selected ? FontWeight.w600 : FontWeight.w400,
                        color: fg)),
              ),
              const SizedBox(width: 18),
              AnimatedScale(
                scale: widget.selected ? 1 : 0,
                duration: Anim.medium,
                curve: Curves.easeOutBack,
                child: Icon(Icons.check_rounded, size: 18, color: p.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
