import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum ApiFailure { unauthorized, forbidden, network, server, request }

class ApiException implements Exception {
  const ApiException(this.failure, this.message, {this.status = 0, this.code, this.retryAfter});

  final ApiFailure failure;
  final String message;

  /// HTTP status, or 0 when the server was never reached.
  final int status;

  /// The server's `error` code, e.g. `unauthenticated`, `trial_expired`, `not_found`.
  final String? code;

  /// From a 429's Retry-After header.
  final Duration? retryAfter;

  @override
  String toString() => 'ApiException(${failure.name}): $message';
}

/// Requests against the Reqall REST API (`{server}/api/v1`), the same API the
/// Electron console uses. Every call carries the bearer, an OAuth access
/// token or an `rq_` key, and answers with the decoded JSON body.
///
/// The server rate-limits bursts, and a refresh plus detail prefetch is one,
/// so at most [maxInFlight] calls run at once and a 429 is retried after its
/// Retry-After (or a short backoff) before it counts as a failure.
class ApiClient {
  ApiClient({
    required this.base,
    required this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
    this.maxInFlight = 4,
    this.retries = 2,
    this.backoff = const Duration(seconds: 1),
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// The API root, e.g. https://www.reqall.net/api/v1.
  final Uri base;

  /// Reads the current bearer token on every call, so a refreshed token
  /// takes effect without rebuilding the client.
  final String Function() token;
  final Duration timeout;
  final int maxInFlight;
  final int retries;
  final Duration backoff;
  final http.Client _http;
  final bool _ownsHttp;
  int _inFlight = 0;
  final _waiting = <Completer<void>>[];

  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) => send('GET', path, query: query);

  Future<dynamic> post(String path, Map<String, Object?> body) => send('POST', path, body: body);

  Future<dynamic> patch(String path, Map<String, Object?> body) => send('PATCH', path, body: body);

  /// [path] is relative to [base] and starts with a slash; null query values
  /// are left out.
  Future<dynamic> send(String method, String path, {Map<String, Object?> query = const {}, Map<String, Object?>? body}) async {
    final params = {
      for (final e in query.entries)
        if (e.value != null) e.key: '${e.value}',
    };
    final url = base.replace(path: '${base.path}$path', queryParameters: params.isEmpty ? null : params);
    await _acquire();
    try {
      for (var attempt = 0;; attempt++) {
        try {
          return await _send(method, url, body);
        } on ApiException catch (e) {
          if (e.status != 429 || attempt >= retries) rethrow;
          await Future<void>.delayed(e.retryAfter ?? backoff * (1 << attempt));
        }
      }
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_inFlight < maxInFlight) {
      _inFlight++;
      return Future.value();
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    return turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _inFlight--;
    }
  }

  Future<dynamic> _send(String method, Uri url, Map<String, Object?>? body) async {
    final req = http.Request(method, url)
      ..headers['Authorization'] = 'Bearer ${token()}'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
    } catch (_) {
      throw ApiException(ApiFailure.network, 'Could not reach ${url.host}');
    }

    final text = utf8.decode(res.bodyBytes);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {}
    final error = json is Map ? json : const {};
    final code = error['error'] is String ? error['error'] as String : null;
    String message(String fallback) => (error['message'] ?? error['error_description'] ?? code ?? fallback).toString();
    ApiException fail(ApiFailure f, String fallback) => ApiException(f, message(fallback), status: res.statusCode, code: code);

    final status = res.statusCode;
    if (status >= 200 && status < 300) {
      if (text.isEmpty) return const <String, dynamic>{};
      if (json == null) throw ApiException(ApiFailure.server, 'Unexpected response', status: status);
      return json;
    }
    if (status == 401) throw fail(ApiFailure.unauthorized, 'Unauthorized');
    if (status == 403) throw fail(ApiFailure.forbidden, 'Forbidden');
    if (status == 429) {
      final after = int.tryParse(res.headers['retry-after']?.trim() ?? '');
      throw ApiException(ApiFailure.server, 'Rate limited by the server (429), try again shortly',
          status: 429, code: code, retryAfter: after == null || after < 0 ? null : Duration(seconds: after.clamp(0, 10)));
    }
    if (status >= 400 && status < 500) throw fail(ApiFailure.request, 'Request failed (HTTP $status)');
    throw ApiException(ApiFailure.server, 'Server returned HTTP $status', status: status, code: code);
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
