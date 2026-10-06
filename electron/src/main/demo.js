// The mock account from the design workshop (designs/lib/shared/mock.dart),
// served behind the repository interface so the console runs offline
// ("try the demo"). Requests are logged like real ones, with a fake latency.

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR

const PROJECTS = [
  { id: 8557, name: 'ReqallSystem/app', count: 3 },
  { id: 4946, name: '.machine/omarchy/fingerskier', count: 212 },
  { id: 84, name: 'fingerskier/reqall_admin', count: 48 },
  { id: 17, name: 'osteostrong/believer_app', count: 391 },
  { id: 144, name: 'turingautomations/pbm_crossx', count: 77 },
  { id: 12, name: 'ReqallSystem/core', count: 640 },
  { id: 31, name: 'ReqallSystem/desktop-app', count: 58 },
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
    m(7910, 'UI: Flutter app UI concept workshop — 4 directions', 'spec', 'open', 'ReqallSystem/app', 3 * MIN,
      'Hearth, Constellation, Stream and Console, all on shared mock data, served over tailscale.'),
    m(7908, 'Flutter app skeleton created at flutter/ (reqall_app, org net.reqall)', 'work', 'active', 'ReqallSystem/app', 34 * MIN,
      'flutter create with android, ios, linux, macos, windows, web. Analyze clean, tests pass.'),
    m(7902, 'Tray menu ignores left-click on Hyprland app-indicators', 'issue', 'open', 'ReqallSystem/desktop-app', 2 * HOUR + 10 * MIN,
      'Linux indicators route left-click to the menu; panel open must be a menu item.'),
    m(7895, 'Credential order: setting > env > ~/.config/reqall/env > config.json', 'arch', 'active', 'ReqallSystem/core', 5 * HOUR,
      'Parsed, never sourced. Shared by the plugin, desktop app and CLI.'),
    m(7881, 'Add per-record deep links (dashboard#records/<id>)', 'todo', 'open', 'ReqallSystem/desktop-app', 9 * HOUR),
    m(7874, 'Mock MCP server covers JSON + SSE replies', 'test', 'active', 'ReqallSystem/desktop-app', 20 * HOUR,
      'node:test against a local HTTP server; auth states ok/none/invalid/paused/error.'),
    m(7860, 'Hyprland gaps 8 → 6 on the ultrawide', 'info', 'active', '.machine/omarchy/fingerskier', DAY + 3 * HOUR),
    m(7841, 'Leaderboard loading-state tests flake on CI', 'issue', 'open', 'osteostrong/believer_app', DAY + 9 * HOUR),
    m(7833, 'ValueNotifier state, no framework dependency', 'arch', 'active', 'turingautomations/pbm_crossx', 2 * DAY),
    m(7820, 'Ship admin app record editor', 'todo', 'open', 'fingerskier/reqall_admin', 2 * DAY + 6 * HOUR),
    m(7811, 'Prefer terse commit messages; push the branch you are on', 'info', 'active', '.user', 3 * DAY),
    m(7799, 'Semantic search boosts the current project', 'spec', 'active', 'ReqallSystem/core', 4 * DAY),
    m(7790, 'SLEEP consolidation merges near-duplicate info records', 'work', 'active', 'ReqallSystem/core', 5 * DAY),
    m(6472, 'FEAT: Reqall desktop-app with omarchy_plugin parity', 'spec', 'resolved', '.machine/omarchy/fingerskier', 17 * DAY,
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

  async #call(name, args, fn) {
    const started = Date.now()
    const ms = this.latencyMs / 2 + Math.random() * this.latencyMs
    await new Promise((r) => setTimeout(r, ms))
    const value = fn()
    this.onLog({ name, args, status: 200, ms: Date.now() - started })
    return value
  }

  async summary() {
    const [memories, openTodos, openIssues, projects] = await Promise.all([
      this.#call('list_records', { limit: 1 }, () => 7910 + this.added),
      this.#call('list_records', { limit: 1, status: 'open', kind: 'todo' }, () => 23),
      this.#call('list_records', { limit: 1, status: 'open', kind: 'issue' }, () => 9),
      this.#call('list_projects', { limit: 1 }, () => 41)
    ])
    return { memories, openTodos, openIssues, projects }
  }

  records({ limit = 50, offset = 0, kind, projectId } = {}) {
    const args = { limit, ...(offset ? { offset } : {}), ...(kind ? { kind } : {}), ...(projectId != null ? { project_id: projectId } : {}) }
    return this.#call('list_records', args, () => {
      const rows = this.rows
        .filter((m) => (!kind || m.kind === kind) && (projectId == null || m.projectId === projectId))
        .sort((a, b) => b.updatedAt - a.updatedAt)
      // list_records carries no body; detail() fills it.
      return { records: rows.slice(offset, offset + limit).map((m) => ({ ...m, body: null })), total: rows.length }
    })
  }

  projects() {
    return this.#call('list_projects', { limit: 100 }, () => PROJECTS.map((p) => ({ ...p })))
  }

  detail(id) {
    return this.#call('get_record', { id }, () => {
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
    return this.#call('upsert_record', { project_id: project.id, title }, () => {
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
    })
  }

  setStatus(id, status) {
    return this.#call('upsert_record', { id, status }, () => {
      const m = this.rows.find((r) => r.id === id)
      if (!m) throw new Error(`Record #${id} not found`)
      Object.assign(m, { status, updatedAt: this.now() })
      return { ...m }
    })
  }
}
