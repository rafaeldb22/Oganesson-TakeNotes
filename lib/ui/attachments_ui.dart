import 'package:flutter/material.dart';

import '../data/note_attachments.dart';
import '../data/note_images.dart';
import '../data/notes_repository.dart';
import 'i18n.dart';
import 'note_image.dart';
import 'note_media.dart';
import 'toast.dart';

IconData mediaIcon(MediaItem m) => switch (m.kind) {
      MediaKind.image => Icons.image_outlined,
      MediaKind.audio => Icons.graphic_eq_rounded,
      MediaKind.file => m.file?.isPdf == true
          ? Icons.picture_as_pdf_outlined
          : Icons.insert_drive_file_outlined,
    };

/// Abre un adjunto directamente: imagen a pantalla completa, audio sonando,
/// PDF en el lector y el resto con su programa.
Future<void> openMediaItem(BuildContext context, MediaItem item) async {
  if (item.kind == MediaKind.image) {
    final bytes = await NoteImages.instance.load(item.path);
    if (!context.mounted) return;
    if (bytes == null) {
      showToast(context, tr('No se pudo abrir la imagen'),
          icon: Icons.error_outline_rounded);
      return;
    }
    await openImageViewer(context,
        image: MemoryImage(bytes),
        heroTag: 'adjunto-${item.path}',
        bytes: () async => bytes);
    return;
  }
  final file = item.file;
  if (file == null) return;
  if (item.kind == MediaKind.file) return openNoteFile(context, file);
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: NoteFileCard(file: file, autoplay: true),
    ),
  );
}

/// Elige un adjunto y lo conecta a la nota sin meterlo en su texto.
/// [kind]: `imagen`, `voz` o `archivo`.
Future<void> pickAndConnect(BuildContext context, NotesRepository repo,
    String noteId, String kind) async {
  switch (kind) {
    case 'imagen':
      for (final bytes in await pickImageBytes(context)) {
        final src = await NoteImages.instance.add(bytes);
        if (src != null) connectMedia(repo, noteId, {'image': src});
      }
    case 'voz':
      final f = await recordVoiceFile(context);
      if (f != null) connectMedia(repo, noteId, fileEmbed(f));
    case 'archivo':
      await pickNoteFiles(
          context, (f) => connectMedia(repo, noteId, fileEmbed(f)));
  }
}
