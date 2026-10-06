import 'theme.dart';

/// Stand-in data for the concept workshop. The shapes follow what the omarchy
/// plugin reads from the MCP endpoint (list_records ×3 + list_projects), so a
/// real fetcher can drop in later without touching the concepts.
class Memory {
  const Memory({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
    required this.project,
    required this.age,
    this.body = '',
    this.links = const [],
  });

  final int id;
  final String title;
  final String body;
  final Kind kind;
  final String status;
  final String project;
  final Duration age;
  final List<int> links;

  DateTime get updatedAt => DateTime.now().subtract(age);
  bool get isOpen => status == 'open';
}

class Project {
  const Project(this.id, this.name, this.count);
  final int id;
  final String name;
  final int count;
}

enum AuthState { ok, loading, none, invalid, paused, error }

class Account {
  const Account({
    required this.auth,
    required this.host,
    required this.email,
    required this.memories,
    required this.openTodos,
    required this.openIssues,
    required this.projects,
    required this.keySource,
  });

  final AuthState auth;
  final String host;
  final String email;
  final int memories;
  final int openTodos;
  final int openIssues;
  final int projects;
  final String keySource;
}

const account = Account(
  auth: AuthState.ok,
  host: 'reqall.net',
  email: 'fingerskier@gmail.com',
  memories: 7910,
  openTodos: 23,
  openIssues: 9,
  projects: 41,
  keySource: '~/.config/reqall/env',
);

const projects = <Project>[
  Project(8557, 'ReqallSystem/app', 3),
  Project(4946, '.machine/omarchy/fingerskier', 212),
  Project(84, 'fingerskier/reqall_admin', 48),
  Project(17, 'osteostrong/believer_app', 391),
  Project(144, 'turingautomations/pbm_crossx', 77),
  Project(12, 'ReqallSystem/core', 640),
  Project(31, 'ReqallSystem/desktop-app', 58),
  Project(2, '.user', 96),
];

const memories = <Memory>[
  Memory(
    id: 7910,
    title: 'UI: Flutter app UI concept workshop — 4 directions',
    body: 'Hearth, Constellation, Stream and Console, all on shared mock data, served over tailscale.',
    kind: Kind.spec,
    status: 'open',
    project: 'ReqallSystem/app',
    age: Duration(minutes: 3),
    links: [7908, 6472],
  ),
  Memory(
    id: 7908,
    title: 'Flutter app skeleton created at flutter/ (reqall_app, org net.reqall)',
    body: 'flutter create with android, ios, linux, macos, windows, web. Analyze clean, tests pass.',
    kind: Kind.work,
    status: 'active',
    project: 'ReqallSystem/app',
    age: Duration(minutes: 34),
    links: [6472],
  ),
  Memory(
    id: 7902,
    title: 'Tray menu ignores left-click on Hyprland app-indicators',
    body: 'Linux indicators route left-click to the menu; panel open must be a menu item.',
    kind: Kind.issue,
    status: 'open',
    project: 'ReqallSystem/desktop-app',
    age: Duration(hours: 2, minutes: 10),
    links: [6472],
  ),
  Memory(
    id: 7895,
    title: 'Credential order: setting > env > ~/.config/reqall/env > config.json',
    body: 'Parsed, never sourced. Shared by the plugin, desktop app and CLI.',
    kind: Kind.arch,
    status: 'active',
    project: 'ReqallSystem/core',
    age: Duration(hours: 5),
    links: [6472, 7902],
  ),
  Memory(
    id: 7881,
    title: 'Add per-record deep links (dashboard#records/<id>)',
    kind: Kind.todo,
    status: 'open',
    project: 'ReqallSystem/desktop-app',
    age: Duration(hours: 9),
    links: [6472],
  ),
  Memory(
    id: 7874,
    title: 'Mock MCP server covers JSON + SSE replies',
    body: 'node:test against a local HTTP server; auth states ok/none/invalid/paused/error.',
    kind: Kind.test,
    status: 'active',
    project: 'ReqallSystem/desktop-app',
    age: Duration(hours: 20),
    links: [7895],
  ),
  Memory(
    id: 7860,
    title: 'Hyprland gaps 8 → 6 on the ultrawide',
    kind: Kind.info,
    status: 'active',
    project: '.machine/omarchy/fingerskier',
    age: Duration(days: 1, hours: 3),
  ),
  Memory(
    id: 6472,
    title: 'FEAT: Reqall desktop-app with omarchy_plugin parity',
    body: 'Tray, panel, keyboard nav, fetcher, settings, tests.',
    kind: Kind.spec,
    status: 'resolved',
    project: '.machine/omarchy/fingerskier',
    age: Duration(days: 17),
  ),
  Memory(
    id: 7841,
    title: 'Leaderboard loading-state tests flake on CI',
    kind: Kind.issue,
    status: 'open',
    project: 'osteostrong/believer_app',
    age: Duration(days: 1, hours: 9),
  ),
  Memory(
    id: 7833,
    title: 'ValueNotifier state, no framework dependency',
    kind: Kind.arch,
    status: 'active',
    project: 'turingautomations/pbm_crossx',
    age: Duration(days: 2),
  ),
  Memory(
    id: 7820,
    title: 'Ship admin app record editor',
    kind: Kind.todo,
    status: 'open',
    project: 'fingerskier/reqall_admin',
    age: Duration(days: 2, hours: 6),
  ),
  Memory(
    id: 7811,
    title: 'Prefer terse commit messages; push the branch you are on',
    kind: Kind.info,
    status: 'active',
    project: '.user',
    age: Duration(days: 3),
  ),
  Memory(
    id: 7799,
    title: 'Semantic search boosts the current project',
    kind: Kind.spec,
    status: 'active',
    project: 'ReqallSystem/core',
    age: Duration(days: 4),
    links: [7895],
  ),
  Memory(
    id: 7790,
    title: 'SLEEP consolidation merges near-duplicate info records',
    kind: Kind.work,
    status: 'active',
    project: 'ReqallSystem/core',
    age: Duration(days: 5),
    links: [7799],
  ),
];

String relativeAge(Duration age) {
  if (age.inMinutes < 1) return 'now';
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  if (age.inDays < 7) return '${age.inDays}d';
  return '${age.inDays ~/ 7}w';
}

/// "ReqallSystem/desktop-app" → "desktop-app"; dotted machine/user projects keep their tail.
String shortProject(String name) => name.split('/').last;
