// What the console signs requests with and where it keeps them. Credentials
// come only from a browser sign-in (OAuth) or a pasted API key. Mirrors
// flutter/lib/auth/credentials.dart.
//
// A credentials object is plain data:
//   { server, source: 'apiKey'|'oauth', apiKey?, accessToken?,
//     refreshToken?, clientId? }

import fs from 'node:fs'
import path from 'node:path'

export const DEFAULT_SERVER = 'https://www.reqall.net'
export const SOURCES = ['apiKey', 'oauth']

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
  return c.source === 'oauth' ? 'signed in' : 'API key'
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

/** Stored credentials, or null for anything unusable (including the old 'cli' source). */
export function credentialsFromJson(j) {
  if (!j || typeof j !== 'object' || !SOURCES.includes(j.source)) return null
  const str = (v) => (typeof v === 'string' && v ? v : undefined)
  const c = {
    server: normalizeServer(j.server || DEFAULT_SERVER),
    source: j.source,
    apiKey: str(j.apiKey),
    accessToken: str(j.accessToken),
    refreshToken: str(j.refreshToken),
    clientId: str(j.clientId)
  }
  for (const k of Object.keys(c)) if (c[k] === undefined) delete c[k]
  return bearer(c) ? c : null
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
