# reqall_app

The Reqall app: your project memory as one stream (the Stream design from
`../designs`), on the live Reqall API.

## Layout

- `lib/api/`: `ApiClient` (REST calls to `/api/v1` with a bearer, at most 4 in flight, 429s retried after `Retry-After`), `LiveRepository` (summary, records, projects, record detail, remember, status), `DemoRepository` (mock account)
- `lib/auth/`: credentials and secure storage, OAuth 2.1 PKCE, platform glue (`platform_io.dart` / `platform_web.dart`)
- `lib/state/session.dart`: sign-in state, data, token refresh, optimistic writes
- `lib/screens/`: `LoginScreen`, `StreamScreen`
- `tool/serve.py`: serves the web build with a same-origin API proxy

## Signing in

Sign in with OAuth or paste an API key. The app does not read the CLI's or
plugin's credential files.

| | Browser sign-in (OAuth) | API key |
|---|---|---|
| Linux / macOS / Windows | ✓ loopback redirect on 127.0.0.1 | ✓ |
| Web on `localhost` | ✓ redirect back to the page | ✓ |
| Web over the network (e.g. tailscale) | ✗ server only allows loopback redirects | ✓ |
| Android / iOS | ✗ needs a custom-scheme redirect allowed on the server | ✓ |

OAuth is authorization code + PKCE with `scope=api` and
`resource={server}/api`; an API key (`rq_…`) is sent as the bearer as is.

Credentials are kept with `flutter_secure_storage` (libsecret on Linux, the
login keychain on macOS). On web it needs a secure context (HTTPS or
localhost); over plain http on the network a sign-in lasts until the tab
closes, and the login screen says so.
OAuth tokens refresh on expiry or on a 401. Refresh tokens rotate on every
use, so the app runs one refresh at a time and saves the new token each time.
If an older build saved CLI credentials, the app ignores them and starts
signed out. "Try the demo" runs on the mock account without a server.

## Web

The server does not send CORS headers for the REST API yet
(fingerskier/reqall_net#124), so the web build talks to its own origin and
`tool/serve.py` forwards `/api/*`, `/oauth/*` and `/.well-known/*` to the real
server:

```sh
flutter build web --release --pwa-strategy=none
python3 tool/serve.py --bind 127.0.0.1 --port 8687        # OAuth works here
python3 tool/serve.py --bind <tailscale-ip> --port 8687   # API key over the network
```

## Checks

```sh
flutter analyze
flutter test        # API, auth, session against a fake REST server; widgets at phone and desktop sizes
```
