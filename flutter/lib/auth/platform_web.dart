import 'package:web/web.dart' as web;

import 'credentials.dart';
import 'oauth.dart';

const _verifierKey = 'reqall.oauth.verifier';
const _stateKey = 'reqall.oauth.state';
const _serverKey = 'reqall.oauth.server';

bool get _loopback {
  final host = Uri.base.host;
  return host == 'localhost' || host == '127.0.0.1' || host == '[::1]' || host == '::1';
}

/// The server only accepts loopback redirect URIs from unregistered
/// clients, so a page served from any other host cannot complete sign-in.
String? oauthUnavailableReason() => _loopback
    ? null
    : 'Browser sign-in works when this page is opened from localhost. Over the network, use an API key.';

String _redirectUri() => '${Uri.base.origin}/';

Future<Credentials?> runOAuth(OAuthApi api, String server) async {
  final pkce = Pkce.generate();
  final state = randomState();
  final store = web.window.sessionStorage;
  store.setItem(_verifierKey, pkce.verifier);
  store.setItem(_stateKey, state);
  store.setItem(_serverKey, server);
  web.window.location.assign(
      authorizeUri(server: server, redirectUri: _redirectUri(), pkce: pkce, state: state).toString());
  return null;
}

Future<Credentials?> completeOAuthRedirect(OAuthApi api) async {
  final q = Uri.base.queryParameters;
  final code = q['code'];
  final error = q['error'];
  if (code == null && error == null) return null;

  final store = web.window.sessionStorage;
  final verifier = store.getItem(_verifierKey);
  final state = store.getItem(_stateKey);
  final server = store.getItem(_serverKey) ?? kDefaultServer;
  for (final k in [_verifierKey, _stateKey, _serverKey]) {
    store.removeItem(k);
  }
  // Drop ?code=…&state=… from the address bar either way.
  final fragment = Uri.base.fragment;
  web.window.history.replaceState(null, '', '${Uri.base.path}${fragment.isEmpty ? '' : '#$fragment'}');

  if (error != null) throw OAuthException(q['error_description'] ?? error);
  if (verifier == null || state == null || q['state'] != state) {
    throw const OAuthException('Sign-in could not be verified; try again');
  }
  return api.exchange(server: server, code: code!, verifier: verifier, redirectUri: _redirectUri());
}

Future<Credentials?> findCliCredentials() async => null;
