/// Platform-specific sign-in pieces: the OAuth browser round trip and
/// whether credentials can be kept.
///
///   oauthUnavailableReason()  null when "Sign in with Reqall" can run here
///   runOAuth(api, server)     desktop: loopback redirect, returns credentials;
///                             web: navigates away, completes on return
///   completeOAuthRedirect()   web: finishes a sign-in the page came back from
///   credentialsPersist()      false on web pages that are not a secure context
library;

export 'platform_stub.dart'
    if (dart.library.io) 'platform_io.dart'
    if (dart.library.js_interop) 'platform_web.dart';
