import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Aviso emergente abajo en el centro, con animación de entrada y de
/// salida (también cuando lo sustituye otro aviso o se pulsa su botón).
/// Solo hay uno a la vez.
void showToast(
  BuildContext context,
  String message, {
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.dismiss();
  late final _ToastHandle handle;
  final entry = OverlayEntry(
    builder: (_) => _Toast(
      handle: handle,
      message: message,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    ),
  );
  handle = _ToastHandle(entry);
  _current = handle;
  overlay.insert(entry);
}

_ToastHandle? _current;

class _ToastHandle {
  _ToastHandle(this.entry);
  final OverlayEntry entry;
  _ToastState? state;
  bool _removed = false;

  /// Cierra con animación de salida.
  void dismiss() => state?.close() ?? remove();

  void remove() {
    if (_removed) return;
    _removed = true;
    entry.remove();
    if (identical(_current, this)) _current = null;
  }
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.handle,
    required this.message,
    required this.duration,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final _ToastHandle handle;
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.handle.state = this;
    _ctrl.forward();
    _timer = Timer(widget.duration, close);
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) await _ctrl.reverse();
    widget.handle.remove();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final curved = CurvedAnimation(
        parent: _ctrl, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    final fade = CurvedAnimation(
        parent: _ctrl, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 24 + MediaQuery.paddingOf(context).bottom,
      child: SafeArea(
        top: false,
        child: Center(
          child: FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.6), end: Offset.zero)
                  .animate(curved),
              child: ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.0).animate(curved),
                child: Material(
                  color: p.card,
                  elevation: 10,
                  shadowColor:
                      Theme.of(context).shadowColor.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: p.separator),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          14, 10, widget.actionLabel == null ? 16 : 6, 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, size: 18, color: p.accent),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(widget.message,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: onSurface)),
                          ),
                          if (widget.actionLabel != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              style: TextButton.styleFrom(
                                  foregroundColor: p.accent,
                                  visualDensity: VisualDensity.compact),
                              onPressed: () {
                                widget.onAction?.call();
                                close();
                              },
                              child: Text(widget.actionLabel!,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
