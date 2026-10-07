import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reqall_app/api/demo_repository.dart';
import 'package:reqall_app/auth/credentials.dart';
import 'package:reqall_app/auth/oauth.dart';
import 'package:reqall_app/shared/theme.dart';
import 'package:reqall_app/state/session.dart';

import 'support/fake_api.dart';

String jwt(DateTime exp) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

/// Secure storage as it behaves on an insecure web origin: every call throws.
class _InsecureStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(UnsupportedError('not a secure context'));
}

/// Secure storage holding one saved value.
class _SavedStorage implements FlutterSecureStorage {
  _SavedStorage(this.value);

  String? value;

  @override
  dynamic noSuchMethod(Invocation invocation) => switch (invocation.memberName) {
        #read => Future<String?>.value(value),
        #delete => Future<void>.sync(() => value = null),
        _ => Future<void>.value(),
      };
}

Session session(FakeApi fake, {CredentialStore? store, Credentials? oauthResult}) => Session(
      store: store ?? MemoryCredentialStore(),
      httpClient: fake.client,
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
  test('starts signed out when nothing is stored', () async {
    final fake = FakeApi();
    final s = session(fake);
    await s.start();
    expect(s.phase, Phase.signedOut);
    expect(s.signInError, isNull);
    expect(fake.calls, isEmpty);
  });

  test('credentials saved from the retired CLI source start signed out', () async {
    final storage = _SavedStorage(jsonEncode({'server': kDefaultServer, 'source': 'cli', 'api_key': 'good-key'}));
    final fake = FakeApi();
    final s = session(fake, store: SecureCredentialStore(storage));
    await s.start();
    expect(s.phase, Phase.signedOut);
    expect(s.credentials, isNull);
    expect(fake.calls, isEmpty);
  });

  test('API key sign-in validates, persists and loads the stream', () async {
    final store = MemoryCredentialStore();
    final fake = FakeApi();
    final s = session(fake, store: store);
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
    expect(fake.calls, contains('GET /api/v1/records?limit=50&offset=0'));
    expect(fake.authHeaders.toSet(), {'Bearer good-key'});
  });

  test('a rejected key stays on the login screen with a reason', () async {
    final store = MemoryCredentialStore();
    final s = session(FakeApi(), store: store);
    await s.start();
    await s.signInWithApiKey('bad-key');
    expect(s.phase, Phase.signedOut);
    expect(s.signInError, contains('rejected'));
    expect(store.value, isNull);
  });

  test('stored credentials resume without a login screen', () async {
    final store = MemoryCredentialStore(
        const Credentials(server: kDefaultServer, source: CredentialSource.apiKey, apiKey: 'good-key'));
    final s = session(FakeApi(), store: store);
    await s.start();
    await settle(s);
    expect(s.phase, Phase.ready);
    expect(s.records, isNotEmpty);
  });

  test('an OAuth 401 refreshes the token once and retries', () async {
    final fake = FakeApi(validTokens: {'fresh'})..tokenResponse = {'access_token': 'fresh', 'refresh_token': 'rt2'};
    final store = MemoryCredentialStore(const Credentials(
        server: kDefaultServer, source: CredentialSource.oauth, accessToken: 'stale', refreshToken: 'rt', clientId: 'cid'));
    final s = session(fake, store: store);
    await s.start();
    await settle(s);
    expect(s.phase, Phase.ready);
    expect(s.records, isNotEmpty);
    expect(fake.tokenRequests, hasLength(1));
    expect(fake.tokenRequests.first['grant_type'], 'refresh_token');
    expect(fake.tokenRequests.first['resource'], 'https://www.reqall.net/api');
    expect(store.value!.accessToken, 'fresh');
    expect(store.value!.refreshToken, 'rt2');
  });

  test('parallel 401s share one refresh, since refresh tokens rotate', () async {
    final fake = FakeApi(validTokens: {'first'});
    final store = MemoryCredentialStore(const Credentials(
        server: kDefaultServer, source: CredentialSource.oauth, accessToken: 'first', refreshToken: 'rt', clientId: 'cid'));
    final s = session(fake, store: store);
    await s.start();
    await settle(s);
    expect(s.records, hasLength(Session.pageSize));

    // The access token lapses; the next burst of requests all get 401.
    fake.validTokens = {'second'};
    fake.tokenResponse = {'access_token': 'second', 'refresh_token': 'rt2'};
    await Future.wait([
      s.refresh(),
      s.loadMore(),
      s.detail(990).then((_) {}, onError: (_) {}),
      s.setStatus(980, 'resolved'),
    ]);
    expect(fake.tokenRequests, hasLength(1));
    expect(fake.tokenRequests.single['refresh_token'], 'rt');
    expect(s.phase, Phase.ready);
    expect(s.problem, isNull);
    expect(store.value!.refreshToken, 'rt2');
    expect(s.lookup(980)!.status, 'resolved');
  });

  test('an expired JWT is refreshed before the request', () async {
    final fake = FakeApi(validTokens: {'fresh'})..tokenResponse = {'access_token': 'fresh'};
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
    final fake = FakeApi(validTokens: {});
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
    final fake = FakeApi();
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
    final s = session(FakeApi(), oauthResult: result);
    await s.start();
    await s.signInWithOAuth();
    expect(s.phase, Phase.ready);
    expect(s.credentials!.source, CredentialSource.oauth);
  });

  test('loadMore pages until the total is reached', () async {
    final s = session(FakeApi());
    await s.start();
    await s.signInWithApiKey('good-key');
    await settle(s);
    expect(s.hasMore, isTrue);
    await s.loadMore();
    expect(s.records, hasLength(60));
    expect(s.hasMore, isFalse);
  });

  test('remember puts the new record on top and bumps the count', () async {
    final s = session(FakeApi());
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
    final fake = FakeApi();
    final s = session(fake);
    await s.start();
    await s.signInWithApiKey('good-key');
    await settle(s);
    expect(await s.setStatus(1000, 'archived'), isNull);
    expect(s.visible.any((m) => m.id == 1000), isFalse);
    expect(s.lookup(1000)!.project, 'lumen-labs/atlas-app', reason: 'PATCH replies carry no project_name');
    fake.failWrites = true;
    final before = s.lookup(999)!.status;
    final pending = s.setStatus(999, 'resolved');
    expect(s.lookup(999)!.status, 'resolved', reason: 'applied before the server answers');
    expect(await pending, 'Your trial has ended');
    expect(s.lookup(999)!.status, before);
  });

  test('sign out clears credentials and data', () async {
    final store = MemoryCredentialStore();
    final s = session(FakeApi(), store: store);
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
    final s = session(FakeApi());
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
      httpClient: FakeApi().client,
      completeRedirect: (_) async => null,
      runOAuth: (_, _) async => throw const OAuthException('Sign-in was cancelled'),
    );
    await s.start();
    await s.signInWithOAuth();
    expect(s.phase, Phase.signedOut);
    expect(s.signInError, 'Sign-in was cancelled');
  });

  test('sign-in still works when credentials cannot be saved', () async {
    final store = SecureCredentialStore(_InsecureStorage());
    expect(await store.read(), isNull);
    final s = session(FakeApi(), store: store);
    await s.start();
    await s.signInWithApiKey('good-key');
    await settle(s);
    expect(s.phase, Phase.ready);
    expect(s.records, isNotEmpty);
    await s.signOut();
    expect(s.phase, Phase.signedOut);
  });

  test('a slow refresh from a previous account never lands in the next one', () async {
    final fake = FakeApi(validTokens: {'key-a', 'key-b'});
    final s = session(fake);
    await s.start();
    await s.signInWithApiKey('key-a');
    final gate = Completer<void>();
    fake.hold = gate.future;
    final stale = s.refresh(); // A's refresh, held in flight
    await Future<void>.delayed(Duration.zero);
    await s.signOut();
    fake.hold = null;
    fake.records.removeRange(10, fake.records.length); // B sees a different account
    await s.signInWithApiKey('key-b');
    await settle(s);
    expect(s.total, 10);
    gate.complete();
    await stale;
    await settle(s);
    expect(s.total, 10, reason: "A's late reply is discarded");
    expect(s.records, hasLength(10));
    expect(s.loading, isFalse);
  });
}
