import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/mock.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';

// Console: the omarchy panel as a terminal. Same keyboard model (j/k move,
// h/l across the action buttons, Enter activates, r/o/a, Esc back), plus a
// command palette, a typed-out request log, and CRT scanlines. Every key has
// a tap equivalent so it still works on a phone over tailscale.

const _bg = Color(0xFF140E0E);
const _rowH = 28.0;
const _paletteRowH = 30.0;
const _spinner = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏';

TextStyle _glow(TextStyle s, [Color? c]) =>
    s.copyWith(shadows: [Shadow(color: (c ?? s.color ?? Rq.accent).withValues(alpha: 0.55), blurRadius: 8)]);

enum _Section { actions, records }

class _Action {
  const _Action(this.id, this.key, this.label);
  final String id;
  final String key;
  final String label;
}

const _actions = [
  _Action('open', 'o', 'Open'),
  _Action('remember', 'a', 'Remember'),
  _Action('refresh', 'r', 'Refresh'),
];

class _PaletteItem {
  const _PaletteItem(this.label, this.hint, this.run, {this.icon = Icons.chevron_right, this.color});
  final String label;
  final String hint;
  final VoidCallback run;
  final IconData icon;
  final Color? color;
}

class ConsoleConcept extends StatefulWidget {
  const ConsoleConcept({super.key});

  @override
  State<ConsoleConcept> createState() => _ConsoleConceptState();
}

class _ConsoleConceptState extends State<ConsoleConcept> with SingleTickerProviderStateMixin {
  final _focus = FocusNode(debugLabel: 'console');
  final _records = ScrollController();
  final _paletteScroll = ScrollController();
  final _query = TextEditingController();
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1060))..repeat();
  final _rng = math.Random(7);

  _Section _section = _Section.records;
  int _actionIndex = 0;
  int _recentIndex = 0;
  Kind? _kind;
  String? _project;

  bool _paletteOpen = false;
  int _paletteSel = 0;
  bool _rememberOpen = false;

  // The log types itself out: finished lines in _log, the line in flight in
  // _typing, the rest queued in _pending.
  final _log = <String>[];
  final _pending = <String>[];
  String? _typing;
  int _typed = 0;
  int _pause = 0;
  int _spin = 0;
  bool _refreshing = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _enqueue([
      '\$ reqall status',
      '→ tools/call list_records … 200 OK 84ms',
      '✓ signed in as ${account.email} · key from ${account.keySource}',
    ]);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _blink.dispose();
    _focus.dispose();
    _records.dispose();
    _paletteScroll.dispose();
    _query.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- data

  List<Memory> get _rows => [
        for (final m in memories)
          if ((_kind == null || m.kind == _kind) && (_project == null || m.project == _project)) m,
      ];

  Memory? get _selected {
    final rows = _rows;
    if (rows.isEmpty) return null;
    return rows[_recentIndex.clamp(0, rows.length - 1)];
  }

  Memory? _byId(int id) {
    final i = memories.indexWhere((m) => m.id == id);
    return i < 0 ? null : memories[i];
  }

  String _ms() => '${40 + _rng.nextInt(90)}ms';

  // ------------------------------------------------------------- log

  void _enqueue(List<String> lines) {
    _pending.addAll(lines);
    _ticker ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    setState(() {
      _spin++;
      if (_pause > 0) {
        _pause--;
        return;
      }
      if (_typing == null) {
        if (_pending.isEmpty) {
          _ticker?.cancel();
          _ticker = null;
          _refreshing = false;
          return;
        }
        _typing = _pending.removeAt(0);
        _typed = 0;
      }
      _typed = math.min(_typed + 2, _typing!.length);
      if (_typed >= _typing!.length) {
        _log.add(_typing!);
        if (_log.length > 60) _log.removeAt(0);
        _typing = null;
        _pause = 6 + _rng.nextInt(18);
      }
    });
  }

  // ------------------------------------------------------------- actions

  void _run(String id) {
    switch (id) {
      case 'open':
        _openDashboard();
      case 'remember':
        _openRemember();
      case 'refresh':
        _refresh();
    }
  }

  void _openDashboard() =>
      _enqueue(['\$ xdg-open https://${account.host}/dashboard', '✓ opened the dashboard in your browser']);

  void _openRecord(Memory m) =>
      _enqueue(['\$ xdg-open https://${account.host}/dashboard#records/${m.id}', '✓ opened #${m.id}']);

  void _refresh() {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    _enqueue([
      '\$ reqall refresh',
      '→ tools/call list_records {status:open, kind:todo} … 200 OK ${_ms()}',
      '→ tools/call list_records {status:open, kind:issue} … 200 OK ${_ms()}',
      '→ tools/call list_records {limit:${memories.length}} … 200 OK ${_ms()}',
      '→ tools/call list_projects … 200 OK ${_ms()}',
      '✓ ${account.memories} memories · ${account.openTodos} todo · ${account.openIssues} issues · ${account.projects} projects',
    ]);
  }

  void _openRemember() => setState(() => _rememberOpen = true);

  void _closeRemember() {
    setState(() => _rememberOpen = false);
    _focus.requestFocus();
  }

  void _remembered(String title) {
    _closeRemember();
    _enqueue([
      '\$ reqall remember "$title"',
      '→ tools/call upsert_record … 200 OK ${_ms()}',
      '✓ remembered',
    ]);
  }

  void _setFilter({Kind? kind, String? project}) {
    setState(() {
      if (kind != null) _kind = kind;
      if (project != null) _project = project;
      _section = _Section.records;
      _recentIndex = 0;
    });
    _enqueue([
      '\$ filter ${kind != null ? 'kind:${kind.name}' : 'project:$project'}',
      '✓ ${_rows.length} of ${memories.length} records',
    ]);
  }

  void _clearFilters({bool kind = true, bool project = true}) {
    setState(() {
      if (kind) _kind = null;
      if (project) _project = null;
      _recentIndex = 0;
    });
  }

  void _goto(int id) {
    setState(() {
      _kind = null;
      _project = null;
      final i = memories.indexWhere((m) => m.id == id);
      if (i >= 0) {
        _section = _Section.records;
        _recentIndex = i;
      }
    });
    _scrollToCursor();
  }

  void _back() => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);

  // ------------------------------------------------------------- cursor

  void _move(int dx, int dy) {
    final rows = _rows;
    setState(() {
      if (_section == _Section.actions) {
        if (dx != 0) _actionIndex = (_actionIndex + dx).clamp(0, _actions.length - 1);
        if (dy > 0 && rows.isNotEmpty) {
          _section = _Section.records;
          _recentIndex = 0;
        }
      } else if (dy < 0) {
        if (_recentIndex > 0) {
          _recentIndex--;
        } else {
          _section = _Section.actions;
        }
      } else if (dy > 0 && _recentIndex < rows.length - 1) {
        _recentIndex++;
      }
    });
    _scrollToCursor();
  }

  void _activate() {
    if (_section == _Section.actions) {
      _run(_actions[_actionIndex].id);
    } else {
      final m = _selected;
      if (m != null) _openRecord(m);
    }
  }

  void _scrollToCursor() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(_records, _recentIndex, _rowH));

  void _ensureVisible(ScrollController c, int index, double h) {
    if (!c.hasClients) return;
    final p = c.position;
    final top = index * h;
    final bottom = top + h;
    double? to;
    if (top < p.pixels) {
      to = top;
    } else if (bottom > p.pixels + p.viewportDimension) {
      to = bottom - p.viewportDimension;
    }
    if (to != null) {
      c.animateTo(to.clamp(0, p.maxScrollExtent), duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    }
  }

  // ------------------------------------------------------------- palette

  void _openPalette() {
    setState(() {
      _paletteOpen = true;
      _paletteSel = 0;
      _query.clear();
    });
  }

  void _closePalette() {
    setState(() => _paletteOpen = false);
    _focus.requestFocus();
  }

  void _movePalette(int delta) {
    final n = _paletteItems().length;
    if (n == 0) return;
    setState(() => _paletteSel = (_paletteSel + delta).clamp(0, n - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(_paletteScroll, _paletteSel, _paletteRowH));
  }

  // Both the key handler and onSubmitted land here on desktop; the first
  // closes the palette so the second is a no-op.
  void _runPalette() {
    if (!_paletteOpen) return;
    final items = _paletteItems();
    if (items.isEmpty) return;
    final item = items[_paletteSel.clamp(0, items.length - 1)].$1;
    _closePalette();
    item.run();
  }

  List<_PaletteItem> _allItems() => [
        _PaletteItem('remember', 'a · add a memory', _openRemember, icon: Icons.bookmark_add_outlined),
        _PaletteItem('refresh', 'r · re-fetch', _refresh, icon: Icons.refresh),
        _PaletteItem('open dashboard', 'o · ${account.host}', _openDashboard, icon: Icons.open_in_new),
        if (_kind != null || _project != null)
          _PaletteItem('clear filters', 'esc', _clearFilters, icon: Icons.filter_alt_off_outlined),
        _PaletteItem('concepts', 'back to the picker', _back, icon: Icons.grid_view_rounded),
        for (final k in Kind.values)
          _PaletteItem('kind:${k.name}', 'filter', () => _setFilter(kind: k), icon: k.icon, color: k.color),
        for (final p in projects)
          _PaletteItem('project:${p.name}', '${p.count}', () => _setFilter(project: p.name), icon: Icons.folder_outlined),
        for (final m in memories)
          _PaletteItem('#${m.id} ${m.title}', 'goto · ${m.kind.name}', () => _goto(m.id), icon: m.kind.icon, color: m.kind.color),
      ];

  List<(_PaletteItem, List<int>)> _paletteItems() {
    final q = _query.text.trim();
    final all = _allItems();
    if (q.isEmpty) return [for (final it in all) (it, const <int>[])];
    final scored = <(_PaletteItem, int, int, List<int>)>[];
    for (var i = 0; i < all.length; i++) {
      final r = _fuzzy(q, all[i].label);
      if (r != null) scored.add((all[i], r.$1, i, r.$2));
    }
    scored.sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
    return [for (final s in scored) (s.$1, s.$4)];
  }

  /// Subsequence match: consecutive hits and word starts score higher.
  static (int, List<int>)? _fuzzy(String query, String text) {
    final t = text.toLowerCase();
    final q = query.toLowerCase();
    var from = 0;
    var last = -2;
    var score = 0;
    final hits = <int>[];
    for (var qi = 0; qi < q.length; qi++) {
      final c = q[qi];
      if (c == ' ') continue;
      final at = t.indexOf(c, from);
      if (at < 0) return null;
      score += at == last + 1 ? 6 : 1;
      if (at == 0 || ' :/#.-'.contains(t[at - 1])) score += 4;
      hits.add(at);
      last = at;
      from = at + 1;
    }
    return (score - t.length ~/ 24, hits);
  }

  // ------------------------------------------------------------- keys

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final mod = hw.isControlPressed || hw.isMetaPressed;
    final repeat = event is KeyRepeatEvent;
    final enter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;

    if (_paletteOpen) {
      if (key == LogicalKeyboardKey.escape) {
        _closePalette();
      } else if (key == LogicalKeyboardKey.arrowDown || (mod && key == LogicalKeyboardKey.keyJ)) {
        _movePalette(1);
      } else if (key == LogicalKeyboardKey.arrowUp || (mod && key == LogicalKeyboardKey.keyK)) {
        _movePalette(-1);
      } else if (enter && !repeat) {
        _runPalette();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (_rememberOpen) {
      if (key != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
      _closeRemember();
      return KeyEventResult.handled;
    }

    if (mod && key == LogicalKeyboardKey.keyK) {
      _openPalette();
      return KeyEventResult.handled;
    }
    if (mod) return KeyEventResult.ignored;

    if (event.character == ':' || event.character == '/') {
      _openPalette();
    } else if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.arrowDown) {
      _move(0, 1);
    } else if (key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.arrowUp) {
      _move(0, -1);
    } else if (key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.arrowLeft) {
      _move(-1, 0);
    } else if (key == LogicalKeyboardKey.keyL || key == LogicalKeyboardKey.arrowRight) {
      _move(1, 0);
    } else if (repeat) {
      return KeyEventResult.ignored;
    } else if (enter) {
      _activate();
    } else if (key == LogicalKeyboardKey.keyR) {
      _refresh();
    } else if (key == LogicalKeyboardKey.keyO) {
      _openDashboard();
    } else if (key == LogicalKeyboardKey.keyA) {
      _openRemember();
    } else if (key == LogicalKeyboardKey.escape) {
      if (_kind != null || _project != null) {
        _clearFilters();
      } else {
        _back();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------- build

  Widget _tap(VoidCallback onTap, Widget child) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            onTap();
            if (!_paletteOpen && !_rememberOpen) _focus.requestFocus();
          },
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: LayoutBuilder(builder: (context, box) => _layout(box.maxWidth >= 820)),
            ),
          ),
          if (_rememberOpen) _rememberOverlay(),
          if (_paletteOpen) _paletteOverlay(),
          const Positioned.fill(
            child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _CrtPainter()))),
          ),
        ]),
      ),
    );
  }

  Widget _layout(bool wide) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _statusLine(wide),
      const SizedBox(height: 16),
      _actionBar(wide),
      const SizedBox(height: 16),
      Expanded(
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 3, child: _recordsBox(wide)),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: _previewBox()),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _recordsBox(wide)),
                const SizedBox(height: 16),
                SizedBox(height: 160, child: _previewBox()),
              ]),
      ),
      const SizedBox(height: 16),
      SizedBox(height: wide ? 112 : 78, child: _logBox()),
      const SizedBox(height: 6),
      _footer(wide),
    ]);
  }

  Widget _statusLine(bool wide) {
    final muted = Rq.mono(size: 12, color: Rq.muted);
    Widget stat(int n, String label) => Text.rich(TextSpan(children: [
          TextSpan(text: '$n', style: Rq.mono(size: 12, weight: FontWeight.w700)),
          TextSpan(text: ' $label', style: muted),
        ]));
    final status = _refreshing ? '${_spinner[(_spin ~/ 4) % _spinner.length]} sync' : '● ok';
    return Row(children: [
      Expanded(
        child: Wrap(spacing: 14, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: 'reqall', style: _glow(Rq.mono(size: 12, weight: FontWeight.w700, color: Rq.accent))),
            TextSpan(text: '@${account.host}', style: Rq.mono(size: 12, color: Rq.textSoft)),
          ])),
          Text(status, style: _glow(Rq.mono(size: 12, color: _refreshing ? Rq.warning : Rq.success))),
          stat(account.memories, 'memories'),
          stat(account.openTodos, 'todo'),
          stat(account.openIssues, 'issues'),
          stat(account.projects, 'projects'),
          if (wide) Text('key: ${account.keySource}', style: muted),
        ]),
      ),
      const SizedBox(width: 8),
      const ConceptsButton(),
    ]);
  }

  Widget _actionBar(bool wide) {
    return _TuiBox(
      title: 'actions',
      active: _section == _Section.actions,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Row(children: [
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < _actions.length; i++) _actionButton(i),
          ]),
        ),
        const SizedBox(width: 8),
        _tap(
          _openPalette,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Rq.accent.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(wide ? '⌘K palette' : '⌘K', style: _glow(Rq.mono(size: 12, color: Rq.accent))),
          ),
        ),
      ]),
    );
  }

  Widget _actionButton(int i) {
    final a = _actions[i];
    final on = _section == _Section.actions && _actionIndex == i;
    final fg = on ? _bg : Rq.text;
    return _tap(
      () {
        setState(() {
          _section = _Section.actions;
          _actionIndex = i;
        });
        _run(a.id);
      },
      AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: on ? Rq.accent : Colors.transparent,
          border: Border.all(color: on ? Rq.accent : Rq.border),
          borderRadius: BorderRadius.circular(3),
          boxShadow: on ? [BoxShadow(color: Rq.accent.withValues(alpha: 0.35), blurRadius: 12)] : null,
        ),
        child: Text.rich(TextSpan(style: Rq.mono(size: 12, weight: on ? FontWeight.w700 : FontWeight.w500, color: fg), children: [
          const TextSpan(text: '['),
          TextSpan(
            text: a.key,
            style: TextStyle(color: on ? _bg : Rq.accent, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
          ),
          TextSpan(text: '] ${a.label}'),
        ])),
      ),
    );
  }

  Widget _recordsBox(bool wide) {
    final rows = _rows;
    final chips = [
      if (_kind != null) ('kind:${_kind!.name}', () => _clearFilters(project: false)),
      if (_project != null) ('project:${shortProject(_project!)}', () => _clearFilters(kind: false)),
    ];
    return _TuiBox(
      title: 'records',
      trailing: '${rows.length}/${memories.length}',
      active: _section == _Section.records,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (label, clear) in chips)
                _tap(
                  clear,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Rq.accent.withValues(alpha: 0.12),
                      border: Border.all(color: Rq.accent.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('$label ×', style: Rq.mono(size: 11, color: Rq.accent)),
                  ),
                ),
            ]),
          ),
        _recordHeader(wide),
        Container(height: 1, color: Rq.border.withValues(alpha: 0.6)),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text('no records match · esc clears filters', style: Rq.mono(size: 12, color: Rq.muted)))
              : ListView.builder(
                  controller: _records,
                  itemExtent: _rowH,
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _recordRow(rows[i], i, wide),
                ),
        ),
      ]),
    );
  }

  Widget _recordHeader(bool wide) {
    final s = Rq.mono(size: 10, weight: FontWeight.w600, color: Rq.muted);
    return SizedBox(
      height: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          SizedBox(width: 66, child: Text('KIND', style: s)),
          SizedBox(width: 50, child: Text('ID', style: s)),
          Expanded(child: Text('TITLE', style: s)),
          if (wide) SizedBox(width: 140, child: Text('PROJECT', style: s)),
          SizedBox(width: 34, child: Text('AGE', style: s, textAlign: TextAlign.right)),
        ]),
      ),
    );
  }

  Widget _recordRow(Memory m, int i, bool wide) {
    final selected = _recentIndex == i;
    final on = selected && _section == _Section.records;
    final muted = Rq.mono(size: 11, color: Rq.muted);
    return _tap(
      () {
        if (on) {
          _openRecord(m);
        } else {
          setState(() {
            _section = _Section.records;
            _recentIndex = i;
          });
        }
      },
      AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: on
              ? Rq.accent.withValues(alpha: 0.16)
              : selected
                  ? Rq.surface.withValues(alpha: 0.35)
                  : null,
          border: Border(left: BorderSide(color: on ? Rq.accent : Colors.transparent, width: 2)),
        ),
        child: Row(children: [
          SizedBox(
            width: 66,
            child: Row(children: [
              Icon(m.kind.icon, size: 13, color: m.kind.color),
              const SizedBox(width: 5),
              Flexible(child: Text(m.kind.name, style: Rq.mono(size: 12, color: m.kind.color), overflow: TextOverflow.clip, softWrap: false)),
            ]),
          ),
          SizedBox(width: 50, child: Text('#${m.id}', style: muted)),
          Expanded(
            child: Text(
              m.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: on
                  ? _glow(Rq.mono(size: 12, weight: FontWeight.w600), Rq.accent)
                  : Rq.mono(size: 12, color: Rq.textSoft),
            ),
          ),
          if (wide)
            SizedBox(
              width: 140,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(shortProject(m.project), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ),
            ),
          SizedBox(width: 34, child: Text(relativeAge(m.age), textAlign: TextAlign.right, style: muted)),
        ]),
      ),
    );
  }

  Widget _previewBox() {
    final m = _selected;
    if (m == null) {
      return _TuiBox(
        title: 'preview',
        child: Center(child: Text('nothing selected', style: Rq.mono(size: 12, color: Rq.muted))),
      );
    }
    final statusColor = switch (m.status) {
      'open' => Rq.warning,
      'active' => Rq.success,
      _ => Rq.muted,
    };
    final outgoing = m.links;
    final incoming = [for (final o in memories) if (o.links.contains(m.id)) o.id];
    return _TuiBox(
      title: 'preview',
      trailing: '#${m.id}',
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(m.kind.icon, size: 14, color: m.kind.color),
            const SizedBox(width: 6),
            Text(m.kind.name, style: Rq.mono(size: 12, weight: FontWeight.w700, color: m.kind.color)),
            const SizedBox(width: 10),
            Text('[${m.status}]', style: Rq.mono(size: 11, color: statusColor)),
            const Spacer(),
            Text('${relativeAge(m.age)} ago', style: Rq.mono(size: 11, color: Rq.muted)),
          ]),
          const SizedBox(height: 8),
          Text(m.title, style: _glow(Rq.mono(size: 14, weight: FontWeight.w700), Rq.accent)),
          const SizedBox(height: 4),
          Text(m.project, style: Rq.mono(size: 11, color: Rq.accent)),
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: [
            TextSpan(
              text: m.body.isEmpty ? '(no body) ' : '${m.body} ',
              style: Rq.mono(size: 12, color: m.body.isEmpty ? Rq.muted : Rq.textSoft),
            ),
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: _BlinkCursor(_blink)),
          ])),
          if (outgoing.isNotEmpty || incoming.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('links', style: Rq.mono(size: 10, weight: FontWeight.w600, color: Rq.muted)),
            const SizedBox(height: 4),
            for (final id in outgoing) _linkRow('→', id),
            for (final id in incoming) _linkRow('←', id),
          ],
        ]),
      ),
    );
  }

  Widget _linkRow(String arrow, int id) {
    final target = _byId(id);
    return _tap(
      () => _goto(id),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(
          TextSpan(style: Rq.mono(size: 11, color: Rq.textSoft), children: [
            TextSpan(text: '$arrow ', style: const TextStyle(color: Rq.accent)),
            TextSpan(text: '#$id ', style: const TextStyle(color: Rq.muted)),
            if (target != null) ...[
              TextSpan(text: '${target.kind.name} ', style: TextStyle(color: target.kind.color)),
              TextSpan(text: target.title),
            ] else
              const TextSpan(text: '(another project)', style: TextStyle(color: Rq.muted)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _logBox() {
    return _TuiBox(
      title: 'log',
      trailing: _refreshing ? _spinner[(_spin ~/ 4) % _spinner.length] : null,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
      child: ListView(reverse: true, padding: EdgeInsets.zero, children: [
        if (_typing != null) _logLine(_typing!.substring(0, _typed), typing: true),
        for (final line in _log.reversed) _logLine(line),
      ]),
    );
  }

  Widget _logLine(String line, {bool typing = false}) {
    return Text.rich(
      TextSpan(children: [
        _logSpan(line),
        if (typing) WidgetSpan(alignment: PlaceholderAlignment.middle, child: _BlinkCursor(_blink, height: 11)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextSpan _logSpan(String line) {
    final base = Rq.mono(size: 11, color: Rq.textSoft);
    if (line.startsWith('\$')) return TextSpan(text: line, style: _glow(base.copyWith(color: Rq.accent)));
    if (line.startsWith('✓')) return TextSpan(text: line, style: base.copyWith(color: Rq.success));
    final ok = line.indexOf('200 OK');
    if (ok >= 0) {
      return TextSpan(style: base, children: [
        TextSpan(text: line.substring(0, ok)),
        TextSpan(text: line.substring(ok), style: const TextStyle(color: Rq.success)),
      ]);
    }
    return TextSpan(text: line, style: base);
  }

  Widget _footer(bool wide) {
    final keys = wide
        ? const [
            ('j/k', 'move'),
            ('h/l', 'actions'),
            ('⏎', 'open'),
            ('r', 'refresh'),
            ('o', 'dashboard'),
            ('a', 'remember'),
            (':', 'palette'),
            ('esc', 'back'),
          ]
        : const [('tap', 'select'), ('tap again', 'open'), ('⌘K', 'palette')];
    return Wrap(spacing: 14, runSpacing: 2, children: [
      for (final (k, v) in keys)
        Text.rich(TextSpan(children: [
          TextSpan(text: k, style: Rq.mono(size: 11, weight: FontWeight.w700, color: Rq.accent)),
          TextSpan(text: ' $v', style: Rq.mono(size: 11, color: Rq.muted)),
        ])),
    ]);
  }

  Widget _barrier(VoidCallback onTap) => Positioned.fill(
        child: GestureDetector(onTap: onTap, child: Container(color: Colors.black.withValues(alpha: 0.55))),
      );

  Widget _paletteOverlay() {
    final items = _paletteItems();
    final sel = items.isEmpty ? 0 : _paletteSel.clamp(0, items.length - 1);
    return Positioned.fill(
      child: Stack(children: [
        _barrier(_closePalette),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 72, 12, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: _TuiBox(
                title: 'command',
                trailing: '${items.length}',
                active: true,
                fill: _bg,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Text('› ', style: _glow(Rq.mono(size: 15, weight: FontWeight.w700, color: Rq.accent))),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        autofocus: true,
                        style: _glow(Rq.mono(size: 14), Rq.accent),
                        cursorColor: Rq.accent,
                        cursorWidth: 9,
                        cursorHeight: 18,
                        decoration: InputDecoration.collapsed(
                          hintText: 'remember, kind:issue, project:…, #7910',
                          hintStyle: Rq.mono(size: 13, color: Rq.muted),
                        ),
                        onChanged: (_) => setState(() => _paletteSel = 0),
                        onSubmitted: (_) => _runPalette(),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Container(height: 1, color: Rq.border),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 10 * _paletteRowH),
                    child: items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('no matches', style: Rq.mono(size: 12, color: Rq.muted)),
                          )
                        : ListView.builder(
                            controller: _paletteScroll,
                            shrinkWrap: true,
                            itemExtent: _paletteRowH,
                            itemCount: items.length,
                            itemBuilder: (context, i) => _paletteRow(items[i].$1, items[i].$2, i == sel, i),
                          ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _paletteRow(_PaletteItem it, List<int> hits, bool on, int i) {
    return _tap(
      () {
        setState(() => _paletteSel = i);
        _runPalette();
      },
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: on ? Rq.accent.withValues(alpha: 0.16) : null,
          border: Border(left: BorderSide(color: on ? Rq.accent : Colors.transparent, width: 2)),
        ),
        child: Row(children: [
          Icon(it.icon, size: 14, color: it.color ?? Rq.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              _highlight(it.label, hits, Rq.mono(size: 13, color: on ? Rq.text : Rq.textSoft)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(it.hint, style: Rq.mono(size: 11, color: Rq.muted)),
        ]),
      ),
    );
  }

  TextSpan _highlight(String s, List<int> hits, TextStyle base) {
    if (hits.isEmpty) return TextSpan(text: s, style: base);
    const hit = TextStyle(color: Rq.accent, fontWeight: FontWeight.w700);
    final marks = hits.toSet();
    final spans = <TextSpan>[];
    final buf = StringBuffer();
    bool? current;
    for (var i = 0; i < s.length; i++) {
      final h = marks.contains(i);
      if (current != null && h != current) {
        spans.add(TextSpan(text: buf.toString(), style: current ? hit : null));
        buf.clear();
      }
      current = h;
      buf.write(s[i]);
    }
    if (buf.isNotEmpty) spans.add(TextSpan(text: buf.toString(), style: current == true ? hit : null));
    return TextSpan(style: base, children: spans);
  }

  Widget _rememberOverlay() {
    return Positioned.fill(
      child: Stack(children: [
        _barrier(_closeRemember),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _TuiBox(
                title: 'remember',
                trailing: 'esc',
                active: true,
                fill: _bg,
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                child: RememberForm(dense: true, onSaved: _remembered),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A box with its title cut into the top border: ╭─┤ title ├──╮
class _TuiBox extends StatelessWidget {
  const _TuiBox({
    required this.title,
    required this.child,
    this.active = false,
    this.trailing,
    this.fill,
    this.padding = const EdgeInsets.fromLTRB(10, 14, 10, 8),
  });

  final String title;
  final Widget child;
  final bool active;
  final String? trailing;
  final Color? fill;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final label = Rq.mono(size: 11, weight: FontWeight.w600, color: active ? Rq.accent : Rq.muted);
    return Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: padding,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? Rq.accent : Rq.border),
          boxShadow: active ? [BoxShadow(color: Rq.accent.withValues(alpha: 0.12), blurRadius: 18)] : null,
        ),
        child: child,
      ),
      Positioned(
        left: 10,
        top: -8,
        child: Container(
          color: _bg,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('┤ $title ├', style: active ? _glow(label) : label),
        ),
      ),
      if (trailing != null)
        Positioned(
          right: 10,
          top: -8,
          child: Container(
            color: _bg,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('┤ ${trailing!} ├', style: label.copyWith(color: Rq.muted)),
          ),
        ),
    ]);
  }
}

class _BlinkCursor extends AnimatedWidget {
  const _BlinkCursor(Animation<double> blink, {this.height = 14}) : super(listenable: blink);

  final double height;

  @override
  Widget build(BuildContext context) {
    final on = (listenable as Animation<double>).value < 0.5;
    return Container(
      width: height * 0.6,
      height: height,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: on ? Rq.accent : Colors.transparent,
        boxShadow: on ? [BoxShadow(color: Rq.accent.withValues(alpha: 0.6), blurRadius: 6)] : null,
      ),
    );
  }
}

/// Scanlines, a warm glow from the top, and a vignette, painted over everything.
class _CrtPainter extends CustomPainter {
  const _CrtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -1.2),
          radius: 1.2,
          colors: [Rq.accent.withValues(alpha: 0.06), Colors.transparent],
        ).createShader(rect),
    );
    final line = Paint()..color = const Color(0x1F000000);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.95,
          colors: [Color(0x00000000), Color(0x8C000000)],
          stops: [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _CrtPainter oldDelegate) => false;
}
