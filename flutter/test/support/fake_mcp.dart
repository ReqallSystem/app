import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory Reqall MCP server behind package:http's MockClient. Answers
/// tools/call for the tools the app uses, plus /oauth/token.
class FakeMcp {
  FakeMcp({this.validTokens = const {'good-key'}, this.sse = false});

  Set<String> validTokens;
  bool sse;
  int? forceStatus;
  bool failWrites = false;
  final calls = <String>[];
  final tokenRequests = <Map<String, String>>[];
  final authHeaders = <String>[];

  /// Answer for /oauth/token; null means 400 invalid_grant.
  Map<String, dynamic>? tokenResponse;

  final records = <Map<String, dynamic>>[
    for (var i = 0; i < 60; i++)
      {
        'id': 1000 - i,
        'project_id': i.isEven ? 1 : 2,
        'project_name': i.isEven ? 'ReqallSystem/app' : '.user',
        'kind': ['spec', 'issue', 'todo', 'info'][i % 4],
        'title': 'Record ${1000 - i}',
        'status': i % 4 == 1 || i % 4 == 2 ? 'open' : 'active',
        'updated_at': DateTime.utc(2026, 10, 5, 12).subtract(Duration(hours: i)).toIso8601String(),
      },
  ];

  final projects = [
    {'id': 1, 'name': 'ReqallSystem/app', 'record_count': 30},
    {'id': 2, 'name': '.user', 'record_count': 30},
  ];

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    if (req.url.path == '/oauth/token') {
      tokenRequests.add(req.bodyFields);
      final r = tokenResponse;
      return r == null
          ? http.Response(jsonEncode({'error': 'invalid_grant'}), 400)
          : http.Response(jsonEncode(r), 200, headers: {'content-type': 'application/json'});
    }
    final auth = req.headers['Authorization'] ?? '';
    authHeaders.add(auth);
    if (forceStatus != null) return http.Response('{"message":"forced"}', forceStatus!);
    if (!validTokens.contains(auth.replaceFirst('Bearer ', ''))) {
      return http.Response(jsonEncode({'message': 'Invalid token'}), 401);
    }
    final rpc = jsonDecode(req.body) as Map<String, dynamic>;
    final params = rpc['params'] as Map<String, dynamic>;
    final name = params['name'] as String;
    final args = (params['arguments'] as Map).cast<String, dynamic>();
    calls.add(name);
    final data = _tool(name, args);
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': rpc['id'],
      'result': data == null
          ? {
              'isError': true,
              'content': [
                {'type': 'text', 'text': 'Record not found or access denied'}
              ],
            }
          : {
              'content': [
                {'type': 'text', 'text': 'ok'}
              ],
              'structuredContent': {'ok': true, 'data': data},
            },
    });
    return sse
        ? http.Response('event: message\ndata: $payload\n\n', 200, headers: {'content-type': 'text/event-stream'})
        : http.Response(payload, 200, headers: {'content-type': 'application/json'});
  }

  Map<String, dynamic>? _tool(String name, Map<String, dynamic> a) {
    switch (name) {
      case 'list_records':
        var list = records.where((r) =>
            (a['kind'] == null || r['kind'] == a['kind']) && (a['status'] == null || r['status'] == a['status']));
        final all = list.toList();
        final offset = (a['offset'] as int?) ?? 0;
        final limit = (a['limit'] as int?) ?? 50;
        return {
          'records': all.skip(offset).take(limit).toList(),
          'total': all.length,
          'limit': limit,
          'offset': offset,
        };
      case 'list_projects':
        return {'projects': projects, 'total': projects.length, 'limit': 100, 'offset': 0};
      case 'get_record':
        final r = records.where((r) => r['id'] == a['id']).firstOrNull;
        return r == null ? null : {'record': {...r, 'body': 'Body of ${r['id']}'}};
      case 'list_links':
        final id = a['entity_id'];
        return {
          'links': [
            {'id': 1, 'source_id': id, 'source_table': 'records', 'target_id': 999, 'target_table': 'records', 'relationship': 'implements'},
            {'id': 2, 'source_id': 998, 'source_table': 'records', 'target_id': id, 'target_table': 'records', 'relationship': 'related'},
            {'id': 3, 'source_id': id, 'source_table': 'records', 'target_id': 1, 'target_table': 'projects', 'relationship': 'related'},
          ],
          'total': 3,
          'limit': 50,
          'offset': 0,
        };
      case 'upsert_record':
        if (failWrites) return null;
        if (a['id'] != null) {
          final r = records.firstWhere((r) => r['id'] == a['id']);
          if (a['status'] != null) r['status'] = a['status'];
          return {'action': 'updated', 'record': r};
        }
        final project = projects.firstWhere((p) => p['id'] == a['project_id']);
        final r = {
          'id': 5000 + records.length,
          'project_id': a['project_id'],
          'kind': a['kind'] ?? 'info',
          'title': a['title'],
          'body': a['body'],
          'status': 'active',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        records.insert(0, {...r, 'project_name': project['name']});
        return {'action': 'created', 'record': r};
    }
    return null;
  }
}
