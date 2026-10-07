import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/demo_repository.dart';
import '../api/models.dart';
import '../api/repository.dart';
import '../auth/credentials.dart';
import '../auth/oauth.dart';
import '../auth/platform.dart' as platform;
import '../shared/theme.dart';

enum Phase { starting, signedOut, ready }

/// Why the account is not answering normally, as the panel's auth states.
enum Problem { invalid, paused, offline }

/// The app's one piece of state: who is signed in, with what, and the
/// stream of records they see. Screens listen to it; it never throws at them.
class Session extends ChangeNotifier {
  Session({
    CredentialStore? store,
    http.Client? httpClient,
    OAuthApi? oauth,
    Future<Credentials?> Function(OAuthApi)? completeRedirect,
    Future<Credentials?> Function(OAuthApi, String)? runOAuth,
    ReqallRepository Function()? demo,
  })  : _store = store ?? SecureCredentialStore(),
        _http = httpClient ?? http.Client(),
        _completeRedirect = completeRedirect ?? platform.completeOAuthRedirect,
        _runOAuth = runOAuth ?? platform.runOAuth,
        _demo = demo ?? DemoRepository.new {
    _oauth = oauth ?? OAuthApi(httpClient: _http);
  }

  final CredentialStore _store;
  final http.Client _http;
  late final OAuthApi _oauth;
  final Future<Credentials?> Function(OAuthApi) _completeRedirect;
  final Future<Credentials?> Function(OAuthApi, String) _runOAuth;
  final ReqallRepository Function() _demo;

  static const pageSize = 50;
  static const _prefetch = 8;

  // ----------------------------------------------------------- auth state

  Phase phase = Phase.starting;
  Credentials? credentials;
  bool demo = false;
  ReqallRepository? _repo;

  bool signingIn = false;
  String? signInError;

  String? get oauthUnavailable => platform.oauthUnavailableReason();

  /// False on web pages that are not a secure context: sign-in still works,
  /// but only until the tab closes.
  bool get credentialsPersist => platform.credentialsPersist();
  String get server => credentials?.server ?? kDefaultServer;
  String get host => demo ? 'demo' : (credentials?.host ?? Uri.parse(kDefaultServer).host);

  // ----------------------------------------------------------- data

  AccountSummary summary = AccountSummary.empty;
  List<Memory> records = [];
  int total = 0;
  List<Project> projects = [];
  bool loading = false;
  bool loadingMore = false;
  Problem? problem;
  String? problemMessage;
  DateTime? updated;
  int? lastAddedId;
  final Map<int, Future<MemoryDetail>> _details = {};
  final Map<int, MemoryDetail> _loaded = {};

  /// Body and links for [id] if they have arrived, without fetching.
  MemoryDetail? loadedDetail(int id) => _loaded[id];

  bool get hasMore => records.length < total;
  Iterable<Memory> get visible => records.where((m) => m.status != 'archived');

  Memory? lookup(int id) => records.where((m) => m.id == id).firstOrNull;

  // ----------------------------------------------------------- lifecycle

  Future<void> start() async {
    try {
      final returned = await _completeRedirect(_oauth);
      if (returned != null) {
        await _adopt(returned);
        return;
      }
    } catch (e) {
      signInError = '$e';
    }
    final stored = await _store.read();
    if (stored != null) {
      await _adopt(stored, persist: false);
      return;
    }
    phase = Phase.signedOut;
    notifyListeners();
  }

  Future<void> signInWithApiKey(String key, {String server = kDefaultServer}) => _signIn(() async => Credentials(
        server: normalizeServer(server),
        source: CredentialSource.apiKey,
        apiKey: key.trim(),
      ));

  Future<void> signInWithOAuth({String server = kDefaultServer}) =>
      _signIn(() => _runOAuth(_oauth, normalizeServer(server)));

  Future<void> startDemo() async {
    _reset();
    demo = true;
    _repo = _demo();
    phase = Phase.ready;
    notifyListeners();
    await refresh();
  }

  Future<void> signOut() async {
    await _store.clear();
    _reset();
    phase = Phase.signedOut;
    notifyListeners();
  }

  Future<void> _signIn(Future<Credentials?> Function() obtain) async {
    if (signingIn) return;
    signingIn = true;
    signInError = null;
    notifyListeners();
    try {
      final c = await obtain();
      if (c == null) return; // web OAuth navigates away and finishes on return
      await _adopt(c, validate: true);
    } on ApiException catch (e) {
      signInError = switch (e.failure) {
        ApiFailure.unauthorized => 'That key was rejected (401). Check it and try again.',
        ApiFailure.forbidden => 'Access is paused for this account (403).',
        ApiFailure.network => 'Could not reach the server. Check the address and your connection.',
        _ => e.message,
      };
    } catch (e) {
      signInError = '$e';
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  /// Makes [c] the active credentials. With [validate], one summary call
  /// must succeed first, so a bad key never reaches the stream.
  Future<void> _adopt(Credentials c, {bool persist = true, bool validate = false}) async {
    final repo = LiveRepository(ApiClient(
      base: apiBase(c.server).resolve('/api/v1'),
      token: () => credentials?.bearer ?? c.bearer,
      httpClient: _http,
    ));
    final previous = credentials;
    credentials = c;
    if (validate) {
      try {
        summary = await repo.summary();
      } catch (_) {
        credentials = previous;
        rethrow;
      }
    }
    _reset(keepCredentials: true);
    _repo = repo;
    if (persist) await _store.write(c);
    phase = Phase.ready;
    notifyListeners();
    unawaited(refresh());
  }

  void _reset({bool keepCredentials = false}) {
    if (!keepCredentials) credentials = null;
    demo = false;
    _repo = null;
    summary = AccountSummary.empty;
    loading = false;
    loadingMore = false;
    records = [];
    total = 0;
    projects = [];
    problem = null;
    problemMessage = null;
    updated = null;
    lastAddedId = null;
    _details.clear();
    _loaded.clear();
    signInError = null;
  }

  // ----------------------------------------------------------- requests

  /// Runs [op] against the repository, refreshing an OAuth token once on
  /// expiry or a 401 and mapping failures onto [problem].
  Future<T?> _guard<T>(Future<T> Function(ReqallRepository repo) op) async {
    final repo = _repo;
    if (repo == null) return null;
    try {
      if (credentials?.tokenExpired == true && credentials!.canRefresh) await _refreshToken();
      final sentWith = credentials?.bearer;
      T value;
      try {
        value = await op(repo);
      } on ApiException catch (e) {
        if (e.failure != ApiFailure.unauthorized || !(credentials?.canRefresh ?? false)) rethrow;
        // A parallel request may already have refreshed while this one was
        // in flight; then the new token just needs a retry.
        if (credentials?.bearer == sentWith) await _refreshToken();
        value = await op(repo);
      }
      // Signed out or switched accounts while this was in flight.
      if (!identical(repo, _repo)) return null;
      if (problem != null) {
        problem = null;
        problemMessage = null;
      }
      return value;
    } on ApiException catch (e) {
      if (!identical(repo, _repo)) return null; // signed out meanwhile
      switch (e.failure) {
        case ApiFailure.unauthorized:
          await _expire(e.message);
        case ApiFailure.forbidden:
          problem = Problem.paused;
          problemMessage = e.message;
        default:
          problem = Problem.offline;
          problemMessage = e.message;
      }
      notifyListeners();
      return null;
    } on OAuthException catch (e) {
      if (identical(repo, _repo)) await _expire(e.message);
      return null;
    }
  }

  Future<void>? _refreshing;

  /// Refresh tokens rotate on every use and the loser of two concurrent
  /// refreshes gets invalid_grant, so callers share one refresh in flight.
  Future<void> _refreshToken() => _refreshing ??= _rotate().whenComplete(() => _refreshing = null);

  Future<void> _rotate() async {
    final before = credentials;
    if (before == null) return;
    final c = await _oauth.refresh(before);
    if (!identical(credentials, before)) return; // signed out or switched meanwhile
    credentials = c;
    await _store.write(c);
  }

  Future<void> _expire(String why) async {
    await _store.clear();
    _reset();
    signInError = 'Your sign-in is no longer valid ($why). Sign in again.';
    phase = Phase.signedOut;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_repo == null || loading) return;
    loading = true;
    notifyListeners();
    final started = _repo;
    final result = await _guard((repo) => Future.wait([
          repo.summary(),
          repo.records(limit: pageSize),
          repo.projects(),
        ]));
    if (!identical(started, _repo)) return; // a newer session owns the flags now
    loading = false;
    if (result != null) {
      summary = result[0] as AccountSummary;
      final page = result[1] as RecordPage;
      records = page.records;
      total = page.total;
      projects = result[2] as List<Project>;
      updated = DateTime.now();
      _details.clear();
      _loaded.clear();
      for (final m in records.take(_prefetch)) {
        unawaited(detail(m.id).then((_) {}, onError: (_) {}));
      }
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_repo == null || loadingMore || !hasMore) return;
    loadingMore = true;
    notifyListeners();
    final started = _repo;
    final page = await _guard((repo) => repo.records(limit: pageSize, offset: records.length));
    if (!identical(started, _repo)) return;
    loadingMore = false;
    if (page != null) {
      final seen = records.map((m) => m.id).toSet();
      records = [...records, ...page.records.where((m) => !seen.contains(m.id))];
      total = page.total;
    }
    notifyListeners();
  }

  /// Body and links for one record, fetched once and folded back into the
  /// list so the card shows its body.
  Future<MemoryDetail> detail(int id) {
    return _details.putIfAbsent(id, () async {
      final d = await _guard((repo) => repo.detail(id));
      if (d == null) {
        _details.remove(id);
        throw StateError(problemMessage ?? 'Could not load #$id');
      }
      _loaded[id] = d;
      final i = records.indexWhere((m) => m.id == id);
      if (i >= 0 && d.memory.body != null) records[i] = records[i].copyWith(body: d.memory.body);
      notifyListeners();
      return d;
    });
  }

  /// Saves a new record. Returns an error message, or null on success.
  Future<String?> remember({required Project project, required String title, String body = '', Kind? kind}) async {
    final m = await _guard((repo) => repo.remember(project: project, title: title, body: body, kind: kind));
    if (m == null) return problemMessage ?? 'Could not save';
    records = [m, ...records.where((r) => r.id != m.id)];
    total++;
    summary = summary.adjust(memories: 1);
    lastAddedId = m.id;
    notifyListeners();
    return null;
  }

  /// Changes a record's status optimistically; reverts and returns an error
  /// message if the server refuses.
  Future<String?> setStatus(int id, String status) async {
    final i = records.indexWhere((m) => m.id == id);
    if (i < 0) return 'Unknown record #$id';
    final before = records[i];
    records[i] = before.copyWith(status: status);
    notifyListeners();
    final saved = await _guard((repo) => repo.setStatus(id, status));
    final j = records.indexWhere((m) => m.id == id);
    if (saved == null) {
      if (j >= 0) records[j] = before;
      notifyListeners();
      return problemMessage ?? 'Could not update #$id';
    }
    if (j >= 0) records[j] = records[j].copyWith(status: saved.status, updatedAt: saved.updatedAt);
    notifyListeners();
    return null;
  }

  @override
  void dispose() {
    _repo?.close();
    _http.close();
    super.dispose();
  }
}
