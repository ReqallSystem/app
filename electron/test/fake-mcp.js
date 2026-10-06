// An in-process Reqall server on 127.0.0.1: tools/call for the tools the
// console uses, plus /oauth/token. Records and projects are mutable so tests
// can arrange state; every call is recorded.

import http from 'node:http'

export async function startFakeMcp({ validTokens = ['good-key'], sse = false } = {}) {
  const fake = {
    validTokens: new Set(validTokens),
    sse,
    forceStatus: null,
    rateLimited: 0, // answer this many tools/calls with 429 first
    inFlight: 0,
    maxInFlight: 0,
    failWrites: false,
    calls: [],
    authHeaders: [],
    tokenRequests: [],
    tokenResponse: null, // null → 400 invalid_grant
    records: Array.from({ length: 60 }, (_, i) => ({
      id: 1000 - i,
      project_id: i % 2 === 0 ? 1 : 2,
      project_name: i % 2 === 0 ? 'ReqallSystem/app' : '.user',
      kind: ['spec', 'issue', 'todo', 'info'][i % 4],
      title: `Record ${1000 - i}`,
      status: i % 4 === 1 || i % 4 === 2 ? 'open' : 'active',
      updated_at: new Date(Date.UTC(2026, 9, 5, 12) - i * 3600_000).toISOString()
    })),
    projects: [
      { id: 1, name: 'ReqallSystem/app', record_count: 30 },
      { id: 2, name: '.user', record_count: 30 }
    ],
    links: [{ source_table: 'records', source_id: 1000, target_table: 'records', target_id: 999, relationship: 'implements' }]
  }

  const tools = {
    list_records(a) {
      let rows = fake.records.filter((r) =>
        (!a.kind || r.kind === a.kind) && (!a.status || r.status === a.status) && (a.project_id == null || r.project_id === a.project_id))
      const total = rows.length
      rows = rows.slice(a.offset || 0, (a.offset || 0) + (a.limit || 50))
      return { records: rows, total }
    },
    list_projects(a) {
      return { projects: fake.projects.slice(a.offset || 0, (a.offset || 0) + (a.limit || 50)), total: fake.projects.length }
    },
    get_record(a) {
      const r = fake.records.find((x) => x.id === a.id)
      if (!r) throw new Error('not found')
      return { record: { ...r, body: `Body of ${r.id}` } }
    },
    list_links(a) {
      return { links: fake.links.filter((l) => l.source_id === a.entity_id || l.target_id === a.entity_id) }
    },
    upsert_record(a) {
      if (fake.failWrites) throw new Error('writes are failing')
      if (a.id) {
        const r = fake.records.find((x) => x.id === a.id)
        Object.assign(r, { status: a.status, updated_at: new Date().toISOString() })
        return { record: r }
      }
      const p = fake.projects.find((x) => x.id === a.project_id)
      const r = {
        id: 2000 + fake.records.length, project_id: a.project_id, project_name: p.name, kind: a.kind || 'info',
        title: a.title, body: a.body || '', status: 'active', updated_at: new Date().toISOString()
      }
      fake.records.unshift(r)
      return { record: r }
    }
  }

  const server = http.createServer(async (req, res) => {
    let body = ''
    for await (const chunk of req) body += chunk
    if (req.url === '/oauth/token') {
      fake.tokenRequests.push(Object.fromEntries(new URLSearchParams(body)))
      const r = fake.tokenResponse
      res.writeHead(r ? 200 : 400, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify(r || { error: 'invalid_grant' }))
      return
    }
    const auth = req.headers.authorization || ''
    fake.authHeaders.push(auth)
    if (fake.rateLimited > 0) {
      fake.rateLimited--
      res.writeHead(429, { 'Retry-After': '0', 'Content-Type': 'application/json' }).end('{"message":"slow down"}')
      return
    }
    if (fake.forceStatus) {
      res.writeHead(fake.forceStatus, { 'Content-Type': 'application/json' }).end('{"message":"forced"}')
      return
    }
    if (!fake.validTokens.has(auth.replace(/^Bearer /, ''))) {
      res.writeHead(401, { 'Content-Type': 'application/json' }).end('{"message":"Invalid token"}')
      return
    }
    const rpc = JSON.parse(body)
    const { name, arguments: args } = rpc.params
    fake.calls.push({ name, args })
    let result
    fake.inFlight++
    fake.maxInFlight = Math.max(fake.maxInFlight, fake.inFlight)
    await new Promise((r) => setTimeout(r, fake.delayMs || 0))
    fake.inFlight--
    try {
      result = { structuredContent: { ok: true, data: tools[name](args || {}) } }
    } catch (e) {
      result = { isError: true, content: [{ type: 'text', text: e.message }] }
    }
    const payload = JSON.stringify({ jsonrpc: '2.0', id: rpc.id, result })
    if (fake.sse) {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' }).end(`event: message\ndata: ${payload}\n\n`)
    } else {
      res.writeHead(200, { 'Content-Type': 'application/json' }).end(payload)
    }
  })
  await new Promise((r) => server.listen(0, '127.0.0.1', r))
  fake.url = `http://127.0.0.1:${server.address().port}`
  fake.close = () => new Promise((r) => { server.closeAllConnections(); server.close(r) })
  return fake
}

/** Resolves once `session` emits a change for which `test()` holds. */
export function until(session, test, timeoutMs = 3000) {
  if (test()) return Promise.resolve()
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => { session.off('change', on); reject(new Error('timed out waiting for session state')) }, timeoutMs)
    const on = () => { if (test()) { clearTimeout(t); session.off('change', on); resolve() } }
    session.on('change', on)
  })
}
