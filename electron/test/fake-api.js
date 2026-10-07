// An in-process Reqall server on 127.0.0.1: the /api/v1 routes the console
// uses, plus /oauth/token. Records and projects are mutable so tests can
// arrange state; every API request is recorded.

import http from 'node:http'

const KINDS = ['issue', 'spec', 'arch', 'test', 'todo', 'info', 'work']
const STATUSES = ['open', 'active', 'resolved', 'archived', 'inactive']

export async function startFakeApi({ validTokens = ['good-key'] } = {}) {
  const fake = {
    validTokens: new Set(validTokens),
    forceStatus: null, // answer every API request with this status
    forceBody: null, // …and this JSON body
    rateLimited: 0, // answer this many API requests with 429 first
    inFlight: 0,
    maxInFlight: 0,
    delayMs: 0,
    failWrites: false,
    calls: [],
    authHeaders: [],
    tokenRequests: [],
    tokenResponse: null, // null → 400 invalid_grant
    records: Array.from({ length: 60 }, (_, i) => ({
      id: 1000 - i,
      project_id: i % 2 === 0 ? 1 : 2,
      project_name: i % 2 === 0 ? 'lumen-labs/atlas-app' : '.user',
      kind: ['spec', 'issue', 'todo', 'info'][i % 4],
      title: `Record ${1000 - i}`,
      status: i % 4 === 1 || i % 4 === 2 ? 'open' : 'active',
      created_at: new Date(Date.UTC(2026, 8, 1)).toISOString(),
      updated_at: new Date(Date.UTC(2026, 9, 5, 12) - i * 3600_000).toISOString()
    })),
    projects: [
      { id: 1, name: 'lumen-labs/atlas-app', visibility: 'private', record_count: 30, link_count: 1, share_count: 0, access: 'owner', role: 'owner' },
      { id: 2, name: '.user', visibility: 'private', record_count: 30, link_count: 0, share_count: 0, access: 'owner', role: 'owner' }
    ],
    links: [{ id: 1, source_table: 'records', source_id: 1000, target_table: 'records', target_id: 999, relationship: 'implements', updated_at: '2026-10-05T12:00:00Z' }]
  }

  const fail = (status, error, message) => ({ status, body: { error, message } })
  const page = (rows, q) => {
    const limit = q.has('limit') ? Number(q.get('limit')) : 50
    const offset = q.has('offset') ? Number(q.get('offset')) : 0
    if (!Number.isInteger(limit) || limit < 1 || limit > 100 || !Number.isInteger(offset) || offset < 0) return null
    return { limit, offset, rows: rows.slice(offset, offset + limit), total: rows.length }
  }
  const withoutName = ({ project_name: _, ...r }) => r // writes answer without project_name

  function route(method, path, q, body) {
    let m
    if (method === 'GET' && path === '/api/v1/records') {
      const kind = q.get('kind')
      const status = q.get('status')
      if (kind && !KINDS.includes(kind)) return fail(400, 'bad_request', `Unknown kind: ${kind}`)
      if (status && !STATUSES.includes(status)) return fail(400, 'bad_request', `Unknown status: ${status}`)
      const project = q.has('project_id') ? Number(q.get('project_id')) : null
      const rows = fake.records
        .filter((r) => (!kind || r.kind === kind) && (!status || r.status === status) && (project == null || r.project_id === project))
        .sort((a, b) => b.updated_at.localeCompare(a.updated_at))
      const p = page(rows, q)
      if (!p) return fail(400, 'bad_request', 'Bad limit or offset')
      return { status: 200, body: { records: p.rows.map(({ body: _, ...r }) => r), total: p.total, limit: p.limit, offset: p.offset } }
    }
    if (method === 'GET' && path === '/api/v1/projects') return { status: 200, body: fake.projects }
    if (method === 'GET' && (m = path.match(/^\/api\/v1\/records\/(\d+)$/))) {
      const r = fake.records.find((x) => x.id === Number(m[1]))
      if (!r) return { status: 404, body: { error: 'not_found' } }
      return { status: 200, body: { body: `Body of ${r.id}`, ...r } }
    }
    if (method === 'GET' && (m = path.match(/^\/api\/v1\/records\/(\d+)\/links$/))) {
      const id = Number(m[1])
      if (!fake.records.some((x) => x.id === id)) return { status: 404, body: { error: 'not_found' } }
      const dir = q.get('direction') || 'both'
      const rows = fake.links.filter((l) =>
        (dir !== 'incoming' && l.source_table === 'records' && l.source_id === id) ||
        (dir !== 'outgoing' && l.target_table === 'records' && l.target_id === id))
      const p = page(rows, q)
      return { status: 200, body: { links: p.rows, total: p.total, limit: p.limit, offset: p.offset } }
    }
    if (method === 'POST' && path === '/api/v1/records') {
      if (fake.failWrites) return fail(403, 'trial_expired', 'Your trial has expired')
      const p = fake.projects.find((x) => x.id === body.project_id)
      if (!p || !String(body.title || '').trim()) return fail(400, 'validation_error', 'project_id and title are required')
      const now = new Date().toISOString()
      const kind = body.kind || 'info'
      const r = {
        id: 2000 + fake.records.length, project_id: p.id, project_name: p.name, kind, title: body.title, body: body.body || '',
        status: ['todo', 'issue', 'spec'].includes(kind) ? 'open' : 'active', created_at: now, updated_at: now
      }
      fake.records.unshift(r)
      return { status: 201, body: { ...withoutName(r), secret_scan_flagged: false } }
    }
    if (method === 'PATCH' && (m = path.match(/^\/api\/v1\/records\/(\d+)$/))) {
      if (fake.failWrites) return fail(400, 'validation_error', 'writes are failing')
      const r = fake.records.find((x) => x.id === Number(m[1]))
      if (!r) return { status: 404, body: { error: 'not_found' } }
      if (body.status && !STATUSES.includes(body.status)) return fail(400, 'validation_error', 'Unknown status')
      Object.assign(r, { status: body.status ?? r.status, updated_at: new Date().toISOString() })
      return { status: 200, body: withoutName(r) }
    }
    return fail(404, 'not_found', `No route for ${method} ${path}`)
  }

  const server = http.createServer(async (req, res) => {
    let raw = ''
    for await (const chunk of req) raw += chunk
    const u = new URL(req.url, 'http://127.0.0.1')
    const json = (status, body, headers = {}) => res.writeHead(status, { 'Content-Type': 'application/json', ...headers }).end(JSON.stringify(body))

    if (u.pathname === '/oauth/token') {
      fake.tokenRequests.push(Object.fromEntries(new URLSearchParams(raw)))
      const r = fake.tokenResponse
      json(r ? 200 : 400, r || { error: 'invalid_grant' })
      return
    }
    const auth = req.headers.authorization || ''
    fake.authHeaders.push(auth)
    if (fake.rateLimited > 0) {
      fake.rateLimited--
      json(429, { error: 'rate_limited', message: 'slow down' }, { 'Retry-After': '0' })
      return
    }
    if (fake.forceStatus) {
      json(fake.forceStatus, fake.forceBody || { error: 'forced', message: 'forced' })
      return
    }
    if (!fake.validTokens.has(auth.replace(/^Bearer /, ''))) {
      json(401, { error: 'unauthenticated', message: 'Invalid token' })
      return
    }
    let body = null
    if (raw) {
      if (req.headers['content-type'] !== 'application/json') return json(400, { error: 'bad_request', message: 'Expected JSON' })
      body = JSON.parse(raw)
    }
    const query = Object.fromEntries(u.searchParams)
    fake.calls.push({ method: req.method, path: u.pathname, query, ...(body ? { body } : {}) })
    fake.inFlight++
    fake.maxInFlight = Math.max(fake.maxInFlight, fake.inFlight)
    await new Promise((r) => setTimeout(r, fake.delayMs || 0))
    fake.inFlight--
    const out = route(req.method, u.pathname, u.searchParams, body || {})
    json(out.status, out.body)
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
