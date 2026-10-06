import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reqall_app/api/demo_repository.dart';
import 'package:reqall_app/auth/credentials.dart';
import 'package:reqall_app/auth/oauth.dart';
import 'package:reqall_app/shared/theme.dart';
import 'package:reqall_app/state/session.dart';

import 'support/fake_mcp.dart';

String jwt(DateTime exp) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Session session(FakeMcp fake, {MemoryCredentialStore? store, Credentials? cli, Credentials? oauthResult}) => Session(
      store: store ?? MemoryCredentialStore(),
      httpClient: fake.client,
      findCli: () async => cli,
      completeRedirect: (_) async => null,
      runOAuth: (_, _) async => oauthResult,
      demo: () => DemoRepository(latency: Duration.zero),
    );

/// Lets the session's fire-and-forget refresh and prefetches settle.
Future<void> settle(Session s) async {
  for (var i = 0; i < 20 && s.loading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void main() {
  test('starts signed out with a CLI candidate when nothing is stored', () async {
    const cli = Credentials(server: kDefaultServer, source: CredentialSource.cli, apiKey: 'good-key');
    final s = session(FakeMcp(), cli: cli);
    await s.start();
    expect(s.phase, Phase.signedOut);
    expect(s.cliCandidate, same(cli));
  });

  test('API key sign-in validates, persists and loads the stream', () async {
    final store = MemoryCredentialStore();
    final s = session(FakeMcp(), store: store);
    await s.start();
    await s.signInWithApiKey(' good-key ');
    await settle(s);
    expect(s.phase, Phase.ready);
    expect(store.value!.apiKey, 'good-key');
    expect(s.summary.memories, 60);
    expect(s.records, hasLength(Session.pageSize));
    expect(s.total, 60);
    expect(s.projects, hasLength(2));
    expect(s.loadedDetail(1000)?.memory.body, 'Body of 1000', reason: 'first records are prefetched');
    expect(s.records.first.body, 'Body of 1000');
  });

  test('a rejected key stays on the login screen with a reason', () async {
    final store = MemoryCredentialStore();
    final s = session(FakeMcp(), store: store);
    await s.start();
    await s.signInWithApiKey('bad-key');
    expect(s.phase, Phase.signedOut);
    expect(s.signInError, contains('rejected'));
    expect(store.value, isNull);
  });

  test('stored credentials resume without a login screen', () async {
    final store = MemoryCredentialStore(
        const Credentials(server: kDefaultServer, source: CredentialSource.apiKey, apiKey: 'good-key'));
    final s = session(FakeMcp(), store: store);
    await s.start();
    await settle(s);
    expect(s.phase, Phase.ready);
    expect(s.records, isNotEmpty);
  });

  test('an OAuth 401 refreshes the token once and retries', () async {
    final fake = FakeMcp(validTokens: {'fresh'})..tokenResponse = {'access_token': 'fresh', 'refresh_token': 'rt2'};
    final store = MemoryCredentialStore(const Credentials(
        server: kDefaultServer, source: CredentialSource.oauth, accessToken: 'stale', refreshToken: 'rt', clientId: 'cid'));
    final s = session(fake, store: store);
    await s.start();
    await settle(s);
    expect(s.phase, Phase.ready);
    expect(s.records, isNotEmpty);
    expect(fake.tokenRequests.first['grant_type'], 'refresh_token');
    expect(store.value!.accessToken, 'fresh');
    expect(store.value!.refreshToken, 'rt2');
  });

  test('an expired JWT is refreshed before the request', () async {
    final fake = FakeMcp(validTokens: {'fresh'})..tokenResponse = {'access_token': 'fresh'};
    final store = MemoryCredentialStore(Credentials(
        server: kDefaultServer,
        source: CredentialSource.oauth,
        accessToken: jwt(DateTime.now().subtract(const Duration(minutes: 5))),
        refreshToken: 'rt',
        clientId: 'cid'));
    final s = session(fake, store: store);
    await s.start();
    await settle(s);
    expect(s.records, isNotEmpty);
    expect(fake.authHeaders.where((h) => h != 'Bearer fresh'), isEmpty);
  });

  test('a dead refresh token signs out with a message', () async {
    final fake = FakeMcp(validTokens: {});
    final store = MemoryCredentialStore(const Credentials(
        server: kDefaultServer, source: CredentialSource.oauth, accessToken: 'stale', refreshToken: 'rt', clientId: 'cid'));
    final s = session(fake, store: store);
    await s.start();
    await settle(s);
    expect(s.phase, Phase.signedOut);
    expect(s.signInError, contains('Sign in again'));
    expect(store.value, isNull);
  });

  test('403 keeps the session and reports a paused problem', () async {
    final fake = FakeMcp();
    final s = session(fake);
    await s.start();
    await s.signInWithApiKey('good-key');
    await settle(s);
    fake.forceStatus = 403;
    await s.refresh();
    expect(s.phase, Phase.ready);
    expect(s.problem, Problem.paused);
    fake.forceStatus = null;
    await s.refresh();
    expect(s.problem, isNull);
  });

  test('OAuth sign-in adopts what the browser flow returns', () async {
    const result = Credentials(
        server: kDefaultServer, source: CredentialSource.oauth, accessToken: 'good-key', refreshToken: 'r', clientId: 'c');
    final s = session(FakeMcp(), oauthResult: result);
    await s.start();
    await s.signInWithOAuth();
    expect(s.phase, Phase.ready);
    expect(s.credentials!.source, CredentialSource.oauth);
  });

  test('loadMore pages until the total is reached', () async {
    final s = session(FakeMcp());
    await s.start();
    await s.signInWithApiKey('good-key');
    await settle(s);
    expect(s.hasMore, isTrue);
    await s.loadMore();
    expect(s.records, hasLength(60));
    expect(s.hasMore, isFalse);
  });

  test('remember puts the new record on top and bumps the count', () async {
    final s = session(FakeMcp());
    await s.start();
    await s.signInWithApiKey('good-key');
    await settle(s);
    final error = await s.remember(project: s.projects.last, title: 'Captured', kind: Kind.todo);
    expect(error, isNull);
    expect(s.records.first.title, 'Captured');
    expect(s.records.first.project, '.user');
    expect(s.lastAddedId, s.records.first.id);
    expect(s.summary.memories, 61);
  });

  test('setStatus is optimistic and reverts on failure', () async {
    final fake = FakeMcp();
    final s = session(fake);
    await s.start();
    await s.signInWithApiKey('good-key');
    await settle(s);
    expect(await s.setStatus(1000, 'archived'), isNull);
    expect(s.visible.any((m) => m.id == 1000), isFalse);
    fake.failWrites = true;
    final before = s.lookup(999)!.status;
    final pending = s.setStatus(999, 'resolved');
    expect(s.lookup(999)!.status, 'resolved', reason: 'applied before the server answers');
    expect(await pending, isNotNull);
    expect(s.lookup(999)!.status, before);
  });

  test('sign out clears credentials and data', () async {
    final store = MemoryCredentialStore();
    final s = session(FakeMcp(), store: store);
    await s.start();
    await s.signInWithApiKey('good-key');
    await settle(s);
    await s.signOut();
    expect(s.phase, Phase.signedOut);
    expect(store.value, isNull);
    expect(s.records, isEmpty);
    expect(s.credentials, isNull);
  });

  test('demo mode runs on the mock account', () async {
    final s = session(FakeMcp());
    await s.start();
    await s.startDemo();
    expect(s.phase, Phase.ready);
    expect(s.demo, isTrue);
    expect(s.summary.memories, 7910);
    expect(s.records, isNotEmpty);
  });

  test('OAuth exceptions from the browser flow show on the login screen', () async {
    final s = Session(
      store: MemoryCredentialStore(),
      httpClient: FakeMcp().client,
      findCli: () async => null,
      completeRedirect: (_) async => null,
      runOAuth: (_, _) async => throw const OAuthException('Sign-in was cancelled'),
    );
    await s.start();
    await s.signInWithOAuth();
    expect(s.phase, Phase.signedOut);
    expect(s.signInError, 'Sign-in was cancelled');
  });
}
