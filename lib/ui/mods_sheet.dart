import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config.dart';
import '../data/mods.dart';
import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';
import 'toast.dart';
import 'update_dialog.dart' show openLink;

/// ⋯ → Mods: instalar, ver y quitar mods de la comunidad (`.ogmod`).
Future<void> showModsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      builder: (_) => const _ModsSheet(),
    );

class _ModsSheet extends StatefulWidget {
  const _ModsSheet();

  @override
  State<_ModsSheet> createState() => _ModsSheetState();
}

class _ModsSheetState extends State<_ModsSheet> {
  bool _busy = false;

  Future<void> _install() async {
    final file = await openFile(acceptedTypeGroups: [
      XTypeGroup(label: tr('Mod de Oganesson'), extensions: ['ogmod', 'zip']),
    ]);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final mod = await Mods.instance.install(await file.readAsBytes());
      if (mounted) {
        showToast(context, trf('Mod instalado: {0}', [mod.name]),
            icon: Icons.extension_rounded);
      }
    } on ModError catch (e) {
      if (mounted) {
        showToast(context, e.message, icon: Icons.error_outline_rounded);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, tr('No se pudo instalar el mod'),
            icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Mod m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trf('¿Quitar «{0}»?', [m.name])),
        content: Text(tr('Sus temas, plantillas, fuentes y acciones de IA '
            'dejarán de estar disponibles.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Quitar'))),
        ],
      ),
    );
    if (ok == true) await Mods.instance.remove(m.id);
  }

  static String _contents(Mod m) => [
        if (m.themes.isNotEmpty) trn(m.themes.length, '{0} tema', '{0} temas'),
        if (m.templates.isNotEmpty)
          trn(m.templates.length, '{0} plantilla', '{0} plantillas'),
        if (m.aiActions.isNotEmpty)
          trn(m.aiActions.length, '{0} acción de IA', '{0} acciones de IA'),
        if (m.fonts.isNotEmpty)
          trn(m.fonts.length, '{0} fuente', '{0} fuentes'),
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: Mods.instance,
      builder: (context, _) {
        final mods = Mods.instance.installed;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(children: [
              Icon(Icons.extension_rounded, color: p.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('Mods'),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _install,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_rounded),
                label: Text(tr('Instalar')),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                tr('Temas, plantillas, fuentes y acciones de IA creados por la '
                    'comunidad. Un mod es un archivo .ogmod; nunca lleva código.'),
                style: TextStyle(color: p.secondary, fontSize: 13)),
            const SizedBox(height: 16),
            if (mods.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: p.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  Icon(Icons.extension_off_outlined,
                      size: 40, color: p.secondary.withValues(alpha: 0.6)),
                  const SizedBox(height: 8),
                  Text(tr('Aún no tienes mods instalados.'),
                      style: TextStyle(color: p.secondary)),
                ]),
              ).animate().fadeIn(duration: Anim.medium)
            else
              for (final (i, m) in mods.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: p.background,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      leading: CircleAvatar(
                        backgroundColor: p.accent.withValues(alpha: 0.15),
                        child: Icon(Icons.extension_rounded, color: p.accent),
                      ),
                      title: Text('${m.name}  ·  v${m.version}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          [
                            if (m.author.isNotEmpty) trf('por {0}', [m.author]),
                            _contents(m),
                            if (m.description.isNotEmpty) m.description,
                          ].join('\n'),
                          style: TextStyle(color: p.secondary, fontSize: 12.5)),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: tr('Quitar'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _remove(m),
                      ),
                    ),
                  ),
                )
                    .animate(delay: (40 * i).ms)
                    .fadeIn(duration: Anim.medium)
                    .slideY(begin: 0.12, curve: Anim.curve),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => openLink(
                  context, '${AppConfig.githubUrl}/blob/main/docs/MODS.md'),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(tr('Cómo crear un mod')),
            ),
          ],
        );
      },
    );
  }
}
