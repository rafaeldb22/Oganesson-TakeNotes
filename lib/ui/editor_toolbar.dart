import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'anim.dart';
import 'theme.dart';
import 'whiteboard.dart';
import 'i18n.dart';

/// Barra de formato propia: limpia, con estados activos claros y una paleta
/// de colores cuidada (sin selector de tamaño: se usan estilos de texto).
class EditorToolbar extends StatelessWidget {
  const EditorToolbar(
      {super.key,
      required this.controller,
      this.onLink,
      this.onImage,
      this.onVoice,
      this.onAttach,
      this.onDraw,
      this.onAi,
      this.onShare,
      this.readOnly = false});
  final QuillController controller;

  /// Nota de voz, adjuntar archivo y dibujar; null = sin botón.
  final VoidCallback? onVoice;
  final VoidCallback? onAttach;
  final VoidCallback? onDraw;

  /// Acciones con IA; null en las notas del Vault.
  final VoidCallback? onAi;

  /// Compartir con otra cuenta; null en las notas del Vault.
  final VoidCallback? onShare;

  /// Nota compartida de solo lectura: sin botones de formato.
  final bool readOnly;

  /// Enlazar otra nota (`[[…]]`); null = sin botón.
  final VoidCallback? onLink;

  /// Añadir imágenes (galería, cámara o archivo); null = sin botón.
  final VoidCallback? onImage;

  static const textColors = <(String, Color?)>[
    ('Por defecto', null),
    ('Gris', Color(0xFF8E8E93)),
    ('Rojo', Color(0xFFE5484D)),
    ('Naranja', Color(0xFFF76B15)),
    ('Ámbar', Color(0xFFD99A00)),
    ('Verde', Color(0xFF30A46C)),
    ('Azul', Color(0xFF3E7BFA)),
    ('Morado', Color(0xFF8E4EC6)),
  ];

  static const highlightColors = <(String, Color?)>[
    ('Sin resaltado', null),
    ('Amarillo', Color(0xFFFFE58F)),
    ('Verde', Color(0xFFB7EBC6)),
    ('Azul', Color(0xFFBFD7FF)),
    ('Rosa', Color(0xFFFFC9DE)),
    ('Lila', Color(0xFFDCCBFF)),
    ('Naranja', Color(0xFFFFD3B0)),
  ];

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Map<String, Attribute> get _attrs =>
      controller.getSelectionStyle().attributes;

  bool _has(Attribute a) => _attrs.containsKey(a.key);

  Object? _value(String key) => _attrs[key]?.value;

  void _toggle(Attribute a) {
    controller.formatSelection(_has(a) ? Attribute.clone(a, null) : a);
  }

  void _toggleBlock(String key, Attribute a) {
    final active = _value(key) == a.value;
    controller.formatSelection(active ? Attribute.clone(a, null) : a);
  }

  void _setHeader(int? level) {
    controller.formatSelection(level == 1
        ? Attribute.h1
        : (level == 2
            ? Attribute.h2
            : (level == 3 ? Attribute.h3 : Attribute.header)));
  }

  void _clear() {
    for (final a in [
      Attribute.bold,
      Attribute.italic,
      Attribute.underline,
      Attribute.strikeThrough,
    ]) {
      controller.formatSelection(Attribute.clone(a, null));
    }
    controller.formatSelection(const ColorAttribute(null));
    controller.formatSelection(const BackgroundAttribute(null));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final header = _value(Attribute.header.key) as int?;
        final list = _value(Attribute.list.key);
        final color = _value(Attribute.color.key) as String?;

        final groups = <List<Widget>>[
          [
            _Btn(
              icon: Icons.undo_rounded,
              tooltip: tr('Deshacer'),
              onTap: controller.hasUndo ? controller.undo : null,
            ),
            _Btn(
              icon: Icons.redo_rounded,
              tooltip: tr('Rehacer'),
              onTap: controller.hasRedo ? controller.redo : null,
            ),
          ],
          [
            _StyleMenu(current: header, onSelect: _setHeader),
          ],
          [
            _Btn(
                icon: Icons.format_bold_rounded,
                tooltip: tr('Negrita'),
                active: _has(Attribute.bold),
                onTap: () => _toggle(Attribute.bold)),
            _Btn(
                icon: Icons.format_italic_rounded,
                tooltip: tr('Cursiva'),
                active: _has(Attribute.italic),
                onTap: () => _toggle(Attribute.italic)),
            _Btn(
                icon: Icons.format_underline_rounded,
                tooltip: tr('Subrayado'),
                active: _has(Attribute.underline),
                onTap: () => _toggle(Attribute.underline)),
            _Btn(
                icon: Icons.format_strikethrough_rounded,
                tooltip: tr('Tachado'),
                active: _has(Attribute.strikeThrough),
                onTap: () => _toggle(Attribute.strikeThrough)),
          ],
          [
            _ColorButton(
              current: color,
              onText: (c) => controller
                  .formatSelection(ColorAttribute(c == null ? null : _hex(c))),
              onHighlight: (c) => controller.formatSelection(
                  BackgroundAttribute(c == null ? null : _hex(c))),
            ),
          ],
          [
            _Btn(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: tr('Lista'),
                active: list == 'bullet',
                onTap: () => _toggleBlock(Attribute.list.key, Attribute.ul)),
            _Btn(
                icon: Icons.format_list_numbered_rounded,
                tooltip: tr('Lista numerada'),
                active: list == 'ordered',
                onTap: () => _toggleBlock(Attribute.list.key, Attribute.ol)),
            _Btn(
                icon: Icons.checklist_rounded,
                tooltip: tr('Casillas'),
                active: list == 'unchecked' || list == 'checked',
                onTap: () =>
                    _toggleBlock(Attribute.list.key, Attribute.unchecked)),
          ],
          [
            _Btn(
                icon: Icons.format_quote_rounded,
                tooltip: tr('Cita'),
                active: _has(Attribute.blockQuote),
                onTap: () => _toggle(Attribute.blockQuote)),
            _Btn(
                icon: Icons.code_rounded,
                tooltip: tr('Código'),
                active: _has(Attribute.codeBlock),
                onTap: () => _toggle(Attribute.codeBlock)),
            _Btn(
                icon: Icons.format_clear_rounded,
                tooltip: tr('Quitar formato'),
                onTap: _clear),
          ],
        ];
        if (readOnly) groups.clear();

        // Insertar: siempre a mano en PC, fijo a la derecha.
        final insert = <Widget>[
          if (onImage != null)
            _Btn(
                icon: Icons.add_photo_alternate_outlined,
                tooltip: tr('Añadir imagen  (o pega con Ctrl+V)'),
                onTap: onImage),
          if (onAttach != null)
            _Btn(
                icon: Icons.attach_file_rounded,
                tooltip: tr('Adjuntar archivo'),
                onTap: onAttach),
          if (onVoice != null)
            _Btn(
                icon: Icons.mic_none_rounded,
                tooltip: tr('Nota de voz'),
                onTap: onVoice),
          if (onDraw != null)
            _Btn(
                icon: Icons.draw_outlined,
                tooltip: tr('Dibujar'),
                onTap: onDraw),
          if (onLink != null)
            _Btn(
                icon: Icons.link_rounded,
                tooltip: tr('Enlazar nota'),
                onTap: onLink),
        ];

        return LayoutBuilder(builder: (context, c) {
          final pinned = c.maxWidth >= 760 && insert.isNotEmpty;
          final all = [
            ...groups,
            if (!pinned && insert.isNotEmpty) insert,
          ];
          final p = Palette.of(context);
          return Container(
            height: 50,
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            decoration: BoxDecoration(
              color: p.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.separator.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ToolbarScroller(
                    children: [
                      for (var g = 0; g < all.length; g++) ...[
                        if (g > 0) const _GroupGap(),
                        ...all[g],
                      ],
                    ],
                  ),
                ),
                if (pinned) ...[
                  const _GroupGap(),
                  ...insert,
                ],
                // La IA siempre a la vista, también en el móvil.
                if (onShare != null)
                  _Btn(
                      icon: Icons.group_add_outlined,
                      tooltip: tr('Compartir'),
                      onTap: onShare),
                if (onAi != null) _AiButton(onTap: onAi!),
                const SizedBox(width: 7),
              ],
            ),
          );
        });
      },
    );
  }
}

/// Barra del modo pizarra: deshacer, herramientas con sus colores y tamaños a
/// mano, y acciones. Pulsar la herramienta activa abre todas sus opciones.
class BoardToolbar extends StatelessWidget {
  const BoardToolbar(
      {super.key,
      required this.controller,
      this.readOnly = false,
      this.onShare,
      this.onAi,
      this.onReadText});
  final BoardController controller;
  final bool readOnly;
  final VoidCallback? onShare;
  final VoidCallback? onAi;

  /// Pasar lo escrito a mano a texto con la IA; null = sin botón.
  final VoidCallback? onReadText;

  void _pick(BuildContext button, BoardTool tool) {
    if (controller.tool != tool) {
      controller.tool = tool;
      return;
    }
    if (tool == BoardTool.lasso) return;
    final box = button.findRenderObject() as RenderBox;
    showBoardToolPanel(button, controller,
        box.localToGlobal(box.size.bottomCenter(Offset.zero)));
  }

  List<Widget> _quick(BuildContext context) {
    final c = controller;
    final ink = Theme.of(context).colorScheme.onSurface;
    final tool = c.tool;
    if (tool == BoardTool.lasso) return const [];
    final colors = switch (tool) {
      BoardTool.pen => const [
          0,
          0xFFE5484D,
          0xFF3E8BFF,
          0xFF30A46C,
          0xFFF5A524
        ],
      BoardTool.marker => boardMarkers.take(5).toList(),
      _ => const <int>[],
    };
    final current = tool == BoardTool.marker ? c.markerColor : c.color;
    final sizes = switch (tool) {
      BoardTool.pen => const [2.0, 4.0, 8.0],
      BoardTool.marker => const [12.0, 20.0, 32.0],
      _ => const [12.0, 24.0, 48.0],
    };
    final width = switch (tool) {
      BoardTool.pen => c.penWidth,
      BoardTool.marker => c.markerWidth,
      _ => c.eraserWidth,
    };
    void setSize(double v) => switch (tool) {
          BoardTool.pen => c.setPen(width: v),
          BoardTool.marker => c.setMarker(width: v),
          _ => c.setEraser(width: v),
        };
    return [
      if (colors.isNotEmpty) ...[
        const _GroupGap(),
        for (final v in colors)
          _Swatch(
            color: v == 0 ? ink : Color(v).withValues(alpha: 1),
            active: v == current,
            onTap: () => tool == BoardTool.marker
                ? c.setMarker(color: v)
                : c.setPen(color: v),
          ),
      ],
      const _GroupGap(),
      for (final (i, v) in sizes.indexed)
        _SizeDot(
          dot: 5.0 + i * 4,
          label: trf('Grosor {0}', [v.round()]),
          active: (width - v).abs() < 0.5,
          onTap: () => setSize(v),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final ink = Theme.of(context).colorScheme.onSurface;
        return Container(
          height: 50,
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.separator.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              if (!readOnly) ...[
                _Btn(
                    icon: Icons.undo_rounded,
                    tooltip: tr('Deshacer'),
                    onTap: c.canUndo ? c.undo : null),
                _Btn(
                    icon: Icons.redo_rounded,
                    tooltip: tr('Rehacer'),
                    onTap: c.canRedo ? c.redo : null),
              ],
              Expanded(
                child: Center(
                  child: _ToolbarScroller(
                    shrink: true,
                    children: [
                      if (!readOnly) ...[
                        _BoardTile(
                          tooltip: tr('Selector'),
                          active: c.tool == BoardTool.lasso,
                          onTap: (b) => _pick(b, BoardTool.lasso),
                          builder: (color) => Icon(Icons.highlight_alt_rounded,
                              size: 22, color: color),
                        ),
                        const _GroupGap(),
                        _BoardTile(
                          tooltip: tr('Boli'),
                          active: c.tool == BoardTool.pen,
                          onTap: (b) => _pick(b, BoardTool.pen),
                          builder: (color) => Icon(Icons.edit_rounded,
                              size: 21,
                              color: c.tool == BoardTool.pen
                                  ? (c.color == 0 ? ink : Color(c.color))
                                  : color),
                        ),
                        _BoardTile(
                          tooltip: tr('Marcador'),
                          active: c.tool == BoardTool.marker,
                          onTap: (b) => _pick(b, BoardTool.marker),
                          builder: (color) => Icon(Icons.border_color_rounded,
                              size: 20,
                              color: c.tool == BoardTool.marker
                                  ? Color(c.markerColor).withValues(alpha: 1)
                                  : color),
                        ),
                        _BoardTile(
                          tooltip: tr('Goma'),
                          active: c.tool == BoardTool.eraser,
                          onTap: (b) => _pick(b, BoardTool.eraser),
                          builder: (color) => EraserIcon(color: color),
                        ),
                        ..._quick(context),
                        const _GroupGap(),
                        _Btn(
                            icon: Icons.add_photo_alternate_outlined,
                            tooltip: tr('Insertar imagen'),
                            onTap: () => c.insertImage?.call()),
                      ],
                      _Btn(
                          icon: Icons.fit_screen_rounded,
                          tooltip: tr('Ver todo'),
                          onTap: () => c.fitView?.call()),
                      if (onReadText != null)
                        _Btn(
                            icon: Icons.document_scanner_outlined,
                            tooltip: tr('Pasar a texto con IA'),
                            onTap: c.isEmpty ? null : onReadText),
                    ],
                  ),
                ),
              ),
              if (onShare != null)
                _Btn(
                    icon: Icons.group_add_outlined,
                    tooltip: tr('Compartir'),
                    onTap: onShare),
              if (onAi != null) _AiButton(onTap: onAi!),
              const SizedBox(width: 7),
            ],
          ),
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.color, required this.active, required this.onTap});
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: tr('Color'),
      child: Bouncy(
        pressedScale: 0.85,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 40,
            child: Center(
              child: AnimatedContainer(
                duration: Anim.fast,
                curve: Anim.curve,
                width: active ? 23 : 19,
                height: active ? 23 : 19,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: active ? p.accent : p.separator,
                      width: active ? 2.5 : 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeDot extends StatelessWidget {
  const _SizeDot({
    required this.dot,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final double dot;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 500),
      child: Bouncy(
        pressedScale: 0.85,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: Anim.fast,
            width: 30,
            height: 32,
            margin: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? fg.withValues(alpha: 0.13) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: active ? fg : p.secondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardTile extends StatefulWidget {
  const _BoardTile({
    required this.tooltip,
    required this.active,
    required this.onTap,
    required this.builder,
  });
  final String tooltip;
  final bool active;
  final void Function(BuildContext button) onTap;
  final Widget Function(Color color) builder;

  @override
  State<_BoardTile> createState() => _BoardTileState();
}

class _BoardTileState extends State<_BoardTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = Theme.of(context).colorScheme.onSurface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: Semantics(
          button: true,
          selected: widget.active,
          label: widget.tooltip,
          child: Bouncy(
            pressedScale: 0.88,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onTap(context),
              child: AnimatedContainer(
                duration: Anim.fast,
                curve: Anim.curve,
                width: 42,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.active
                      ? fg.withValues(alpha: 0.13)
                      : (_hover ? p.hover : Colors.transparent),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: AnimatedScale(
                  scale: widget.active ? 1.08 : 1,
                  duration: Anim.medium,
                  curve: Curves.easeOutBack,
                  child: widget.builder(fg),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Separador corto y redondeado entre grupos de botones.
class _GroupGap extends StatelessWidget {
  const _GroupGap();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 1.5,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Palette.separator(context),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      );
}

/// Botón de la IA: destaca del resto y su destello gira al pasar el ratón.
class _AiButton extends StatefulWidget {
  const _AiButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AiButton> createState() => _AiButtonState();
}

class _AiButtonState extends State<_AiButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: tr('Acciones con IA'),
        waitDuration: const Duration(milliseconds: 500),
        child: Bouncy(
          pressedScale: 0.9,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Anim.medium,
              curve: Anim.curve,
              height: 36,
              margin: const EdgeInsets.only(left: 4, top: 6, bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  accent.withValues(alpha: _hover ? 0.30 : 0.18),
                  accent.withValues(alpha: _hover ? 0.16 : 0.08),
                ]),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: accent.withValues(alpha: _hover ? 0.5 : 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: _hover ? 0.125 : 0,
                    duration: Anim.medium,
                    curve: Curves.easeOutBack,
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 17, color: accent),
                  ),
                  const SizedBox(width: 5),
                  Text(tr('IA'),
                      style: TextStyle(
                          color: accent,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila horizontal desplazable de la barra. En escritorio la rueda del ratón
/// (vertical) la mueve en horizontal y también se puede arrastrar con el
/// ratón; un degradado en el borde avisa de que quedan botones ocultos.
class _ToolbarScroller extends StatefulWidget {
  const _ToolbarScroller({required this.children, this.shrink = false});
  final List<Widget> children;

  /// Ocupa solo lo que necesita (para centrarse si hay sitio de sobra).
  final bool shrink;

  @override
  State<_ToolbarScroller> createState() => _ToolbarScrollerState();
}

class _ToolbarScrollerState extends State<_ToolbarScroller> {
  static const _fade = 28.0;
  final _ctrl = ScrollController();
  bool _atStart = true;
  bool _atEnd = true;
  double? _wheelTarget;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_update);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _update() {
    if (!_ctrl.hasClients) return;
    final p = _ctrl.position;
    final start = p.pixels <= p.minScrollExtent + 0.5;
    final end = p.pixels >= p.maxScrollExtent - 0.5;
    if (start != _atStart || end != _atEnd) {
      setState(() {
        _atStart = start;
        _atEnd = end;
      });
    }
  }

  void _onSignal(PointerSignalEvent event) {
    // Solo la rueda vertical: el desplazamiento horizontal (trackpad,
    // Mayús+rueda) ya lo gestiona el propio ListView.
    if (event is! PointerScrollEvent || event.scrollDelta.dx != 0) return;
    if (!_ctrl.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final p = _ctrl.position;
      final target = ((_wheelTarget ?? p.pixels) +
              (e as PointerScrollEvent).scrollDelta.dy)
          .clamp(p.minScrollExtent, p.maxScrollExtent);
      if (target == p.pixels) return;
      _wheelTarget = target;
      _ctrl
          .animateTo(target,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic)
          .whenComplete(() {
        if (_wheelTarget == target) _wheelTarget = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context)
        .copyWith(dragDevices: PointerDeviceKind.values.toSet());
    return NotificationListener<ScrollMetricsNotification>(
      // Cambia el ancho disponible (p. ej. al redimensionar la ventana).
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _update();
        });
        return false;
      },
      child: Listener(
        onPointerSignal: _onSignal,
        child: ShaderMask(
          // Máscara de opacidad (no es un color visible): blanco = se ve,
          // transparente = se desvanece en el borde con botones ocultos.
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final f =
                bounds.width > 0 ? (_fade / bounds.width).clamp(0.0, 0.5) : 0.0;
            return LinearGradient(
              colors: [
                _atStart ? Colors.white : Colors.transparent,
                Colors.white,
                Colors.white,
                _atEnd ? Colors.white : Colors.transparent,
              ],
              stops: [0, f, 1 - f, 1],
            ).createShader(bounds);
          },
          child: ScrollConfiguration(
            behavior: behavior,
            child: ListView(
              controller: _ctrl,
              shrinkWrap: widget.shrink,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: widget.children,
            ),
          ),
        ),
      ),
    );
  }
}

class _Btn extends StatefulWidget {
  const _Btn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final accent = p.accent;
    final enabled = widget.onTap != null;
    final active = widget.active;
    final fg = active
        ? accent
        : (enabled
            ? Theme.of(context).colorScheme.onSurface
            : p.secondary.withValues(alpha: 0.35));
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: Bouncy(
          pressedScale: 0.85,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Anim.fast,
              curve: Anim.curve,
              width: 36,
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.16)
                    : (_hover && enabled ? p.hover : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: active
                        ? accent.withValues(alpha: 0.3)
                        : Colors.transparent),
              ),
              child: AnimatedScale(
                scale: active ? 1.08 : (_hover && enabled ? 1.06 : 1),
                duration: Anim.medium,
                curve: Curves.easeOutBack,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: fg),
                  duration: Anim.fast,
                  builder: (_, color, __) =>
                      Icon(widget.icon, size: 20, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Menú de estilos de párrafo con vista previa de cada uno.
class _StyleMenu extends StatelessWidget {
  const _StyleMenu({required this.current, required this.onSelect});
  final int? current;
  final void Function(int?) onSelect;

  static const _names = {
    null: 'Texto',
    1: 'Título',
    2: 'Subtítulo',
    3: 'Encabezado'
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: tr('Estilo de texto'),
      position: PopupMenuPosition.under,
      onSelected: (v) => onSelect(v == 0 ? null : v),
      itemBuilder: (_) => [
        _item(context, 1, tr('Título'), 22, FontWeight.w800),
        _item(context, 2, tr('Subtítulo'), 18, FontWeight.w700),
        _item(context, 3, tr('Encabezado'), 15.5, FontWeight.w700),
        _item(context, 0, tr('Texto'), 15, FontWeight.w400),
      ],
      child: Container(
        height: 34,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: Anim.fast,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                      .animate(a),
                  child: c,
                ),
              ),
              child: Text(tr(_names[current] ?? 'Texto'),
                  key: ValueKey(current),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<int> _item(BuildContext context, int value, String label,
      double size, FontWeight weight) {
    final sel = (current ?? 0) == value;
    return PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: sel
                ? Icon(Icons.check_rounded,
                    size: 18, color: Palette.accent(context))
                : null,
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: size, fontWeight: weight)),
        ],
      ),
    );
  }
}

/// Botón "A" que abre una paleta de color de texto y de resaltado.
class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.current,
    required this.onText,
    required this.onHighlight,
  });

  final String? current;
  final void Function(Color?) onText;
  final void Function(Color?) onHighlight;

  Color? get _currentColor {
    final c = current;
    if (c == null || !c.startsWith('#') || c.length < 7) return null;
    final v = int.tryParse(c.substring(1, 7), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final underline = _currentColor ?? Palette.secondary(context);
    return Tooltip(
      message: tr('Color'),
      waitDuration: const Duration(milliseconds: 500),
      child: Bouncy(
        pressedScale: 0.85,
        child: GestureDetector(
          onTap: () => _open(context),
          child: Container(
            width: 38,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(tr('A'),
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                AnimatedContainer(
                  duration: Anim.medium,
                  curve: Anim.curve,
                  width: 18,
                  height: 3.5,
                  decoration: BoxDecoration(
                    color: underline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final pos =
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('Cerrar'),
      barrierColor: Colors.transparent,
      transitionDuration: Anim.medium,
      transitionBuilder: (_, a, __, child) {
        final curved = CurvedAnimation(
            parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
        return FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: ScaleTransition(
            alignment: Alignment((pos.dx / overlay.size.width) * 2 - 1,
                (pos.dy / overlay.size.height) * 2 - 1),
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) {
        final maxX = overlay.size.width - 300;
        return Stack(
          children: [
            Positioned(
              left: pos.dx.clamp(8.0, maxX < 8 ? 8.0 : maxX),
              top: pos.dy + 4,
              child: Material(
                color: Palette.card(ctx),
                elevation: 10,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 292,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(ctx, tr('Color del texto')),
                      _swatches(ctx, EditorToolbar.textColors, (c) {
                        onText(c);
                        Navigator.pop(ctx);
                      }, textStyle: true),
                      const SizedBox(height: 12),
                      _label(ctx, tr('Resaltado')),
                      _swatches(ctx, EditorToolbar.highlightColors, (c) {
                        onHighlight(c);
                        Navigator.pop(ctx);
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _label(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: Palette.secondary(context))),
      );

  Widget _swatches(BuildContext context, List<(String, Color?)> colors,
      void Function(Color?) onPick,
      {bool textStyle = false}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (name, c) in colors)
          Tooltip(
            message: tr(name),
            child: Bouncy(
              pressedScale: 0.85,
              hoverScale: 1.1,
              child: GestureDetector(
                onTap: () => onPick(c),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: textStyle ? Palette.background(context) : c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.separator(context)),
                  ),
                  child: c == null
                      ? Icon(Icons.block,
                          size: 15, color: Palette.secondary(context))
                      : (textStyle
                          ? Text(tr('A'),
                              style: TextStyle(
                                  color: c,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800))
                          : null),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
