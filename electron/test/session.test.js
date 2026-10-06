import { test, after, beforeEach } from 'node:test'
import assert from 'node:assert/strict'
import { Session } from '../src/main/session.js'
import { MemoryCredentialStore } from '../src/main/credentials.js'
import { DemoRepository } from '../src/main/demo.js'
import { startFakeApi, until } from './fake-api.js'

const fake = await startFakeApi()
after(() => fake.close())
beforeEach(() => {
  fake.validTokens = new Set(['good-key'])
  fake.forceStatus = null
  fake.forceBody = null
  fake.failWrites = false
  fake.tokenResponse = null
  fake.calls.length = 0
})

function make(opts = {}) {
  const lines = []
  const s = new Session({ store: new MemoryCredentialStore(), demo: (o) => new DemoRepository({ ...o, latencyMs: 2 }), ...opts })
  s.on('log', (l) => lines.push(...l))
  return { s, lines }
}
const ready = (s) => until(s, () => s.phase === 'ready' && !s.loading && s.updated != null)

test('starts signed out with no CLI option, even over saved CLI credentials', async () => {
  const { s } = make({ store: new MemoryCredentialStore({ server: fake.url, source: 'cli', apiKey: 'good-key', origin: '~/.config/reqall/env' }) })
  await s.start()
  assert.equal(s.phase, 'signedOut')
  assert.equal(s.credentials, null)
  assert.equal(s.snapshot().cli, undefined)
  assert.equal(s.continueWithCli, undefined)
  assert.equal(fake.calls.length, 0, 'nothing is sent with them')
})

test('a rejected API key leaves the session signed out with a reason', async () => {
  const { s, lines } = make()
  await s.start()
  await s.signInWithApiKey('bad-key', fake.url)
  assert.equal(s.phase, 'signedOut')
  assert.match(s.signInError, /rejected \(401\)/)
  assert.ok(lines.some((l) => l.startsWith('✗ GET /api/v1/records?limit=1') && l.includes('401')))
  assert.equal(s.store.read(), null)
})

test('API key sign-in validates, persists, and loads summary, records, projects', async () => {
  const { s, lines } = make()
  await s.start()
  await s.signInWithApiKey(' good-key ', fake.url)
  await ready(s)
  assert.equal(s.store.read().apiKey, 'good-key')
  assert.deepEqual(s.summary, { memories: 60, openTodos: 15, openIssues: 15, projects: 2 })
  assert.equal(s.total, 60)
  assert.equal(s.projects.length, 2)
  assert.ok(lines.includes('$ reqall refresh'))
  assert.ok(lines.some((l) => /^→ GET \/api\/v1\/records\?limit=1&status=open&kind=todo … 200 OK \d+ms$/.test(l)))
  assert.ok(lines.some((l) => /^→ GET \/api\/v1\/records\?limit=50 … 200 OK \d+ms$/.test(l)))
  assert.ok(lines.some((l) => /^→ GET \/api\/v1\/projects … 200 OK \d+ms$/.test(l)))
  assert.ok(!lines.some((l) => /\/records\/\d+/.test(l)), 'detail prefetches stay out of the log')
  assert.ok(lines.includes('✓ 60 memories · 15 todo · 15 issues · 2 projects'))
  const snap = s.snapshot()
  assert.equal(JSON.parse(JSON.stringify(snap)).records.length, 50, 'the snapshot survives structured cloning')
})

test('saved credentials are used on start; loadMore pages; filters go to the server', async () => {
  const { s } = make({ store: new MemoryCredentialStore({ server: fake.url, source: 'apiKey', apiKey: 'good-key' }) })
  await s.start()
  await ready(s)
  await s.loadMore()
  assert.equal(s.records.length, 60)
  assert.equal(s.hasMore, false)
  await s.setFilter({ kind: 'issue' })
  assert.equal(s.total, 15)
  assert.ok(s.records.every((m) => m.kind === 'issue'))
  assert.deepEqual(fake.calls.at(-1), { method: 'GET', path: '/api/v1/records', query: { limit: '50', kind: 'issue' } })
  await s.setFilter({ projectId: 2 })
  assert.ok(s.records.every((m) => m.kind === 'issue' && m.projectId === 2))
  await s.setFilter({ kind: null, projectId: null })
  assert.equal(s.total, 60)
  fake.forceStatus = 500
  await s.setFilter({ kind: 'todo' })
  assert.equal(s.filter.kind, null, 'a failed filter does not stick')
  assert.equal(s.problem, 'offline')
})

test('a validated sign-in does not fetch the summary twice', async () => {
  const { s } = make()
  await s.start()
  await s.signInWithApiKey('good-key', fake.url)
  await ready(s)
  assert.equal(fake.calls.filter((c) => c.path === '/api/v1/records' && c.query.limit === '1' && !c.query.kind).length, 1)
})

test('detail folds the body into the list and keeps links', async () => {
  const { s } = make({ store: new MemoryCredentialStore({ server: fake.url, source: 'apiKey', apiKey: 'good-key' }) })
  await s.start()
  await ready(s)
  const d = await s.detail(1000)
  assert.equal(d.memory.body, 'Body of 1000')
  assert.equal(s.records[0].body, 'Body of 1000')
  assert.deepEqual(s.snapshot().details[1000].links, [{ otherId: 999, relationship: 'implements', outgoing: true }])
  assert.equal(await s.detail(1), null, 'a record the server will not return')
  assert.equal(s.snapshot().detailErrors[1], 'Not found')
  assert.equal(s.problem, null, 'a 404 is not an outage')
  const before = fake.calls.length
  assert.equal(await s.detail(1), null)
  assert.equal(fake.calls.length, before, 'a failed detail is not refetched until a refresh')
})

test('remember inserts the new record; setStatus is optimistic and reverts on failure', async () => {
  const { s, lines } = make({ store: new MemoryCredentialStore({ server: fake.url, source: 'apiKey', apiKey: 'good-key' }) })
  await s.start()
  await ready(s)
  assert.equal(await s.remember({ projectId: 99, title: 'x' }), 'Pick a project')
  assert.equal(await s.remember({ projectId: 1, title: ' New idea ', body: 'b', kind: 'todo' }), null)
  assert.equal(s.records[0].title, 'New idea')
  assert.equal(s.records[0].project, 'lumen-labs/atlas-app', 'filled from the chosen project')
  assert.equal(s.lastAddedId, s.records[0].id)
  assert.ok(lines.some((l) => /^→ POST \/api\/v1\/records … 201 Created \d+ms$/.test(l)))
  assert.equal(s.summary.memories, 61)

  assert.equal(await s.setStatus(1000, 'resolved'), null)
  assert.equal(s.records.find((m) => m.id === 1000).status, 'resolved')
  assert.equal(s.records.find((m) => m.id === 1000).project, 'lumen-labs/atlas-app', 'PATCH keeps the old project name')
  assert.ok(lines.some((l) => /^→ PATCH \/api\/v1\/records\/1000 … 200 OK \d+ms$/.test(l)))
  const issues = s.summary.openIssues
  assert.equal(await s.setStatus(999, 'resolved'), null) // an open issue
  assert.equal(s.summary.openIssues, issues - 1)
  assert.equal(await s.setStatus(999, 'open'), null)
  assert.equal(s.summary.openIssues, issues)
  fake.failWrites = true
  const p = s.setStatus(1000, 'archived')
  assert.equal(s.records.find((m) => m.id === 1000).status, 'archived', 'applied before the server answers')
  assert.match(await p, /writes are failing/)
  assert.equal(s.records.find((m) => m.id === 1000).status, 'resolved', 'reverted')
  assert.equal(s.problem, null, 'a refused write is not an outage')
})

test('a 403 marks the account paused without signing out', async () => {
  const { s } = make({ store: new MemoryCredentialStore({ server: fake.url, source: 'apiKey', apiKey: 'good-key' }) })
  await s.start()
  await ready(s)
  fake.forceStatus = 403
  fake.forceBody = { error: 'key_paused', message: 'This key is paused' }
  await s.refresh()
  assert.equal(s.phase, 'ready')
  assert.equal(s.problem, 'paused')
  assert.equal(s.problemMessage, 'This key is paused')
  fake.forceStatus = null
  await s.refresh()
  assert.equal(s.problem, null)
})

test('a paused key is named when signing in', async () => {
  const { s } = make()
  await s.start()
  fake.forceStatus = 403
  fake.forceBody = { error: 'key_paused' }
  await s.signInWithApiKey('good-key', fake.url)
  assert.equal(s.phase, 'signedOut')
  assert.match(s.signInError, /key is paused \(403\)/)
})

test('an expired trial refuses writes without signing out', async () => {
  const { s } = make({ store: new MemoryCredentialStore({ server: fake.url, source: 'apiKey', apiKey: 'good-key' }) })
  await s.start()
  await ready(s)
  fake.failWrites = true
  assert.match(await s.remember({ projectId: 1, title: 'Blocked by the plan' }), /trial has expired/)
  assert.equal(s.phase, 'ready')
  assert.equal(s.problem, 'paused')
})

test('OAuth tokens refresh once on a 401 and the request is retried', async () => {
  fake.validTokens = new Set(['fresh'])
  fake.tokenResponse = { access_token: 'fresh', refresh_token: 'rt-2' }
  const store = new MemoryCredentialStore({ server: fake.url, source: 'oauth', accessToken: 'stale', refreshToken: 'rt-1', clientId: 'cid' })
  const { s } = make({ store })
  await s.start()
  await ready(s)
  assert.equal(s.problem, null)
  assert.equal(s.credentials.accessToken, 'fresh')
  assert.equal(store.read().refreshToken, 'rt-2')
  assert.equal(fake.tokenRequests.at(-1).refresh_token, 'rt-1')
  assert.equal(fake.tokenRequests.at(-1).resource, fake.url + '/api')
  assert.equal(fake.authHeaders.at(-1), 'Bearer fresh')
})

test('concurrent 401s share one token refresh', async () => {
  fake.validTokens = new Set(['t1'])
  const store = new MemoryCredentialStore({ server: fake.url, source: 'oauth', accessToken: 't1', refreshToken: 'rt-1', clientId: 'cid' })
  const { s } = make({ store })
  await s.start()
  await ready(s)
  fake.validTokens = new Set(['t2']) // t1 is revoked server-side
  fake.tokenResponse = { access_token: 't2', refresh_token: 'rt-2' }
  const before = fake.tokenRequests.length
  const [a, b] = await Promise.all([s.detail(1000), s.detail(999), s.loadMore(), s.setStatus(998, 'resolved')])
  assert.ok(a && b, 'every call succeeded after the refresh')
  assert.equal(fake.tokenRequests.length - before, 1, 'one refresh for four concurrent 401s')
  assert.equal(s.phase, 'ready')
  assert.equal(store.read().refreshToken, 'rt-2')
})

test('a revoked API key is not refreshed: a 401 signs out', async () => {
  const { s } = make({ store: new MemoryCredentialStore({ server: fake.url, source: 'apiKey', apiKey: 'revoked' }) })
  const before = fake.tokenRequests.length
  await s.start()
  await until(s, () => s.phase === 'signedOut')
  assert.match(s.signInError, /no longer valid/)
  assert.equal(fake.tokenRequests.length, before)
  assert.equal(s.store.read(), null)
})

test('an OAuth refresh that fails signs out', async () => {
  fake.validTokens = new Set(['other'])
  const { s } = make({ store: new MemoryCredentialStore({ server: fake.url, source: 'oauth', accessToken: 'stale', refreshToken: 'spent', clientId: 'cid' }) })
  await s.start()
  await until(s, () => s.phase === 'signedOut')
  assert.match(s.signInError, /invalid_grant/)
  assert.equal(s.store.read(), null)
})

test('browser sign-in goes through the injected runner and can be cancelled', async () => {
  let release
  const { s } = make({
    runOAuth: (_api, server, { signal }) => new Promise((resolve, reject) => {
      release = () => resolve({ server, source: 'oauth', accessToken: 'good-key' })
      signal.addEventListener('abort', () => reject(new Error('Sign-in was cancelled')))
    })
  })
  await s.start()
  const first = s.signInWithOAuth(fake.url)
  assert.equal(s.signingIn, true)
  s.cancelSignIn()
  await first
  assert.equal(s.signInError, 'Sign-in was cancelled')
  const second = s.signInWithOAuth(fake.url)
  release()
  await second
  await ready(s)
  assert.equal(s.snapshot().keySource, 'oauth')
})

test('demo mode serves the mock account and signing out returns to sign-in', async () => {
  const { s, lines } = make()
  await s.start()
  await s.startDemo()
  await ready(s)
  assert.equal(s.host, 'demo')
  assert.equal(s.summary.memories, 7910)
  assert.equal(s.records[0].id, 7910)
  assert.equal((await s.detail(7910)).links.length, 2)
  await s.setFilter({ kind: 'issue' })
  assert.deepEqual(s.records.map((m) => m.id), [7902, 7841])
  assert.ok(lines.some((l) => /^→ GET \/api\/v1\/records\?limit=1&status=open&kind=todo … 200 OK \d+ms$/.test(l)))
  assert.ok(lines.some((l) => l.startsWith('→ GET /api/v1/records?limit=50&kind=issue')))
  await s.signOut()
  assert.equal(s.phase, 'signedOut')
  assert.equal(s.records.length, 0)
})
