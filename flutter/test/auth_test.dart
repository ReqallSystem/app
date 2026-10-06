import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reqall_app/auth/credentials.dart';
import 'package:reqall_app/auth/oauth.dart';

import 'support/fake_api.dart';

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

  test('authorize URL carries PKCE, scope, state and the API resource', () {
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
      'scope': 'api',
      'state': 'st',
      'resource': 'https://www.reqall.net/api',
    });
    expect(appClientId, hasLength(32));
  });

  group('OAuthApi', () {
    test('exchanges a code for oauth credentials', () async {
      final fake = FakeApi()..tokenResponse = {'access_token': 'at', 'refresh_token': 'rt'};
      final c = await OAuthApi(httpClient: fake.client)
          .exchange(server: 'https://www.reqall.net', code: 'c0de', verifier: 'v', redirectUri: 'http://127.0.0.1:1/callback');
      expect(c.source, CredentialSource.oauth);
      expect(c.bearer, 'at');
      expect(c.canRefresh, isTrue);
      expect(fake.tokenRequests.single, containsPair('grant_type', 'authorization_code'));
      expect(fake.tokenRequests.single, containsPair('resource', 'https://www.reqall.net/api'));
      expect(fake.tokenRequests.single, containsPair('client_id', appClientId));
    });

    test('refresh sends the API resource and keeps the rotated refresh token', () async {
      final fake = FakeApi()..tokenResponse = {'access_token': 'at2', 'refresh_token': 'rt2', 'token_type': 'Bearer'};
      const c = Credentials(
          server: 'https://alt.example/', source: CredentialSource.oauth, accessToken: 'at', refreshToken: 'rt', clientId: 'cid');
      final next = await OAuthApi(httpClient: fake.client).refresh(c);
      expect(fake.tokenRequests.single,
          {'grant_type': 'refresh_token', 'refresh_token': 'rt', 'client_id': 'cid', 'resource': 'https://alt.example/api'});
      expect(next.accessToken, 'at2');
      expect(next.refreshToken, 'rt2');
    });

    test('refresh keeps the old refresh token when none is returned', () async {
      final fake = FakeApi()..tokenResponse = {'access_token': 'at2'};
      const c = Credentials(
          server: kDefaultServer, source: CredentialSource.oauth, accessToken: 'at', refreshToken: 'rt', clientId: 'cid');
      final next = await OAuthApi(httpClient: fake.client).refresh(c);
      expect(next.accessToken, 'at2');
      expect(next.refreshToken, 'rt');
    });

    test('a rejected grant is an OAuthException', () async {
      await expectLater(
        OAuthApi(httpClient: FakeApi().client).exchange(server: kDefaultServer, code: 'x', verifier: 'v', redirectUri: 'r'),
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

    test('the retired cli source loads as signed out', () {
      expect(Credentials.fromJson({'server': kDefaultServer, 'source': 'cli', 'api_key': 'rq_old'}), isNull);
      expect(Credentials.fromJson({'server': kDefaultServer, 'source': 'cli', 'access_token': 'at'}), isNull);
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
}
