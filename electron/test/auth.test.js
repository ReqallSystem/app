import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import crypto from 'node:crypto'
import * as credentials from '../src/main/credentials.js'
import { challengeFor, authorizeUrl, generatePkce, OAuthApi, runOAuth, APP_CLIENT_ID } from '../src/main/oauth.js'
import { startFakeApi } from './fake-api.js'

const { jwtExpiry, tokenExpired, normalizeServer, credentialsFromJson, sourceLabel, FileCredentialStore } = credentials
const fake = await startFakeApi()
after(() => fake.close())
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'reqall-console-'))
after(() => fs.rmSync(tmp, { recursive: true, force: true }))

const jwt = (exp) => ['e30', Buffer.from(JSON.stringify({ exp })).toString('base64url'), 'sig'].join('.')

test('credentials come only from OAuth or an API key; stored CLI credentials read as signed out', () => {
  assert.deepEqual(credentials.SOURCES, ['apiKey', 'oauth'])
  for (const gone of ['resolveCliCredentials', 'findCliCredentials', 'cliPaths', 'parseEnvFile']) {
    assert.equal(credentials[gone], undefined, `${gone} is gone`)
  }
  assert.equal(credentialsFromJson({ server: 'https://www.reqall.net', source: 'cli', apiKey: 'rq_old', origin: '~/.config/reqall/env' }), null)
  assert.equal(credentialsFromJson({ server: 'https://www.reqall.net', source: 'cli', accessToken: 'at' }), null)
  assert.deepEqual(credentialsFromJson({ server: 'x.test/', source: 'apiKey', apiKey: 'rq_k', origin: 'stale' }), { server: 'https://x.test', source: 'apiKey', apiKey: 'rq_k' })
  assert.equal(sourceLabel({ source: 'oauth' }), 'signed in')
  assert.equal(sourceLabel({ source: 'apiKey' }), 'API key')
})

test('jwt expiry and normalisation helpers', () => {
  assert.equal(jwtExpiry(jwt(100)), 100_000)
  assert.equal(jwtExpiry('not-a-jwt'), null)
  assert.equal(tokenExpired({ accessToken: jwt(Date.now() / 1000 + 30) }), true, 'within a minute counts as expired')
  assert.equal(tokenExpired({ apiKey: 'k' }), false)
  assert.equal(normalizeServer(' www.reqall.net// '), 'https://www.reqall.net')
  assert.equal(normalizeServer(''), 'https://www.reqall.net')
  assert.equal(credentialsFromJson({ source: 'apiKey', server: 'x.test' }), null, 'no bearer, no credentials')
  assert.equal(credentialsFromJson({ source: 'nope', apiKey: 'k' }), null)
})

test('file store encrypts at rest and keeps nothing without a keychain', () => {
  const key = crypto.randomBytes(32)
  const box = {
    available: () => true,
    encrypt: (s) => { const iv = crypto.randomBytes(12); const c = crypto.createCipheriv('aes-256-gcm', key, iv); const e = Buffer.concat([c.update(s, 'utf8'), c.final()]); return Buffer.concat([iv, c.getAuthTag(), e]) },
    decrypt: (b) => { const d = crypto.createDecipheriv('aes-256-gcm', key, b.subarray(0, 12)); d.setAuthTag(b.subarray(12, 28)); return Buffer.concat([d.update(b.subarray(28)), d.final()]).toString('utf8') }
  }
  const file = path.join(tmp, 'creds.bin')
  const store = new FileCredentialStore(file, box)
  store.write({ server: 'https://www.reqall.net', source: 'apiKey', apiKey: 'secret-key' })
  assert.ok(!fs.readFileSync(file).includes('secret-key'), 'the key is not on disk in clear')
  assert.equal(store.read().apiKey, 'secret-key')
  if (process.platform !== 'win32') assert.equal(fs.statSync(file).mode & 0o777, 0o600)
  store.clear()
  assert.equal(store.read(), null)
  fs.writeFileSync(file, box.encrypt(JSON.stringify({ server: 'https://www.reqall.net', source: 'cli', apiKey: 'from-the-cli' })))
  assert.equal(store.read(), null, 'a saved CLI sign-in loads as signed out')

  const none = new FileCredentialStore(path.join(tmp, 'none.bin'), { available: () => false })
  assert.equal(none.persists, false)
  none.write({ server: 'https://x', source: 'apiKey', apiKey: 'k' })
  assert.equal(fs.existsSync(path.join(tmp, 'none.bin')), false)
})

test('PKCE challenge matches RFC 7636 appendix B', () => {
  assert.equal(challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM')
  const u = new URL(authorizeUrl({ server: 'www.reqall.net', redirectUri: 'http://127.0.0.1:5/callback', pkce: generatePkce(), state: 's' }))
  assert.equal(u.origin + u.pathname, 'https://www.reqall.net/oauth/authorize')
  assert.equal(u.searchParams.get('client_id'), APP_CLIENT_ID)
  assert.equal(u.searchParams.get('resource'), 'https://www.reqall.net/api')
  assert.equal(u.searchParams.get('scope'), 'api')
  assert.equal(u.searchParams.get('response_type'), 'code')
  assert.equal(u.searchParams.get('redirect_uri'), 'http://127.0.0.1:5/callback')
  assert.equal(u.searchParams.get('state'), 's')
  assert.equal(u.searchParams.get('code_challenge_method'), 'S256')
})

test('runOAuth: browser round trip through the loopback listener, then token exchange', async () => {
  fake.tokenResponse = { access_token: 'at-1', refresh_token: 'rt-1' }
  const openExternal = async (url) => {
    const u = new URL(url)
    const back = new URL(u.searchParams.get('redirect_uri'))
    back.searchParams.set('code', 'the-code')
    back.searchParams.set('state', u.searchParams.get('state'))
    const res = await fetch(back)
    assert.match(await res.text(), /signed in/)
  }
  const c = await runOAuth(new OAuthApi(), fake.url, { openExternal })
  assert.deepEqual(c, { server: fake.url, source: 'oauth', accessToken: 'at-1', refreshToken: 'rt-1', clientId: APP_CLIENT_ID })
  const req = fake.tokenRequests.at(-1)
  assert.equal(req.grant_type, 'authorization_code')
  assert.equal(req.code, 'the-code')
  assert.equal(req.client_id, APP_CLIENT_ID)
  assert.equal(req.resource, fake.url + '/api')
  assert.equal(challengeFor(req.code_verifier).length, 43)
  assert.match(req.redirect_uri, /^http:\/\/127\.0\.0\.1:\d+\/callback$/)
})

test('runOAuth: a wrong state is rejected, and abort cancels', async () => {
  const forged = async (url) => {
    const back = new URL(new URL(url).searchParams.get('redirect_uri'))
    back.searchParams.set('code', 'c')
    back.searchParams.set('state', 'forged')
    await fetch(back)
  }
  await assert.rejects(runOAuth(new OAuthApi(), fake.url, { openExternal: forged }), /cancelled/)
  const ac = new AbortController()
  const p = runOAuth(new OAuthApi(), fake.url, { openExternal: async () => setTimeout(() => ac.abort(), 10), signal: ac.signal })
  await assert.rejects(p, /cancelled/)
})

test('refresh rotates the refresh token, keeps the old one when none is returned, and reports failures', async () => {
  fake.tokenResponse = { access_token: 'at-2', refresh_token: 'rt-2', token_type: 'Bearer', expires_in: 28800, scope: 'api' }
  const rotated = await new OAuthApi().refresh({ server: fake.url, source: 'oauth', accessToken: 'x', refreshToken: 'rt-1', clientId: 'cid' })
  assert.equal(rotated.refreshToken, 'rt-2')
  assert.deepEqual(fake.tokenRequests.at(-1), { grant_type: 'refresh_token', refresh_token: 'rt-1', client_id: 'cid', resource: fake.url + '/api' })
  fake.tokenResponse = { access_token: 'at-3' }
  const c = await new OAuthApi().refresh(rotated)
  assert.equal(c.accessToken, 'at-3')
  assert.equal(c.refreshToken, 'rt-2')
  fake.tokenResponse = null
  await assert.rejects(new OAuthApi().refresh(c), /Sign-in failed: invalid_grant/)
})
