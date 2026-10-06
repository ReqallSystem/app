// Everything the console reads from or writes to Reqall. LiveRepository talks
// to the REST API under /api/v1; DemoRepository (demo.js) serves the mock
// account behind the same methods. Records come back through toMemory,
// projects through toProject, so the session never sees raw API output.

import { toMemory, toProject } from '../shared/model.js'

const total = (data) => (Number.isFinite(Number(data && data.total)) ? Number(data.total) : 0)
const projectList = (data) => (Array.isArray(data) ? data : data && Array.isArray(data.projects) ? data.projects : [])
  .filter((p) => p && typeof p === 'object')

/** GET /records query for the console's filters. */
export function filterArgs({ kind, projectId } = {}) {
  return { ...(kind ? { kind } : {}), ...(projectId != null ? { project_id: projectId } : {}) }
}

export class LiveRepository {
  constructor(api) {
    this.api = api
  }

  /** The panel's four numbers: three record totals and the project count. */
  async summary() {
    const [all, todos, issues, projects] = await Promise.all([
      this.api.get('/records', { limit: 1 }),
      this.api.get('/records', { limit: 1, status: 'open', kind: 'todo' }),
      this.api.get('/records', { limit: 1, status: 'open', kind: 'issue' }),
      this.api.get('/projects')
    ])
    return { memories: total(all), openTodos: total(todos), openIssues: total(issues), projects: projectList(projects).length }
  }

  async records({ limit = 50, offset = 0, kind, projectId } = {}) {
    const data = await this.api.get('/records', {
      limit: Math.max(1, Math.min(100, limit)),
      ...(offset ? { offset } : {}),
      ...filterArgs({ kind, projectId })
    })
    const list = data && Array.isArray(data.records) ? data.records.filter((r) => r && typeof r === 'object') : []
    return { records: list.map(toMemory), total: total(data) }
  }

  /** GET /projects is not paged: one call returns them all. */
  async projects() {
    return projectList(await this.api.get('/projects')).map(toProject)
  }

  /** Body and links for one record: the record and its links, both directions. */
  async detail(id) {
    const [rec, links] = await Promise.all([
      this.api.get(`/records/${encodeURIComponent(id)}`),
      this.api.get(`/records/${encodeURIComponent(id)}/links`, { direction: 'both', limit: 50 })
    ])
    const out = []
    for (const l of links && Array.isArray(links.links) ? links.links : []) {
      const outgoing = l.source_table === 'records' && Number(l.source_id) === id
      if ((outgoing ? l.target_table : l.source_table) !== 'records') continue
      out.push({
        otherId: Number(outgoing ? l.target_id : l.source_id),
        relationship: String(l.relationship ?? 'related'),
        outgoing
      })
    }
    return { memory: toMemory(rec), links: out }
  }

  /** POST /records answers without project_name; the chosen project fills it. */
  async remember({ project, title, body = '', kind }) {
    const data = await this.api.post('/records', {
      project_id: project.id,
      title,
      ...(body ? { body } : {}),
      ...(kind ? { kind } : {})
    })
    const memory = toMemory(data)
    return memory.project ? memory : { ...memory, project: project.name }
  }

  /** PATCH answers without project_name too; the session keeps the row's own. */
  async setStatus(id, status) {
    return toMemory(await this.api.patch(`/records/${encodeURIComponent(id)}`, { status }))
  }
}
