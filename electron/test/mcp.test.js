import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import { McpClient, McpError, Failure } from '../src/main/mcp.js'
import { LiveRepository } from '../src/main/repository.js'
import { startFakeMcp } from './fake-mcp.js'

const fake = await startFakeMcp()
after(() => fake.close())

const client = (token = 'good-key', onLog) => new McpClient({ endpoint: fake.url + '/mcp', token: () => token, onLog })

test('reads JSON replies and returns the data object', async () => {
  fake.sse = false
  const data = await client().call('list_records', { limit: 2 })
  assert.equal(data.records.length, 2)
  assert.equal(data.total, 60)
})

test('reads one-event SSE replies', async () => {
  fake.sse = true
  try {
    const data = await client().call('list_projects', {})
    assert.equal(data.total, 2)
  } finally {
    fake.sse = false
  }
})

test('maps 401 and 403 to unauthorized and forbidden', async () => {
  await assert.rejects(client('bad').call('list_records'), (e) => e instanceof McpError && e.failure === Failure.unauthorized && e.message === 'Invalid token')
  fake.forceStatus = 403
  try {
    await assert.rejects(client().call('list_records'), (e) => e.failure === Failure.forbidden)
    fake.forceStatus = 500
    await assert.rejects(client().call('list_records'), (e) => e.failure === Failure.server && /500/.test(e.message))
  } finally {
    fake.forceStatus = null
  }
})

test('tool errors arrive as tool failures with the server text', async () => {
  await assert.rejects(client().call('get_record', { id: 1 }), (e) => e.failure === Failure.tool && e.message === 'not found')
})

test('an unreachable server is a network failure', async () => {
  const c = new McpClient({ endpoint: 'http://127.0.0.1:1/mcp', token: () => 'x', timeoutMs: 2000 })
  await assert.rejects(c.call('list_records'), (e) => e.failure === Failure.network)
})

test('every call is reported to onLog with status and timing', async () => {
  const seen = []
  await client('good-key', (e) => seen.push(e)).call('list_records', { limit: 1 })
  await client('bad', (e) => seen.push(e)).call('list_records').catch(() => {})
  assert.equal(seen[0].name, 'list_records')
  assert.equal(seen[0].status, 200)
  assert.ok(seen[0].ms >= 0)
  assert.equal(seen[1].status, 401)
})

test('repository: summary, filtered records, projects, detail with links', async () => {
  const repo = new LiveRepository(client())
  assert.deepEqual(await repo.summary(), { memories: 60, openTodos: 15, openIssues: 15, projects: 2 })
  const page = await repo.records({ limit: 5, kind: 'issue', projectId: 2 })
  assert.equal(page.total, 15)
  assert.ok(page.records.every((m) => m.kind === 'issue' && m.projectId === 2 && m.project === '.user'))
  assert.equal(typeof page.records[0].updatedAt, 'number')
  assert.deepEqual((await repo.projects()).map((p) => p.name), ['lumen-labs/atlas-app', '.user'])
  const d = await repo.detail(1000)
  assert.equal(d.memory.body, 'Body of 1000')
  assert.deepEqual(d.links, [{ otherId: 999, relationship: 'implements', outgoing: true }])
  const back = await repo.detail(999)
  assert.deepEqual(back.links, [{ otherId: 1000, relationship: 'implements', outgoing: false }])
})

test('a 429 is retried after Retry-After, then gives up with a clear message', async () => {
  fake.rateLimited = 2
  const data = await client().call('list_projects', {})
  assert.equal(data.total, 2)
  fake.rateLimited = 3
  await assert.rejects(client().call('list_projects', {}), (e) => e.status === 429 && /Rate limited/.test(e.message))
  fake.rateLimited = 0
})

test('at most maxInFlight calls run at once', async () => {
  fake.delayMs = 30
  fake.maxInFlight = 0
  try {
    const c = new McpClient({ endpoint: fake.url + '/mcp', token: () => 'good-key', maxInFlight: 2 })
    await Promise.all(Array.from({ length: 6 }, () => c.call('list_projects', {})))
    assert.equal(fake.maxInFlight, 2)
  } finally {
    fake.delayMs = 0
  }
})
