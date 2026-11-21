import 'package:flutter/material.dart';

/// Curvas y duraciones comunes para que todo se mueva igual.
class Anim {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
}

/// Encoge un poco al pulsar y crece al pasar el ratón (efecto "botón vivo").
class Bouncy extends StatefulWidget {
  const Bouncy({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
    this.hoverScale = 1.0,
  });

  final Widget child;
  final double pressedScale;
  final double hoverScale;

  @override
  State<Bouncy> createState() => _BouncyState();
}

class _BouncyState extends State<Bouncy> {
  bool _pressed = false;
  bool _hover = false;

  void _set({bool? pressed, bool? hover}) {
    if (!mounted) return;
    setState(() {
      _pressed = pressed ?? _pressed;
      _hover = hover ?? _hover;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed
        ? widget.pressedScale
        : (_hover ? widget.hoverScale : 1.0);
    return MouseRegion(
      onEnter: (_) => _set(hover: true),
      onExit: (_) => _set(hover: false, pressed: false),
      child: Listener(
        onPointerDown: (_) => _set(pressed: true),
        onPointerUp: (_) => _set(pressed: false),
        onPointerCancel: (_) => _set(pressed: false),
        child: AnimatedScale(
          scale: scale,
          duration: _pressed ? const Duration(milliseconds: 90) : Anim.medium,
          curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Transición tipo iPhone: la nota entra desde la derecha y la lista
/// se desplaza un poco a la izquierda y se atenúa.
Widget pushTransition(Widget child, Animation<double> animation,
    {required bool isPage}) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  if (isPage) {
    return SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(curved),
      child: DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [
          BoxShadow(blurRadius: 24, color: Color(0x33000000)),
        ]),
        child: child,
      ),
    );
  }
  return SlideTransition(
    position:
        Tween(begin: const Offset(-0.3, 0), end: Offset.zero).animate(curved),
    child: FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(curved),
      child: child,
    ),
  );
}

/// Transición suave al cambiar de nota en el panel derecho (PC).
Widget fadeThrough(Widget child, Animation<double> animation) {
  final curved = CurvedAnimation(parent: animation, curve: Anim.curve);
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: Tween(begin: 0.985, end: 1.0).animate(curved),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    ),
  );
}
