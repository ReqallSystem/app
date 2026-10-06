import '../shared/theme.dart';

/// One Reqall record, as list_records / get_record / upsert_record return it.
/// list_records carries no body, so [body] is null until get_record fills it.
class Memory {
  const Memory({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
    required this.project,
    required this.updatedAt,
    this.projectId,
    this.body,
  });

  final int id;
  final String title;
  final String? body;
  final Kind kind;
  final String status;
  final String project;
  final int? projectId;
  final DateTime updatedAt;

  Duration get age {
    final d = DateTime.now().difference(updatedAt);
    return d.isNegative ? Duration.zero : d;
  }

  bool get isOpen => status == 'open';

  Memory copyWith({String? status, String? body, String? project, DateTime? updatedAt}) => Memory(
        id: id,
        title: title,
        kind: kind,
        status: status ?? this.status,
        project: project ?? this.project,
        projectId: projectId,
        updatedAt: updatedAt ?? this.updatedAt,
        body: body ?? this.body,
      );

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
        id: (j['id'] as num).toInt(),
        title: (j['title'] ?? '').toString(),
        body: j['body'] as String?,
        kind: kindFromName(j['kind']?.toString()),
        status: (j['status'] ?? 'open').toString(),
        project: (j['project_name'] ?? j['project'] ?? '').toString(),
        projectId: (j['project_id'] as num?)?.toInt(),
        updatedAt: DateTime.tryParse((j['updated_at'] ?? j['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      );
}

Kind kindFromName(String? name) {
  for (final k in Kind.values) {
    if (k.name == name) return k;
  }
  return Kind.work;
}

class Project {
  const Project(this.id, this.name, [this.count = 0]);

  final int id;
  final String name;
  final int count;

  factory Project.fromJson(Map<String, dynamic> j) =>
      Project((j['id'] as num).toInt(), (j['name'] ?? '').toString(), (j['record_count'] as num?)?.toInt() ?? 0);

  @override
  bool operator ==(Object other) => other is Project && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A link between two records, seen from one of them.
class MemoryLink {
  const MemoryLink({required this.otherId, required this.relationship, required this.outgoing});

  final int otherId;
  final String relationship;
  final bool outgoing;
}

/// Body and links for one record, fetched when its card opens.
class MemoryDetail {
  const MemoryDetail(this.memory, this.links);

  final Memory memory;
  final List<MemoryLink> links;
}

/// The panel's synopsis: the same four numbers the omarchy widget shows.
class AccountSummary {
  const AccountSummary({required this.memories, required this.openTodos, required this.openIssues, required this.projects});

  final int memories;
  final int openTodos;
  final int openIssues;
  final int projects;

  static const empty = AccountSummary(memories: 0, openTodos: 0, openIssues: 0, projects: 0);

  AccountSummary adjust({int memories = 0}) =>
      AccountSummary(memories: this.memories + memories, openTodos: openTodos, openIssues: openIssues, projects: projects);
}

/// A page of records plus the total the server reports.
class RecordPage {
  const RecordPage(this.records, this.total);

  final List<Memory> records;
  final int total;
}

String relativeAge(Duration age) {
  if (age.inMinutes < 1) return 'now';
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  if (age.inDays < 7) return '${age.inDays}d';
  if (age.inDays < 365) return '${age.inDays ~/ 7}w';
  return '${age.inDays ~/ 365}y';
}

/// "lumen-labs/atlas-desktop" → "atlas-desktop"; dotted machine/user projects keep their tail.
String shortProject(String name) => name.split('/').last;
