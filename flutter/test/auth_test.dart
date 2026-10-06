import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reqall_app/auth/cli_credentials.dart';
import 'package:reqall_app/auth/credentials.dart';
import 'package:reqall_app/auth/oauth.dart';

import 'support/fake_mcp.dart';

String jwt(DateTime exp) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

void main() {
  group('PKCE', () {
    test('matches the RFC 7636 example', () {
      expect(Pkce.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('generates unpadded url-safe pairs', () {
      final p = Pkce.generate();
      expect(p.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(p.challenge, Pkce.challengeFor(p.verifier));
    });
  });

  test('authorize URL carries PKCE, scope, state and the MCP resource', () {
    final p = Pkce.generate();
    final uri = authorizeUri(
        server: 'https://www.reqall.net/', redirectUri: 'http://127.0.0.1:5555/callback', pkce: p, state: 'st');
    expect(uri.toString(), startsWith('https://www.reqall.net/oauth/authorize?'));
    expect(uri.queryParameters, {
      'client_id': appClientId,
      'redirect_uri': 'http://127.0.0.1:5555/callback',
      'response_type': 'code',
      'code_challenge': p.challenge,
      'code_challenge_method': 'S256',
      'scope': 'mcp',
      'state': 'st',
      'resource': 'https://www.reqall.net/mcp',
    });
    expect(appClientId, hasLength(32));
  });

  group('OAuthApi', () {
    test('exchanges a code for oauth credentials', () async {
      final fake = FakeMcp()..tokenResponse = {'access_token': 'at', 'refresh_token': 'rt'};
      final c = await OAuthApi(httpClient: fake.client)
          .exchange(server: 'https://www.reqall.net', code: 'c0de', verifier: 'v', redirectUri: 'http://127.0.0.1:1/callback');
      expect(c.source, CredentialSource.oauth);
      expect(c.bearer, 'at');
      expect(c.canRefresh, isTrue);
      expect(fake.tokenRequests.single, containsPair('grant_type', 'authorization_code'));
      expect(fake.tokenRequests.single, containsPair('resource', 'https://www.reqall.net/mcp'));
    });

    test('refresh keeps the old refresh token when none is returned', () async {
      final fake = FakeMcp()..tokenResponse = {'access_token': 'at2'};
      const c = Credentials(
          server: kDefaultServer, source: CredentialSource.oauth, accessToken: 'at', refreshToken: 'rt', clientId: 'cid');
      final next = await OAuthApi(httpClient: fake.client).refresh(c);
      expect(next.accessToken, 'at2');
      expect(next.refreshToken, 'rt');
    });

    test('a rejected grant is an OAuthException', () async {
      await expectLater(
        OAuthApi(httpClient: FakeMcp().client).exchange(server: kDefaultServer, code: 'x', verifier: 'v', redirectUri: 'r'),
        throwsA(isA<OAuthException>()),
      );
    });
  });

  group('Credentials', () {
    test('round-trips through JSON', () {
      const c = Credentials(server: kDefaultServer, source: CredentialSource.apiKey, apiKey: 'k');
      final back = Credentials.fromJson(c.toJson())!;
      expect(back.bearer, 'k');
      expect(back.source, CredentialSource.apiKey);
      expect(back.toJson().containsKey('access_token'), isFalse);
    });

    test('expiry comes from the JWT exp claim', () {
      final soon = Credentials(
          server: kDefaultServer, source: CredentialSource.oauth, accessToken: jwt(DateTime.now().add(const Duration(seconds: 30))));
      final later = Credentials(
          server: kDefaultServer, source: CredentialSource.oauth, accessToken: jwt(DateTime.now().add(const Duration(hours: 1))));
      expect(soon.tokenExpired, isTrue);
      expect(later.tokenExpired, isFalse);
    });

    test('normalizeServer', () {
      expect(normalizeServer(''), kDefaultServer);
      expect(normalizeServer('reqall.example/'), 'https://reqall.example');
      expect(normalizeServer('http://localhost:3000//'), 'http://localhost:3000');
    });
  });

  group('CLI credentials', () {
    test('environment beats env file beats config.json', () {
      final c = resolveCliCredentials(
        environment: {'REQALL_API_KEY': 'from-env'},
        envFile: 'REQALL_API_KEY=from-file',
        configJson: '{"api_key":"from-config"}',
      );
      expect(c!.bearer, 'from-env');
      expect(c.source, CredentialSource.cli);
      expect(resolveCliCredentials(environment: {}, envFile: 'export REQALL_API_KEY="from-file"\n', configJson: '{}')!.bearer,
          'from-file');
      expect(resolveCliCredentials(environment: {}, configJson: '{"api_key":"from-config"}')!.bearer, 'from-config');
    });

    test('takes an unexpired access token but never the refresh token', () {
      final token = jwt(DateTime.now().add(const Duration(hours: 1)));
      final c = resolveCliCredentials(
          environment: {}, configJson: jsonEncode({'access_token': token, 'refresh_token': 'rt', 'client_id': 'cli'}))!;
      expect(c.bearer, token);
      expect(c.canRefresh, isFalse);
      final stale = jwt(DateTime.now().subtract(const Duration(hours: 1)));
      expect(resolveCliCredentials(environment: {}, configJson: jsonEncode({'access_token': stale})), isNull);
    });

    test('server comes from REQALL_API_URL or the env file', () {
      final c = resolveCliCredentials(environment: {}, envFile: "REQALL_API_KEY=k\nREQALL_API_URL='https://alt.example/'");
      expect(c!.server, 'https://alt.example');
      expect(resolveCliCredentials(environment: {}, envFile: '# nothing'), isNull);
    });
  });
}
