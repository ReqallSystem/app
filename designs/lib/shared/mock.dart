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
  email: 'alex@example.com',
  memories: 7910,
  openTodos: 23,
  openIssues: 9,
  projects: 41,
  keySource: '~/.config/reqall/env',
);

const projects = <Project>[
  Project(8557, 'lumen-labs/atlas-app', 3),
  Project(4946, '.machine/devbox/alex', 212),
  Project(84, 'alex/admin-console', 48),
  Project(17, 'quarry-co/harvest-app', 391),
  Project(144, 'tidewater/ledger-sync', 77),
  Project(12, 'lumen-labs/atlas-core', 640),
  Project(31, 'lumen-labs/atlas-desktop', 58),
  Project(2, '.user', 96),
];

const memories = <Memory>[
  Memory(
    id: 7910,
    title: 'UI: Atlas app concept workshop — 4 directions',
    body: 'Four layouts on shared mock data, reviewed on a phone and a laptop.',
    kind: Kind.spec,
    status: 'open',
    project: 'lumen-labs/atlas-app',
    age: Duration(minutes: 3),
    links: [7908, 6472],
  ),
  Memory(
    id: 7908,
    title: 'Atlas app skeleton created for all six platforms',
    body: 'Android, iOS, Linux, macOS, Windows and web targets. Analyze clean, tests pass.',
    kind: Kind.work,
    status: 'active',
    project: 'lumen-labs/atlas-app',
    age: Duration(minutes: 34),
    links: [6472],
  ),
  Memory(
    id: 7902,
    title: 'Tray menu ignores left-click on Linux app indicators',
    body: 'Linux indicators route left-click to the menu; opening the panel must be a menu item.',
    kind: Kind.issue,
    status: 'open',
    project: 'lumen-labs/atlas-desktop',
    age: Duration(hours: 2, minutes: 10),
    links: [6472],
  ),
  Memory(
    id: 7895,
    title: 'Credential order: setting > environment > env file > config file',
    body: 'Parsed, never sourced. Shared by every client.',
    kind: Kind.arch,
    status: 'active',
    project: 'lumen-labs/atlas-core',
    age: Duration(hours: 5),
    links: [6472, 7902],
  ),
  Memory(
    id: 7881,
    title: 'Add per-record deep links to the dashboard',
    kind: Kind.todo,
    status: 'open',
    project: 'lumen-labs/atlas-desktop',
    age: Duration(hours: 9),
    links: [6472],
  ),
  Memory(
    id: 7874,
    title: 'Mock server covers JSON + SSE replies',
    body: 'node:test against a local HTTP server; auth states ok/none/invalid/paused/error.',
    kind: Kind.test,
    status: 'active',
    project: 'lumen-labs/atlas-desktop',
    age: Duration(hours: 20),
    links: [7895],
  ),
  Memory(
    id: 7860,
    title: 'Window gaps 8 → 6 on the wide monitor',
    kind: Kind.info,
    status: 'active',
    project: '.machine/devbox/alex',
    age: Duration(days: 1, hours: 3),
  ),
  Memory(
    id: 6472,
    title: 'FEAT: Atlas desktop app with tray panel parity',
    body: 'Tray, panel, keyboard nav, fetcher, settings, tests.',
    kind: Kind.spec,
    status: 'resolved',
    project: '.machine/devbox/alex',
    age: Duration(days: 17),
  ),
  Memory(
    id: 7841,
    title: 'Leaderboard loading-state tests flake on CI',
    kind: Kind.issue,
    status: 'open',
    project: 'quarry-co/harvest-app',
    age: Duration(days: 1, hours: 9),
  ),
  Memory(
    id: 7833,
    title: 'ValueNotifier state, no framework dependency',
    kind: Kind.arch,
    status: 'active',
    project: 'tidewater/ledger-sync',
    age: Duration(days: 2),
  ),
  Memory(
    id: 7820,
    title: 'Ship the admin record editor',
    kind: Kind.todo,
    status: 'open',
    project: 'alex/admin-console',
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
    project: 'lumen-labs/atlas-core',
    age: Duration(days: 4),
    links: [7895],
  ),
  Memory(
    id: 7790,
    title: 'Nightly consolidation merges near-duplicate notes',
    kind: Kind.work,
    status: 'active',
    project: 'lumen-labs/atlas-core',
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

/// "lumen-labs/atlas-desktop" → "atlas-desktop"; dotted machine/user projects keep their tail.
String shortProject(String name) => name.split('/').last;
