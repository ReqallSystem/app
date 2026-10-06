# Reqall Console

The Reqall desktop app as a keyboard-first terminal: the **Console** design
from `../designs` (concept 04), on the Reqall REST API (`/api/v1`). It signs
in, reads and writes the same way as the Flutter app in `../flutter`.

| | |
|---|---|
| ![](screenshots/console-desktop.png) | ![](screenshots/console-palette.png) |
| ![](screenshots/sign-in.png) | ![](screenshots/console-remember.png) |

## Using it

- **Status line**: host, sync state (`● ok`, `● paused` on 403, `● offline`), memories / open todos / open issues / projects, and how you signed in.
- **Records**: newest first, 50 at a time; scrolling or `j` near the end loads more. Filters (`kind:`, `project:`) run on the server.
- **Preview**: body and links of the selected record. Enter on a link that is not in the list peeks at it; `esc` goes back.
- **Log**: every request the app makes (`GET /api/v1/records?limit=50 … 200 OK 84ms`), typed out as it happens. Detail fetches only show up when they fail.
- **Palette** (`:`, `/`, `⌘K` / `Ctrl+K`): fuzzy over actions, `resolve` / `reopen` / `archive` for the selection, `kind:*`, `project:*`, and `#id` goto.
- **Remember** (`a`): project, title, optional body, kind or auto. `Ctrl+Enter` saves.

| Key | | Key | |
|---|---|---|---|
| `j` / `k` | move | `r` | refresh |
| `h` / `l` | across the actions | `o` | open the dashboard |
| `⏎` | activate / open the record | `a` | remember |
| `x` | resolve (or reopen) | `:` `/` `⌘K` | palette |
| `esc` | back: peek, then filters | | |

Everything is also clickable: click selects a row, a second click opens it.

## Signing in

- **Browser** (OAuth 2.1 + PKCE, scope `api`, resource `{server}/api`): the system browser signs in and redirects to a one-shot listener on `127.0.0.1`. Tokens refresh on expiry or a 401, one refresh at a time, since refresh tokens rotate.
- **API key**: paste an `rq_…` key from the dashboard; it is sent as the bearer token.
- **Demo**: the mock account from the design workshop; nothing leaves the machine.

Those are the only two: the console does not read credentials other Reqall
clients left on the machine (`REQALL_API_KEY`, `~/.config/reqall`). A sign-in
saved by an older build from those reads as signed out.

Credentials are encrypted with the OS keychain through Electron's
`safeStorage` (Keychain, DPAPI, or the Secret Service on Linux: the app asks
for `gnome-libsecret`, so it works on Hyprland and other non-GNOME desktops).
Without a keychain nothing is written and the sign-in lasts until you quit;
the sign-in screen says so.

## Layout

- `src/main/index.js`: app lifecycle, window, menu, keychain
- `src/main/bridge.js`: session ⇄ renderer over IPC (arguments are coerced; the renderer is not trusted)
- `src/main/session.js`: sign-in state, data, token refresh, filters, optimistic writes, the request log
- `src/main/api.js`: REST client for `/api/v1`, bearer read per request, at most 4 in flight, 429s retried after `Retry-After`
- `src/main/repository.js`, `demo.js`: live and mock data behind the same methods
- `src/main/credentials.js`, `oauth.js`: credential storage, PKCE and the loopback redirect
- `src/preload.cjs`: the `window.reqall` bridge (context isolation, sandbox, no Node in the page)
- `src/renderer/`: the console itself, plain HTML/CSS/JS with a strict CSP and bundled JetBrains Mono
- `src/shared/model.js`: kinds, ages, fuzzy match, REST records and projects to the console's shape

## Develop

```sh
npm install
npm start            # the app
npm test             # node:test: REST client, auth, session against a local fake server
npm run screenshots  # renders the demo offscreen into screenshots/ (no display needed)
npm run pack         # unpacked build in dist/; npm run build for AppImage / tar.gz / dmg / exe
```

On Hyprland the window tiles like any other; add a window rule for class
`reqall-console` to float it.
