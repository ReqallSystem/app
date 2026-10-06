// Everything the console reads from or writes to Reqall. LiveRepository talks
// to the MCP endpoint; DemoRepository (demo.js) serves the mock account behind
// the same methods. Records come back through toMemory, projects through
// toProject, so the session never sees raw tool output.

import { toMemory, toProject } from '../shared/model.js'

const total = (data) => (Number.isFinite(Number(data && data.total)) ? Number(data.total) : 0)

/** list_records arguments for the console's filters. */
export function filterArgs({ kind, projectId } = {}) {
  return { ...(kind ? { kind } : {}), ...(projectId != null ? { project_id: projectId } : {}) }
}

export class LiveRepository {
  constructor(mcp) {
    this.mcp = mcp
  }

  /** The panel's four numbers, the same the omarchy widget shows. */
  async summary() {
    const [all, todos, issues, projects] = await Promise.all([
      this.mcp.call('list_records', { limit: 1 }),
      this.mcp.call('list_records', { limit: 1, status: 'open', kind: 'todo' }),
      this.mcp.call('list_records', { limit: 1, status: 'open', kind: 'issue' }),
      this.mcp.call('list_projects', { limit: 1 })
    ])
    return { memories: total(all), openTodos: total(todos), openIssues: total(issues), projects: total(projects) }
  }

  async records({ limit = 50, offset = 0, kind, projectId } = {}) {
    const data = await this.mcp.call('list_records', {
      limit: Math.max(1, Math.min(100, limit)),
      ...(offset ? { offset } : {}),
      ...filterArgs({ kind, projectId })
    })
    const list = Array.isArray(data.records) ? data.records.filter((r) => r && typeof r === 'object') : []
    return { records: list.map(toMemory), total: total(data) }
  }

  async projects() {
    const out = []
    for (let offset = 0; offset < 1000; offset += 100) {
      const data = await this.mcp.call('list_projects', { limit: 100, offset })
      const page = Array.isArray(data.projects) ? data.projects.map(toProject) : []
      out.push(...page)
      if (page.length < 100 || out.length >= total(data)) break
    }
    return out
  }

  /** Body and links for one record: get_record + list_links. */
  async detail(id) {
    const [rec, links] = await Promise.all([
      this.mcp.call('get_record', { id }),
      this.mcp.call('list_links', { entity_id: id, entity_type: 'records', direction: 'both', limit: 50 })
    ])
    const out = []
    for (const l of Array.isArray(links.links) ? links.links : []) {
      const outgoing = l.source_table === 'records' && Number(l.source_id) === id
      if ((outgoing ? l.target_table : l.source_table) !== 'records') continue
      out.push({
        otherId: Number(outgoing ? l.target_id : l.source_id),
        relationship: String(l.relationship ?? 'related'),
        outgoing
      })
    }
    return { memory: toMemory(rec.record), links: out }
  }

  async remember({ project, title, body = '', kind }) {
    const data = await this.mcp.call('upsert_record', {
      project_id: project.id,
      title,
      ...(body ? { body } : {}),
      ...(kind ? { kind } : {})
    })
    const memory = toMemory(data.record)
    return memory.project ? memory : { ...memory, project: project.name }
  }

  async setStatus(id, status) {
    const data = await this.mcp.call('upsert_record', { id, status })
    return toMemory(data.record)
  }
}
