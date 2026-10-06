// What the console signs requests with, where it keeps them, and how it finds
// credentials the other Reqall clients left on this machine. Mirrors
// flutter/lib/auth/credentials.dart and cli_credentials.dart.
//
// A credentials object is plain data:
//   { server, source: 'apiKey'|'oauth'|'cli', apiKey?, accessToken?,
//     refreshToken?, clientId?, origin? }
// `origin` says where CLI credentials came from, for the status line.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

export const DEFAULT_SERVER = 'https://www.reqall.net'
export const SOURCES = ['apiKey', 'oauth', 'cli']

export function normalizeServer(input) {
  let s = String(input ?? '').trim()
  if (!s) return DEFAULT_SERVER
  if (!s.includes('://')) s = 'https://' + s
  return s.replace(/\/+$/, '')
}

export function hostOf(server) {
  try { return new URL(server).host } catch { return String(server) }
}

export const bearer = (c) => (c && (c.accessToken || c.apiKey)) || ''
export const canRefresh = (c) => !!(c && c.refreshToken && c.clientId)

export function sourceLabel(c) {
  if (!c) return ''
  if (c.source === 'oauth') return 'signed in'
  if (c.source === 'cli') return c.origin || 'CLI credentials'
  return 'API key'
}

/** Expiry of a JWT as epoch ms, or null when the token is not a JWT with exp. */
export function jwtExpiry(token) {
  const parts = String(token).split('.')
  if (parts.length !== 3) return null
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'))
    return typeof payload.exp === 'number' ? payload.exp * 1000 : null
  } catch {
    return null
  }
}

/** True when the access token is a JWT that expires within a minute. */
export function tokenExpired(c, now = Date.now()) {
  if (!c || !c.accessToken) return false
  const exp = jwtExpiry(c.accessToken)
  return exp != null && exp < now + 60_000
}

export function credentialsFromJson(j) {
  if (!j || typeof j !== 'object' || !SOURCES.includes(j.source)) return null
  const str = (v) => (typeof v === 'string' && v ? v : undefined)
  const c = {
    server: normalizeServer(j.server || DEFAULT_SERVER),
    source: j.source,
    apiKey: str(j.apiKey),
    accessToken: str(j.accessToken),
    refreshToken: str(j.refreshToken),
    clientId: str(j.clientId),
    origin: str(j.origin)
  }
  for (const k of Object.keys(c)) if (c[k] === undefined) delete c[k]
  return bearer(c) ? c : null
}

// ------------------------------------------------------------ CLI credentials

function unquote(v) {
  const s = String(v)
  if (s.length >= 2 && ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'")))) {
    return s.slice(1, -1)
  }
  return s
}

/** Parses the plugin's env file line by line; it is never sourced. */
export function parseEnvFile(text) {
  const out = { key: '', url: '' }
  for (const raw of String(text || '').split(/\r?\n/)) {
    let line = raw.trimStart()
    if (line.startsWith('export ')) line = line.slice(7)
    if (line.startsWith('REQALL_API_KEY=')) out.key = unquote(line.slice(15).trim())
    else if (line.startsWith('REQALL_API_URL=')) out.url = unquote(line.slice(15).trim())
    else if (line.startsWith('REQALL_URL=')) out.url = unquote(line.slice(11).trim())
  }
  return out
}

/**
 * Credentials left on this machine by the other Reqall clients, in the
 * desktop app's and widget's order:
 *   1. REQALL_API_KEY in the environment
 *   2. <env dir>/env, the file the Claude Code plugin sources (parsed, never sourced)
 *   3. <config dir>/config.json, written by `reqall login`
 * Only keys and access tokens are taken: refreshing the CLI's refresh token
 * here would rotate it out from under the CLI.
 */
export function resolveCliCredentials({ environment = {}, envFile, configJson, envPath = 'env', configPath = 'config.json', now } = {}) {
  const fromFile = parseEnvFile(envFile || '')
  let apiKey = ''
  let accessToken = ''
  let origin = ''
  if (environment.REQALL_API_KEY) {
    apiKey = environment.REQALL_API_KEY; origin = '$REQALL_API_KEY'
  } else if (fromFile.key) {
    apiKey = fromFile.key; origin = envPath
  } else if (configJson) {
    try {
      const cfg = JSON.parse(configJson)
      if (cfg && typeof cfg.api_key === 'string' && cfg.api_key) {
        apiKey = cfg.api_key; origin = configPath
      } else if (cfg && typeof cfg.access_token === 'string' && cfg.access_token) {
        accessToken = cfg.access_token; origin = configPath
      }
    } catch { /* an unreadable config is the same as no config */ }
  }
  if (!apiKey && !accessToken) return null

  const url = environment.REQALL_API_URL || environment.REQALL_URL || fromFile.url || DEFAULT_SERVER
  const c = { server: normalizeServer(url), source: 'cli', origin }
  if (apiKey) c.apiKey = apiKey
  else c.accessToken = accessToken
  return tokenExpired(c, now) ? null : c
}

/** Where the CLI keeps config.json, per platform; the plugin's env file is under ~/.config/reqall everywhere. */
export function cliPaths({ env = process.env, platform = process.platform, home = os.homedir() } = {}) {
  const tilde = (p) => (p.startsWith(home + path.sep) ? '~' + p.slice(home.length) : p)
  const envDir = env.REQALL_CONFIG_DIR || path.join(home, '.config', 'reqall')
  const configDir = env.REQALL_CONFIG_DIR || (
    platform === 'win32' ? path.join(env.APPDATA || path.join(home, 'AppData', 'Roaming'), 'reqall')
      : platform === 'darwin' ? path.join(home, 'Library', 'Application Support', 'reqall')
        : path.join(env.XDG_CONFIG_HOME || path.join(home, '.config'), 'reqall'))
  const envFile = path.join(envDir, 'env')
  const configFile = path.join(configDir, 'config.json')
  return { envFile, configFile, envLabel: tilde(envFile), configLabel: tilde(configFile) }
}

export function findCliCredentials({ env = process.env, platform = process.platform, home = os.homedir() } = {}) {
  const p = cliPaths({ env, platform, home })
  const read = (f) => { try { return fs.readFileSync(f, 'utf8') } catch { return null } }
  return resolveCliCredentials({
    environment: env,
    envFile: read(p.envFile),
    configJson: read(p.configFile),
    envPath: p.envLabel,
    configPath: p.configLabel
  })
}

// ------------------------------------------------------------------- stores

/**
 * Credentials in one file under userData, encrypted with the OS keychain
 * through Electron's safeStorage (passed in as `crypto` so tests need no
 * Electron). When no keychain is available the store keeps nothing on disk:
 * the sign-in lasts until the app quits, and `persists` says so.
 */
export class FileCredentialStore {
  constructor(file, crypto) {
    this.file = file
    this.crypto = crypto
  }

  get persists() {
    try { return this.crypto.available() } catch { return false }
  }

  read() {
    if (!this.persists) return null
    try {
      const raw = this.crypto.decrypt(fs.readFileSync(this.file))
      return credentialsFromJson(JSON.parse(raw))
    } catch {
      return null
    }
  }

  write(c) {
    if (!this.persists) return
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true })
      fs.writeFileSync(this.file, this.crypto.encrypt(JSON.stringify(c)), { mode: 0o600 })
    } catch (e) {
      console.warn('reqall: credentials not saved:', e.message)
    }
  }

  clear() {
    try { fs.rmSync(this.file, { force: true }) } catch (e) { console.warn('reqall: credentials not cleared:', e.message) }
  }
}

export class MemoryCredentialStore {
  constructor(value = null) {
    this.value = value
    this.persists = true
  }

  read() { return this.value }
  write(c) { this.value = c }
  clear() { this.value = null }
}
