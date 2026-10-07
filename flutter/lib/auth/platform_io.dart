import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'credentials.dart';
import 'oauth.dart';

bool get _desktop => Platform.isLinux || Platform.isMacOS || Platform.isWindows;

String? oauthUnavailableReason() => _desktop
    ? null
    : 'Browser sign-in on mobile needs the server to allow the app\'s redirect. Use an API key for now.';

/// Runs the PKCE flow through the system browser with a one-shot loopback
/// listener on 127.0.0.1, which the server allows for any client.
Future<Credentials?> runOAuth(OAuthApi api, String server) async {
  final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final redirectUri = 'http://127.0.0.1:${listener.port}/callback';
  final pkce = Pkce.generate();
  final state = randomState();
  final code = Completer<String>();

  final sub = listener.listen((req) async {
    if (req.uri.path != '/callback') {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final q = req.uri.queryParameters;
    final ok = q['code'] != null && q['state'] == state;
    req.response.headers.contentType = ContentType.html;
    req.response.write('<html><body style="font-family:sans-serif;background:#2b1d1d;color:#fdf5e6;padding:40px">'
        '<h2>${ok ? 'Signed in to Reqall' : 'Sign-in failed'}</h2><p>You can close this tab.</p></body></html>');
    await req.response.close();
    if (code.isCompleted) return;
    if (ok) {
      code.complete(q['code']);
    } else {
      code.completeError(OAuthException(q['error_description'] ?? q['error'] ?? 'Sign-in was cancelled'));
    }
  });

  try {
    final url = authorizeUri(server: server, redirectUri: redirectUri, pkce: pkce, state: state);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw const OAuthException('Could not open a browser');
    }
    final value = await code.future.timeout(const Duration(minutes: 5),
        onTimeout: () => throw const OAuthException('Sign-in timed out after 5 minutes'));
    return await api.exchange(server: server, code: value, verifier: pkce.verifier, redirectUri: redirectUri);
  } finally {
    await sub.cancel();
    await listener.close(force: true);
  }
}

Future<Credentials?> completeOAuthRedirect(OAuthApi api) async => null;

bool credentialsPersist() => true;
