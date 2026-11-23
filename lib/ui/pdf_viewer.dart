import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';

/// Lector de PDF a pantalla completa: páginas seguidas, zoom con la rueda
/// (Ctrl), los dedos o los botones. [onExternal] lo abre con otra aplicación.
Future<void> openPdfViewer(BuildContext context, String path, String name,
        {VoidCallback? onExternal}) =>
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
      transitionDuration: Anim.medium,
      reverseTransitionDuration: Anim.fast,
      pageBuilder: (_, __, ___) =>
          _PdfScreen(path: path, name: name, onExternal: onExternal),
      transitionsBuilder: (_, a, __, c) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Anim.curve),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Anim.curve)),
          child: c,
        ),
      ),
    ));

class _PdfScreen extends StatefulWidget {
  const _PdfScreen({required this.path, required this.name, this.onExternal});
  final String path;
  final String name;
  final VoidCallback? onExternal;

  @override
  State<_PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<_PdfScreen> {
  final _ctrl = PdfViewerController();
  int? _page;
  int _pages = 0;

  void _go(int delta) {
    final page = _page;
    if (page == null || _pages == 0) return;
    _ctrl.goToPage(pageNumber: (page + delta).clamp(1, _pages));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ready = _pages > 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _go(-1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: p.background,
          appBar: AppBar(
            backgroundColor: p.card,
            leading: IconButton(
              tooltip: tr('Cerrar'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.maybePop(context),
            ),
            titleSpacing: 0,
            title: Text(widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            actions: [
              if (ready) ...[
                IconButton(
                  tooltip: tr('Página anterior'),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  onPressed: (_page ?? 1) > 1 ? () => _go(-1) : null,
                ),
                Text('${_page ?? 1} / $_pages',
                    style: TextStyle(
                        color: p.secondary,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                IconButton(
                  tooltip: tr('Página siguiente'),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: (_page ?? 1) < _pages ? () => _go(1) : null,
                ),
                IconButton(
                  tooltip: tr('Alejar'),
                  icon: const Icon(Icons.zoom_out_rounded),
                  onPressed: () => _ctrl.zoomDown(),
                ),
                IconButton(
                  tooltip: tr('Acercar'),
                  icon: const Icon(Icons.zoom_in_rounded),
                  onPressed: () => _ctrl.zoomUp(),
                ),
              ],
              if (widget.onExternal != null)
                IconButton(
                  tooltip: tr('Abrir con otra aplicación'),
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: widget.onExternal,
                ),
              const SizedBox(width: 6),
            ],
          ),
          body: PdfViewer.file(
            widget.path,
            controller: _ctrl,
            params: PdfViewerParams(
              backgroundColor: p.background,
              onViewerReady: (doc, c) {
                if (!mounted) return;
                setState(() {
                  _pages = doc.pages.length;
                  _page = c.pageNumber ?? 1;
                });
              },
              onPageChanged: (n) {
                if (mounted && n != null) setState(() => _page = n);
              },
              loadingBannerBuilder: (_, __, ___) => const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              errorBannerBuilder: (context, _, __, ___) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('No se pudo abrir el PDF'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.secondary)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
