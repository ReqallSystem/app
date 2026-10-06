import '../shared/theme.dart';
import 'api_client.dart';
import 'models.dart';

/// Everything the app reads from or writes to Reqall. [LiveRepository] talks
/// to the REST API; the demo repository serves the mock account.
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
  LiveRepository(this.api);

  final ApiClient api;

  static int _total(dynamic data) => data is Map ? (data['total'] as num?)?.toInt() ?? 0 : 0;

  static Iterable<Map<String, dynamic>> _list(dynamic data, String key) =>
      ((data is Map ? data[key] : data) as List? ?? const []).whereType<Map<String, dynamic>>();

  static Map<String, dynamic> _object(dynamic data) =>
      data is Map<String, dynamic> ? data : throw const ApiException(ApiFailure.server, 'Unexpected response');

  @override
  Future<AccountSummary> summary() async {
    final results = await Future.wait([
      api.get('/records', {'limit': 1}),
      api.get('/records', {'limit': 1, 'status': 'open', 'kind': 'todo'}),
      api.get('/records', {'limit': 1, 'status': 'open', 'kind': 'issue'}),
      api.get('/projects'),
    ]);
    return AccountSummary(
      memories: _total(results[0]),
      openTodos: _total(results[1]),
      openIssues: _total(results[2]),
      projects: _list(results[3], 'projects').length,
    );
  }

  @override
  Future<RecordPage> records({int limit = 50, int offset = 0}) async {
    final data = await api.get('/records', {'limit': limit.clamp(1, 100), 'offset': offset});
    return RecordPage(_list(data, 'records').map(Memory.fromJson).toList(), _total(data));
  }

  /// One unpaged array.
  @override
  Future<List<Project>> projects() async => _list(await api.get('/projects'), 'projects').map(Project.fromJson).toList();

  @override
  Future<MemoryDetail> detail(int id) async {
    final results = await Future.wait([
      api.get('/records/$id'),
      api.get('/records/$id/links', {'direction': 'both', 'limit': 50}),
    ]);
    final memory = Memory.fromJson(_object(results[0]));
    final links = <MemoryLink>[];
    for (final l in _list(results[1], 'links')) {
      final outgoing = l['source_table'] == 'records' && (l['source_id'] as num?)?.toInt() == id;
      final otherTable = outgoing ? l['target_table'] : l['source_table'];
      if (otherTable != 'records') continue;
      final other = ((outgoing ? l['target_id'] : l['source_id']) as num).toInt();
      links.add(MemoryLink(otherId: other, relationship: (l['relationship'] ?? 'related').toString(), outgoing: outgoing));
    }
    return MemoryDetail(memory, links);
  }

  /// The create response has no project_name, so it comes from [project].
  @override
  Future<Memory> remember({required Project project, required String title, String body = '', Kind? kind}) async {
    final data = await api.post('/records', {
      'project_id': project.id,
      'title': title,
      if (body.isNotEmpty) 'body': body,
      'kind': ?kind?.name,
    });
    final memory = Memory.fromJson(_object(data));
    return memory.project.isEmpty ? memory.copyWith(project: project.name) : memory;
  }

  /// The update response has no project_name: [Memory.project] comes back
  /// empty, and callers keep the name they already have.
  @override
  Future<Memory> setStatus(int id, String status) async =>
      Memory.fromJson(_object(await api.patch('/records/$id', {'status': status})));

  @override
  void close() => api.close();
}
