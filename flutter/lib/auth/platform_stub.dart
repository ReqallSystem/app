import 'credentials.dart';
import 'oauth.dart';

String? oauthUnavailableReason() => 'Sign-in is not available on this platform; use an API key.';

Future<Credentials?> runOAuth(OAuthApi api, String server) async => null;

Future<Credentials?> completeOAuthRedirect(OAuthApi api) async => null;

bool credentialsPersist() => true;
