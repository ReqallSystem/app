# reqall_app

The Reqall app: your project memory as one stream (the Stream design from
`../designs`), on the live Reqall API.

## Layout

- `lib/api/`: `McpClient` (JSON-RPC `tools/call` to `/mcp`, JSON or SSE replies), `LiveRepository` (summary, records, projects, record detail, remember, status), `DemoRepository` (mock account)
- `lib/auth/`: credentials and secure storage, OAuth 2.1 PKCE, CLI credential discovery, platform glue (`platform_io.dart` / `platform_web.dart`)
- `lib/state/session.dart`: sign-in state, data, token refresh, optimistic writes
- `lib/screens/`: `LoginScreen`, `StreamScreen`
- `tool/serve.py`: serves the web build with a same-origin API proxy

## Signing in

| | Browser sign-in (OAuth) | API key | CLI credentials |
|---|---|---|---|
| Linux / macOS / Windows | ✓ loopback redirect on 127.0.0.1 | ✓ | ✓ `REQALL_API_KEY`, `~/.config/reqall/env`, `config.json` |
| Web on `localhost` | ✓ redirect back to the page | ✓ | |
| Web over the network (e.g. tailscale) | ✗ server only allows loopback redirects | ✓ | |
| Android / iOS | ✗ needs a custom-scheme redirect allowed on the server | ✓ | |

Credentials are kept with `flutter_secure_storage` (libsecret on Linux).
OAuth tokens refresh on expiry or on a 401. CLI credentials are used as they
are and never refreshed, since refreshing would rotate the CLI's token out
from under it. "Try the demo" runs on the mock account without a server.

## Web

The server's CORS policy only admits claude.ai and cursor.com, so the web
build talks to its own origin and `tool/serve.py` forwards `/mcp`, `/oauth/*`
and `/.well-known/*` to the real server:

```sh
flutter build web --release --pwa-strategy=none
python3 tool/serve.py --bind 127.0.0.1 --port 8687        # OAuth works here
python3 tool/serve.py --bind <tailscale-ip> --port 8687   # API key over the network
```

## Checks

```sh
flutter analyze
flutter test        # API, auth, session against a fake MCP server; widgets at phone and desktop sizes
```
