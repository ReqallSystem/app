// The mock account from the design workshop (designs/lib/shared/mock.dart),
// served behind the repository interface so the console runs offline
// ("try the demo"). Requests are logged like the REST calls a live account
// would make, with a fake latency.

import { apiPath } from './api.js'

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR

const PROJECTS = [
  { id: 8557, name: 'lumen-labs/atlas-app', count: 3 },
  { id: 4946, name: '.machine/devbox/alex', count: 212 },
  { id: 84, name: 'alex/admin-console', count: 48 },
  { id: 17, name: 'quarry-co/harvest-app', count: 391 },
  { id: 144, name: 'tidewater/ledger-sync', count: 77 },
  { id: 12, name: 'lumen-labs/atlas-core', count: 640 },
  { id: 31, name: 'lumen-labs/atlas-desktop', count: 58 },
  { id: 2, name: '.user', count: 96 }
]

const LINKS = {
  7910: [7908, 6472],
  7908: [6472],
  7902: [6472],
  7895: [6472, 7902],
  7881: [6472],
  7874: [7895],
  7799: [7895],
  7790: [7799]
}

function seed(now) {
  const projectId = (name) => PROJECTS.find((p) => p.name === name).id
  const m = (id, title, kind, status, project, age, body = '') =>
    ({ id, title, body, kind, status, project, projectId: projectId(project), updatedAt: now - age })
  return [
    m(7910, 'UI: Atlas app concept workshop — 4 directions', 'spec', 'open', 'lumen-labs/atlas-app', 3 * MIN,
      'Four layouts on shared mock data, reviewed on a phone and a laptop.'),
    m(7908, 'Atlas app skeleton created for all six platforms', 'work', 'active', 'lumen-labs/atlas-app', 34 * MIN,
      'Android, iOS, Linux, macOS, Windows and web targets. Analyze clean, tests pass.'),
    m(7902, 'Tray menu ignores left-click on Linux app indicators', 'issue', 'open', 'lumen-labs/atlas-desktop', 2 * HOUR + 10 * MIN,
      'Linux indicators route left-click to the menu; opening the panel must be a menu item.'),
    m(7895, 'Credential order: setting > environment > env file > config file', 'arch', 'active', 'lumen-labs/atlas-core', 5 * HOUR,
      'Parsed, never sourced. Shared by every client.'),
    m(7881, 'Add per-record deep links to the dashboard', 'todo', 'open', 'lumen-labs/atlas-desktop', 9 * HOUR),
    m(7874, 'Mock server covers JSON + SSE replies', 'test', 'active', 'lumen-labs/atlas-desktop', 20 * HOUR,
      'node:test against a local HTTP server; auth states ok/none/invalid/paused/error.'),
    m(7860, 'Window gaps 8 → 6 on the wide monitor', 'info', 'active', '.machine/devbox/alex', DAY + 3 * HOUR),
    m(7841, 'Leaderboard loading-state tests flake on CI', 'issue', 'open', 'quarry-co/harvest-app', DAY + 9 * HOUR),
    m(7833, 'ValueNotifier state, no framework dependency', 'arch', 'active', 'tidewater/ledger-sync', 2 * DAY),
    m(7820, 'Ship the admin record editor', 'todo', 'open', 'alex/admin-console', 2 * DAY + 6 * HOUR),
    m(7811, 'Prefer terse commit messages; push the branch you are on', 'info', 'active', '.user', 3 * DAY),
    m(7799, 'Semantic search boosts the current project', 'spec', 'active', 'lumen-labs/atlas-core', 4 * DAY),
    m(7790, 'Nightly consolidation merges near-duplicate notes', 'work', 'active', 'lumen-labs/atlas-core', 5 * DAY),
    m(6472, 'FEAT: Atlas desktop app with tray panel parity', 'spec', 'resolved', '.machine/devbox/alex', 17 * DAY,
      'Tray, panel, keyboard nav, fetcher, settings, tests.')
  ]
}

export class DemoRepository {
  constructor({ latencyMs = 250, onLog = () => {}, now = Date.now } = {}) {
    this.latencyMs = latencyMs
    this.onLog = onLog
    this.rows = seed(now())
    this.added = 0
    this.now = now
  }

  async #call(method, path, query, fn, status = 200) {
    const started = Date.now()
    const ms = this.latencyMs / 2 + Math.random() * this.latencyMs
    await new Promise((r) => setTimeout(r, ms))
    const value = fn()
    this.onLog({ method, path: apiPath(path, query), status, ms: Date.now() - started })
    return value
  }

  async summary() {
    const [memories, openTodos, openIssues, projects] = await Promise.all([
      this.#call('GET', '/records', { limit: 1 }, () => 7910 + this.added),
      this.#call('GET', '/records', { limit: 1, status: 'open', kind: 'todo' }, () => 23),
      this.#call('GET', '/records', { limit: 1, status: 'open', kind: 'issue' }, () => 9),
      this.#call('GET', '/projects', {}, () => 41)
    ])
    return { memories, openTodos, openIssues, projects }
  }

  records({ limit = 50, offset = 0, kind, projectId } = {}) {
    const args = { limit, ...(offset ? { offset } : {}), ...(kind ? { kind } : {}), ...(projectId != null ? { project_id: projectId } : {}) }
    return this.#call('GET', '/records', args, () => {
      const rows = this.rows
        .filter((m) => (!kind || m.kind === kind) && (projectId == null || m.projectId === projectId))
        .sort((a, b) => b.updatedAt - a.updatedAt)
      // The record list carries no body; detail() fills it.
      return { records: rows.slice(offset, offset + limit).map((m) => ({ ...m, body: null })), total: rows.length }
    })
  }

  projects() {
    return this.#call('GET', '/projects', {}, () => PROJECTS.map((p) => ({ ...p })))
  }

  detail(id) {
    return this.#call('GET', `/records/${id}`, {}, () => {
      const memory = this.rows.find((m) => m.id === id)
      if (!memory) throw new Error(`Record #${id} not found`)
      const links = [
        ...(LINKS[id] || []).map((otherId) => ({ otherId, relationship: 'related', outgoing: true })),
        ...Object.entries(LINKS)
          .filter(([, to]) => to.includes(id))
          .map(([from]) => ({ otherId: Number(from), relationship: 'related', outgoing: false }))
      ]
      return { memory: { ...memory }, links }
    })
  }

  remember({ project, title, body = '', kind }) {
    return this.#call('POST', '/records', {}, () => {
      this.added++
      const k = kind || 'info'
      const memory = {
        id: 7920 + this.added,
        title,
        body,
        kind: k,
        status: ['todo', 'issue', 'spec'].includes(k) ? 'open' : 'active',
        project: project.name,
        projectId: project.id,
        updatedAt: this.now()
      }
      this.rows.push(memory)
      return { ...memory }
    }, 201)
  }

  setStatus(id, status) {
    return this.#call('PATCH', `/records/${id}`, {}, () => {
      const m = this.rows.find((r) => r.id === id)
      if (!m) throw new Error(`Record #${id} not found`)
      Object.assign(m, { status, updatedAt: this.now() })
      return { ...m }
    })
  }
}
