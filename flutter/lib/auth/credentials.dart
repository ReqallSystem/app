import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kDefaultServer = 'https://www.reqall.net';

enum CredentialSource { apiKey, oauth }

/// What the app signs requests with. [server] is the canonical Reqall host
/// (dashboard links, OAuth resource); [apiBase] is where requests actually
/// go, which on web is this page's own origin so a same-origin proxy can
/// forward them (the server does not send CORS headers for /api yet).
class Credentials {
  const Credentials({
    required this.server,
    required this.source,
    this.apiKey,
    this.accessToken,
    this.refreshToken,
    this.clientId,
  });

  final String server;
  final CredentialSource source;
  final String? apiKey;
  final String? accessToken;
  final String? refreshToken;
  final String? clientId;

  String get bearer => accessToken ?? apiKey ?? '';
  bool get canRefresh => refreshToken != null && clientId != null;

  String get host => Uri.tryParse(server)?.host ?? server;

  String get sourceLabel => switch (source) {
        CredentialSource.apiKey => 'API key',
        CredentialSource.oauth => 'signed in',
      };

  /// True when the access token is a JWT that expires within a minute.
  bool get tokenExpired {
    final token = accessToken;
    if (token == null) return false;
    final exp = jwtExpiry(token);
    return exp != null && exp.isBefore(DateTime.now().add(const Duration(minutes: 1)));
  }

  Credentials withTokens({required String accessToken, String? refreshToken}) => Credentials(
        server: server,
        source: source,
        apiKey: apiKey,
        accessToken: accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        clientId: clientId,
      );

  Map<String, dynamic> toJson() => {
        'server': server,
        'source': source.name,
        'api_key': ?apiKey,
        'access_token': ?accessToken,
        'refresh_token': ?refreshToken,
        'client_id': ?clientId,
      };

  /// Null for anything unusable, including the retired `cli` source, which
  /// leaves the app signed out.
  static Credentials? fromJson(Map<String, dynamic> j) {
    final source = CredentialSource.values.where((s) => s.name == j['source']).firstOrNull;
    if (source == null) return null;
    final c = Credentials(
      server: (j['server'] as String?) ?? kDefaultServer,
      source: source,
      apiKey: j['api_key'] as String?,
      accessToken: j['access_token'] as String?,
      refreshToken: j['refresh_token'] as String?,
      clientId: j['client_id'] as String?,
    );
    return c.bearer.isEmpty ? null : c;
  }
}

DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final exp = payload is Map ? payload['exp'] : null;
    return exp is num ? DateTime.fromMillisecondsSinceEpoch((exp * 1000).toInt()) : null;
  } catch (_) {
    return null;
  }
}

String normalizeServer(String input) {
  var s = input.trim();
  if (s.isEmpty) return kDefaultServer;
  if (!s.contains('://')) s = 'https://$s';
  return s.replaceAll(RegExp(r'/+$'), '');
}

/// Where API and token requests go: the server itself on native platforms,
/// this page's origin on web.
Uri apiBase(String server) => kIsWeb ? Uri.parse(Uri.base.origin) : Uri.parse(server);

abstract class CredentialStore {
  Future<Credentials?> read();
  Future<void> write(Credentials credentials);
  Future<void> clear();
}

/// Keychain / libsecret / Credential Manager on native; WebCrypto-wrapped
/// localStorage on web. Failures are swallowed: the web store only works in
/// a secure context (HTTPS or localhost), and a session that cannot be saved
/// should still work until the tab closes rather than block sign-in.
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // The data-protection keychain needs a keychain-access-groups
              // entitlement (and so a signing team); the login keychain does not.
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  static const _key = 'reqall.credentials';
  final FlutterSecureStorage _storage;

  @override
  Future<Credentials?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return Credentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(Credentials credentials) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(credentials.toJson()));
    } catch (e) {
      debugPrint('reqall: credentials not saved: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (e) {
      debugPrint('reqall: credentials not cleared: $e');
    }
  }
}

class MemoryCredentialStore implements CredentialStore {
  MemoryCredentialStore([this.value]);

  Credentials? value;

  @override
  Future<Credentials?> read() async => value;

  @override
  Future<void> write(Credentials credentials) async => value = credentials;

  @override
  Future<void> clear() async => value = null;
}
