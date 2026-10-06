// OAuth 2.1 authorization code + PKCE against the Reqall server, the same flow
// the CLI and the Flutter app run. The server accepts unregistered clients
// whose redirect_uri is a loopback address, so the app needs no registration:
// a one-shot listener on 127.0.0.1 catches the redirect from the browser.

import crypto from 'node:crypto'
import http from 'node:http'
import { normalizeServer } from './credentials.js'

const b64 = (buf) => Buffer.from(buf).toString('base64url')

export function challengeFor(verifier) {
  return b64(crypto.createHash('sha256').update(verifier, 'ascii').digest())
}

export function generatePkce() {
  const verifier = b64(crypto.randomBytes(32))
  return { verifier, challenge: challengeFor(verifier) }
}

export const randomState = () => b64(crypto.randomBytes(16))

/** The app's stable public client id, derived like the CLI's and shared with the Flutter app. */
export const APP_CLIENT_ID = crypto.createHash('sha256').update('reqall-app').digest('hex').slice(0, 32)

/** RFC 8707 resource: tokens are bound to the server's MCP endpoint. */
export const mcpResource = (server) => normalizeServer(server) + '/mcp'

export function authorizeUrl({ server, redirectUri, pkce, state }) {
  const u = new URL(normalizeServer(server) + '/oauth/authorize')
  const q = {
    client_id: APP_CLIENT_ID,
    redirect_uri: redirectUri,
    response_type: 'code',
    code_challenge: pkce.challenge,
    code_challenge_method: 'S256',
    scope: 'mcp',
    state,
    resource: mcpResource(server)
  }
  for (const [k, v] of Object.entries(q)) u.searchParams.set(k, v)
  return u.toString()
}

export class OAuthError extends Error {}

export class OAuthApi {
  constructor({ fetchImpl = fetch } = {}) {
    this.fetchImpl = fetchImpl
  }

  async exchange({ server, code, verifier, redirectUri }) {
    const tokens = await this.#token(server, {
      grant_type: 'authorization_code',
      code,
      code_verifier: verifier,
      redirect_uri: redirectUri,
      client_id: APP_CLIENT_ID,
      resource: mcpResource(server)
    })
    const c = { server: normalizeServer(server), source: 'oauth', accessToken: tokens.access_token, clientId: APP_CLIENT_ID }
    if (tokens.refresh_token) c.refreshToken = tokens.refresh_token
    return c
  }

  async refresh(c) {
    if (!c || !c.refreshToken || !c.clientId) throw new OAuthError('Nothing to refresh with')
    const tokens = await this.#token(c.server, {
      grant_type: 'refresh_token',
      refresh_token: c.refreshToken,
      client_id: c.clientId,
      resource: mcpResource(c.server)
    })
    return { ...c, accessToken: tokens.access_token, refreshToken: tokens.refresh_token || c.refreshToken }
  }

  async #token(server, form) {
    const url = normalizeServer(server) + '/oauth/token'
    let res
    try {
      res = await this.fetchImpl(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(form).toString(),
        signal: AbortSignal.timeout(20000)
      })
    } catch {
      throw new OAuthError('Could not reach ' + new URL(url).host)
    }
    let json = null
    try { json = JSON.parse(await res.text()) } catch { /* not JSON */ }
    if (res.status !== 200 || !json || typeof json.access_token !== 'string') {
      const why = (json && (json.error_description || json.message || json.error)) || 'HTTP ' + res.status
      throw new OAuthError('Sign-in failed: ' + why)
    }
    return json
  }
}

const page = (ok) => `<!doctype html><meta charset="utf-8"><title>Reqall</title>
<body style="font-family:'JetBrains Mono',monospace;background:#140e0e;color:#fdf5e6;padding:40px">
<h2 style="color:${ok ? '#4ade80' : '#ff8a80'}">${ok ? '✓ signed in to reqall' : '✗ sign-in failed'}</h2>
<p style="color:#a9a9a9">You can close this tab and go back to the console.</p></body>`

/**
 * Runs the PKCE flow through the system browser. `openExternal(url)` opens
 * the authorize page; the promise settles when the browser comes back to the
 * loopback listener, after `timeoutMs`, or when `signal` aborts.
 */
export async function runOAuth(api, server, { openExternal, timeoutMs = 5 * 60_000, signal } = {}) {
  const pkce = generatePkce()
  const state = randomState()
  let settle
  const code = new Promise((resolve, reject) => { settle = { resolve, reject } })
  code.catch(() => {}) // awaited below; this only keeps an early rejection from going unhandled

  const listener = http.createServer((req, res) => {
    const u = new URL(req.url, 'http://127.0.0.1')
    if (u.pathname !== '/callback') {
      res.writeHead(404).end()
      return
    }
    const got = u.searchParams.get('code')
    const ok = !!got && u.searchParams.get('state') === state
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(page(ok))
    if (ok) settle.resolve(got)
    else settle.reject(new OAuthError(u.searchParams.get('error_description') || u.searchParams.get('error') || 'Sign-in was cancelled'))
  })
  await new Promise((resolve, reject) => {
    listener.once('error', reject)
    listener.listen(0, '127.0.0.1', resolve)
  })
  const redirectUri = `http://127.0.0.1:${listener.address().port}/callback`
  const timer = setTimeout(() => settle.reject(new OAuthError('Sign-in timed out after 5 minutes')), timeoutMs)
  const abort = () => settle.reject(new OAuthError('Sign-in was cancelled'))
  if (signal) {
    if (signal.aborted) abort()
    else signal.addEventListener('abort', abort, { once: true })
  }

  try {
    await openExternal(authorizeUrl({ server, redirectUri, pkce, state }))
    const value = await code
    return await api.exchange({ server, code: value, verifier: pkce.verifier, redirectUri })
  } finally {
    clearTimeout(timer)
    if (signal) signal.removeEventListener('abort', abort)
    listener.closeAllConnections()
    listener.close()
  }
}
