import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'anim.dart';
import 'theme.dart';
import 'i18n.dart';

bool get isDesktopWindows => !kIsWeb && Platform.isWindows;

/// Barra de título propia para Windows (como la de Chrome): se puede
/// arrastrar para mover la ventana, doble clic para maximizar y tiene sus
/// propios botones de minimizar, maximizar y cerrar.
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key});

  static const height = 36.0;

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _maximized = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((m) {
      if (mounted) setState(() => _maximized = m);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowRestore() => setState(() => _maximized = false);
  @override
  void onWindowFocus() => setState(() => _focused = true);
  @override
  void onWindowBlur() => setState(() => _focused = false);

  Future<void> _toggleMax() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AnimatedContainer(
      duration: Anim.medium,
      height: AppTitleBar.height,
      decoration: BoxDecoration(
        color: Palette.titleBar(context),
        border: Border(bottom: BorderSide(color: p.separator, width: 1)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedOpacity(
          // Ventana sin foco: barra atenuada, como las apps nativas.
          duration: Anim.fast,
          opacity: _focused ? 1 : 0.55,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) => windowManager.startDragging(),
                  onDoubleTap: _toggleMax,
                  child: const SizedBox.expand(),
                ),
              ),
              _WinButton(
                tooltip: tr('Minimizar'),
                icon: Icons.remove_rounded,
                onTap: () => windowManager.minimize(),
              ),
              _WinButton(
                tooltip: _maximized ? tr('Restaurar') : tr('Maximizar'),
                icon: _maximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                iconSize: _maximized ? 13 : 15,
                onTap: _toggleMax,
              ),
              _WinButton(
                tooltip: tr('Cerrar'),
                icon: Icons.close_rounded,
                danger: true,
                onTap: () => windowManager.close(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.danger = false,
    this.iconSize = 16,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final double iconSize;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bg = _hover
        ? (widget.danger ? const Color(0xFFE81123) : p.searchFill)
        : Colors.transparent;
    final fg = _hover && widget.danger ? Colors.white : p.secondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Anim.fast,
          width: 46,
          height: AppTitleBar.height,
          color: bg,
          child: Icon(widget.icon, size: widget.iconSize, color: fg),
        ),
      ),
    );
  }
}
