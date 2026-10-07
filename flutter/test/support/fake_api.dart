import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory Reqall REST API behind package:http's MockClient. Answers
/// the /api/v1 routes the app uses, plus /oauth/token.
class FakeApi {
  FakeApi({this.validTokens = const {'good-key'}});

  Set<String> validTokens;

  /// Answer every API request with this status and `{error, message}`.
  int? forceStatus;
  String forceCode = 'forced';

  /// Answer this many API requests with 429 before serving them.
  int rateLimited = 0;
  String? retryAfter = '0';

  /// When set, API replies wait for it, to hold requests in flight.
  Future<void>? hold;
  bool failWrites = false;

  /// Requests as "METHOD /path?query".
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  final tokenRequests = <Map<String, String>>[];
  final authHeaders = <String>[];
  int inFlight = 0;
  int maxInFlight = 0;

  /// Answer for /oauth/token; null means 400 invalid_grant.
  Map<String, dynamic>? tokenResponse;

  final records = <Map<String, dynamic>>[
    for (var i = 0; i < 60; i++)
      {
        'id': 1000 - i,
        'project_id': i.isEven ? 1 : 2,
        'project_name': i.isEven ? 'lumen-labs/atlas-app' : '.user',
        'kind': ['spec', 'issue', 'todo', 'info'][i % 4],
        'title': 'Record ${1000 - i}',
        'status': i % 4 == 1 || i % 4 == 2 ? 'open' : 'active',
        'created_at': DateTime.utc(2026, 9, 1).toIso8601String(),
        'updated_at': DateTime.utc(2026, 10, 5, 12).subtract(Duration(hours: i)).toIso8601String(),
      },
  ];

  final projects = <Map<String, dynamic>>[
    {'id': 1, 'name': 'lumen-labs/atlas-app', 'visibility': 'private', 'record_count': 30, 'access': 'owner'},
    {'id': 2, 'name': '.user', 'visibility': 'private', 'record_count': 30, 'access': 'owner'},
  ];

  late final http.Client client = MockClient(_handle);

  static const _kinds = {'spec', 'issue', 'todo', 'info', 'arch', 'test', 'work'};
  static const _statuses = {'open', 'active', 'resolved', 'archived'};

  static http.Response _json(Object body, [int status = 200, Map<String, String> headers = const {}]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});

  static http.Response _error(int status, String code, String message) =>
      _json({'error': code, 'message': message}, status);

  Future<http.Response> _handle(http.Request req) async {
    if (req.url.path == '/oauth/token') {
      tokenRequests.add(req.bodyFields);
      final r = tokenResponse;
      return r == null ? _json({'error': 'invalid_grant'}, 400) : _json(r);
    }
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (hold != null) await hold;
      await Future<void>.delayed(Duration.zero);
      return _api(req);
    } finally {
      inFlight--;
    }
  }

  http.Response _api(http.Request req) {
    final auth = req.headers['Authorization'] ?? '';
    authHeaders.add(auth);
    final path = req.url.path;
    final q = req.url.queryParameters;
    calls.add('${req.method} $path${req.url.hasQuery ? '?${req.url.query}' : ''}');
    if (!path.startsWith('/api/v1/')) return _error(404, 'not_found', 'No route');
    if (forceStatus != null) return _error(forceStatus!, forceCode, 'forced');
    if (!validTokens.contains(auth.replaceFirst('Bearer ', ''))) {
      return _error(401, 'unauthenticated', 'Invalid token');
    }
    if (rateLimited > 0) {
      rateLimited--;
      return _json({'error': 'rate_limited', 'message': 'slow down'}, 429, {'retry-after': ?retryAfter});
    }
    final body = req.body.isEmpty ? <String, dynamic>{} : (jsonDecode(req.body) as Map).cast<String, dynamic>();
    if (req.body.isNotEmpty) {
      if (req.headers['Content-Type']?.startsWith('application/json') != true) {
        return _error(400, 'bad_request', 'Expected JSON');
      }
      bodies.add(body);
    }
    final segments = path.substring('/api/v1/'.length).split('/');
    final id = segments.length > 1 ? int.tryParse(segments[1]) : null;

    switch ((req.method, segments.first, segments.length)) {
      case ('GET', 'projects', 1):
        return _json(projects);
      case ('GET', 'records', 1):
        final limit = int.tryParse(q['limit'] ?? '50') ?? 0;
        final offset = int.tryParse(q['offset'] ?? '0') ?? 0;
        if (limit < 1 || limit > 100) return _error(400, 'bad_request', 'limit must be 1-100');
        if (q['kind'] != null && !_kinds.contains(q['kind'])) return _error(400, 'bad_request', 'Unknown kind');
        if (q['status'] != null && !_statuses.contains(q['status'])) return _error(400, 'bad_request', 'Unknown status');
        final all = records
            .where((r) =>
                (q['kind'] == null || r['kind'] == q['kind']) &&
                (q['status'] == null || r['status'] == q['status']) &&
                (q['project_id'] == null || '${r['project_id']}' == q['project_id']))
            .toList();
        return _json({'records': all.skip(offset).take(limit).toList(), 'total': all.length, 'limit': limit, 'offset': offset});
      case ('GET', 'records', 2):
        final r = records.where((r) => r['id'] == id).firstOrNull;
        return r == null ? _error(404, 'not_found', 'Record not found') : _json({...r, 'body': 'Body of $id'});
      case ('GET', 'records', 3) when segments[2] == 'links':
        if (!records.any((r) => r['id'] == id)) return _error(404, 'not_found', 'Record not found');
        return _json({
          'links': [
            {'id': 1, 'source_id': id, 'source_table': 'records', 'target_id': 999, 'target_table': 'records', 'relationship': 'implements'},
            {'id': 2, 'source_id': 998, 'source_table': 'records', 'target_id': id, 'target_table': 'records', 'relationship': 'related'},
            {'id': 3, 'source_id': id, 'source_table': 'records', 'target_id': 1, 'target_table': 'projects', 'relationship': 'related'},
          ],
          'total': 3,
          'limit': int.tryParse(q['limit'] ?? '50'),
          'offset': 0,
        });
      case ('POST', 'records', 1):
        if (failWrites) return _error(403, 'trial_expired', 'Your trial has ended');
        final project = projects.where((p) => p['id'] == body['project_id']).firstOrNull;
        if (project == null || (body['title'] ?? '').toString().isEmpty) {
          return _error(400, 'validation_error', 'project_id and title are required');
        }
        final now = DateTime.now().toUtc().toIso8601String();
        final r = {
          'id': 5000 + records.length,
          'project_id': body['project_id'],
          'kind': body['kind'] ?? 'info',
          'title': body['title'],
          'body': body['body'],
          'status': 'active',
          'created_at': now,
          'updated_at': now,
          'secret_scan_flagged': false,
        };
        records.insert(0, {...r, 'project_name': project['name']}..remove('body'));
        return _json(r, 201); // no project_name, like the server
      case ('PATCH', 'records', 2):
        if (failWrites) return _error(403, 'trial_expired', 'Your trial has ended');
        final r = records.where((r) => r['id'] == id).firstOrNull;
        if (r == null) return _error(404, 'not_found', 'Record not found');
        if (body['status'] != null) r['status'] = body['status'];
        r['updated_at'] = DateTime.now().toUtc().toIso8601String();
        return _json({...r, 'body': 'Body of $id'}..remove('project_name'));
    }
    return _error(404, 'not_found', 'No route');
  }
}
