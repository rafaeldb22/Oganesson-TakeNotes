import 'package:flutter/material.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'text_menu.dart';
import 'i18n.dart';

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

/// Crear o editar una carpeta (nombre + color). Devuelve la carpeta.
Future<Folder?> editFolderDialog(BuildContext context, NotesRepository repo,
    {Folder? folder}) async {
  final name = TextEditingController(text: folder?.name ?? '');
  var color = folder?.color ?? folderColors.first;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title:
            Text(folder == null ? tr('Nueva carpeta') : tr('Editar carpeta')),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                contextMenuBuilder: textFieldMenu,
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Nombre'),
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
              child: Text(tr('Borrar carpeta')),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'ok'),
              child: Text(folder == null ? tr('Crear') : tr('Guardar'))),
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
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('Mover a carpeta'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: Text(tr('Sin carpeta')),
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
            title: Text(tr('Nueva carpeta…')),
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
