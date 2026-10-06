import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import { ApiClient, ApiError, Failure, apiPath } from '../src/main/api.js'
import { LiveRepository } from '../src/main/repository.js'
import { startFakeApi } from './fake-api.js'

const fake = await startFakeApi()
after(() => fake.close())

const client = (token = 'good-key', onLog) => new ApiClient({ server: fake.url, token: () => token, onLog })

test('apiPath prefixes /api/v1 and drops empty query values', () => {
  assert.equal(apiPath('/records', { limit: 1, status: 'open', kind: undefined, project_id: null }), '/api/v1/records?limit=1&status=open')
  assert.equal(apiPath('/projects'), '/api/v1/projects')
})

test('GET returns the parsed body and sends the bearer', async () => {
  const data = await client().get('/records', { limit: 2 })
  assert.equal(data.records.length, 2)
  assert.equal(data.total, 60)
  assert.equal(fake.authHeaders.at(-1), 'Bearer good-key')
  assert.deepEqual(fake.calls.at(-1), { method: 'GET', path: '/api/v1/records', query: { limit: '2' } })
  assert.ok(Array.isArray(await client().get('/projects')), 'projects come back as a plain array')
})

test('the token is read on every request', async () => {
  let token = 'bad'
  const c = new ApiClient({ server: fake.url, token: () => token })
  await assert.rejects(c.get('/projects'), (e) => e.failure === Failure.unauthorized)
  token = 'good-key'
  assert.equal((await c.get('/projects')).length, 2)
})

test('maps 401, 403, 5xx to unauthorized, forbidden, server', async () => {
  await assert.rejects(client('bad').get('/records'), (e) => e instanceof ApiError && e.failure === Failure.unauthorized && e.message === 'Invalid token' && e.code === 'unauthenticated')
  fake.forceStatus = 403
  fake.forceBody = { error: 'key_paused' }
  try {
    await assert.rejects(client().get('/records'), (e) => e.failure === Failure.forbidden && e.code === 'key_paused' && /paused/.test(e.message))
    fake.forceStatus = 500
    fake.forceBody = null
    await assert.rejects(client().get('/records'), (e) => e.failure === Failure.server && /500/.test(e.message))
  } finally {
    fake.forceStatus = null
    fake.forceBody = null
  }
})

test('400 and 404 are request failures with the server text', async () => {
  await assert.rejects(client().get('/records/1'), (e) => e.failure === Failure.request && e.status === 404 && e.code === 'not_found' && e.message === 'Not found')
  await assert.rejects(client().get('/records', { kind: 'bogus' }), (e) => e.failure === Failure.request && e.status === 400 && e.message === 'Unknown kind: bogus')
})

test('an unreachable server is a network failure', async () => {
  const c = new ApiClient({ server: 'http://127.0.0.1:1', token: () => 'x', timeoutMs: 2000 })
  await assert.rejects(c.get('/records'), (e) => e.failure === Failure.network)
})

test('every request is reported to onLog as METHOD /api/v1/path?query with status and timing', async () => {
  const seen = []
  await client('good-key', (e) => seen.push(e)).get('/records', { limit: 1, status: 'open', kind: 'todo' })
  await client('bad', (e) => seen.push(e)).get('/records').catch(() => {})
  assert.equal(seen[0].method, 'GET')
  assert.equal(seen[0].path, '/api/v1/records?limit=1&status=open&kind=todo')
  assert.equal(seen[0].status, 200)
  assert.ok(seen[0].ms >= 0)
  assert.equal(seen[1].status, 401)
  assert.equal(seen[1].error, 'Invalid token')
})

test('POST and PATCH send JSON bodies', async () => {
  const created = await client().post('/records', { project_id: 2, title: 'Sketch the sync loop', kind: 'todo' })
  assert.equal(created.title, 'Sketch the sync loop')
  assert.equal(created.project_name, undefined)
  assert.deepEqual(fake.calls.at(-1).body, { project_id: 2, title: 'Sketch the sync loop', kind: 'todo' })
  const patched = await client().patch(`/records/${created.id}`, { status: 'resolved' })
  assert.equal(patched.status, 'resolved')
  assert.equal(fake.calls.at(-1).method, 'PATCH')
  fake.records.shift()
})

test('repository: summary, filtered records, projects, detail with links', async () => {
  const repo = new LiveRepository(client())
  assert.deepEqual(await repo.summary(), { memories: 60, openTodos: 15, openIssues: 15, projects: 2 })
  const page = await repo.records({ limit: 5, kind: 'issue', projectId: 2 })
  assert.equal(page.total, 15)
  assert.equal(page.records.length, 5)
  assert.ok(page.records.every((m) => m.kind === 'issue' && m.projectId === 2 && m.project === '.user' && m.body === null))
  assert.equal(typeof page.records[0].updatedAt, 'number')
  assert.deepEqual(fake.calls.at(-1).query, { limit: '5', kind: 'issue', project_id: '2' })
  assert.deepEqual(await repo.projects(), [{ id: 1, name: 'lumen-labs/atlas-app', count: 30 }, { id: 2, name: '.user', count: 30 }])
  const d = await repo.detail(1000)
  assert.equal(d.memory.body, 'Body of 1000')
  assert.equal(d.memory.project, 'lumen-labs/atlas-app')
  assert.deepEqual(d.links, [{ otherId: 999, relationship: 'implements', outgoing: true }])
  assert.ok(fake.calls.slice(-2).some((c) => c.path === '/api/v1/records/1000/links' && c.query.direction === 'both'))
  const back = await repo.detail(999)
  assert.deepEqual(back.links, [{ otherId: 1000, relationship: 'implements', outgoing: false }])
})

test('repository: writes fill project_name from the chosen project', async () => {
  const repo = new LiveRepository(client())
  const m = await repo.remember({ project: { id: 1, name: 'lumen-labs/atlas-app' }, title: 'Draft the onboarding copy', kind: 'todo' })
  assert.equal(m.project, 'lumen-labs/atlas-app')
  assert.equal(m.kind, 'todo')
  assert.deepEqual(fake.calls.at(-1).body, { project_id: 1, title: 'Draft the onboarding copy', kind: 'todo' })
  const s = await repo.setStatus(m.id, 'resolved')
  assert.equal(s.status, 'resolved')
  assert.deepEqual(fake.calls.at(-1), { method: 'PATCH', path: `/api/v1/records/${m.id}`, query: {}, body: { status: 'resolved' } })
  fake.records.shift()
})

test('a 429 is retried after Retry-After, then gives up with a clear message', async () => {
  fake.rateLimited = 2
  assert.equal((await client().get('/projects')).length, 2)
  fake.rateLimited = 3
  await assert.rejects(client().get('/projects'), (e) => e.status === 429 && /Rate limited/.test(e.message))
  fake.rateLimited = 0
})

test('at most maxInFlight requests run at once', async () => {
  fake.delayMs = 30
  fake.maxInFlight = 0
  try {
    const c = new ApiClient({ server: fake.url, token: () => 'good-key', maxInFlight: 2 })
    await Promise.all(Array.from({ length: 6 }, () => c.get('/projects')))
    assert.equal(fake.maxInFlight, 2)
  } finally {
    fake.delayMs = 0
  }
})
