import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/mock.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';

/// Concept 02 — Constellation. The account as a night sky: every project is a
/// sun, every memory a star on an orbit around it, coloured by kind and sized
/// by how fresh it is. Links between records are faint threads that light up
/// (with a travelling spark) when either end is selected. The panel's hero,
/// stats and Remember form ride along in a frosted header.
class ConstellationConcept extends StatefulWidget {
  const ConstellationConcept({super.key});

  @override
  State<ConstellationConcept> createState() => _ConstellationConceptState();
}

const _tilt = 0.82; // orbits are drawn as slightly squashed ellipses for depth
const _headerInset = 168.0;

const _sunPalette = <Color>[
  Rq.accent,
  Color(0xFFFFB86B),
  Color(0xFF8AB4F8),
  Color(0xFF51CF66),
  Color(0xFFB197FC),
  Color(0xFFC49A6C),
  Color(0xFF3BC9DB),
  Color(0xFFFF8A80),
];

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

class _ConstellationConceptState extends State<ConstellationConcept> with TickerProviderStateMixin {
  // _clock only drives repaints; time itself comes from the stopwatch so
  // painting and hit-testing agree on where every star is.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..forward();
  final _watch = Stopwatch()..start();
  final _tc = TransformationController();

  final List<Memory> _stars = [...memories];
  final Set<Kind> _filter = {};
  int? _selectedId;
  String? _selectedProject;
  int _nextId = 7911;
  int? _bornId;
  double _bornAt = 0;

  _Layout? _layout;
  Size? _fittedFor;

  double get _t => _watch.elapsedMicroseconds / 1e6;

  @override
  void dispose() {
    _clock.dispose();
    _intro.dispose();
    _tc.dispose();
    _layout?.dispose();
    super.dispose();
  }

  _Layout _layoutFor(Size canvas) {
    final current = _layout;
    if (current != null && current.size == canvas && current.count == _stars.length) return current;
    current?.dispose();
    return _layout = _Layout(canvas, _stars);
  }

  /// Fits the canvas into the space under the header whenever the viewport
  /// changes size (first load, rotation, window resize).
  void _maybeFit(Size viewport, Size canvas, double top) {
    if (_fittedFor == viewport) return;
    _fittedFor = viewport;
    final region = Rect.fromLTWH(0, top, viewport.width, math.max(120, viewport.height - top - 24));
    final scale = math.min(region.width / canvas.width, region.height / canvas.height);
    final dx = region.left + (region.width - canvas.width * scale) / 2;
    final dy = region.top + (region.height - canvas.height * scale) / 2;
    final matrix = Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(dx, dy, 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tc.value = matrix;
    });
  }

  void _onTap(Offset p) {
    final layout = _layout;
    if (layout == null) return;
    final t = _t;
    final iv = _intro.value;
    final scale = _tc.value.getMaxScaleOnAxis();
    _Orbit? best;
    var bestD = 26 / scale;
    for (final o in layout.orbits) {
      final d = (layout.starAt(o, t, iv) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    if (best != null) {
      _selectStar(best.memory.id);
      return;
    }
    for (final s in layout.suns) {
      if ((layout.sunAt(s, iv) - p).distance < s.radius + 16 / scale) {
        setState(() {
          _selectedProject = _selectedProject == s.name ? null : s.name;
          _selectedId = null;
        });
        return;
      }
    }
    setState(() {
      _selectedId = null;
      _selectedProject = null;
    });
  }

  void _selectStar(int id) => setState(() {
        _selectedId = id;
        _selectedProject = null;
      });

  void _clear() => setState(() {
        _selectedId = null;
        _selectedProject = null;
      });

  void _bigBang() {
    _clear();
    _intro.forward(from: 0);
  }

  void _open([int? id]) {
    final target = id == null ? 'https://${account.host}/dashboard' : 'https://${account.host}/dashboard#records/$id';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Rq.surface,
      content: Text('Would open $target', style: Rq.mono(size: 12)),
    ));
  }

  void _addStar(String title) {
    final m = Memory(
      id: _nextId++,
      title: title,
      kind: Kind.info,
      status: 'active',
      project: projects.first.name,
      age: Duration.zero,
    );
    setState(() {
      _stars.add(m);
      _bornId = m.id;
      _bornAt = _t;
      _selectedId = m.id;
      _selectedProject = null;
    });
  }

  void _remember() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black38,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _Frosted(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome, color: Rq.accent, size: 20),
                    const SizedBox(width: 8),
                    Text('Remember', style: Rq.display(size: 20)),
                    const Spacer(),
                    Text('a new star is born', style: Rq.mono(size: 11, color: Rq.muted)),
                  ]),
                  const SizedBox(height: 14),
                  RememberForm(onSaved: (title) {
                    _addStar(title);
                    Navigator.of(ctx).pop();
                  }),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Memory> _linked(Memory m) {
    final ids = {...m.links, for (final o in _stars) if (o.links.contains(m.id)) o.id};
    return [for (final s in _stars) if (ids.contains(s.id)) s];
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Rq.bgDeep,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _clear,
          const SingleActivator(LogicalKeyboardKey.keyR): _bigBang,
          const SingleActivator(LogicalKeyboardKey.keyA): _remember,
          const SingleActivator(LogicalKeyboardKey.keyO): _open,
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(builder: (context, box) {
            final viewport = box.biggest;
            final wide = viewport.width >= 820;
            final portrait = viewport.width / viewport.height < 0.9;
            final canvas = portrait ? const Size(900, 1400) : const Size(1600, 1000);
            final layout = _layoutFor(canvas);
            _maybeFit(viewport, canvas, mq.padding.top + _headerInset);

            return Stack(children: [
              const Positioned.fill(child: _Nebula()),
              Positioned.fill(
                child: RepaintBoundary(child: CustomPaint(painter: _StarfieldPainter(_watch, _clock))),
              ),
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _tc,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(1200),
                  minScale: 0.15,
                  maxScale: 4,
                  child: SizedBox.fromSize(
                    size: canvas,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _onTap(d.localPosition),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: canvas,
                          painter: _MapPainter(
                            layout: layout,
                            watch: _watch,
                            intro: _intro,
                            selectedId: _selectedId,
                            selectedProject: _selectedProject,
                            filter: _filter,
                            bornId: _bornId,
                            bornAt: _bornAt,
                            repaint: Listenable.merge([_clock, _intro]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: Padding(padding: const EdgeInsets.all(12), child: _header(wide)),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 12 + mq.padding.bottom,
                child: const ConceptsButton(),
              ),
              if (wide)
                Positioned(
                  right: 16,
                  bottom: 16 + mq.padding.bottom,
                  child: Text('drag to pan · scroll to zoom · tap a star · r big bang · a remember',
                      style: Rq.mono(size: 11, color: Rq.muted.withValues(alpha: 0.7))),
                ),
              Positioned(
                left: wide ? null : 12,
                right: wide ? 16 : 12,
                top: wide ? mq.padding.top + _headerInset + 8 : null,
                bottom: wide ? null : 56 + mq.padding.bottom,
                width: wide ? 340 : null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _detailCard(layout) ?? const SizedBox.shrink(key: ValueKey('none')),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _header(bool wide) {
    return _Frosted(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const ReqallMark(size: 38, radius: 9, glow: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Wordmark(size: 18),
              Text(
                '${account.host} · ${_fmt(account.memories)} memories',
                style: Rq.mono(size: 11, color: Rq.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          _HeaderButton(icon: Icons.bookmark_add_outlined, label: 'Remember', showLabel: wide, onTap: _remember),
          const SizedBox(width: 6),
          _HeaderButton(icon: Icons.refresh_rounded, label: 'Refresh', showLabel: wide, onTap: _bigBang),
          const SizedBox(width: 6),
          _HeaderButton(icon: Icons.open_in_new_rounded, label: 'Open', showLabel: wide, onTap: _open),
        ]),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _StatPill(value: account.memories, label: 'memories', color: Rq.accent),
            _StatPill(value: account.openTodos, label: 'open todos', color: Kind.todo.color),
            _StatPill(value: account.openIssues, label: 'open issues', color: Kind.issue.color),
            _StatPill(value: account.projects, label: 'projects', color: Rq.textSoft),
          ]),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            GestureDetector(
              onTap: () => setState(_filter.clear),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _filter.isEmpty ? Rq.accent.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _filter.isEmpty ? Rq.accent : Rq.border),
                ),
                child: Text('all', style: Rq.mono(size: 11, color: _filter.isEmpty ? Rq.accent : Rq.textSoft)),
              ),
            ),
            for (final k in Kind.values)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: KindChip(
                  k,
                  selected: _filter.contains(k),
                  onTap: () => setState(() => _filter.contains(k) ? _filter.remove(k) : _filter.add(k)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget? _detailCard(_Layout layout) {
    final id = _selectedId;
    if (id != null) {
      final m = _stars.where((s) => s.id == id).firstOrNull;
      if (m == null) return null;
      final linked = _linked(m);
      return _Frosted(
        key: ValueKey('star$id'),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KindBadge(m.kind, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(m.title, style: Rq.display(size: 17, weight: FontWeight.w600)),
              ),
            ),
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.close_rounded, size: 18, color: Rq.muted),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          if (m.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(m.body, style: Rq.body(size: 13, color: Rq.textSoft)),
            ),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${shortProject(m.project)} · ${m.kind.name} · ${m.status}',
                  style: Rq.mono(size: 11, color: Rq.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('#${m.id} · ${relativeAge(m.age)}', style: Rq.mono(size: 11, color: m.kind.color)),
            ]),
          ),
          if (linked.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('LINKED', style: Rq.mono(size: 10, color: Rq.muted).copyWith(letterSpacing: 1.4)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in linked) _StarChip(memory: l, onTap: () => _selectStar(l.id)),
            ]),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _open(m.id),
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('Open in Reqall'),
            style: TextButton.styleFrom(foregroundColor: Rq.accent, visualDensity: VisualDensity.compact),
          ),
        ]),
      );
    }
    final name = _selectedProject;
    if (name != null) {
      final sun = layout.byName[name];
      if (sun == null) return null;
      final mine = _stars.where((s) => s.project == name).toList()..sort((a, b) => a.age.compareTo(b.age));
      return _Frosted(
        key: ValueKey('sun$name'),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sun.color,
                boxShadow: [BoxShadow(color: sun.color.withValues(alpha: 0.6), blurRadius: 10)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name, style: Rq.display(size: 17, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.close_rounded, size: 18, color: Rq.muted),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '${mine.length} in view · ${_fmt(sun.total)} memories in project',
            style: Rq.mono(size: 11, color: Rq.muted),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in mine) _StarChip(memory: m, onTap: () => _selectStar(m.id)),
          ]),
        ]),
      );
    }
    return null;
  }
}

// ------------------------------------------------------------------ layout

class _Sun {
  _Sun({required this.name, required this.home, required this.radius, required this.color, required this.total})
      : label = _label(name, Rq.textSoft),
        labelDim = _label(name, Rq.textSoft.withValues(alpha: 0.3));

  final String name;
  final Offset home;
  final double radius;
  final Color color;
  final int total;
  final TextPainter label;
  final TextPainter labelDim;

  static TextPainter _label(String name, Color color) => TextPainter(
        text: TextSpan(text: shortProject(name), style: Rq.mono(size: 20, weight: FontWeight.w600, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();

  void dispose() {
    label.dispose();
    labelDim.dispose();
  }
}

class _Orbit {
  _Orbit({
    required this.memory,
    required this.sun,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.size,
    required this.order,
  });

  final Memory memory;
  final _Sun sun;
  final double radius;
  final double speed;
  final double phase;
  final double size;
  final int order;
}

/// Where everything lives on the canvas. Suns sit on a loose ellipse around
/// the centre; each project's memories orbit it, newest innermost.
class _Layout {
  _Layout(this.size, List<Memory> stars) : count = stars.length {
    final names = <String>[];
    for (final m in stars) {
      if (!names.contains(m.project)) names.add(m.project);
    }
    final portrait = size.height > size.width;
    final rx = size.width * (portrait ? 0.30 : 0.34);
    final ry = size.height * (portrait ? 0.35 : 0.31);
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final seed = name.codeUnits.fold<int>(0, (a, b) => a + b);
      final jitter = (seed % 100) / 100 - 0.5;
      final angle = -math.pi / 2 + i * 2 * math.pi / names.length + jitter * 0.3;
      final reach = 1 + jitter * 0.2;
      final total = projects.where((p) => p.name == name).map((p) => p.count).firstOrNull ??
          stars.where((m) => m.project == name).length;
      final sun = _Sun(
        name: name,
        home: center + Offset(math.cos(angle) * rx * reach, math.sin(angle) * ry * reach),
        radius: 14 + 4.2 * math.log(1 + total),
        color: _sunPalette[i % _sunPalette.length],
        total: total,
      );
      suns.add(sun);
      byName[name] = sun;
    }

    var order = 0;
    for (var i = 0; i < suns.length; i++) {
      final s = suns[i];
      final mine = stars.where((m) => m.project == s.name).toList()..sort((a, b) => a.age.compareTo(b.age));
      for (var j = 0; j < mine.length; j++) {
        final m = mine[j];
        final hours = m.age.inMinutes / 60;
        final fresh = (math.log(1 + hours) / math.log(1 + 24 * 30)).clamp(0.0, 1.0);
        final o = _Orbit(
          memory: m,
          sun: s,
          radius: s.radius + 38 + j * 28,
          speed: (i.isEven ? 1 : -1) * 0.3 / (1 + j * 0.45),
          phase: (m.id * 2.399963) % (2 * math.pi),
          size: ui.lerpDouble(13, 6, fresh)!,
          order: order++,
        );
        orbits.add(o);
        byId[m.id] = o;
      }
    }
  }

  final Size size;
  final int count;
  final suns = <_Sun>[];
  final byName = <String, _Sun>{};
  final orbits = <_Orbit>[];
  final byId = <int, _Orbit>{};

  Offset get center => size.center(Offset.zero);

  double sunReveal(double intro) => Curves.easeOutCubic.transform(intro.clamp(0.0, 1.0));

  Offset sunAt(_Sun s, double intro) => Offset.lerp(center, s.home, sunReveal(intro))!;

  /// Staggered, slightly overshooting fly-out from the centre (the big bang).
  double starReveal(_Orbit o, double intro) {
    final delay = 0.12 + 0.45 * o.order / math.max(1, orbits.length);
    return Curves.easeOutBack.transform(((intro - delay) / (1 - delay)).clamp(0.0, 1.0));
  }

  double angleAt(_Orbit o, double t) => o.phase + t * o.speed;

  Offset starAt(_Orbit o, double t, double intro) {
    final a = angleAt(o, t);
    final home = sunAt(o.sun, intro) + Offset(math.cos(a) * o.radius, math.sin(a) * o.radius * _tilt);
    return Offset.lerp(center, home, starReveal(o, intro))!;
  }

  void dispose() {
    for (final s in suns) {
      s.dispose();
    }
  }
}

// ---------------------------------------------------------------- painters

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.layout,
    required this.watch,
    required this.intro,
    required this.selectedId,
    required this.selectedProject,
    required this.filter,
    required this.bornId,
    required this.bornAt,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _Layout layout;
  final Stopwatch watch;
  final Animation<double> intro;
  final int? selectedId;
  final String? selectedProject;
  final Set<Kind> filter;
  final int? bornId;
  final double bornAt;

  double _vis(Memory m) {
    final kindOk = filter.isEmpty || filter.contains(m.kind);
    final projectOk = selectedProject == null || selectedProject == m.project;
    return kindOk && projectOk ? 1 : 0.16;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = watch.elapsedMicroseconds / 1e6;
    final iv = intro.value;
    final center = layout.center;
    final sunReveal = layout.sunReveal(iv);

    // The big bang: a shock ring and a fading flash at the centre.
    if (iv < 1) {
      final ring = Curves.easeOutCubic.transform(iv);
      canvas.drawCircle(
        center,
        ring * size.longestSide * 0.7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + 30 * (1 - ring)
          ..color = Rq.accent.withValues(alpha: 0.35 * (1 - ring))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      canvas.drawCircle(
        center,
        60 * (1 - iv),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8 * (1 - iv))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
      );
    }

    final pos = <int, Offset>{for (final o in layout.orbits) o.memory.id: layout.starAt(o, t, iv)};
    final sunPos = <String, Offset>{for (final s in layout.suns) s.name: layout.sunAt(s, iv)};

    // Orbit rings.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final o in layout.orbits) {
      ringPaint.color = o.sun.color.withValues(alpha: 0.08 * _vis(o.memory) * sunReveal);
      canvas.drawOval(
        Rect.fromCenter(center: sunPos[o.sun.name]!, width: o.radius * 2, height: o.radius * 2 * _tilt),
        ringPaint,
      );
    }

    // Links: faint threads, lit with a travelling spark when selected.
    final thread = Paint()..strokeWidth = 1;
    final glow = Paint()
      ..strokeWidth = 6
      ..color = Rq.accent.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final hotThread = Paint()
      ..strokeWidth = 1.6
      ..color = Rq.accentHover.withValues(alpha: 0.9);
    final spark = Paint()
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final o in layout.orbits) {
      for (final id in o.memory.links) {
        final other = layout.byId[id];
        if (other == null) continue;
        final a = pos[o.memory.id]!;
        final b = pos[id]!;
        if (selectedId == o.memory.id || selectedId == id) {
          canvas.drawLine(a, b, glow);
          canvas.drawLine(a, b, hotThread);
          final p = (t * 0.6 + id * 0.137) % 1.0;
          canvas.drawCircle(Offset.lerp(a, b, p)!, 4, spark);
        } else {
          final vis = math.min(_vis(o.memory), _vis(other.memory));
          thread.color = Rq.textSoft.withValues(alpha: 0.16 * vis * sunReveal);
          canvas.drawLine(a, b, thread);
        }
      }
    }

    // Suns.
    for (final s in layout.suns) {
      final c = sunPos[s.name]!;
      final dim = selectedProject != null && selectedProject != s.name;
      final alpha = dim ? 0.3 : 1.0;
      final r = s.radius * (1 + 0.06 * math.sin(t * 1.3 + s.home.dx)) * sunReveal;
      if (r <= 0.5) continue;
      canvas.drawCircle(
        c,
        r * 2.6,
        Paint()
          ..color = s.color.withValues(alpha: 0.22 * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            r,
            [Colors.white.withValues(alpha: alpha), s.color.withValues(alpha: alpha), s.color.withValues(alpha: 0.55 * alpha)],
            const [0, 0.45, 1],
          ),
      );
      if (selectedProject == s.name) {
        canvas.drawCircle(
          c,
          r + 12 + 5 * math.sin(t * 3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = s.color.withValues(alpha: 0.7),
        );
      }
      final label = dim ? s.labelDim : s.label;
      label.paint(canvas, c + Offset(-label.width / 2, s.radius + 12));
    }

    // Stars.
    final starGlow = Paint();
    final core = Paint();
    final heart = Paint();
    for (final o in layout.orbits) {
      final m = o.memory;
      final reveal = layout.starReveal(o, iv);
      if (reveal <= 0) continue;
      final p = pos[m.id]!;
      final vis = _vis(m);
      final depth = 0.82 + 0.18 * math.sin(layout.angleAt(o, t));
      final r = o.size * depth * math.min(reveal, 1.0);
      final twinkle = 0.85 + 0.15 * math.sin(t * 2.2 + m.id);
      starGlow
        ..color = m.kind.color.withValues(alpha: 0.34 * vis * twinkle)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.2);
      canvas.drawCircle(p, r * 2.8, starGlow);
      core.color = m.kind.color.withValues(alpha: vis);
      canvas.drawCircle(p, r, core);
      heart.color = Colors.white.withValues(alpha: 0.85 * vis);
      canvas.drawCircle(p, r * 0.38, heart);

      if (selectedId == m.id) {
        canvas.drawCircle(
          p,
          r + 7 + 2 * math.sin(t * 5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = Colors.white.withValues(alpha: 0.85),
        );
        canvas.drawCircle(
          p,
          r + 16,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = m.kind.color.withValues(alpha: 0.3),
        );
      }
      if (bornId == m.id) {
        final age = t - bornAt;
        if (age < 3) {
          canvas.drawCircle(
            p,
            r + age * 60,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = m.kind.color.withValues(alpha: 0.8 * (1 - age / 3)),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}

/// Screen-fixed twinkling starfield with the occasional shooting star.
class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter(this.watch, Listenable repaint) : super(repaint: repaint);

  final Stopwatch watch;

  static final _points = () {
    final rnd = math.Random(7);
    return List.generate(
      240,
      (_) => (
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        r: rnd.nextDouble() * 1.2 + 0.3,
        phase: rnd.nextDouble() * math.pi * 2,
        speed: rnd.nextDouble() * 1.5 + 0.4,
        rose: rnd.nextDouble() < 0.18,
      ),
    );
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = watch.elapsedMicroseconds / 1e6;
    final paint = Paint();
    for (final s in _points) {
      final a = 0.2 + 0.55 * (0.5 + 0.5 * math.sin(t * s.speed + s.phase));
      paint.color = (s.rose ? Rq.accentHover : Rq.text).withValues(alpha: a);
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.r, paint);
    }

    // A shooting star every nine seconds.
    const period = 9.0;
    const life = 0.9;
    final cycle = t % period;
    if (cycle < life) {
      final rnd = math.Random((t ~/ period) + 1);
      final start = Offset(size.width * (0.1 + rnd.nextDouble() * 0.7), size.height * rnd.nextDouble() * 0.4);
      final dir = Offset(1, 0.35 + rnd.nextDouble() * 0.3) / 1.1;
      final p = cycle / life;
      final head = start + dir * (p * size.shortestSide * 0.6);
      final tail = head - dir * 120;
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(tail, head, [
            Colors.transparent,
            Rq.text.withValues(alpha: 0.9 * (1 - p)),
          ]),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => false;
}

// ----------------------------------------------------------------- widgets

class _Nebula extends StatelessWidget {
  const _Nebula();

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF15112B), Color(0xFF1C1424), Rq.bgDeep],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.7, -0.35),
            radius: 0.9,
            colors: [Rq.accent.withValues(alpha: 0.12), Colors.transparent],
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.85, 0.7),
            radius: 0.8,
            colors: [Color(0x266C5CE7), Colors.transparent],
          ),
        ),
      ),
    ]);
  }
}

class _Frosted extends StatelessWidget {
  const _Frosted({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Rq.border.withValues(alpha: 0.7)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Rq.surface.withValues(alpha: 0.55), Rq.bgDeep.withValues(alpha: 0.55)],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.label, required this.showLabel, required this.onTap});

  final IconData icon;
  final String label;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Rq.accent.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Rq.accent.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 9, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: Rq.accent),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Text(label, style: Rq.body(size: 13, weight: FontWeight.w500, color: Rq.text)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.value, required this.label, required this.color});

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(_fmt(value), style: Rq.mono(size: 12, weight: FontWeight.w700, color: color)),
        const SizedBox(width: 5),
        Text(label, style: Rq.mono(size: 11, color: Rq.textSoft)),
      ]),
    );
  }
}

class _StarChip extends StatelessWidget {
  const _StarChip({required this.memory, required this.onTap});

  final Memory memory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = memory;
    return Material(
      color: m.kind.color.withValues(alpha: 0.1),
      shape: StadiumBorder(side: BorderSide(color: m.kind.color.withValues(alpha: 0.35))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: m.kind.color),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '#${m.id} ${m.title}',
                  style: Rq.mono(size: 11, color: Rq.textSoft),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
