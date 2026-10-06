// The console's one piece of state: who is signed in, with what, and the
// records they see. A port of flutter/lib/state/session.dart. The main process
// owns it; the renderer gets snapshot() over IPC on every 'change', and the
// request log as 'log' events. It never throws at its callers: failures land
// in `problem` / `signInError` and in the log.

import { EventEmitter } from 'node:events'
import { McpClient, McpError, Failure } from './mcp.js'
import { LiveRepository } from './repository.js'
import { DemoRepository } from './demo.js'
import { OAuthApi, OAuthError } from './oauth.js'
import {
  DEFAULT_SERVER, normalizeServer, hostOf, bearer, canRefresh, tokenExpired, sourceLabel, MemoryCredentialStore
} from './credentials.js'
import { formatArgs } from '../shared/model.js'

export const PAGE_SIZE = 50
const PREFETCH = 3
const QUIET = new Set(['get_record', 'list_links'])

export class Session extends EventEmitter {
  constructor({
    store = new MemoryCredentialStore(),
    fetchImpl = fetch,
    oauth,
    findCli = () => null,
    runOAuth = async () => { throw new OAuthError('Browser sign-in is not available') },
    demo = (opts) => new DemoRepository(opts)
  } = {}) {
    super()
    this.store = store
    this.fetchImpl = fetchImpl
    this.oauth = oauth || new OAuthApi({ fetchImpl })
    this.findCli = findCli
    this.runOAuth = runOAuth
    this.makeDemo = demo

    this.phase = 'starting'
    this.credentials = null
    this.demo = false
    this.repo = null
    this.cliCandidate = null
    this.signingIn = false
    this.signInError = null
    this.abort = null
    this.tokenRefresh = null
    this.#resetData()
  }

  #resetData() {
    this.summary = { memories: 0, openTodos: 0, openIssues: 0, projects: 0 }
    this.records = []
    this.total = 0
    this.projects = []
    this.filter = { kind: null, projectId: null }
    this.loading = false
    this.loadingMore = false
    this.problem = null
    this.problemMessage = null
    this.lastError = null
    this.updated = null
    this.lastAddedId = null
    this.details = new Map()
    this.pending = new Map()
    this.detailErrors = new Map()
    this.seq = 0
  }

  // ------------------------------------------------------------- output

  changed() {
    this.emit('change')
  }

  log(...lines) {
    this.emit('log', lines)
  }

  /**
   * One request, as the console prints it. Detail fetches run on every cursor
   * move and after each refresh, so they are only logged when they fail.
   */
  #logCall = ({ name, args, status, ms, error }) => {
    if (status === 200 && QUIET.has(name)) return
    const call = `tools/call ${name}${args && Object.keys(args).length ? ' ' + formatArgs(args) : ''}`
    if (status === 200) this.log(`→ ${call} … 200 OK ${ms}ms`)
    else this.log(`✗ ${call} … ${status || 'ERR'} ${error || ''}`.trimEnd())
  }

  get hasMore() {
    return this.records.length < this.total
  }

  get host() {
    return this.demo ? 'demo' : hostOf(this.credentials ? this.credentials.server : DEFAULT_SERVER)
  }

  get server() {
    return this.credentials ? this.credentials.server : DEFAULT_SERVER
  }

  snapshot() {
    const c = this.credentials
    return {
      phase: this.phase,
      demo: this.demo,
      host: this.host,
      server: this.server,
      keySource: this.demo ? 'demo account' : c ? (c.source === 'cli' ? sourceLabel(c) : c.source === 'oauth' ? 'oauth' : 'api key') : '',
      signingIn: this.signingIn,
      signInError: this.signInError,
      cli: this.cliCandidate ? { host: hostOf(this.cliCandidate.server), origin: sourceLabel(this.cliCandidate) } : null,
      credentialsPersist: this.store.persists !== false,
      summary: this.summary,
      records: this.records,
      total: this.total,
      hasMore: this.hasMore,
      projects: this.projects,
      filter: this.filter,
      loading: this.loading,
      loadingMore: this.loadingMore,
      problem: this.problem,
      problemMessage: this.problemMessage,
      updated: this.updated,
      lastAddedId: this.lastAddedId,
      details: Object.fromEntries(this.details),
      detailErrors: Object.fromEntries(this.detailErrors)
    }
  }

  // ----------------------------------------------------------- lifecycle

  async start() {
    const stored = this.store.read()
    if (stored) {
      this.log('$ reqall status', `✓ using saved credentials for ${hostOf(stored.server)}`)
      await this.#adopt(stored, { persist: false })
      return
    }
    this.cliCandidate = this.findCli()
    this.phase = 'signedOut'
    this.changed()
  }

  signInWithApiKey(key, server = DEFAULT_SERVER) {
    return this.#signIn('api key', async () => ({ server: normalizeServer(server), source: 'apiKey', apiKey: String(key).trim() }))
  }

  signInWithOAuth(server = DEFAULT_SERVER) {
    return this.#signIn('browser', async () => {
      this.abort = new AbortController()
      this.log(`$ reqall login --browser ${hostOf(normalizeServer(server))}`, '… waiting for the browser')
      try {
        return await this.runOAuth(this.oauth, normalizeServer(server), { signal: this.abort.signal })
      } finally {
        this.abort = null
      }
    })
  }

  continueWithCli() {
    return this.#signIn('cli', async () => this.cliCandidate)
  }

  /** Gives up on a browser sign-in that is waiting for its redirect. */
  cancelSignIn() {
    if (this.abort) this.abort.abort()
  }

  async startDemo() {
    this.#reset()
    this.demo = true
    this.repo = this.makeDemo({ onLog: this.#logCall })
    this.phase = 'ready'
    this.log('$ reqall demo', '✓ demo account · nothing leaves this machine')
    this.changed()
    await this.refresh()
  }

  async signOut() {
    this.store.clear()
    this.#reset()
    if (!this.cliCandidate) this.cliCandidate = this.findCli()
    this.phase = 'signedOut'
    this.log('$ reqall logout', '✓ signed out')
    this.changed()
  }

  async #signIn(how, obtain) {
    if (this.signingIn) return
    this.signingIn = true
    this.signInError = null
    this.changed()
    try {
      const c = await obtain()
      if (!c) throw new Error('No credentials found')
      this.log(`$ reqall login --${how.replace(' ', '-')}`)
      await this.#adopt(c, { validate: true })
    } catch (e) {
      if (e instanceof McpError) {
        this.signInError = e.failure === Failure.unauthorized ? 'That key was rejected (401). Check it and try again.'
          : e.failure === Failure.forbidden ? 'Access is paused for this account (403).'
            : e.failure === Failure.network ? 'Could not reach the server. Check the address and your connection.'
              : e.message
      } else {
        this.signInError = e && e.message ? e.message : String(e)
      }
      this.log(`✗ ${this.signInError}`)
    } finally {
      this.signingIn = false
      this.changed()
    }
  }

  /** Makes `c` the active credentials. With `validate`, one summary call must succeed first. */
  async #adopt(c, { persist = true, validate = false } = {}) {
    const repo = new LiveRepository(new McpClient({
      endpoint: c.server + '/mcp',
      token: () => bearer(this.credentials) || bearer(c),
      fetchImpl: this.fetchImpl,
      onLog: this.#logCall
    }))
    let summary = null
    if (validate) {
      const previous = this.credentials
      this.credentials = c
      try {
        summary = await repo.summary()
      } catch (e) {
        this.credentials = previous
        throw e
      }
    }
    this.#reset()
    this.credentials = c
    this.repo = repo
    if (summary) this.summary = summary
    if (persist) this.store.write(c)
    this.phase = 'ready'
    this.log(`✓ signed in to ${hostOf(c.server)} · ${sourceLabel(c)}`)
    this.changed()
    // A validated sign-in already has the summary; don't ask for it twice.
    this.refresh({ summary: !summary })
  }

  #reset() {
    this.cancelSignIn()
    this.credentials = null
    this.demo = false
    this.repo = null
    this.signInError = null
    this.#resetData()
  }

  // ------------------------------------------------------------ requests

  /**
   * Runs `op` against the repository, refreshing an OAuth token once on
   * expiry or a 401. Every failure lands in `lastError`; only the ones that
   * say the account or server is unwell (403, network, HTTP errors) set
   * `problem`, so a tool refusing one call does not mark the app offline.
   * Returns undefined when the call failed or the account changed meanwhile.
   */
  async #guard(op) {
    const repo = this.repo
    if (!repo) return undefined
    try {
      if (tokenExpired(this.credentials) && canRefresh(this.credentials)) await this.#refreshToken()
      const sent = bearer(this.credentials)
      let value
      try {
        value = await op(repo)
      } catch (e) {
        if (!(e instanceof McpError) || e.failure !== Failure.unauthorized || !canRefresh(this.credentials)) throw e
        // Another call may have refreshed while this one was in flight.
        if (bearer(this.credentials) === sent) await this.#refreshToken()
        value = await op(repo)
      }
      if (repo !== this.repo) return undefined
      if (this.problem) {
        this.problem = null
        this.problemMessage = null
      }
      return value
    } catch (e) {
      if (repo !== this.repo) return undefined
      if (e instanceof OAuthError || (e instanceof McpError && e.failure === Failure.unauthorized)) {
        this.#expire(e.message)
        return undefined
      }
      this.lastError = e && e.message ? e.message : String(e)
      if (e instanceof McpError && e.failure !== Failure.tool) {
        this.problem = e.failure === Failure.forbidden ? 'paused' : 'offline'
        this.problemMessage = this.lastError
      }
      this.changed()
      return undefined
    }
  }

  /**
   * One refresh at a time: with rotating refresh tokens, a second concurrent
   * refresh would spend the already-rotated token, get invalid_grant, and
   * sign out a session that had just refreshed fine.
   */
  #refreshToken() {
    if (!this.tokenRefresh) {
      const credentials = this.credentials
      this.log('→ oauth/token refresh_token')
      this.tokenRefresh = this.oauth.refresh(credentials).then((c) => {
        if (this.credentials === credentials) {
          this.credentials = c
          this.store.write(c)
        }
      }).finally(() => { this.tokenRefresh = null })
    }
    return this.tokenRefresh
  }

  #expire(why) {
    this.store.clear()
    this.#reset()
    this.signInError = `Your sign-in is no longer valid (${why}). Sign in again.`
    this.log(`✗ ${this.signInError}`)
    this.phase = 'signedOut'
    this.changed()
  }

  #recordArgs(offset = 0) {
    return { limit: PAGE_SIZE, offset, kind: this.filter.kind || undefined, projectId: this.filter.projectId ?? undefined }
  }

  async refresh({ summary: withSummary = true } = {}) {
    if (!this.repo || this.loading) return
    this.loading = true
    this.log('$ reqall refresh')
    this.changed()
    const repo = this.repo
    const seq = ++this.seq
    const result = await this.#guard((r) => Promise.all([
      withSummary ? r.summary() : this.summary,
      r.records(this.#recordArgs()),
      r.projects()
    ]))
    if (repo !== this.repo) return // a newer session owns the flags now
    this.loading = false
    if (result) {
      const [summary, page, projects] = result
      this.summary = summary
      this.projects = projects
      if (seq === this.seq) {
        this.records = page.records
        this.total = page.total
      }
      this.updated = Date.now()
      this.details.clear()
      this.pending.clear()
      this.detailErrors.clear()
      this.log(`✓ ${summary.memories} memories · ${summary.openTodos} todo · ${summary.openIssues} issues · ${summary.projects} projects`)
      for (const m of this.records.slice(0, PREFETCH)) this.detail(m.id)
    } else if (this.lastError) {
      this.log(`✗ ${this.lastError}`)
    }
    this.changed()
  }

  /** Narrows the record list on the server; null clears a dimension. */
  async setFilter({ kind, projectId } = {}) {
    if (!this.repo) return
    const next = {
      kind: kind === undefined ? this.filter.kind : kind,
      projectId: projectId === undefined ? this.filter.projectId : projectId
    }
    if (next.kind === this.filter.kind && next.projectId === this.filter.projectId) return
    const previous = this.filter
    this.filter = next
    const project = this.projects.find((p) => p.id === next.projectId)
    const parts = [next.kind && `kind:${next.kind}`, project && `project:${project.name}`].filter(Boolean)
    this.log(`$ filter ${parts.join(' ') || '--clear'}`)
    const repo = this.repo
    const seq = ++this.seq
    this.loadingMore = false
    this.changed()
    const page = await this.#guard((r) => r.records(this.#recordArgs()))
    if (repo !== this.repo || seq !== this.seq) return
    if (page) {
      this.records = page.records
      this.total = page.total
      this.log(`✓ ${page.total} records`)
    } else {
      this.filter = previous // the list still shows the old filter's records
      if (this.lastError) this.log(`✗ ${this.lastError}`)
    }
    this.changed()
  }

  async loadMore() {
    if (!this.repo || this.loadingMore || this.loading || !this.hasMore) return
    this.loadingMore = true
    this.changed()
    const repo = this.repo
    const seq = this.seq
    const page = await this.#guard((r) => r.records(this.#recordArgs(this.records.length)))
    if (repo !== this.repo) return
    this.loadingMore = false
    if (page && seq === this.seq) {
      const seen = new Set(this.records.map((m) => m.id))
      this.records = [...this.records, ...page.records.filter((m) => !seen.has(m.id))]
      this.total = page.total
    }
    this.changed()
  }

  /**
   * Body and links for one record, fetched once and folded back into the
   * list. A failure is remembered until the next refresh, not retried.
   */
  detail(id) {
    if (this.details.has(id)) return Promise.resolve(this.details.get(id))
    if (this.detailErrors.has(id)) return Promise.resolve(null)
    if (this.pending.has(id)) return this.pending.get(id)
    const repo = this.repo
    const p = this.#guard((r) => r.detail(id)).then((d) => {
      if (repo !== this.repo) return null
      this.pending.delete(id)
      if (!d) {
        this.detailErrors.set(id, this.lastError || `Could not load #${id}`)
        this.changed()
        return null
      }
      this.detailErrors.delete(id)
      this.details.set(id, d)
      const i = this.records.findIndex((m) => m.id === id)
      if (i >= 0 && d.memory.body != null) this.records[i] = { ...this.records[i], body: d.memory.body }
      this.changed()
      return d
    })
    this.pending.set(id, p)
    return p
  }

  /** Saves a new record. Returns an error message, or null on success. */
  async remember({ projectId, title, body = '', kind }) {
    const project = this.projects.find((p) => p.id === projectId)
    if (!project) return 'Pick a project'
    if (!String(title || '').trim()) return 'Give it a title'
    this.log(`$ reqall remember ${JSON.stringify(String(title).trim())} --project ${project.name}${kind ? ' --kind ' + kind : ''}`)
    const m = await this.#guard((r) => r.remember({ project, title: String(title).trim(), body: String(body || '').trim(), kind: kind || undefined }))
    if (!m) {
      const why = this.lastError || 'Could not save'
      this.log(`✗ ${why}`)
      return why
    }
    const fits = (!this.filter.kind || this.filter.kind === m.kind) && (this.filter.projectId == null || this.filter.projectId === project.id)
    if (fits) {
      this.records = [m, ...this.records.filter((r) => r.id !== m.id)]
      this.total++
    }
    this.summary = { ...this.summary, memories: this.summary.memories + 1 }
    this.lastAddedId = m.id
    this.log(`✓ remembered #${m.id} in ${project.name}`)
    this.changed()
    return null
  }

  /** Changes a record's status optimistically; reverts and returns an error message if refused. */
  async setStatus(id, status) {
    const i = this.records.findIndex((m) => m.id === id)
    if (i < 0) return `Unknown record #${id}`
    const before = this.records[i]
    this.records[i] = { ...before, status }
    this.log(`$ reqall status #${id} ${status}`)
    this.changed()
    const saved = await this.#guard((r) => r.setStatus(id, status))
    const j = this.records.findIndex((m) => m.id === id)
    if (!saved) {
      if (j >= 0) this.records[j] = before
      const why = this.lastError || `Could not update #${id}`
      this.log(`✗ ${why}`)
      this.changed()
      return why
    }
    if (j >= 0) this.records[j] = { ...this.records[j], status: saved.status, updatedAt: saved.updatedAt }
    // The header counts open todos and issues; keep them in step.
    const delta = (saved.status === 'open') - (before.status === 'open')
    if (delta && before.kind === 'todo') this.summary = { ...this.summary, openTodos: this.summary.openTodos + delta }
    if (delta && before.kind === 'issue') this.summary = { ...this.summary, openIssues: this.summary.openIssues + delta }
    const d = this.details.get(id)
    if (d) this.details.set(id, { ...d, memory: { ...d.memory, status: saved.status } })
    this.log(`✓ #${id} is ${saved.status}`)
    this.changed()
    return null
  }
}
