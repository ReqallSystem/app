// Pure helpers shared by the main process and the renderer: record kinds,
// relative ages, project names, the palette's fuzzy match and log formatting.
// No Node or DOM APIs here, so both sides (and the tests) can import it.

/** Record kinds in the dashboard's order, with its colours. */
export const KINDS = ['issue', 'spec', 'arch', 'test', 'todo', 'info', 'work']

export const KIND_COLORS = {
  issue: '#FF6B6B',
  spec: '#51CF66',
  arch: '#D4A5A5',
  test: '#FFD43B',
  todo: '#C49A6C',
  info: '#1098AD',
  work: '#868E96'
}

export const STATUSES = ['open', 'active', 'resolved', 'archived', 'inactive']

export function kindFromName(name) {
  return KINDS.includes(name) ? name : 'work'
}

/** One record as list_records / get_record / upsert_record return it. */
export function toMemory(j) {
  const updated = Date.parse(j.updated_at || j.created_at || '')
  return {
    id: Number(j.id),
    title: String(j.title ?? ''),
    body: typeof j.body === 'string' ? j.body : null,
    kind: kindFromName(j.kind),
    status: String(j.status ?? 'open'),
    project: String(j.project_name ?? j.project ?? ''),
    projectId: j.project_id == null ? null : Number(j.project_id),
    updatedAt: Number.isFinite(updated) ? updated : Date.now()
  }
}

export function toProject(j) {
  return { id: Number(j.id), name: String(j.name ?? ''), count: Number(j.record_count ?? 0) || 0 }
}

/** "3m", "5h", "2d", "3w", "1y"; "now" under a minute. */
export function relativeAge(ms) {
  const m = Math.floor(Math.max(0, ms) / 60000)
  if (m < 1) return 'now'
  if (m < 60) return `${m}m`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h`
  const d = Math.floor(h / 24)
  if (d < 7) return `${d}d`
  if (d < 365) return `${Math.floor(d / 7)}w`
  return `${Math.floor(d / 365)}y`
}

/** "ReqallSystem/desktop-app" → "desktop-app"; dotted machine/user projects keep their tail. */
export function shortProject(name) {
  return String(name).split('/').pop()
}

/**
 * Subsequence match for the command palette: consecutive hits and word
 * starts score higher. Returns { score, hits } or null when [query] is not
 * a subsequence of [text]. Spaces in the query are ignored.
 */
export function fuzzy(query, text) {
  const t = String(text).toLowerCase()
  const q = String(query).toLowerCase()
  let from = 0
  let last = -2
  let score = 0
  const hits = []
  for (const c of q) {
    if (c === ' ') continue
    const at = t.indexOf(c, from)
    if (at < 0) return null
    score += at === last + 1 ? 6 : 1
    if (at === 0 || ' :/#.-'.includes(t[at - 1])) score += 4
    hits.push(at)
    last = at
    from = at + 1
  }
  return { score: score - Math.floor(t.length / 24), hits }
}

/** Ranks [items] (each with a `label`) against [query]; stable for ties. */
export function rank(query, items) {
  const q = String(query).trim()
  if (!q) return items.map((item) => ({ item, hits: [] }))
  const scored = []
  items.forEach((item, i) => {
    const r = fuzzy(q, item.label)
    if (r) scored.push({ item, hits: r.hits, score: r.score, i })
  })
  scored.sort((a, b) => (a.score !== b.score ? b.score - a.score : a.i - b.i))
  return scored.map(({ item, hits }) => ({ item, hits }))
}

/** `{limit:1, status:open, kind:todo}` for the request log; '' for no args. */
export function formatArgs(args) {
  const entries = Object.entries(args || {}).filter(([, v]) => v !== undefined && v !== null && v !== '')
  if (!entries.length) return ''
  const show = (v) => {
    const s = typeof v === 'string' ? v : JSON.stringify(v)
    return s.length > 40 ? s.slice(0, 39) + '…' : s
  }
  return '{' + entries.map(([k, v]) => `${k}:${show(v)}`).join(', ') + '}'
}
