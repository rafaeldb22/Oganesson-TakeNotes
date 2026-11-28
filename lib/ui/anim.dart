import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// En el móvil el teclado solo se abre cuando el usuario toca un campo; en
/// el PC los campos pueden enfocarse solos.
final bool autoKeyboard = !Platform.isAndroid;

/// Curvas y duraciones comunes para que todo se mueva igual.
/// Al volver a la app (desde segundo plano o la bandeja) todo entra con un
/// fundido y un pequeño zoom rápidos, no con la animación de inicio.
final resumeTicks = ValueNotifier<int>(0);

class ResumeFade extends StatefulWidget {
  const ResumeFade({super.key, required this.child});
  final Widget child;

  @override
  State<ResumeFade> createState() => _ResumeFadeState();
}

class _ResumeFadeState extends State<ResumeFade>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320), value: 1);
  late final AppLifecycleListener _life;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    resumeTicks.addListener(_play);
    _life = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        // Solo si de verdad estuvo fuera (no al cambiar de ventana un momento).
        final at = _hiddenAt;
        if (at != null && DateTime.now().difference(at).inMilliseconds > 400) {
          _play();
        }
        _hiddenAt = null;
      },
    );
  }

  void _play() => _c.forward(from: 0);

  @override
  void dispose() {
    resumeTicks.removeListener(_play);
    _life.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(t),
      child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(t), child: widget.child),
    );
  }
}

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
    final scale =
        _pressed ? widget.pressedScale : (_hover ? widget.hoverScale : 1.0);
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

/// Base común de las transiciones de pantalla: siempre la misma estructura
/// (opacidad > escala > desplazamiento > sombra). Así se puede cambiar de
/// una transición a otra a mitad de camino (p. ej. al eliminar la nota
/// abierta) sin que Flutter recree la pantalla que está saliendo.
Widget _layered(
  Widget child,
  Animation<double> animation, {
  double fadeFrom = 1,
  double scaleFrom = 1,
  Offset slideFrom = Offset.zero,
  bool shadow = false,
  Curve curve = Curves.easeOutCubic,
  Curve reverseCurve = Curves.easeInCubic,
}) {
  final curved = CurvedAnimation(
      parent: animation, curve: curve, reverseCurve: reverseCurve);
  return FadeTransition(
    opacity: Tween(begin: fadeFrom, end: 1.0).animate(curved),
    child: ScaleTransition(
      scale: Tween(begin: scaleFrom, end: 1.0).animate(curved),
      child: SlideTransition(
        position: Tween(begin: slideFrom, end: Offset.zero).animate(curved),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: shadow
                ? const [BoxShadow(blurRadius: 24, color: Color(0x33000000))]
                : const [],
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// Transición tipo iPhone: la nota entra desde la derecha y la lista
/// se desplaza un poco a la izquierda y se atenúa.
Widget pushTransition(Widget child, Animation<double> animation,
        {required bool isPage}) =>
    isPage
        ? _layered(child, animation,
            slideFrom: const Offset(1, 0), shadow: true)
        : _layered(child, animation,
            fadeFrom: 0.4, slideFrom: const Offset(-0.3, 0));

/// Transición suave al cambiar de nota en el panel derecho (PC).
Widget fadeThrough(Widget child, Animation<double> animation) => _layered(
      child,
      animation,
      fadeFrom: 0,
      scaleFrom: 0.985,
      slideFrom: const Offset(0, 0.015),
      curve: Anim.curve,
      reverseCurve: Anim.curve,
    );

/// Salida de una nota eliminada: se encoge, baja un poco y se desvanece
/// (como una tarjeta que se descarta).
Widget discardTransition(Widget child, Animation<double> animation) =>
    _layered(child, animation,
        fadeFrom: 0, scaleFrom: 0.88, slideFrom: const Offset(0, 0.08));

/// Lo que queda debajo de una nota eliminada: aparece sin moverse.
Widget stillTransition(Widget child, Animation<double> animation,
        {bool fade = false}) =>
    _layered(child, animation, fadeFrom: fade ? 0 : 1);
