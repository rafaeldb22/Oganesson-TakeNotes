import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/note_attachments.dart';
import '../data/note_images.dart';
import '../data/note_links.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'attachments_ui.dart';
import 'context_menu.dart';
import 'link_picker.dart';
import 'theme.dart';
import 'i18n.dart';

/// Red de notas (como la vista de grafo de Obsidian): cada nota es un nodo
/// y cada enlace `[[…]]` una línea. Simulación de fuerzas sencilla:
/// repulsión entre nodos, muelles en los enlaces y gravedad hacia el centro.
///
/// Rueda / pellizco: zoom. Arrastrar el fondo: mover. Arrastrar un nodo:
/// recolocarlo. Tocar un nodo: abrir la nota. Pasar el ratón: resaltar la
/// nota y sus vecinas.
class GraphView extends StatefulWidget {
  const GraphView({super.key, required this.repo, required this.onOpenNote});

  final NotesRepository repo;
  final void Function(String id) onOpenNote;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _Node {
  _Node(this.id, this.pos);
  final String id;
  Offset pos;
  Offset vel = Offset.zero;
  bool pinned = false;
}

/// Una bola de archivo conectada a una nota.
class _GraphMedia {
  const _GraphMedia(this.noteId, this.item);
  final String noteId;
  final MediaItem item;
}

class _GraphViewState extends State<GraphView> with TickerProviderStateMixin {
  late final Ticker _ticker;
  final _nodes = <String, _Node>{};

  /// Bolas de archivo (id de nodo → adjunto) y las de cada nota.
  final _media = <String, _GraphMedia>{};
  final _mediaOfNote = <String, Set<String>>{};

  /// Miniaturas ya decodificadas, por ruta.
  final _thumbs = <String, ui.Image>{};
  final _thumbsLoading = <String>{};
  static const _mediaRadius = 17.0;

  Set<String> _links(String id) {
    final m = _media[id];
    if (m != null) return {m.noteId};
    final own = _mediaOfNote[id];
    final notes = _graph!.neighbors(id);
    return own == null ? notes : {...notes, ...own};
  }

  Future<void> _loadThumb(String path) async {
    if (_thumbs.containsKey(path) || !_thumbsLoading.add(path)) return;
    try {
      final bytes = await NoteImages.instance.load(path);
      if (bytes == null) return;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 120);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) return image.dispose();
      setState(() => _thumbs[path] = image);
    } catch (_) {
      // Sin miniatura se ve el icono de imagen.
    } finally {
      _thumbsLoading.remove(path);
    }
  }

  /// Clic izquierdo: abre directamente la nota o el archivo.
  void _openAt(Offset local) {
    final id = _hit(local);
    if (id == null) return;
    final media = _media[id];
    if (media != null) {
      openMediaItem(context, media.item);
    } else {
      widget.onOpenNote(id);
    }
  }

  /// Clic derecho o pulsación larga sobre una bola.
  Future<void> _nodeMenu(Offset local, Offset global) async {
    final id = _hit(local);
    if (id == null) return;
    final media = _media[id];
    if (media != null) {
      final owner = widget.repo.byId(media.noteId);
      final canEdit = owner != null && widget.repo.canEdit(owner);
      final choice = await showContextMenu(context,
          position: global,
          title: media.item.name,
          entries: [
            MenuEntry('abrir', Icons.open_in_full_rounded, tr('Abrir')),
            if (canEdit)
              MenuEntry(
                  'quitar', Icons.link_off_rounded, tr('Quitar de la red'),
                  subtitle:
                      media.item.linked ? null : tr('Sigue dentro de la nota'),
                  danger: true),
          ]);
      if (!mounted) return;
      if (choice == 'abrir') await openMediaItem(context, media.item);
      if (choice == 'quitar') {
        if (media.item.linked) {
          removeLinkedMedia(widget.repo, media.noteId, media.item.path);
        } else {
          disconnectMedia(widget.repo, media.noteId, media.item.path);
        }
      }
      return;
    }
    final note = widget.repo.byId(id);
    if (note == null) return;
    final foreign = widget.repo.isForeign(note);
    // Los adjuntos conectados son de quien creó la nota.
    final canAttach = !foreign;
    final choice = await showContextMenu(context,
        position: global,
        title: note.title,
        entries: [
          MenuEntry('abrir', Icons.open_in_new_rounded, tr('Abrir nota')),
          if (!foreign)
            MenuEntry(
                'enlazar', Icons.hub_outlined, tr('Conectar con otras notas…')),
          if (!foreign && _graph!.neighbors(id).isNotEmpty)
            MenuEntry('desconectar', Icons.link_off_rounded,
                tr('Desconectar notas…')),
          if (canAttach) ...[
            MenuEntry.section(tr('Conectar con archivos')),
            MenuEntry('imagen', Icons.image_outlined, tr('Imagen')),
            MenuEntry('voz', Icons.mic_none_rounded, tr('Mensaje de voz')),
            MenuEntry(
                'archivo', Icons.insert_drive_file_outlined, tr('Archivo')),
          ],
        ]);
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'abrir':
        widget.onOpenNote(id);
      case 'enlazar':
        await showLinkNotesPicker(context, widget.repo, id);
      case 'desconectar':
        await _disconnect(id);
      default:
        await pickAndConnect(context, widget.repo, id, choice);
    }
  }

  /// Quitar varias conexiones de una nota con una sola confirmación.
  Future<void> _disconnect(String id) async {
    final others = [
      for (final o in _graph!.neighbors(id))
        if (widget.repo.byId(o) case final n?) n
    ];
    final off = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          icon: const Icon(Icons.link_off_rounded),
          title: Text(tr('Desconectar notas')),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: 380,
            child: ListView(shrinkWrap: true, children: [
              for (final n in others)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: off.contains(n.id),
                  title: Text(n.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onChanged: (v) =>
                      set(() => v == true ? off.add(n.id) : off.remove(n.id)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Cancelar'))),
            FilledButton(
                onPressed: off.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(trf('Desconectar {0}', [off.length]))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    for (final o in off) {
      widget.repo.removeLink(id, o);
    }
    _reheat(0.4);
  }

  final _rnd = math.Random(7);
  NoteGraph? _graph;
  int _graphVersion = -1;
  bool _showOrphans = true;

  // Vista: posición del mundo en pantalla = pos * _scale + _offset.
  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;
  bool _centered = false;

  /// Reencuadra en cada paso mientras la red se coloca, hasta que el
  /// usuario la mueva o haga zoom (entonces manda él).
  bool _autoFit = true;

  // Interacción.
  String? _hover;

  /// Nodo resaltado que se está dibujando (se mantiene mientras se
  /// desvanece) y animación del resaltado.
  String? _shownHover;
  late final AnimationController _hoverCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  )
    ..addListener(() => setState(() {}))
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed && _hover == null) {
        _shownHover = null;
      }
    });

  void _setHover(String? h) {
    setState(() => _hover = h);
    if (h != null) {
      // De un nodo a otro: arranca desde un punto intermedio, más fluido.
      final from = _shownHover != null && _shownHover != h ? 0.35 : null;
      _shownHover = h;
      _hoverCtrl.forward(from: from);
    } else {
      _hoverCtrl.reverse();
    }
  }

  /// Entrada de la red: los nodos aparecen del centro hacia fuera,
  /// creciendo y con un fundido; luego los enlaces y las etiquetas.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(() => setState(() {}));

  /// Colocación final calculada antes de mostrar la red (la cámara se
  /// encuadra en ella desde el principio: sin zoom a tirones).
  Map<String, Offset> _finalLayout = {};

  // Rebote de entrada: cuánto se recogen las notas, energía inicial,
  // velocidad máxima y amortiguación (más alta = rebota más).
  static const _bounceFrom = 0.45;
  static const _bounceAlpha = 0.5;
  static const _maxSpeed = 9.0;
  static const _damping = 0.875;

  /// Retraso de cada nodo en la entrada (0 = el del centro, 1 = el último).
  final Map<String, double> _introDelay = {};

  void _startIntro() {
    if (_nodes.isEmpty) return;
    var c = Offset.zero;
    for (final n in _nodes.values) {
      c += n.pos;
    }
    c /= _nodes.length.toDouble();
    final byDist = _nodes.values.toList()
      ..sort((a, b) => (a.pos - c).distance.compareTo((b.pos - c).distance));
    for (var i = 0; i < byDist.length; i++) {
      _introDelay[byDist[i].id] =
          byDist.length == 1 ? 0 : i / (byDist.length - 1);
    }
    _intro.forward(from: 0);
  }

  String? _dragging;
  Offset? _lastFocal;
  double _startScale = 1;

  // Energía de la simulación: se para sola cuando todo está quieto.
  double _alpha = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.repo.addListener(_onRepo);
    _sync();
    // La red se coloca ANTES de verse (sin dibujar): así no "explota" al
    // entrar; solo queda la animación de entrada, suave.
    _presettle();
    // Rebote de entrada: las notas parten recogidas hacia el centro de su
    // sitio final y se expanden hasta él con un rebote suave.
    _finalLayout = {for (final n in _nodes.values) n.id: n.pos};
    var center = Offset.zero;
    for (final p in _finalLayout.values) {
      center += p;
    }
    if (_finalLayout.isNotEmpty) center /= _finalLayout.length.toDouble();
    for (final n in _nodes.values) {
      n.pos = center + (n.pos - center) * _bounceFrom;
      n.vel = Offset.zero;
    }
    _alpha = _bounceAlpha;
  }

  @override
  void dispose() {
    widget.repo.removeListener(_onRepo);
    _ticker.dispose();
    _intro.dispose();
    _hoverCtrl.dispose();
    for (final t in _thumbs.values) {
      t.dispose();
    }
    super.dispose();
  }

  void _onRepo() {
    if (widget.repo.version != _graphVersion) {
      setState(_sync);
    }
  }

  List<Note> get _visible {
    final g = _graph!;
    return _showOrphans
        ? g.nodes
        : g.nodes
            .where((n) => g.degree(n.id) > 0 || _mediaOfNote.containsKey(n.id))
            .toList();
  }

  /// Ajusta los nodos a las notas actuales conservando las posiciones.
  void _sync() {
    _graph = NoteGraph.of(widget.repo);
    _graphVersion = widget.repo.version;
    _media.clear();
    _mediaOfNote.clear();
    for (final n in _graph!.nodes) {
      for (final item in allMediaOf(n)) {
        if (!item.inGraph) continue;
        final id = 'm|${n.id}|${item.path}';
        _media[id] = _GraphMedia(n.id, item);
        (_mediaOfNote[n.id] ??= {}).add(id);
        if (item.kind == MediaKind.image) _loadThumb(item.path);
      }
    }
    // Las notas primero: así una bola de archivo nace junto a la suya.
    final ids = {..._visible.map((n) => n.id)};
    ids.addAll(_media.keys.where((m) => ids.contains(_media[m]!.noteId)));
    _nodes.removeWhere((id, _) => !ids.contains(id));
    for (final id in ids) {
      if (_nodes.containsKey(id)) continue;
      // Las nuevas aparecen junto a una vecina si la tienen.
      final near =
          _links(id).map((n) => _nodes[n]).whereType<_Node>().firstOrNull;
      final base = near?.pos ?? Offset.zero;
      final spread = near == null ? 160.0 : 40.0;
      _nodes[id] = _Node(
          id,
          base +
              Offset((_rnd.nextDouble() - 0.5) * spread,
                  (_rnd.nextDouble() - 0.5) * spread));
    }
    _reheat(0.8);
  }

  /// Arrastrar el fondo: como en el espacio, cada nota tiene su propia
  /// inercia (se queda un poco atrás, cada una distinto y con un ángulo
  /// propio) y después vuelve flotando a su sitio. Nada reacciona igual ni
  /// alrededor de un mismo punto.
  void _wake(Offset screen, Offset delta) {
    if (delta == Offset.zero) return;
    final world = delta / _scale;
    for (final n in _nodes.values) {
      if (n.pinned) continue;
      final h = n.id.hashCode;
      // Masa e inclinación fijas por nota (siempre las mismas para cada una).
      // Suave: cada nota se queda solo un poco atrás.
      final lag = 0.015 + (h & 0xff) / 255 * 0.07;
      final turn = (((h >> 8) & 0xff) / 255 - 0.5) * 0.9;
      final c = math.cos(turn), s = math.sin(turn);
      final v =
          Offset(world.dx * c - world.dy * s, world.dx * s + world.dy * c);
      n.vel -= v * lag;
    }
    _drift = 1;
    _reheat(0.08);
  }

  /// Tras arrastrar el fondo, menos rozamiento un rato: flotan.
  double _drift = 0;

  void _reheat([double a = 0.5]) {
    _alpha = math.max(_alpha, a);
    if (!_ticker.isActive) _ticker.start();
  }

  /// Calcula la colocación sin dibujar (hasta que se queda quieta).
  void _presettle() {
    final n = _nodes.length;
    if (n == 0) return;
    final maxIter = (2e6 / (n * n)).clamp(80, 500).round();
    _alpha = 1;
    for (var i = 0; i < maxIter; i++) {
      final e = _step(decay: 0.975);
      if (i > 40 && e < 0.001) break;
    }
  }

  void _tick(Duration _) {
    final energy = _step();
    final count = _nodes.length;
    if ((_autoFit || !_centered) && _size != Size.zero) {
      _fit(smooth: _centered);
    }
    setState(() {});
    if (_dragging == null && (count == 0 || energy / count < 0.002)) {
      _ticker.stop();
      _autoFit = false;
    }
  }

  /// Un paso de la simulación (fuerzas y movimiento). Devuelve la energía.
  double _step({double decay = 0.99}) {
    final g = _graph;
    if (g == null) return 0;
    final list = _nodes.values.toList();
    const repulsion = 5200.0;
    const springLength = 90.0;
    const spring = 0.035;
    const gravity = 0.012;

    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      var f = -a.pos * gravity;
      for (var j = 0; j < list.length; j++) {
        if (i == j) continue;
        var d = a.pos - list[j].pos;
        var dist2 = d.distanceSquared;
        if (dist2 < 0.01) {
          d = Offset(_rnd.nextDouble() - 0.5, _rnd.nextDouble() - 0.5);
          dist2 = 0.25;
        }
        if (dist2 > 250000) continue; // muy lejos: no influye
        f += d / math.sqrt(dist2) * (repulsion / dist2);
      }
      for (final nId in _links(a.id)) {
        final b = _nodes[nId];
        if (b == null) continue;
        final d = b.pos - a.pos;
        final dist = d.distance;
        if (dist == 0) continue;
        f += d / dist * ((dist - springLength) * spring);
      }
      a.vel = (a.vel + f * _alpha) * (_damping + 0.05 * _drift);
    }
    var energy = 0.0;
    for (final n in list) {
      if (n.pinned || n.id == _dragging) {
        n.vel = Offset.zero;
        continue;
      }
      final v = n.vel.distance > _maxSpeed
          ? n.vel / n.vel.distance * _maxSpeed
          : n.vel;
      n.pos += v;
      energy += v.distanceSquared;
    }
    _alpha = math.max(0.02, _alpha * decay);
    _drift *= 0.97;
    return energy;
  }

  /// Encaja todo el grafo en la vista. Con [smooth], la cámara se acerca
  /// poco a poco al encuadre (sin saltos de zoom mientras la red se mueve).
  void _fit({bool smooth = false}) {
    if (_nodes.isEmpty || _size == Size.zero) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final n in _nodes.values) {
      minX = math.min(minX, n.pos.dx);
      minY = math.min(minY, n.pos.dy);
      maxX = math.max(maxX, n.pos.dx);
      maxY = math.max(maxY, n.pos.dy);
    }
    final w = math.max(maxX - minX, 1.0) + 160;
    final h = math.max(maxY - minY, 1.0) + 160;
    final targetScale =
        math.min(_size.width / w, _size.height / h).clamp(0.3, 1.6);
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final targetOffset =
        Offset(_size.width / 2, _size.height / 2) - center * targetScale;
    if (smooth) {
      const k = 0.1;
      _scale += (targetScale - _scale) * k;
      _offset += (targetOffset - _offset) * k;
    } else {
      _scale = targetScale;
      _offset = targetOffset;
    }
    _centered = true;
  }

  /// Encuadre inicial sobre la colocación final (no sobre las notas, que
  /// aún están recogidas en el centro).
  void _fitToFinal() {
    if (_finalLayout.isEmpty) return _fit();
    final saved = {for (final n in _nodes.values) n.id: n.pos};
    for (final n in _nodes.values) {
      n.pos = _finalLayout[n.id] ?? n.pos;
    }
    _fit();
    for (final n in _nodes.values) {
      n.pos = saved[n.id] ?? n.pos;
    }
  }

  Offset _toWorld(Offset screen) => (screen - _offset) / _scale;

  double _radius(String id) => _media.containsKey(id)
      ? _mediaRadius
      : 5 + 2.2 * math.sqrt(_graph!.degree(id).toDouble());

  String? _hit(Offset screen) {
    final w = _toWorld(screen);
    String? best;
    var bestD = double.infinity;
    for (final n in _nodes.values) {
      final d = (n.pos - w).distance;
      final r = _radius(n.id) + 6 / _scale;
      if (d <= r && d < bestD) {
        best = n.id;
        bestD = d;
      }
    }
    return best;
  }

  void _zoomAt(Offset focal, double factor) {
    _autoFit = false;
    final newScale = (_scale * factor).clamp(0.2, 4.0);
    final world = _toWorld(focal);
    setState(() {
      _scale = newScale;
      _offset = focal - world * _scale;
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = _graph!;
    final p = Palette.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final orphans = g.nodes
        .where((n) => g.degree(n.id) == 0 && !_mediaOfNote.containsKey(n.id))
        .length;
    final notesById = {for (final n in g.nodes) n.id: n};

    // La cabecera es una barra propia y el lienzo empieza debajo y se
    // recorta (ClipRect): los nodos nunca tapan la barra ni el resto de la
    // app, aunque se arrastren o se haga zoom.
    return Material(
      color: p.card,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                  p.background.withValues(alpha: 0.35), p.card),
              border: Border(
                  bottom:
                      BorderSide(color: p.separator.withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                Icon(Icons.hub_outlined, size: 20, color: p.accent),
                const SizedBox(width: 8),
                Text(tr('Red de notas'),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: onSurface)),
              ],
            ),
          ),
          Expanded(
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LayoutBuilder(builder: (context, c) {
                      final size = c.biggest;
                      if (size != _size) {
                        _size = size;
                        if (!_centered) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _fitToFinal();
                              _autoFit = false;
                            });
                            if (!_intro.isAnimating && _intro.value == 0) {
                              _startIntro();
                            }
                          });
                        }
                      }
                      return Listener(
                        onPointerSignal: (e) {
                          if (e is PointerScrollEvent) {
                            GestureBinding.instance.pointerSignalResolver
                                .register(e, (ev) {
                              final s = ev as PointerScrollEvent;
                              _zoomAt(s.localPosition,
                                  math.pow(0.998, s.scrollDelta.dy).toDouble());
                            });
                          }
                        },
                        child: MouseRegion(
                          cursor: _hover != null
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.grab,
                          onHover: (e) {
                            final h = _hit(e.localPosition);
                            if (h != _hover) _setHover(h);
                          },
                          onExit: (_) => _setHover(null),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _openAt(d.localPosition),
                            onSecondaryTapUp: (d) =>
                                _nodeMenu(d.localPosition, d.globalPosition),
                            onLongPressStart: (d) =>
                                _nodeMenu(d.localPosition, d.globalPosition),
                            onScaleStart: (d) {
                              _lastFocal = d.localFocalPoint;
                              _startScale = _scale;
                              _autoFit = false;
                              _dragging = d.pointerCount == 1
                                  ? _hit(d.localFocalPoint)
                                  : null;
                              if (_dragging != null) _reheat(0.3);
                            },
                            onScaleUpdate: (d) {
                              final last = _lastFocal ?? d.localFocalPoint;
                              _lastFocal = d.localFocalPoint;
                              if (_dragging != null) {
                                final n = _nodes[_dragging!];
                                if (n != null) {
                                  // El nodo no puede salir del panel.
                                  final r = _radius(n.id) * _scale + 4;
                                  final pt = Offset(
                                    d.localFocalPoint.dx
                                        .clamp(r, math.max(r, _size.width - r)),
                                    d.localFocalPoint.dy.clamp(
                                        r, math.max(r, _size.height - r)),
                                  );
                                  n.pos = _toWorld(pt);
                                  _reheat(0.3);
                                }
                                return;
                              }
                              setState(() {
                                if (d.pointerCount > 1) {
                                  final world = _toWorld(d.localFocalPoint);
                                  _scale =
                                      (_startScale * d.scale).clamp(0.2, 4.0);
                                  _offset = d.localFocalPoint - world * _scale;
                                } else {
                                  final delta = d.localFocalPoint - last;
                                  _offset += delta;
                                  _wake(d.localFocalPoint, delta);
                                }
                              });
                            },
                            onScaleEnd: (_) {
                              _dragging = null;
                              _lastFocal = null;
                            },
                            child: CustomPaint(
                              size: size,
                              painter: _GraphPainter(
                                nodes: _nodes,
                                graph: g,
                                notes: notesById,
                                media: _media,
                                thumbs: _thumbs,
                                links: _links,
                                scale: _scale,
                                offset: _offset,
                                hover: _dragging ?? _shownHover,
                                intro: _intro.value,
                                introDelay: _introDelay,
                                hoverT:
                                    _dragging != null ? 1 : _hoverCtrl.value,
                                radius: _radius,
                                colors: p,
                                labelColor: onSurface,
                                labelFont: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.fontFamily,
                                textDirection: Directionality.of(context),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  // Controles abajo a la izquierda.
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Row(
                      children: [
                        if (orphans > 0) ...[
                          _Pill(
                            icon: _showOrphans
                                ? Icons.blur_on_rounded
                                : Icons.blur_off_rounded,
                            label: _showOrphans
                                ? tr('Sueltas: sí')
                                : tr('Sueltas: no'),
                            tooltip: _showOrphans
                                ? trf('Ocultar notas sin enlaces ({0})',
                                    [orphans])
                                : trf('Mostrar notas sin enlaces ({0})',
                                    [orphans]),
                            onTap: () => setState(() {
                              _showOrphans = !_showOrphans;
                              _sync();
                              _centered = false;
                              _autoFit = true;
                            }),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _Pill(
                          icon: Icons.center_focus_strong_rounded,
                          tooltip: tr('Centrar'),
                          onTap: () => setState(_fit),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.label});
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.background,
        shape: StadiumBorder(side: BorderSide(color: p.separator)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: label == null ? 8 : 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: p.secondary),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(label!,
                      style: TextStyle(fontSize: 12, color: p.secondary)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Caracteres de una etiqueta de la red.
const _maxLabel = 14;

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.graph,
    required this.notes,
    required this.media,
    required this.thumbs,
    required this.links,
    required this.scale,
    required this.offset,
    required this.hover,
    required this.intro,
    required this.introDelay,
    required this.hoverT,
    required this.radius,
    required this.colors,
    required this.labelColor,
    this.labelFont,
    required this.textDirection,
  });

  final Map<String, _Node> nodes;
  final NoteGraph graph;
  final Map<String, Note> notes;
  final Map<String, _GraphMedia> media;
  final Map<String, ui.Image> thumbs;
  final Set<String> Function(String id) links;
  final double scale;
  final Offset offset;
  final String? hover;

  /// Progreso de la entrada (0..1) y retraso de cada nodo (0..1).
  final double intro;
  final Map<String, double> introDelay;

  /// Aparición de un nodo en la entrada (0 = oculto, 1 = visible).
  double appear(String id) {
    if (intro >= 1) return 1;
    final d = introDelay[id] ?? 0;
    // Fundido rápido y casi a la vez (el movimiento lo da el rebote).
    final p = ((intro - d * 0.25) / 0.75).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(p);
  }

  /// Progreso de la animación de resaltado (0..1).
  final double hoverT;
  final double Function(String id) radius;
  final NotasColors colors;
  final Color labelColor;

  /// Fuente de las etiquetas (la del tema, como el resto del texto).
  final String? labelFont;
  final TextDirection textDirection;

  Offset _s(Offset world) => world * scale + offset;

  /// Bola de archivo: borde, y dentro la imagen o el icono de su tipo.
  void _paintMedia(Canvas canvas, Offset c, double r, _GraphMedia m,
      double alpha, bool isHover, double t) {
    final accent = colors.accent;
    if (isHover) {
      canvas.drawCircle(
          c, r + 7 * t, Paint()..color = accent.withValues(alpha: 0.2 * t));
    }
    canvas.drawCircle(
        c, r, Paint()..color = colors.background.withValues(alpha: alpha));
    final thumb = m.item.kind == MediaKind.image ? thumbs[m.item.path] : null;
    if (thumb != null) {
      final w = thumb.width.toDouble(), h = thumb.height.toDouble();
      final side = math.min(w, h);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      canvas.drawImageRect(
          thumb,
          Rect.fromCenter(
              center: Offset(w / 2, h / 2), width: side, height: side),
          Rect.fromCircle(center: c, radius: r),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Colors.white.withValues(alpha: alpha));
      canvas.restore();
    } else {
      final icon = mediaIcon(m.item);
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: r * 1.1,
            color: accent.withValues(alpha: alpha),
          ),
        ),
        textDirection: textDirection,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHover ? 2.6 : 2
          ..color = accent.withValues(alpha: alpha));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // t: progreso de la animación de resaltado (0 = nada, 1 = completo).
    final t = Curves.easeOutCubic.transform(hoverT.clamp(0.0, 1.0));
    final focus = hover == null || !nodes.containsKey(hover)
        ? null
        : {hover!, ...links(hover!)};
    double lerp(double a, double b) => a + (b - a) * t;

    // Enlaces.
    final edge = Paint()..style = PaintingStyle.stroke;
    void drawEdge(String from, String to) {
      final a = nodes[from], b = nodes[to];
      if (a == null || b == null) return;
      final lit = focus != null && (from == hover || to == hover);
      // En la entrada, el enlace aparece cuando ya se ven sus dos notas.
      final show = math.min(appear(from), appear(to));
      if (show <= 0.01) return;
      final color = lit
          ? Color.lerp(colors.secondary.withValues(alpha: 0.35),
              colors.accent.withValues(alpha: 0.95), t)!
          : colors.secondary
              .withValues(alpha: focus == null ? 0.35 : lerp(0.35, 0.1));
      edge
        ..color = color.withValues(alpha: color.a * show)
        ..strokeWidth = lit ? lerp(1.2, 2.4) : 1.2;
      canvas.drawLine(_s(a.pos), _s(b.pos), edge);
    }

    graph.outgoing.forEach((from, targets) {
      for (final to in targets) {
        drawEdge(from, to);
      }
    });
    media.forEach((id, m) => drawEdge(m.noteId, id));

    // Nodos.
    for (final n in nodes.values) {
      final note = notes[n.id];
      final file = media[n.id];
      if (note == null && file == null) continue;
      final c = _s(n.pos);
      final isHover = n.id == hover;
      final inFocus = focus?.contains(n.id) ?? false;
      final a0 = appear(n.id);
      if (a0 <= 0.01) continue;
      final grow = (isHover ? lerp(1, 1.4) : (inFocus ? lerp(1, 1.12) : 1.0)) *
          (0.6 + 0.4 * a0);
      final r = radius(n.id) * scale.clamp(0.6, 1.6) * grow;
      if (file != null) {
        final alpha = focus != null && !inFocus ? lerp(a0, 0.2) : a0;
        _paintMedia(canvas, c, r, file, alpha, isHover, t);
        continue;
      }
      final base = colors.accent; // el color de la nota es solo de su mecha
      final orphan = links(n.id).isEmpty;
      final alpha = (orphan ? 0.55 : 1.0) * a0;
      final fill = Paint()
        ..color = (orphan ? colors.secondary : base).withValues(
            alpha: focus != null && !inFocus ? lerp(alpha, 0.16) : alpha);
      if (isHover) {
        // Halo que se expande.
        canvas.drawCircle(c, r + lerp(0, 9),
            Paint()..color = base.withValues(alpha: 0.22 * t));
        canvas.drawCircle(
            c,
            r + lerp(0, 3),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = base.withValues(alpha: 0.6 * t));
      }
      canvas.drawCircle(c, r, fill);
    }

    // Etiquetas: con zoom suficiente, o para la nota resaltada y vecinas.
    for (final n in nodes.values) {
      final label = notes[n.id]?.title ?? media[n.id]?.item.name;
      if (label == null) continue;
      final isHover = n.id == hover;
      final inFocus = focus?.contains(n.id) ?? false;
      final big = graph.degree(n.id) >= 3;
      final always = scale >= 0.85 || (big && scale >= 0.5);
      // Visibilidad: las de fuera del foco se desvanecen.
      final double visible;
      if (focus == null) {
        visible = always ? 1 : 0;
      } else if (inFocus) {
        visible = always ? 1 : t;
      } else {
        visible = always ? 1 - t : 0;
      }
      // En la entrada, la etiqueta aparece justo después de su nota.
      final labelIn = Curves.easeOut
          .transform(((appear(n.id) - 0.4) / 0.6).clamp(0.0, 1.0));
      if (visible * labelIn <= 0.01) continue;
      final title = label.length > _maxLabel
          ? '${label.substring(0, _maxLabel - 1).trimRight()}…'
          : label;
      final tp = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(
            fontFamily: labelFont,
            fontSize: isHover ? lerp(11.5, 13.5) : 11.5,
            fontWeight: isHover && t > 0.5 ? FontWeight.w700 : FontWeight.w500,
            color: labelColor.withValues(alpha: 0.92 * visible * labelIn),
          ),
        ),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      final c = _s(n.pos);
      final grow = isHover ? lerp(1, 1.4) : (inFocus ? lerp(1, 1.12) : 1.0);
      final r = radius(n.id) * scale.clamp(0.6, 1.6) * grow;
      tp.paint(canvas,
          c + Offset(-tp.width / 2, r + 4 + (isHover ? lerp(0, 3) : 0)));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
