import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'anim.dart';
import 'theme.dart';

/// Barra de formato propia: limpia, con estados activos claros y una paleta
/// de colores cuidada (sin selector de tamaño: se usan estilos de texto).
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.controller});
  final QuillController controller;

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

  Map<String, Attribute> get _attrs => controller.getSelectionStyle().attributes;

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
              tooltip: 'Deshacer',
              onTap: controller.hasUndo ? controller.undo : null,
            ),
            _Btn(
              icon: Icons.redo_rounded,
              tooltip: 'Rehacer',
              onTap: controller.hasRedo ? controller.redo : null,
            ),
          ],
          [
            _StyleMenu(current: header, onSelect: _setHeader),
          ],
          [
            _Btn(
                icon: Icons.format_bold_rounded,
                tooltip: 'Negrita',
                active: _has(Attribute.bold),
                onTap: () => _toggle(Attribute.bold)),
            _Btn(
                icon: Icons.format_italic_rounded,
                tooltip: 'Cursiva',
                active: _has(Attribute.italic),
                onTap: () => _toggle(Attribute.italic)),
            _Btn(
                icon: Icons.format_underline_rounded,
                tooltip: 'Subrayado',
                active: _has(Attribute.underline),
                onTap: () => _toggle(Attribute.underline)),
            _Btn(
                icon: Icons.format_strikethrough_rounded,
                tooltip: 'Tachado',
                active: _has(Attribute.strikeThrough),
                onTap: () => _toggle(Attribute.strikeThrough)),
          ],
          [
            _ColorButton(
              current: color,
              onText: (c) => controller.formatSelection(
                  ColorAttribute(c == null ? null : _hex(c))),
              onHighlight: (c) => controller.formatSelection(
                  BackgroundAttribute(c == null ? null : _hex(c))),
            ),
          ],
          [
            _Btn(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: 'Lista',
                active: list == 'bullet',
                onTap: () => _toggleBlock(Attribute.list.key, Attribute.ul)),
            _Btn(
                icon: Icons.format_list_numbered_rounded,
                tooltip: 'Lista numerada',
                active: list == 'ordered',
                onTap: () => _toggleBlock(Attribute.list.key, Attribute.ol)),
            _Btn(
                icon: Icons.checklist_rounded,
                tooltip: 'Casillas',
                active: list == 'unchecked' || list == 'checked',
                onTap: () =>
                    _toggleBlock(Attribute.list.key, Attribute.unchecked)),
          ],
          [
            _Btn(
                icon: Icons.format_quote_rounded,
                tooltip: 'Cita',
                active: _has(Attribute.blockQuote),
                onTap: () => _toggle(Attribute.blockQuote)),
            _Btn(
                icon: Icons.code_rounded,
                tooltip: 'Código',
                active: _has(Attribute.codeBlock),
                onTap: () => _toggle(Attribute.codeBlock)),
            _Btn(
                icon: Icons.format_clear_rounded,
                tooltip: 'Quitar formato',
                onTap: _clear),
          ],
        ];

        return Container(
          height: 46,
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          decoration: BoxDecoration(
            color: Palette.background(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              for (var g = 0; g < groups.length; g++) ...[
                if (g > 0)
                  Center(
                    child: Container(
                      width: 1,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: Palette.separator(context),
                    ),
                  ),
                ...groups[g],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Btn extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Bouncy(
        pressedScale: 0.85,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Anim.fast,
            width: 36,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 20,
              color: active
                  ? accent
                  : (enabled
                      ? null
                      : Palette.secondary(context).withValues(alpha: 0.4)),
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

  static const _names = {null: 'Texto', 1: 'Título', 2: 'Subtítulo', 3: 'Encabezado'};

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Estilo de texto',
      position: PopupMenuPosition.under,
      onSelected: (v) => onSelect(v == 0 ? null : v),
      itemBuilder: (_) => [
        _item(context, 1, 'Título', 22, FontWeight.w800),
        _item(context, 2, 'Subtítulo', 18, FontWeight.w700),
        _item(context, 3, 'Encabezado', 15.5, FontWeight.w700),
        _item(context, 0, 'Texto', 15, FontWeight.w400),
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
            Text(_names[current] ?? 'Texto',
                style: const TextStyle(fontWeight: FontWeight.w600)),
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
      message: 'Color',
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
                const Text('A',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Container(
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
    final pos = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
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
                      _label(ctx, 'Color del texto'),
                      _swatches(ctx, EditorToolbar.textColors, (c) {
                        onText(c);
                        Navigator.pop(ctx);
                      }, textStyle: true),
                      const SizedBox(height: 12),
                      _label(ctx, 'Resaltado'),
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
            message: name,
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
                          ? Text('A',
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
