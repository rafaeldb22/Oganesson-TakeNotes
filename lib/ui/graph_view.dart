import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/note_links.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
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

class _GraphViewState extends State<GraphView> with TickerProviderStateMixin {
  late final Ticker _ticker;
  final _nodes = <String, _Node>{};
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

  String? _dragging;
  Offset? _lastFocal;
  double _startScale = 1;
  Offset _downPos = Offset.zero;
  bool _moved = false;

  // Energía de la simulación: se para sola cuando todo está quieto.
  double _alpha = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.repo.addListener(_onRepo);
    _sync();
  }

  @override
  void dispose() {
    widget.repo.removeListener(_onRepo);
    _ticker.dispose();
    _hoverCtrl.dispose();
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
        : g.nodes.where((n) => g.degree(n.id) > 0).toList();
  }

  /// Ajusta los nodos a las notas actuales conservando las posiciones.
  void _sync() {
    _graph = NoteGraph.of(widget.repo);
    _graphVersion = widget.repo.version;
    final ids = _visible.map((n) => n.id).toSet();
    _nodes.removeWhere((id, _) => !ids.contains(id));
    for (final id in ids) {
      if (_nodes.containsKey(id)) continue;
      // Las nuevas aparecen junto a una vecina si la tienen.
      final near = _graph!
          .neighbors(id)
          .map((n) => _nodes[n])
          .whereType<_Node>()
          .firstOrNull;
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

  void _reheat([double a = 0.5]) {
    _alpha = math.max(_alpha, a);
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration _) {
    final g = _graph;
    if (g == null) return;
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
      for (final nId in g.neighbors(a.id)) {
        final b = _nodes[nId];
        if (b == null) continue;
        final d = b.pos - a.pos;
        final dist = d.distance;
        if (dist == 0) continue;
        f += d / dist * ((dist - springLength) * spring);
      }
      a.vel = (a.vel + f * _alpha) * 0.82;
    }
    var energy = 0.0;
    for (final n in list) {
      if (n.pinned || n.id == _dragging) {
        n.vel = Offset.zero;
        continue;
      }
      final v = n.vel.distance > 30 ? n.vel / n.vel.distance * 30 : n.vel;
      n.pos += v;
      energy += v.distanceSquared;
    }
    _alpha = math.max(0.02, _alpha * 0.99);
    if ((_autoFit || !_centered) && _size != Size.zero) _fit();
    setState(() {});
    if (_dragging == null && (list.isEmpty || energy / list.length < 0.002)) {
      _ticker.stop();
      _autoFit = false;
    }
  }

  /// Encaja todo el grafo en la vista.
  void _fit() {
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
    _scale = math.min(_size.width / w, _size.height / h).clamp(0.3, 1.6);
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    _offset = Offset(_size.width / 2, _size.height / 2) - center * _scale;
    _centered = true;
  }

  Offset _toWorld(Offset screen) => (screen - _offset) / _scale;

  double _radius(String id) =>
      5 + 2.2 * math.sqrt(_graph!.degree(id).toDouble());

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
    final orphans = g.nodes.where((n) => g.degree(n.id) == 0).length;
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
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '${trn(g.nodes.length, '{0} nota', '{0} notas')} · '
                    '${trn(g.edgeCount, '{0} enlace', '{0} enlaces')}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.secondary),
                  ),
                ),
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
                            if (mounted) setState(_fit);
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
                            onScaleStart: (d) {
                              _downPos = d.localFocalPoint;
                              _lastFocal = d.localFocalPoint;
                              _startScale = _scale;
                              _moved = false;
                              _autoFit = false;
                              _dragging = d.pointerCount == 1
                                  ? _hit(d.localFocalPoint)
                                  : null;
                              if (_dragging != null) _reheat(0.3);
                            },
                            onScaleUpdate: (d) {
                              if ((d.localFocalPoint - _downPos).distance > 4) {
                                _moved = true;
                              }
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
                                  _offset += d.localFocalPoint - last;
                                }
                              });
                            },
                            onScaleEnd: (_) {
                              final tapped = !_moved ? _hit(_downPos) : null;
                              _dragging = null;
                              _lastFocal = null;
                              if (tapped != null) widget.onOpenNote(tapped);
                            },
                            child: CustomPaint(
                              size: size,
                              painter: _GraphPainter(
                                nodes: _nodes,
                                graph: g,
                                notes: notesById,
                                scale: _scale,
                                offset: _offset,
                                hover: _dragging ?? _shownHover,
                                hoverT:
                                    _dragging != null ? 1 : _hoverCtrl.value,
                                radius: _radius,
                                colors: p,
                                labelColor: onSurface,
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

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.graph,
    required this.notes,
    required this.scale,
    required this.offset,
    required this.hover,
    required this.hoverT,
    required this.radius,
    required this.colors,
    required this.labelColor,
    required this.textDirection,
  });

  final Map<String, _Node> nodes;
  final NoteGraph graph;
  final Map<String, Note> notes;
  final double scale;
  final Offset offset;
  final String? hover;

  /// Progreso de la animación de resaltado (0..1).
  final double hoverT;
  final double Function(String id) radius;
  final NotasColors colors;
  final Color labelColor;
  final TextDirection textDirection;

  Offset _s(Offset world) => world * scale + offset;

  @override
  void paint(Canvas canvas, Size size) {
    // t: progreso de la animación de resaltado (0 = nada, 1 = completo).
    final t = Curves.easeOutCubic.transform(hoverT.clamp(0.0, 1.0));
    final focus = hover == null ? null : {hover!, ...graph.neighbors(hover!)};
    double lerp(double a, double b) => a + (b - a) * t;

    // Enlaces.
    final edge = Paint()..style = PaintingStyle.stroke;
    graph.outgoing.forEach((from, targets) {
      final a = nodes[from];
      if (a == null) return;
      for (final to in targets) {
        final b = nodes[to];
        if (b == null) continue;
        final lit = focus != null && (from == hover || to == hover);
        edge
          ..color = lit
              ? Color.lerp(colors.secondary.withValues(alpha: 0.35),
                  colors.accent.withValues(alpha: 0.95), t)!
              : colors.secondary
                  .withValues(alpha: focus == null ? 0.35 : lerp(0.35, 0.1))
          ..strokeWidth = lit ? lerp(1.2, 2.4) : 1.2;
        canvas.drawLine(_s(a.pos), _s(b.pos), edge);
      }
    });

    // Nodos.
    for (final n in nodes.values) {
      final note = notes[n.id];
      if (note == null) continue;
      final c = _s(n.pos);
      final isHover = n.id == hover;
      final inFocus = focus?.contains(n.id) ?? false;
      final grow = isHover ? lerp(1, 1.4) : (inFocus ? lerp(1, 1.12) : 1.0);
      final r = radius(n.id) * scale.clamp(0.6, 1.6) * grow;
      final base = note.color != null ? Color(note.color!) : colors.accent;
      final orphan = graph.degree(n.id) == 0;
      final alpha = orphan ? 0.55 : 1.0;
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
      final note = notes[n.id];
      if (note == null) continue;
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
      if (visible <= 0.01) continue;
      final title = note.title.length > 28
          ? '${note.title.substring(0, 27)}…'
          : note.title;
      final tp = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(
            fontSize: isHover ? lerp(11.5, 13.5) : 11.5,
            fontWeight: isHover && t > 0.5 ? FontWeight.w700 : FontWeight.w500,
            color: labelColor.withValues(alpha: 0.92 * visible),
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
