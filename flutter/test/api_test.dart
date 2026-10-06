import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reqall_app/api/mcp_client.dart';
import 'package:reqall_app/api/models.dart';
import 'package:reqall_app/api/repository.dart';
import 'package:reqall_app/shared/theme.dart';

import 'support/fake_mcp.dart';

McpClient client(FakeMcp fake, [String token = 'good-key']) =>
    McpClient(endpoint: Uri.parse('https://example.test/mcp'), token: () => token, httpClient: fake.client);

void main() {
  group('McpClient', () {
    test('sends a bearer tools/call and returns data from JSON', () async {
      final fake = FakeMcp();
      final data = await client(fake).call('list_projects', {'limit': 1});
      expect(data['total'], 2);
      expect(fake.authHeaders.single, 'Bearer good-key');
      expect(fake.calls, ['list_projects']);
    });

    test('reads the data line of an SSE reply', () async {
      final data = await client(FakeMcp(sse: true)).call('list_records', {'limit': 2});
      expect((data['records'] as List).length, 2);
    });

    test('maps 401 and 403', () async {
      await expectLater(client(FakeMcp(), 'nope').call('list_projects'),
          throwsA(isA<McpException>().having((e) => e.failure, 'failure', McpFailure.unauthorized)));
      final paused = FakeMcp()..forceStatus = 403;
      await expectLater(client(paused).call('list_projects'),
          throwsA(isA<McpException>().having((e) => e.failure, 'failure', McpFailure.forbidden)));
    });

    test('surfaces tool errors from text content', () async {
      await expectLater(
          client(FakeMcp()).call('get_record', {'id': 1}),
          throwsA(isA<McpException>()
              .having((e) => e.failure, 'failure', McpFailure.tool)
              .having((e) => e.message, 'message', contains('not found'))));
    });

    test('reports transport failures as network', () async {
      final broken = McpClient(
        endpoint: Uri.parse('https://example.test/mcp'),
        token: () => 'k',
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      );
      await expectLater(
          broken.call('list_projects'), throwsA(isA<McpException>().having((e) => e.failure, 'f', McpFailure.network)));
    });
  });

  group('LiveRepository', () {
    test('summary counts like the panel', () async {
      final s = await LiveRepository(client(FakeMcp())).summary();
      expect(s.memories, 60);
      expect(s.openTodos, 15);
      expect(s.openIssues, 15);
      expect(s.projects, 2);
    });

    test('records page carries total and parses fields', () async {
      final page = await LiveRepository(client(FakeMcp())).records(limit: 10, offset: 5);
      expect(page.total, 60);
      expect(page.records.first.id, 995);
      expect(page.records.first.kind, Kind.issue);
      expect(page.records.first.project, '.user');
      expect(page.records.first.body, isNull);
    });

    test('detail reads body and record links in both directions', () async {
      final d = await LiveRepository(client(FakeMcp())).detail(1000);
      expect(d.memory.body, 'Body of 1000');
      expect(d.links.map((l) => (l.otherId, l.outgoing, l.relationship)),
          [(999, true, 'implements'), (998, false, 'related')]);
    });

    test('remember creates in the chosen project and fills its name', () async {
      final fake = FakeMcp();
      final m = await LiveRepository(client(fake))
          .remember(project: const Project(2, '.user'), title: 'New thing', body: 'why', kind: Kind.todo);
      expect(m.title, 'New thing');
      expect(m.kind, Kind.todo);
      expect(m.project, '.user');
    });

    test('setStatus updates by id', () async {
      final m = await LiveRepository(client(FakeMcp())).setStatus(999, 'resolved');
      expect(m.status, 'resolved');
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
