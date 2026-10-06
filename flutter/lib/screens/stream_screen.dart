import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../shared/mock.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';

/// Stream: the account as a river of memories through time.
/// A collapsing hero carries the panel's synopsis; below it, memories run
/// down a kind-coloured rail under sticky day headers. Swipe right to
/// resolve, left to archive, tap to open in place, and a frosted capture bar
/// floats over everything for Remember.
class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

const _maxContent = 720.0;
const _heroExpanded = 290.0;
const _heroCollapsed = 64.0;

class _StreamScreenState extends State<StreamScreen> with TickerProviderStateMixin {
  late final AnimationController _entrance =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  late final Animation<double> _spinTurns = CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic);
  final _scroll = ScrollController();

  late final List<Memory> _items = List.of(memories)..sort((a, b) => a.age.compareTo(b.age));
  Kind? _filter;
  final Set<int> _expanded = {};
  int? _flashId;
  int? _pulseId;
  int _added = 0;
  bool _captureOpen = false;

  @override
  void dispose() {
    _entrance.dispose();
    _spin.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- actions

  Memory _withStatus(Memory m, String status) => Memory(
        id: m.id,
        title: m.title,
        body: m.body,
        kind: m.kind,
        status: status,
        project: m.project,
        age: m.age,
        links: m.links,
      );

  void _refresh() {
    _spin.forward(from: 0);
    _entrance.forward(from: 0);
    _snack('Refreshed from ${account.host}');
  }

  void _toggleResolved(Memory m) {
    final before = m.status;
    final after = m.status == 'resolved' ? 'open' : 'resolved';
    _setStatus(m.id, after);
    if (after == 'resolved') _flash(m.id);
    _snack(after == 'resolved' ? 'Resolved #${m.id}' : 'Reopened #${m.id}', undo: () => _setStatus(m.id, before));
  }

  void _setStatus(int id, String status) {
    final i = _items.indexWhere((m) => m.id == id);
    if (i < 0) return;
    setState(() => _items[i] = _withStatus(_items[i], status));
  }

  void _archive(Memory m) {
    final i = _items.indexWhere((x) => x.id == m.id);
    if (i < 0) return;
    setState(() {
      _items.removeAt(i);
      _expanded.remove(m.id);
    });
    _snack('Archived #${m.id}', undo: () => setState(() => _items.insert(math.min(i, _items.length), m)));
  }

  void _flash(int id) {
    setState(() => _flashId = id);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _flashId == id) setState(() => _flashId = null);
    });
  }

  void _remember(String title) {
    final id = _items.fold<int>(account.memories, (hi, m) => math.max(hi, m.id)) + 1;
    setState(() {
      _items.insert(
        0,
        Memory(id: id, title: title, kind: Kind.info, status: 'open', project: projects.first.name, age: Duration.zero),
      );
      _pulseId = id;
      _added++;
      _captureOpen = false;
      _filter = null;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
    }
    _snack('Remembered #$id');
  }

  void _snack(String message, {VoidCallback? undo}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        backgroundColor: Rq.surfaceHover,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Rq.border)),
        content: Text(message, style: Rq.body(size: 13)),
        action: undo == null ? null : SnackBarAction(label: 'Undo', textColor: Rq.accent, onPressed: undo),
      ));
  }

  // ------------------------------------------------------------- grouping

  static const _days = ['Today', 'Yesterday', 'This week', 'Earlier'];

  String _dayOf(Memory m) {
    final now = DateTime.now();
    final days = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(m.updatedAt)).inDays;
    if (days <= 0) return _days[0];
    if (days == 1) return _days[1];
    if (days < 7) return _days[2];
    return _days[3];
  }

  Memory? _lookup(int id) {
    for (final m in _items) {
      if (m.id == id) return m;
    }
    for (final m in memories) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Outgoing links plus anything that links here.
  List<int> _linked(Memory m) {
    final ids = <int>{...m.links};
    for (final other in [..._items, ...memories]) {
      if (other.links.contains(m.id)) ids.add(other.id);
    }
    ids.remove(m.id);
    return ids.toList();
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = math.max(16.0, (width - _maxContent) / 2);
    final visible = _items.where((m) => _filter == null || m.kind == _filter).toList();
    final groups = <String, List<Memory>>{};
    for (final m in visible) {
      groups.putIfAbsent(_dayOf(m), () => []).add(m);
    }

    var index = 0;
    final slivers = <Widget>[
      _hero(),
      SliverToBoxAdapter(child: _filterRow(pad)),
    ];
    for (final day in _days) {
      final group = groups[day];
      if (group == null) continue;
      slivers.add(SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        sliver: SliverMainAxisGroup(slivers: [
          SliverPersistentHeader(pinned: true, delegate: _DayHeader(day, group.length)),
          SliverList.list(children: [
            for (var i = 0; i < group.length; i++)
              _stagger(
                index++,
                _row(group[i], prev: i > 0 ? group[i - 1] : null, next: i < group.length - 1 ? group[i + 1] : null),
              ),
          ]),
        ]),
      ));
    }
    if (visible.isEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text('Nothing here — the stream is quiet.',
              textAlign: TextAlign.center, style: Rq.body(color: Rq.muted)),
        ),
      ));
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 140)));

    return Scaffold(
      backgroundColor: Rq.bg,
      body: Stack(children: [
        CustomScrollView(controller: _scroll, slivers: slivers),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _maxContent), child: _captureBar()),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------- hero

  Widget _hero() {
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      expandedHeight: _heroExpanded,
      collapsedHeight: _heroCollapsed,
      toolbarHeight: _heroCollapsed,
      backgroundColor: Rq.bg,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: LayoutBuilder(builder: (context, box) {
        final t = ((box.maxHeight - _heroCollapsed) / (_heroExpanded - _heroCollapsed)).clamp(0.0, 1.0);
        final full = ((t - 0.25) / 0.75).clamp(0.0, 1.0);
        final compact = (1 - t * 2).clamp(0.0, 1.0);
        return Stack(fit: StackFit.expand, clipBehavior: Clip.hardEdge, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.8, -1.3),
                radius: 1.4,
                colors: [Color.lerp(const Color(0xFF4A2D2A), Rq.bg, 1 - t)!, Rq.bg],
              ),
              border: const Border(bottom: BorderSide(color: Rq.border)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: full < 0.5,
              child: Opacity(opacity: full, child: _centred(_heroFull())),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _heroCollapsed,
            child: IgnorePointer(
              ignoring: compact < 0.5,
              child: Opacity(opacity: compact, child: _centred(_heroCompact())),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _centred(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContent + 32),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child),
        ),
      );

  int get _total => account.memories + _added;

  Widget _heroFull() {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const ReqallMark(size: 48, glow: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Wordmark(size: 22),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Rq.success,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Rq.success.withValues(alpha: 0.6), blurRadius: 6)],
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(account.email,
                      overflow: TextOverflow.ellipsis, style: Rq.body(size: 12, color: Rq.textSoft)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                    color: Rq.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(account.host, style: Rq.mono(size: 11, color: Rq.accent)),
                ),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _total.toDouble()),
                duration: const Duration(milliseconds: 1400),
                curve: Curves.easeOutExpo,
                builder: (context, v, _) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (r) =>
                        const LinearGradient(colors: [Rq.text, Rq.accent]).createShader(r),
                    child: Text(_fmt(v.round()), style: Rq.display(size: 52, weight: FontWeight.w800)),
                  ),
                ),
              ),
              Text('memories', style: Rq.mono(size: 12, color: Rq.muted)),
            ]),
          ),
          FilledButton.icon(
            onPressed: () => _snack('Would open https://${account.host}/dashboard'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open Reqall'),
            style: FilledButton.styleFrom(
              backgroundColor: Rq.accent.withValues(alpha: 0.16),
              foregroundColor: Rq.accent,
              side: BorderSide(color: Rq.accent.withValues(alpha: 0.4)),
            ),
          ),
          const SizedBox(width: 8),
          _refreshButton(),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Pill(color: Kind.todo.color, value: account.openTodos, label: 'open todos'),
          _Pill(color: Kind.issue.color, value: account.openIssues, label: 'open issues'),
          _Pill(color: Rq.accent, value: account.projects, label: 'projects'),
        ]),
      ]),
    );
  }

  Widget _heroCompact() {
    return Row(children: [
      const ReqallMark(size: 30, radius: 7),
      const SizedBox(width: 10),
      const Wordmark(size: 18),
      const Spacer(),
      Text(_fmt(_total), style: Rq.mono(size: 13, weight: FontWeight.w700, color: Rq.accent)),
      const SizedBox(width: 4),
      _refreshButton(size: 34),
    ]);
  }

  Widget _refreshButton({double size = 40}) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(side: BorderSide(color: Rq.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _refresh,
          child: RotationTransition(
            turns: _spinTurns,
            child: Icon(Icons.refresh_rounded, size: size * 0.5, color: Rq.textSoft),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- filter

  Widget _filterRow(double pad) {
    final allSelected = _filter == null;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(pad, 14, pad, 8),
        children: [
          GestureDetector(
            onTap: () => setState(() => _filter = null),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: allSelected ? Rq.accent.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: allSelected ? Rq.accent : Rq.border),
              ),
              child: Text('all · ${_items.length}', style: Rq.mono(size: 11, color: allSelected ? Rq.accent : Rq.textSoft)),
            ),
          ),
          for (final k in Kind.values) ...[
            const SizedBox(width: 6),
            KindChip(k, selected: _filter == k, onTap: () => setState(() => _filter = _filter == k ? null : k)),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- rows

  Widget _stagger(int i, Widget child) {
    final start = math.min(i * 0.07, 0.6);
    final interval = Interval(start, start + 0.4);
    return AnimatedBuilder(
      animation: _entrance,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(interval.transform(_entrance.value));
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child));
      },
    );
  }

  Widget _row(Memory m, {Memory? prev, Memory? next}) {
    return Stack(children: [
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: 28,
        child: CustomPaint(
          painter: _RailPainter(
            color: m.kind.color,
            prev: prev?.kind.color,
            next: next?.kind.color,
            resolved: m.status == 'resolved',
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 36, bottom: 12),
        child: Dismissible(
          key: ValueKey('stream-${m.id}'),
          background: _swipeBackground(
            Alignment.centerLeft,
            Rq.success,
            m.status == 'resolved' ? Icons.undo_rounded : Icons.check_circle_outline,
            m.status == 'resolved' ? 'reopen' : 'resolve',
          ),
          secondaryBackground: _swipeBackground(Alignment.centerRight, Rq.muted, Icons.archive_outlined, 'archive'),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              _toggleResolved(m);
              return false;
            }
            return true;
          },
          onDismissed: (_) => _archive(m),
          child: _pulse(m, _card(m)),
        ),
      ),
    ]);
  }

  Widget _swipeBackground(Alignment align, Color color, IconData icon, String label) {
    final left = align == Alignment.centerLeft;
    return Container(
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!left) Text(label, style: Rq.mono(size: 11, color: color)),
        if (!left) const SizedBox(width: 8),
        Icon(icon, color: color),
        if (left) const SizedBox(width: 8),
        if (left) Text(label, style: Rq.mono(size: 11, color: color)),
      ]),
    );
  }

  Widget _pulse(Memory m, Widget card) {
    if (m.id != _pulseId) return card;
    return TweenAnimationBuilder<double>(
      key: ValueKey('pulse-${m.id}'),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 2000),
      curve: Curves.easeOut,
      child: card,
      builder: (context, v, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Rq.accent.withValues(alpha: 0.55 * v), blurRadius: 26 * v, spreadRadius: 2 * v),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _card(Memory m) {
    final open = _expanded.contains(m.id);
    final resolved = m.status == 'resolved';
    final flashing = _flashId == m.id;
    final linked = _linked(m);
    final statusColor = switch (m.status) {
      'open' => Rq.accent,
      'resolved' => Rq.success,
      _ => Rq.muted,
    };

    return GestureDetector(
      onTap: () => setState(() => open ? _expanded.remove(m.id) : _expanded.add(m.id)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: flashing ? Color.alphaBlend(Rq.success.withValues(alpha: 0.18), Rq.surface) : Rq.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: flashing
                ? Rq.success
                : open
                    ? m.kind.color.withValues(alpha: 0.5)
                    : Rq.border,
          ),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KindBadge(m.kind, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    m.title,
                    maxLines: open ? null : 2,
                    overflow: open ? null : TextOverflow.ellipsis,
                    style: Rq.body(size: 15, weight: FontWeight.w600, color: resolved ? Rq.textSoft : Rq.text),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(style: Rq.mono(size: 11, color: Rq.muted), children: [
                      TextSpan(text: shortProject(m.project)),
                      const TextSpan(text: ' · '),
                      TextSpan(text: m.kind.name, style: TextStyle(color: m.kind.color)),
                      const TextSpan(text: ' · '),
                      TextSpan(text: m.status, style: TextStyle(color: statusColor)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(relativeAge(m.age), style: Rq.mono(size: 11, color: Rq.muted)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                    child: child,
                  ),
                  child: resolved
                      ? const Icon(Icons.check_circle_rounded, key: ValueKey('done'), size: 18, color: Rq.success)
                      : const SizedBox(key: ValueKey('todo'), width: 18, height: 18),
                ),
              ]),
            ]),
            if (m.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                m.body,
                maxLines: open ? null : 2,
                overflow: open ? null : TextOverflow.ellipsis,
                style: Rq.body(size: 13, color: Rq.textSoft),
              ),
            ],
            if (linked.isNotEmpty && !open) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.link_rounded, size: 14, color: Rq.muted),
                const SizedBox(width: 4),
                Text('${linked.length} linked', style: Rq.mono(size: 11, color: Rq.muted)),
              ]),
            ],
            if (open) ..._details(m, linked),
          ]),
        ),
      ),
    );
  }

  List<Widget> _details(Memory m, List<int> linked) {
    return [
      const SizedBox(height: 12),
      Container(height: 1, color: Rq.border),
      const SizedBox(height: 10),
      if (linked.isEmpty) Text('No links yet', style: Rq.mono(size: 11, color: Rq.muted)),
      for (final id in linked)
        Builder(builder: (context) {
          final other = _lookup(id);
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded.add(id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                if (other != null) KindBadge(other.kind, size: 20) else const SizedBox(width: 20),
                const SizedBox(width: 8),
                Text('#$id', style: Rq.mono(size: 11, color: Rq.accent)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(other?.title ?? 'not loaded',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Rq.body(size: 12, color: Rq.textSoft)),
                ),
              ]),
            ),
          );
        }),
      const SizedBox(height: 10),
      Row(children: [
        Text('#${m.id}', style: Rq.mono(size: 11, color: Rq.muted)),
        const Spacer(),
        Text('→ resolve   ← archive', style: Rq.mono(size: 10, color: Rq.muted)),
      ]),
    ];
  }

  // ------------------------------------------------------------- capture

  Widget _captureBar() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Rq.accent.withValues(alpha: _captureOpen ? 0.28 : 0.16), blurRadius: 30, spreadRadius: 1),
          const BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            padding: EdgeInsets.all(_captureOpen ? 16 : 6),
            decoration: BoxDecoration(
              color: Rq.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Rq.accent.withValues(alpha: _captureOpen ? 0.6 : 0.3)),
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: _captureOpen ? _captureForm() : _captureCollapsed(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _captureCollapsed() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _captureOpen = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          const Icon(Icons.bookmark_add_outlined, color: Rq.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text('Remember something…', style: Rq.body(size: 15, color: Rq.muted))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Rq.accent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('+', style: Rq.mono(size: 14, weight: FontWeight.w700, color: Rq.bg)),
          ),
        ]),
      ),
    );
  }

  Widget _captureForm() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.bookmark_add_outlined, color: Rq.accent, size: 20),
        const SizedBox(width: 8),
        Text('Remember', style: Rq.display(size: 17)),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _captureOpen = false),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Rq.textSoft),
        ),
      ]),
      const SizedBox(height: 8),
      RememberForm(dense: true, onSaved: _remember),
    ]);
  }
}

String _fmt(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.value, required this.label});

  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$value', style: Rq.mono(size: 12, weight: FontWeight.w700, color: color)),
        const SizedBox(width: 4),
        Text(label, style: Rq.body(size: 12, color: Rq.textSoft)),
      ]),
    );
  }
}

class _DayHeader extends SliverPersistentHeaderDelegate {
  _DayHeader(this.label, this.count);

  final String label;
  final int count;

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Rq.bg.withValues(alpha: 0.94),
      alignment: Alignment.centerLeft,
      child: Row(children: [
        Text(label, style: Rq.display(size: 14, weight: FontWeight.w600, color: Rq.accent)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(color: Rq.surface, borderRadius: BorderRadius.circular(999)),
          child: Text('$count', style: Rq.mono(size: 10, color: Rq.muted)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Rq.border, Rq.border.withValues(alpha: 0)]),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  bool shouldRebuild(_DayHeader old) => old.label != label || old.count != count;
}

/// One segment of the timeline rail: blends from the previous memory's kind
/// colour into this one, then on toward the next, with a glowing node.
class _RailPainter extends CustomPainter {
  _RailPainter({required this.color, this.prev, this.next, this.resolved = false});

  final Color color;
  final Color? prev;
  final Color? next;
  final bool resolved;

  static const nodeY = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint();

    void segment(double top, double bottom, Color a, Color b) {
      if (bottom <= top) return;
      final rect = Rect.fromLTRB(x - 1, top, x + 1, bottom);
      line.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [a, b],
      ).createShader(rect);
      canvas.drawRect(rect, line);
    }

    if (prev != null) {
      segment(0, nodeY, Color.lerp(prev, color, 0.5)!, color);
    } else {
      segment(nodeY - 22, nodeY, color.withValues(alpha: 0), color);
    }
    if (next != null) {
      segment(nodeY, size.height, color, Color.lerp(color, next, 0.5)!);
    } else {
      segment(nodeY, math.min(size.height, nodeY + 44), color, color.withValues(alpha: 0));
    }

    final center = Offset(x, nodeY);
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    if (resolved) {
      canvas.drawCircle(center, 5, Paint()..color = Rq.bg);
      canvas.drawCircle(
        center,
        5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawCircle(center, 5.5, Paint()..color = color);
      canvas.drawCircle(center, 2, Paint()..color = Rq.bg);
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.color != color || old.prev != prev || old.next != next || old.resolved != resolved;
}
