import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'credentials.dart';

/// OAuth 2.1 authorization-code + PKCE against the Reqall server, the same
/// flow the CLI runs but for the REST API audience. The server accepts
/// unregistered clients whose redirect_uri is a loopback address, so the app
/// needs no registration.
class Pkce {
  Pkce._(this.verifier, this.challenge);

  factory Pkce.generate([Random? random]) {
    final r = random ?? Random.secure();
    final verifier = _b64(List<int>.generate(32, (_) => r.nextInt(256)));
    return Pkce._(verifier, challengeFor(verifier));
  }

  final String verifier;
  final String challenge;

  static String challengeFor(String verifier) => _b64(sha256.convert(ascii.encode(verifier)).bytes);
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String randomState([Random? random]) {
  final r = random ?? Random.secure();
  return _b64(List<int>.generate(16, (_) => r.nextInt(256)));
}

/// A stable public client id for the app, derived like the CLI's.
final String appClientId = sha256.convert(utf8.encode('reqall-app')).toString().substring(0, 32);

/// RFC 8707 resource: tokens are bound to the server's REST API.
String apiResource(String server) => '${normalizeServer(server)}/api';

Uri authorizeUri({required String server, required String redirectUri, required Pkce pkce, required String state}) =>
    Uri.parse('${normalizeServer(server)}/oauth/authorize').replace(queryParameters: {
      'client_id': appClientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'code_challenge': pkce.challenge,
      'code_challenge_method': 'S256',
      'scope': 'api',
      'state': state,
      'resource': apiResource(server),
    });

class OAuthException implements Exception {
  const OAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OAuthApi {
  OAuthApi({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<Credentials> exchange({
    required String server,
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final tokens = await _token(server, {
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirectUri,
      'client_id': appClientId,
      'resource': apiResource(server),
    });
    return Credentials(
      server: normalizeServer(server),
      source: CredentialSource.oauth,
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String?,
      clientId: appClientId,
    );
  }

  /// Refresh tokens rotate on every use, so the returned credentials carry
  /// the new one; callers must persist it and never refresh concurrently.
  Future<Credentials> refresh(Credentials c) async {
    if (!c.canRefresh) throw const OAuthException('Nothing to refresh with');
    final tokens = await _token(c.server, {
      'grant_type': 'refresh_token',
      'refresh_token': c.refreshToken!,
      'client_id': c.clientId!,
      'resource': apiResource(c.server),
    });
    return c.withTokens(accessToken: tokens['access_token'] as String, refreshToken: tokens['refresh_token'] as String?);
  }

  Future<Map<String, dynamic>> _token(String server, Map<String, String> form) async {
    final url = apiBase(normalizeServer(server)).resolve('/oauth/token');
    http.Response res;
    try {
      res = await _http.post(url, body: form).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw OAuthException('Could not reach ${url.host}');
    }
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode != 200 || json == null || json['access_token'] is! String) {
      final why = json?['error_description'] ?? json?['message'] ?? json?['error'] ?? 'HTTP ${res.statusCode}';
      throw OAuthException('Sign-in failed: $why');
    }
    return json;
  }
}
