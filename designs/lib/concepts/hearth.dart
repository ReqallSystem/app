import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/mock.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';

/// Hearth: the omarchy panel, warmed up. Same sections in the same order
/// (hero, actions, usage tiles, recent memories, footer) and the same keys,
/// with an ember glow behind it, counters that roll, and a Remember sheet.
class HearthConcept extends StatefulWidget {
  const HearthConcept({super.key});

  @override
  State<HearthConcept> createState() => _HearthConceptState();
}

class _Action {
  const _Action(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

class _HearthConceptState extends State<HearthConcept> with TickerProviderStateMixin {
  late final AnimationController embers = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  final focus = FocusNode();

  AuthState auth = AuthState.ok;
  bool refreshing = false;
  int generation = 0; // bumps on refresh so counters and rows replay
  DateTime updated = DateTime.now();
  final recent = memories.take(8).toList();

  // Panel cursor, as in Panel.qml: actions row, then recent rows.
  bool cursorActive = false;
  bool onActions = true;
  int actionIndex = 0;
  int recentIndex = 0;

  @override
  void dispose() {
    embers.dispose();
    focus.dispose();
    super.dispose();
  }

  bool get signedIn => auth == AuthState.ok;

  List<_Action> get actions => switch (auth) {
        AuthState.ok => const [
            _Action('open', 'Open Reqall', Icons.open_in_new_rounded),
            _Action('remember', 'Remember', Icons.bookmark_add_outlined),
            _Action('refresh', 'Refresh', Icons.refresh_rounded),
          ],
        AuthState.error => const [
            _Action('refresh', 'Retry', Icons.refresh_rounded),
            _Action('open', 'Open Reqall', Icons.open_in_new_rounded),
          ],
        AuthState.loading => const [_Action('refresh', 'Refresh', Icons.refresh_rounded)],
        _ => const [
            _Action('signin', 'Sign in / Sign up', Icons.login_rounded),
            _Action('apikey', 'Get API key', Icons.key_rounded),
            _Action('cli', 'CLI login', Icons.terminal_rounded),
          ],
      };

  void cycleAuth() {
    const order = [AuthState.ok, AuthState.none, AuthState.invalid, AuthState.error];
    setState(() {
      auth = order[(order.indexOf(auth) + 1) % order.length];
      actionIndex = 0;
      onActions = true;
    });
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      refreshing = false;
      generation++;
      updated = DateTime.now();
    });
  }

  void toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text, style: Rq.body(color: Rq.text)),
        backgroundColor: Rq.surface,
        behavior: SnackBarBehavior.floating,
        width: 360,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Rq.border)),
      ));
  }

  void run(String id) {
    switch (id) {
      case 'refresh':
        refresh();
      case 'remember':
        remember();
      case 'open':
        toast('Would open https://reqall.net/dashboard');
      case 'signin':
        toast('Would open https://reqall.net/auth/login');
      case 'apikey':
        toast('Would open https://reqall.net/dashboard#keys');
      case 'cli':
        toast('Would run `reqall login` in a terminal');
    }
  }

  Future<void> remember() async {
    if (!signedIn) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) => _RememberSheet(
        onSaved: (title) {
          Navigator.of(context).pop();
          setState(() {
            recent.insert(
              0,
              Memory(id: 7911 + generation, title: title, kind: Kind.info, status: 'active', project: projects.first.name, age: Duration.zero),
            );
            if (recent.length > 8) recent.removeLast();
          });
          toast('Remembered “$title”');
        },
      ),
    );
    focus.requestFocus();
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rows = signedIn ? recent.length : 0;
    void move(int dx, int dy) {
      setState(() {
        cursorActive = true;
        if (onActions) {
          if (dx != 0) actionIndex = (actionIndex + dx).clamp(0, actions.length - 1);
          if (dy > 0 && rows > 0) {
            onActions = false;
            recentIndex = 0;
          }
        } else {
          if (dy < 0) {
            if (recentIndex > 0) {
              recentIndex--;
            } else {
              onActions = true;
            }
          } else if (dy > 0 && recentIndex < rows - 1) {
            recentIndex++;
          }
        }
      });
    }

    if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.arrowDown) {
      move(0, 1);
    } else if (key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.arrowUp) {
      move(0, -1);
    } else if (key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.arrowLeft) {
      move(-1, 0);
    } else if (key == LogicalKeyboardKey.keyL || key == LogicalKeyboardKey.arrowRight) {
      move(1, 0);
    } else if (key == LogicalKeyboardKey.enter) {
      if (onActions) {
        run(actions[actionIndex.clamp(0, actions.length - 1)].id);
      } else if (rows > 0) {
        toast('Would open record #${recent[recentIndex].id}');
      }
    } else if (key == LogicalKeyboardKey.keyR) {
      refresh();
    } else if (key == LogicalKeyboardKey.keyO) {
      run('open');
    } else if (key == LogicalKeyboardKey.keyA) {
      remember();
    } else if (key == LogicalKeyboardKey.escape) {
      if (cursorActive) {
        setState(() => cursorActive = false);
      } else {
        Navigator.of(context).maybePop();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rq.bgDeep,
      body: Focus(
        focusNode: focus,
        autofocus: true,
        onKeyEvent: onKey,
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: embers,
              builder: (context, _) => CustomPaint(painter: _EmberPainter(embers.value, refreshing)),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 56, 16, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _panel(),
                ),
              ),
            ),
          ),
          const Positioned(top: 12, left: 12, child: SafeArea(child: ConceptsButton())),
        ]),
      ),
    );
  }

  Widget _panel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          decoration: BoxDecoration(
            color: Rq.bg.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Rq.border),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 18))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _hero(),
            const SizedBox(height: 16),
            _actions(),
            const SizedBox(height: 18),
            if (signedIn) ...[
              _tiles(),
              const SizedBox(height: 20),
              _recentHeader(),
              const SizedBox(height: 8),
              _recent(),
            ] else
              _problem(),
            const SizedBox(height: 14),
            _footer(),
          ]),
        ),
      ),
    );
  }

  Widget _hero() {
    final pill = switch (auth) {
      AuthState.ok => ('signed in', Rq.success),
      AuthState.none => ('signed out', Rq.muted),
      AuthState.invalid => ('key rejected', Rq.danger),
      AuthState.paused => ('paused', Rq.warning),
      AuthState.error => ('offline', Rq.danger),
      AuthState.loading => ('loading', Rq.muted),
    };
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Rq.border))),
      child: Row(children: [
        _BreathingMark(active: signedIn),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Wordmark())),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Tap to preview other auth states',
                child: GestureDetector(
                  onTap: cycleAuth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: pill.$2.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: pill.$2.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: pill.$2, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(pill.$1, style: Rq.mono(size: 11, color: pill.$2)),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(signedIn ? '${account.email} · ${account.host}' : account.host,
                style: Rq.mono(size: 12, color: Rq.muted), overflow: TextOverflow.ellipsis),
            if (signedIn)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _Counter(key: ValueKey('m$generation'), value: account.memories, suffix: ' memories',
                    style: Rq.mono(size: 12, color: Rq.accent)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _actions() {
    final list = actions;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < list.length; i++)
        _ActionButton(
          action: list[i],
          primary: i == 0,
          focused: cursorActive && onActions && actionIndex == i,
          spinning: list[i].id == 'refresh' && refreshing,
          onTap: () {
            setState(() {
              onActions = true;
              actionIndex = i;
            });
            run(list[i].id);
          },
        ),
    ]);
  }

  Widget _tiles() {
    final tiles = [
      ('memories', account.memories, Icons.psychology_outlined, Rq.accent),
      ('open todos', account.openTodos, Kind.todo.icon, Kind.todo.color),
      ('open issues', account.openIssues, Kind.issue.icon, Kind.issue.color),
      ('projects', account.projects, Icons.folder_outlined, Kind.info.color),
    ];
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 10) / 2;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < tiles.length; i++)
          SizedBox(
            width: w,
            child: _Tile(
              key: ValueKey('t$i-$generation'),
              label: tiles[i].$1,
              value: tiles[i].$2,
              icon: tiles[i].$3,
              color: tiles[i].$4,
              loading: refreshing,
              delay: i * 90,
            ),
          ),
      ]);
    });
  }

  Widget _recentHeader() {
    return Row(children: [
      Expanded(child: Text('Recent memories', style: Rq.display(size: 15, weight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      Text('${recent.length} of ${account.memories}', style: Rq.mono(size: 11, color: Rq.muted)),
    ]);
  }

  Widget _recent() {
    return Column(children: [
      for (var i = 0; i < recent.length; i++)
        _Entrance(
          key: ValueKey('r${recent[i].id}-$generation'),
          delay: 220 + i * 55,
          child: _MemoryRow(
            memory: recent[i],
            focused: cursorActive && !onActions && recentIndex == i,
            loading: refreshing,
            onTap: () {
              setState(() {
                cursorActive = true;
                onActions = false;
                recentIndex = i;
              });
              toast('Would open record #${recent[i].id}');
            },
          ),
        ),
    ]);
  }

  Widget _problem() {
    final (title, body) = switch (auth) {
      AuthState.invalid => ('That key was rejected', 'The server answered 401. Get a fresh API key or log in from the CLI.'),
      AuthState.error => ('Can’t reach reqall.net', 'The last refresh failed. Check the connection and retry.'),
      _ => ('Not signed in', 'Sign in to see your memories, open work and projects here.'),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Rq.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Rq.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Rq.display(size: 16, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(body, style: Rq.body(size: 13, color: Rq.textSoft)),
      ]),
    );
  }

  Widget _footer() {
    final ago = DateTime.now().difference(updated);
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Rq.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('updated ${ago.inSeconds < 5 ? 'just now' : '${relativeAge(ago)} ago'} · key ${account.keySource}',
            style: Rq.mono(size: 11, color: Rq.muted)),
        const SizedBox(height: 4),
        Text('j/k move · h/l buttons · ⏎ open · r refresh · a remember · o dashboard',
            style: Rq.mono(size: 10.5, color: Rq.muted.withValues(alpha: 0.7))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- pieces

class _BreathingMark extends StatefulWidget {
  const _BreathingMark({required this.active});
  final bool active;

  @override
  State<_BreathingMark> createState() => _BreathingMarkState();
}

class _BreathingMarkState extends State<_BreathingMark> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (widget.active)
              BoxShadow(color: Rq.accent.withValues(alpha: 0.15 + 0.25 * c.value), blurRadius: 14 + 16 * c.value, spreadRadius: 1),
          ],
        ),
        child: Opacity(opacity: widget.active ? 1 : 0.5, child: child),
      ),
      child: const ReqallMark(size: 56, radius: 12),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({required this.action, required this.primary, required this.focused, required this.spinning, required this.onTap});
  final _Action action;
  final bool primary;
  final bool focused;
  final bool spinning;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  bool hover = false;

  @override
  void didUpdateWidget(covariant _ActionButton old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !spin.isAnimating) spin.repeat();
    if (!widget.spinning && spin.isAnimating) spin.forward(from: spin.value).then((_) => spin.reset());
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lit = hover || widget.focused;
    final fg = widget.primary ? Rq.bg : (lit ? Rq.text : Rq.textSoft);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.primary ? (lit ? Rq.accentHover : Rq.accent) : (lit ? Rq.surfaceHover : Rq.surface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.focused ? Rq.text : (lit ? Rq.borderHover : Rq.border), width: widget.focused ? 1.5 : 1),
            boxShadow: [if (widget.primary && lit) BoxShadow(color: Rq.accent.withValues(alpha: 0.35), blurRadius: 18)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            RotationTransition(turns: spin, child: Icon(widget.action.icon, size: 16, color: fg)),
            const SizedBox(width: 8),
            Text(widget.action.label, style: Rq.body(size: 13, weight: FontWeight.w600, color: fg)),
          ]),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({super.key, required this.value, required this.style, this.suffix = '', this.delay = 0});
  final int value;
  final TextStyle style;
  final String suffix;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 1100 + delay),
      curve: Interval(delay / (1100 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, t, _) {
        final n = (value * t).round();
        final s = n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
        return Text('$s$suffix', style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]));
      },
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({super.key, required this.label, required this.value, required this.icon, required this.color, required this.loading, required this.delay});
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool loading;
  final int delay;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.withValues(alpha: hover ? 0.2 : 0.12), Rq.surface.withValues(alpha: 0.4)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hover ? c.withValues(alpha: 0.6) : Rq.border),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              widget.loading
                  ? const _Shimmer(width: 56, height: 26)
                  : _Counter(value: widget.value, delay: widget.delay, style: Rq.display(size: 26, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(widget.label, style: Rq.mono(size: 11, color: Rq.muted)),
            ]),
          ),
          Icon(widget.icon, color: c.withValues(alpha: 0.85), size: 22),
        ]),
      ),
    );
  }
}

class _MemoryRow extends StatefulWidget {
  const _MemoryRow({required this.memory, required this.focused, required this.loading, required this.onTap});
  final Memory memory;
  final bool focused;
  final bool loading;
  final VoidCallback onTap;

  @override
  State<_MemoryRow> createState() => _MemoryRowState();
}

class _MemoryRowState extends State<_MemoryRow> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.memory;
    final lit = hover || widget.focused;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: lit ? Rq.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(color: lit ? m.kind.color : Colors.transparent, width: 3),
            ),
          ),
          child: Row(children: [
            KindBadge(m.kind, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: widget.loading
                  ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Shimmer(width: 220, height: 13),
                      SizedBox(height: 6),
                      _Shimmer(width: 140, height: 10),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.title, style: Rq.body(size: 13.5, weight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 1),
                      Text.rich(
                        TextSpan(style: Rq.mono(size: 11, color: Rq.muted), children: [
                          TextSpan(text: shortProject(m.project)),
                          const TextSpan(text: ' · '),
                          TextSpan(text: m.kind.name, style: TextStyle(color: m.kind.color)),
                          const TextSpan(text: ' · '),
                          TextSpan(text: m.status, style: TextStyle(color: m.isOpen ? Rq.warning : Rq.muted)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
            ),
            const SizedBox(width: 8),
            Text(m.age == Duration.zero ? 'now' : relativeAge(m.age), style: Rq.mono(size: 11, color: Rq.muted)),
          ]),
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({super.key, required this.delay, required this.child});
  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = 380 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.width, required this.height});
  final double width;
  final double height;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: LinearGradient(
            begin: Alignment(-1 + 3 * c.value - 1, 0),
            end: Alignment(1 + 3 * c.value - 1, 0),
            colors: const [Rq.surface, Rq.surfaceHover, Rq.surface],
          ),
        ),
      ),
    );
  }
}

class _RememberSheet extends StatelessWidget {
  const _RememberSheet({required this.onSaved});
  final ValueChanged<String> onSaved;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Rq.bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Rq.border),
              boxShadow: [BoxShadow(color: Rq.accent.withValues(alpha: 0.18), blurRadius: 40)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: Rq.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.bookmark_add_outlined, color: Rq.accent, size: 20),
                const SizedBox(width: 8),
                Text('Remember', style: Rq.display(size: 18)),
              ]),
              const SizedBox(height: 14),
              RememberForm(onSaved: onSaved),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Slow-drifting embers and two breathing glows behind the panel; they
/// quicken while a refresh is in flight.
class _EmberPainter extends CustomPainter {
  _EmberPainter(this.t, this.busy);
  final double t;
  final bool busy;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = Rq.bgDeep);

    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    void glow(Offset c, double r, Color color, double a) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color.withValues(alpha: a), color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(size.width * 0.5, size.height * 1.05), size.shortestSide * (0.75 + 0.08 * pulse), const Color(0xFFE07A4F), 0.22);
    glow(Offset(size.width * 0.15, size.height * 0.05), size.shortestSide * 0.6, Rq.accent, 0.10 + 0.04 * pulse);

    final rng = math.Random(7);
    final speed = busy ? 3.0 : 1.0;
    for (var i = 0; i < 46; i++) {
      final x0 = rng.nextDouble();
      final phase = rng.nextDouble();
      final drift = rng.nextDouble() * 0.06;
      final r = 0.8 + rng.nextDouble() * 2.2;
      final y = (1.1 - ((t * speed + phase) % 1.0) * 1.25);
      final x = x0 + math.sin((t * 2 + phase) * math.pi * 2) * drift;
      final fade = (1 - (1.1 - y) / 1.25).clamp(0.0, 1.0);
      final color = Color.lerp(const Color(0xFFFFB27A), Rq.accent, rng.nextDouble())!;
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        r,
        Paint()
          ..color = color.withValues(alpha: 0.55 * fade)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmberPainter old) => old.t != t || old.busy != busy;
}
