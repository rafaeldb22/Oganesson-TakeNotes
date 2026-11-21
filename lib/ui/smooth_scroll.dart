import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Desplazamiento suave con la rueda del ratón: en vez de saltar de golpe,
/// cada paso de la rueda anima la lista hasta su destino (y los pasos
/// seguidos se acumulan, así que el movimiento es continuo).
///
/// Úsalo como `controller:` de listas y vistas desplazables.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.duration = const Duration(milliseconds: 460),
    this.curve = Curves.easeOutCubic,
    this.wheelFactor = 0.9,
  });

  /// Duración de la animación de cada paso de la rueda.
  final Duration duration;
  final Curve curve;

  /// Multiplica la distancia de cada paso (menos de 1 = más lento).
  final double wheelFactor;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
      ScrollContext context, ScrollPosition? oldPosition) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      duration: duration,
      curve: curve,
      wheelFactor: wheelFactor,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    required this.duration,
    required this.curve,
    required this.wheelFactor,
  });

  final Duration duration;
  final Curve curve;
  final double wheelFactor;

  /// Destino acumulado mientras dura la animación.
  double? _target;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) return;
    final from = _target ?? pixels;
    final target =
        (from + delta * wheelFactor).clamp(minScrollExtent, maxScrollExtent);
    if (target == pixels && _target == null) return;
    _target = target;
    animateTo(target, duration: duration, curve: curve).whenComplete(() {
      if (_target == target) _target = null;
    });
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    _target = null; // arrastre con el dedo: manda el usuario
    return super.drag(details, dragCancelCallback);
  }

  @override
  void jumpTo(double value) {
    _target = null;
    super.jumpTo(value);
  }
}
