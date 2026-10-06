import '../shared/theme.dart';
import 'models.dart';
import 'repository.dart';

/// The mock account from the design workshop, served behind the repository
/// interface so the app runs offline ("Try the demo") and in widget tests.
class DemoRepository implements ReqallRepository {
  DemoRepository({this.latency = const Duration(milliseconds: 250)}) : _records = _seed();

  final Duration latency;
  final List<Memory> _records;
  final Map<int, List<int>> _links = {
    7910: [7908, 6472],
    7908: [6472],
    7902: [6472],
    7895: [6472, 7902],
    7881: [6472],
    7874: [7895],
    7799: [7895],
    7790: [7799],
  };

  static const _projects = <Project>[
    Project(8557, 'ReqallSystem/app', 3),
    Project(4946, '.machine/omarchy/fingerskier', 212),
    Project(84, 'fingerskier/reqall_admin', 48),
    Project(17, 'osteostrong/believer_app', 391),
    Project(144, 'turingautomations/pbm_crossx', 77),
    Project(12, 'ReqallSystem/core', 640),
    Project(31, 'ReqallSystem/desktop-app', 58),
    Project(2, '.user', 96),
  ];

  int _added = 0;

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<AccountSummary> summary() async {
    await _wait();
    return AccountSummary(memories: 7910 + _added, openTodos: 23, openIssues: 9, projects: 41);
  }

  @override
  Future<RecordPage> records({int limit = 50, int offset = 0}) async {
    await _wait();
    final sorted = List.of(_records)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return RecordPage(sorted.skip(offset).take(limit).toList(), sorted.length);
  }

  @override
  Future<List<Project>> projects() async {
    await _wait();
    return _projects;
  }

  @override
  Future<MemoryDetail> detail(int id) async {
    await _wait();
    final memory = _records.firstWhere((m) => m.id == id);
    final links = <MemoryLink>[
      for (final other in _links[id] ?? const <int>[]) MemoryLink(otherId: other, relationship: 'related', outgoing: true),
      for (final e in _links.entries)
        if (e.value.contains(id)) MemoryLink(otherId: e.key, relationship: 'related', outgoing: false),
    ];
    return MemoryDetail(memory, links);
  }

  @override
  Future<Memory> remember({required Project project, required String title, String body = '', Kind? kind}) async {
    await _wait();
    _added++;
    final memory = Memory(
      id: 7920 + _added,
      title: title,
      body: body,
      kind: kind ?? Kind.info,
      status: kind == Kind.todo || kind == Kind.issue || kind == Kind.spec ? 'open' : 'active',
      project: project.name,
      projectId: project.id,
      updatedAt: DateTime.now(),
    );
    _records.add(memory);
    return memory;
  }

  @override
  Future<Memory> setStatus(int id, String status) async {
    await _wait();
    final i = _records.indexWhere((m) => m.id == id);
    _records[i] = _records[i].copyWith(status: status, updatedAt: DateTime.now());
    return _records[i];
  }

  @override
  void close() {}

  static List<Memory> _seed() {
    final now = DateTime.now();
    Memory m(int id, String title, Kind kind, String status, String project, Duration age, [String body = '']) =>
        Memory(id: id, title: title, body: body, kind: kind, status: status, project: project, updatedAt: now.subtract(age));
    return [
      m(7910, 'UI: Flutter app UI concept workshop — 4 directions', Kind.spec, 'open', 'ReqallSystem/app',
          const Duration(minutes: 3), 'Hearth, Constellation, Stream and Console, all on shared mock data, served over tailscale.'),
      m(7908, 'Flutter app skeleton created at flutter/ (reqall_app, org net.reqall)', Kind.work, 'active', 'ReqallSystem/app',
          const Duration(minutes: 34), 'flutter create with android, ios, linux, macos, windows, web. Analyze clean, tests pass.'),
      m(7902, 'Tray menu ignores left-click on Hyprland app-indicators', Kind.issue, 'open', 'ReqallSystem/desktop-app',
          const Duration(hours: 2, minutes: 10), 'Linux indicators route left-click to the menu; panel open must be a menu item.'),
      m(7895, 'Credential order: setting > env > ~/.config/reqall/env > config.json', Kind.arch, 'active', 'ReqallSystem/core',
          const Duration(hours: 5), 'Parsed, never sourced. Shared by the plugin, desktop app and CLI.'),
      m(7881, 'Add per-record deep links (dashboard#records/<id>)', Kind.todo, 'open', 'ReqallSystem/desktop-app',
          const Duration(hours: 9)),
      m(7874, 'Mock MCP server covers JSON + SSE replies', Kind.test, 'active', 'ReqallSystem/desktop-app',
          const Duration(hours: 20), 'node:test against a local HTTP server; auth states ok/none/invalid/paused/error.'),
      m(7860, 'Hyprland gaps 8 → 6 on the ultrawide', Kind.info, 'active', '.machine/omarchy/fingerskier',
          const Duration(days: 1, hours: 3)),
      m(7841, 'Leaderboard loading-state tests flake on CI', Kind.issue, 'open', 'osteostrong/believer_app',
          const Duration(days: 1, hours: 9)),
      m(7833, 'ValueNotifier state, no framework dependency', Kind.arch, 'active', 'turingautomations/pbm_crossx',
          const Duration(days: 2)),
      m(7820, 'Ship admin app record editor', Kind.todo, 'open', 'fingerskier/reqall_admin', const Duration(days: 2, hours: 6)),
      m(7811, 'Prefer terse commit messages; push the branch you are on', Kind.info, 'active', '.user', const Duration(days: 3)),
      m(7799, 'Semantic search boosts the current project', Kind.spec, 'active', 'ReqallSystem/core', const Duration(days: 4)),
      m(7790, 'SLEEP consolidation merges near-duplicate info records', Kind.work, 'active', 'ReqallSystem/core',
          const Duration(days: 5)),
      m(6472, 'FEAT: Reqall desktop-app with omarchy_plugin parity', Kind.spec, 'resolved', '.machine/omarchy/fingerskier',
          const Duration(days: 17), 'Tray, panel, keyboard nav, fetcher, settings, tests.'),
    ];
  }
}
