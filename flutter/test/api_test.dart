import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reqall_app/api/api_client.dart';
import 'package:reqall_app/api/models.dart';
import 'package:reqall_app/api/repository.dart';
import 'package:reqall_app/shared/theme.dart';

import 'support/fake_api.dart';

ApiClient client(FakeApi fake, {String token = 'good-key', int maxInFlight = 4}) => ApiClient(
      base: Uri.parse('https://example.test/api/v1'),
      token: () => token,
      httpClient: fake.client,
      maxInFlight: maxInFlight,
      backoff: Duration.zero,
    );

Matcher failsWith(ApiFailure failure, [Object? message]) => throwsA(isA<ApiException>()
    .having((e) => e.failure, 'failure', failure)
    .having((e) => e.message, 'message', message ?? anything));

void main() {
  group('ApiClient', () {
    test('sends a bearer GET with the query and returns the JSON body', () async {
      final fake = FakeApi();
      final data = await client(fake).get('/records', {'limit': 2, 'kind': null, 'offset': 0});
      expect((data['records'] as List).length, 2);
      expect(data['total'], 60);
      expect(fake.authHeaders.single, 'Bearer good-key');
      expect(fake.calls, ['GET /api/v1/records?limit=2&offset=0']);
    });

    test('sends JSON bodies on POST and PATCH', () async {
      final fake = FakeApi();
      await client(fake).patch('/records/999', {'status': 'resolved'});
      expect(fake.calls.single, 'PATCH /api/v1/records/999');
      expect(fake.bodies.single, {'status': 'resolved'});
    });

    test('maps 401, 403, 4xx and 5xx', () async {
      await expectLater(client(FakeApi(), token: 'nope').get('/projects'), failsWith(ApiFailure.unauthorized, 'Invalid token'));
      final paused = FakeApi()
        ..forceStatus = 403
        ..forceCode = 'key_paused';
      await expectLater(
          client(paused).get('/projects'),
          throwsA(isA<ApiException>()
              .having((e) => e.failure, 'failure', ApiFailure.forbidden)
              .having((e) => e.code, 'code', 'key_paused')));
      await expectLater(client(FakeApi()).get('/records/1'), failsWith(ApiFailure.request, 'Record not found'));
      await expectLater(client(FakeApi()).get('/records', {'kind': 'nonsense'}), failsWith(ApiFailure.request));
      await expectLater(client(FakeApi()..forceStatus = 502).get('/projects'), failsWith(ApiFailure.server, contains('502')));
    });

    test('reports transport failures as network', () async {
      final broken = ApiClient(
        base: Uri.parse('https://example.test/api/v1'),
        token: () => 'k',
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      );
      await expectLater(broken.get('/projects'), failsWith(ApiFailure.network, contains('example.test')));
    });

    test('a 429 is retried after Retry-After, then gives up with a clear message', () async {
      final fake = FakeApi()..rateLimited = 2;
      expect(await client(fake).get('/projects'), hasLength(2));
      expect(fake.calls, hasLength(3));

      final busy = FakeApi()
        ..rateLimited = 10
        ..retryAfter = null; // falls back to the (zero, in tests) backoff
      await expectLater(
          client(busy).get('/projects'),
          throwsA(isA<ApiException>()
              .having((e) => e.status, 'status', 429)
              .having((e) => e.failure, 'failure', ApiFailure.server)
              .having((e) => e.message, 'message', contains('Rate limited'))));
      expect(busy.calls, hasLength(3), reason: 'one try plus two retries');
    });

    test('at most maxInFlight requests run at once', () async {
      final fake = FakeApi();
      final c = client(fake, maxInFlight: 2);
      await Future.wait([for (var i = 0; i < 7; i++) c.get('/records/${1000 - i}')]);
      expect(fake.maxInFlight, 2);
      expect(fake.calls, hasLength(7));
    });
  });

  group('LiveRepository', () {
    test('summary counts like the panel', () async {
      final fake = FakeApi();
      final s = await LiveRepository(client(fake)).summary();
      expect(s.memories, 60);
      expect(s.openTodos, 15);
      expect(s.openIssues, 15);
      expect(s.projects, 2);
      expect(fake.calls, unorderedEquals([
        'GET /api/v1/records?limit=1',
        'GET /api/v1/records?limit=1&status=open&kind=todo',
        'GET /api/v1/records?limit=1&status=open&kind=issue',
        'GET /api/v1/projects',
      ]));
    });

    test('records page carries total and parses fields', () async {
      final page = await LiveRepository(client(FakeApi())).records(limit: 10, offset: 5);
      expect(page.total, 60);
      expect(page.records.first.id, 995);
      expect(page.records.first.kind, Kind.issue);
      expect(page.records.first.project, '.user');
      expect(page.records.first.projectId, 2);
      expect(page.records.first.body, isNull);
    });

    test('projects come from the plain array', () async {
      final projects = await LiveRepository(client(FakeApi())).projects();
      expect(projects.map((p) => (p.id, p.name, p.count)), [(1, 'lumen-labs/atlas-app', 30), (2, '.user', 30)]);
    });

    test('detail reads body and record links in both directions', () async {
      final fake = FakeApi();
      final d = await LiveRepository(client(fake)).detail(1000);
      expect(d.memory.body, 'Body of 1000');
      expect(d.memory.project, 'lumen-labs/atlas-app');
      expect(d.links.map((l) => (l.otherId, l.outgoing, l.relationship)),
          [(999, true, 'implements'), (998, false, 'related')]);
      expect(fake.calls, contains('GET /api/v1/records/1000/links?direction=both&limit=50'));
    });

    test('remember creates in the chosen project and fills its name', () async {
      final fake = FakeApi();
      final m = await LiveRepository(client(fake))
          .remember(project: const Project(2, '.user'), title: 'New thing', body: 'why', kind: Kind.todo);
      expect(fake.bodies.single, {'project_id': 2, 'title': 'New thing', 'body': 'why', 'kind': 'todo'});
      expect(m.title, 'New thing');
      expect(m.kind, Kind.todo);
      expect(m.project, '.user');
    });

    test('setStatus patches by id', () async {
      final m = await LiveRepository(client(FakeApi())).setStatus(999, 'resolved');
      expect(m.status, 'resolved');
      expect(m.id, 999);
    });
  });

  test('relativeAge buckets', () {
    expect(relativeAge(const Duration(seconds: 10)), 'now');
    expect(relativeAge(const Duration(minutes: 5)), '5m');
    expect(relativeAge(const Duration(hours: 3)), '3h');
    expect(relativeAge(const Duration(days: 3)), '3d');
    expect(relativeAge(const Duration(days: 30)), '4w');
  });
}
