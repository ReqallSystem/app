import '../shared/theme.dart';
import 'mcp_client.dart';
import 'models.dart';

/// Everything the app reads from or writes to Reqall. [LiveRepository] talks
/// to the MCP endpoint; the demo repository serves the mock account.
abstract class ReqallRepository {
  Future<AccountSummary> summary();
  Future<RecordPage> records({int limit = 50, int offset = 0});
  Future<List<Project>> projects();
  Future<MemoryDetail> detail(int id);
  Future<Memory> remember({required Project project, required String title, String body = '', Kind? kind});
  Future<Memory> setStatus(int id, String status);
  void close() {}
}

class LiveRepository implements ReqallRepository {
  LiveRepository(this.mcp);

  final McpClient mcp;

  static int _total(Map<String, dynamic> data) => (data['total'] as num?)?.toInt() ?? 0;

  @override
  Future<AccountSummary> summary() async {
    final results = await Future.wait([
      mcp.call('list_records', {'limit': 1}),
      mcp.call('list_records', {'limit': 1, 'status': 'open', 'kind': 'todo'}),
      mcp.call('list_records', {'limit': 1, 'status': 'open', 'kind': 'issue'}),
      mcp.call('list_projects', {'limit': 1}),
    ]);
    return AccountSummary(
      memories: _total(results[0]),
      openTodos: _total(results[1]),
      openIssues: _total(results[2]),
      projects: _total(results[3]),
    );
  }

  @override
  Future<RecordPage> records({int limit = 50, int offset = 0}) async {
    final data = await mcp.call('list_records', {'limit': limit.clamp(1, 100), 'offset': offset});
    final list = (data['records'] as List? ?? const []).whereType<Map<String, dynamic>>().map(Memory.fromJson).toList();
    return RecordPage(list, _total(data));
  }

  @override
  Future<List<Project>> projects() async {
    final out = <Project>[];
    for (var offset = 0; offset < 1000; offset += 100) {
      final data = await mcp.call('list_projects', {'limit': 100, 'offset': offset});
      final page = (data['projects'] as List? ?? const []).whereType<Map<String, dynamic>>().map(Project.fromJson).toList();
      out.addAll(page);
      if (page.length < 100 || out.length >= _total(data)) break;
    }
    return out;
  }

  @override
  Future<MemoryDetail> detail(int id) async {
    final results = await Future.wait([
      mcp.call('get_record', {'id': id}),
      mcp.call('list_links', {'entity_id': id, 'entity_type': 'records', 'direction': 'both', 'limit': 50}),
    ]);
    final memory = Memory.fromJson(results[0]['record'] as Map<String, dynamic>);
    final links = <MemoryLink>[];
    for (final l in (results[1]['links'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      final outgoing = l['source_table'] == 'records' && (l['source_id'] as num?)?.toInt() == id;
      final otherTable = outgoing ? l['target_table'] : l['source_table'];
      if (otherTable != 'records') continue;
      final other = ((outgoing ? l['target_id'] : l['source_id']) as num).toInt();
      links.add(MemoryLink(otherId: other, relationship: (l['relationship'] ?? 'related').toString(), outgoing: outgoing));
    }
    return MemoryDetail(memory, links);
  }

  @override
  Future<Memory> remember({required Project project, required String title, String body = '', Kind? kind}) async {
    final data = await mcp.call('upsert_record', {
      'project_id': project.id,
      'title': title,
      if (body.isNotEmpty) 'body': body,
      'kind': ?kind?.name,
    });
    final memory = Memory.fromJson(data['record'] as Map<String, dynamic>);
    return memory.project.isEmpty ? memory.copyWith(project: project.name) : memory;
  }

  @override
  Future<Memory> setStatus(int id, String status) async {
    final data = await mcp.call('upsert_record', {'id': id, 'status': status});
    return Memory.fromJson(data['record'] as Map<String, dynamic>);
  }

  @override
  void close() => mcp.close();
}
