import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'theme.dart';

/// Colores para las carpetas.
const folderColors = <int>[
  0xFF5C8DF6, // azul
  0xFF30A46C, // verde
  0xFFF5A524, // ámbar
  0xFFE76F51, // coral
  0xFFE5484D, // rojo
  0xFF8E4EC6, // morado
  0xFF12A594, // turquesa
  0xFF8D8D8D, // gris
];

/// Fila de filtros: Todas · Temporales · Calendario · carpetas · + carpeta.
class FilterChips extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.repo,
    required this.selected,
    required this.onSelect,
  });

  final NotesRepository repo;
  final String selected;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final folders = repo.folders;
    final temporales = repo.temporales.where((n) => !n.done).length;
    final vencidas = repo.temporales.where((n) => n.isOverdue()).length;

    final chips = <Widget>[
      _chip(context, 'todas', 'Todas', Icons.notes),
      _chip(context, 'temporales', 'Temporales', Icons.alarm,
          badge: temporales == 0 ? null : '$temporales',
          badgeColor: vencidas > 0 ? const Color(0xFFE5484D) : null),
      _chip(context, 'calendario', 'Calendario', Icons.calendar_month),
      for (final f in folders)
        _chip(context, f.id, f.name, Icons.folder,
            color: f.color == null ? null : Color(f.color!),
            badge: '${repo.countIn(f.id)}',
            onLongPress: () => editFolderDialog(context, repo, folder: f)),
      Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Bouncy(
          pressedScale: 0.9,
          child: ActionChip(
            avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('Carpeta'),
            onPressed: () async {
              final f = await editFolderDialog(context, repo);
              if (f != null) onSelect(f.id);
            },
          ),
        ),
      ),
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i]
            .animate(delay: (30 * i).ms)
            .fadeIn(duration: Anim.medium)
            .slideX(begin: 0.3, curve: Anim.curve),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String id,
    String label,
    IconData icon, {
    Color? color,
    String? badge,
    Color? badgeColor,
    VoidCallback? onLongPress,
  }) {
    final sel = id == selected;
    final accent = Palette.accent(context);
    final c = color ?? accent;
    return Bouncy(
      pressedScale: 0.92,
      child: GestureDetector(
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: AnimatedContainer(
          duration: Anim.medium,
          curve: Anim.curve,
          // Sin sombras: un tinte suave del color y borde fino al elegirlo.
          decoration: BoxDecoration(
            color: sel
                ? c.withValues(alpha: 0.16)
                : Palette.searchFill(context).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: sel ? c.withValues(alpha: 0.55) : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelect(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 16,
                        color: sel ? c : (color ?? Palette.secondary(context))),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: sel ? c : null)),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: badgeColor ??
                              (sel
                                  ? c.withValues(alpha: 0.22)
                                  : Palette.separator(context)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(badge,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: badgeColor != null
                                    ? Colors.white
                                    : (sel ? c : null))),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}

/// Crear o editar una carpeta (nombre + color). Devuelve la carpeta.
Future<Folder?> editFolderDialog(BuildContext context, NotesRepository repo,
    {Folder? folder}) async {
  final name = TextEditingController(text: folder?.name ?? '');
  var color = folder?.color ?? folderColors.first;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(folder == null ? 'Nueva carpeta' : 'Editar carpeta'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.pop(ctx, 'ok'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in folderColors)
                    GestureDetector(
                      onTap: () => setLocal(() => color = c),
                      child: AnimatedContainer(
                        duration: Anim.fast,
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == c
                                ? Theme.of(ctx).colorScheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: color == c
                            ? const Icon(Icons.check,
                                size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (folder != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'borrar'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Borrar carpeta'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'ok'),
              child: Text(folder == null ? 'Crear' : 'Guardar')),
        ],
      ),
    ),
  );

  final text = name.text.trim();
  name.dispose();
  if (result == 'borrar' && folder != null) {
    repo.deleteFolder(folder.id);
    return null;
  }
  if (result != 'ok' || text.isEmpty) return null;
  if (folder == null) return repo.createFolder(text, color: color);
  repo.renameFolder(folder.id, text, color: color);
  return folder;
}

/// Elegir carpeta. Devuelve '' para "sin carpeta", null si se cancela.
Future<String?> pickFolder(
    BuildContext context, NotesRepository repo, String? current) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Mover a carpeta',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('Sin carpeta'),
            trailing: current == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final f in repo.folders)
            ListTile(
              leading: Icon(Icons.folder,
                  color: f.color == null ? null : Color(f.color!)),
              title: Text(f.name),
              trailing: current == f.id ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, f.id),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Nueva carpeta…'),
            onTap: () async {
              final f = await editFolderDialog(ctx, repo);
              if (ctx.mounted) Navigator.pop(ctx, f?.id);
            },
          ),
        ],
      ),
    ),
  );
}
