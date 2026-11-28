import 'package:flutter/material.dart';

import 'i18n.dart';
import 'theme.dart';

/// Lista de las teclas rápidas, por secciones.
Future<void> showShortcuts(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _ShortcutsDialog(),
    );

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  static List<(IconData, String, List<(String, List<String>)>)> get _groups => [
        (
          Icons.explore_outlined,
          tr('Moverse'),
          [
            (tr('Ir al inicio'), ['Ctrl', 'H']),
            (tr('Atrás'), ['Alt', '←']),
            (tr('Adelante'), ['Alt', '→']),
            (tr('Notas'), ['Ctrl', '1']),
            (tr('Calendario'), ['Ctrl', '2']),
            (tr('Red de notas'), ['Ctrl', '3']),
            (tr('Siguiente nota'), ['Ctrl', 'Tab']),
            (tr('Nota anterior'), ['Ctrl', 'Mayús', 'Tab']),
            (tr('Nota de arriba / de abajo'), ['Ctrl', '↑ ↓']),
            (tr('Buscar (en la nota si hay una abierta)'), ['Ctrl', 'F']),
            (tr('Paleta de comandos'), ['Ctrl', 'K']),
            (tr('Cerrar la nota'), ['Ctrl', 'W']),
            (tr('Ocultar o mostrar el panel'), ['Ctrl', 'Q']),
          ],
        ),
        (
          Icons.edit_note_rounded,
          tr('Crear'),
          [
            (tr('Nueva nota'), ['Ctrl', 'N']),
            (tr('Nota rápida desde cualquier sitio'), ['Ctrl', 'Alt', 'N']),
            (tr('Abrir Oganesson desde cualquier sitio'), ['Ctrl', 'Alt', 'O']),
            (tr('Asistente IA'), ['Ctrl', 'J']),
          ],
        ),
        (
          Icons.text_fields_rounded,
          tr('Texto'),
          [
            (tr('Negrita'), ['Ctrl', 'B']),
            (tr('Cursiva'), ['Ctrl', 'I']),
            (tr('Subrayado'), ['Ctrl', 'U']),
            (tr('Deshacer'), ['Ctrl', 'Z']),
            (tr('Rehacer'), ['Ctrl', 'Y']),
          ],
        ),
        (
          Icons.draw_outlined,
          tr('Pizarra'),
          [
            (tr('Copiar'), ['Ctrl', 'C']),
            (tr('Cortar'), ['Ctrl', 'X']),
            (tr('Pegar'), ['Ctrl', 'V']),
            (tr('Duplicar'), ['Ctrl', 'D']),
            (tr('Seleccionar todo'), ['Ctrl', 'A']),
            (tr('Eliminar'), ['Supr']),
            (tr('Zoom'), ['Ctrl', tr('Rueda')]),
          ],
        ),
        (
          Icons.tune_rounded,
          tr('App'),
          [
            (tr('Tema y colores'), ['Ctrl', ',']),
            (tr('Teclas rápidas'), ['Ctrl', '/']),
          ],
        ),
        (
          Icons.mouse_outlined,
          tr('Ratón'),
          [
            (tr('Atrás'), [tr('Botón lateral trasero')]),
            (tr('Adelante'), [tr('Botón lateral delantero')]),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: 760, maxHeight: size.height * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 10, 8),
              child: Row(
                children: [
                  Icon(Icons.keyboard_rounded, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr('Teclas rápidas'),
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: tr('Cerrar'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: LayoutBuilder(builder: (context, box) {
                  final two = box.maxWidth >= 640;
                  final width = two ? (box.maxWidth - 12) / 2 : box.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (icon, title, rows) in _groups)
                        SizedBox(
                          width: width,
                          child: _Group(icon: icon, title: title, rows: rows),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.icon, required this.title, required this.rows});
  final IconData icon;
  final String title;
  final List<(String, List<String>)> rows;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: p.accent),
              const SizedBox(width: 7),
              Text(title,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: p.accent)),
            ],
          ),
          const SizedBox(height: 6),
          for (final (label, keys) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 3,
                      runSpacing: 3,
                      children: [for (final k in keys) _KeyCap(k)],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          top: BorderSide(color: p.separator),
          left: BorderSide(color: p.separator),
          right: BorderSide(color: p.separator),
          bottom: BorderSide(color: p.separator, width: 2),
        ),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
