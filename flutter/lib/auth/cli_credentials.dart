import 'dart:convert';

import 'credentials.dart';

/// Resolves credentials left on this machine by the other Reqall clients, in
/// the desktop app's and widget's order:
///   1. REQALL_API_KEY in the environment
///   2. `<config dir>/env`, the file the Claude Code plugin sources (parsed, never sourced)
///   3. `<config dir>/config.json`, written by `reqall login`
/// Only keys and access tokens are taken: refreshing the CLI's refresh token
/// here would rotate it out from under the CLI.
Credentials? resolveCliCredentials({
  required Map<String, String> environment,
  String? envFile,
  String? configJson,
}) {
  final fromFile = parseEnvFile(envFile ?? '');
  String? key = environment['REQALL_API_KEY'];
  if (key == null || key.isEmpty) key = fromFile.key;
  String? accessToken;
  if (key == null || key.isEmpty) {
    key = null;
    try {
      final cfg = jsonDecode(configJson ?? '');
      if (cfg is Map) {
        final apiKey = cfg['api_key'];
        final token = cfg['access_token'];
        if (apiKey is String && apiKey.isNotEmpty) {
          key = apiKey;
        } else if (token is String && token.isNotEmpty) {
          accessToken = token;
        }
      }
    } catch (_) {
      // An unreadable config is the same as no config.
    }
  }
  if (key == null && accessToken == null) return null;

  final url = [environment['REQALL_API_URL'], environment['REQALL_URL'], fromFile.url]
      .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);
  final credentials = Credentials(
    server: normalizeServer(url ?? kDefaultServer),
    source: CredentialSource.cli,
    apiKey: key,
    accessToken: accessToken,
  );
  return credentials.tokenExpired ? null : credentials;
}

({String? key, String? url}) parseEnvFile(String text) {
  String? key;
  String? url;
  String unquote(String v) {
    if (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
      return v.substring(1, v.length - 1);
    }
    return v;
  }

  for (final raw in const LineSplitter().convert(text)) {
    var line = raw.trimLeft();
    if (line.startsWith('export ')) line = line.substring(7);
    if (line.startsWith('REQALL_API_KEY=')) {
      key = unquote(line.substring(15).trim());
    } else if (line.startsWith('REQALL_API_URL=')) {
      url = unquote(line.substring(15).trim());
    } else if (line.startsWith('REQALL_URL=')) {
      url = unquote(line.substring(11).trim());
    }
  }
  return (key: key, url: url);
}
