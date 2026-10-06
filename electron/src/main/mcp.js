// One JSON-RPC `tools/call` against the Reqall MCP endpoint, the same request
// the Flutter app, desktop app and omarchy widget make. The server answers as
// plain JSON or as a one-event SSE stream; both are handled. Every call is
// reported to `onLog`, which feeds the console's request log.
//
// The server rate-limits bursts, and a refresh plus detail prefetch is one,
// so at most `maxInFlight` calls run at once and a 429 is retried after its
// Retry-After (or a short backoff) before it counts as a failure.

export const Failure = Object.freeze({
  unauthorized: 'unauthorized',
  forbidden: 'forbidden',
  network: 'network',
  server: 'server',
  tool: 'tool'
})

export class McpError extends Error {
  constructor(failure, message, status = 0) {
    super(message)
    this.failure = failure
    this.status = status
  }
}

export class McpClient {
  /**
   * @param {object} o
   * @param {string} o.endpoint full URL of the MCP endpoint, e.g. https://www.reqall.net/mcp
   * @param {() => string} o.token read on every call, so a refreshed token applies at once
   */
  constructor({ endpoint, token, fetchImpl = fetch, timeoutMs = 20000, onLog = () => {}, maxInFlight = 4, retries = 2, backoffMs = 1000 }) {
    this.endpoint = endpoint
    this.token = token
    this.fetchImpl = fetchImpl
    this.timeoutMs = timeoutMs
    this.onLog = onLog
    this.maxInFlight = maxInFlight
    this.retries = retries
    this.backoffMs = backoffMs
    this.id = 0
    this.inFlight = 0
    this.waiting = []
  }

  async call(name, args = {}) {
    await this.#acquire()
    const started = Date.now()
    const log = (status, error) => this.onLog({ name, args, status, ms: Date.now() - started, error })
    try {
      for (let attempt = 0; ; attempt++) {
        try {
          const data = await this.#call(name, args)
          log(200)
          return data
        } catch (e) {
          if (!(e instanceof McpError) || e.status !== 429 || attempt >= this.retries) throw e
          await new Promise((r) => setTimeout(r, e.retryAfterMs ?? this.backoffMs * 2 ** attempt))
        }
      }
    } catch (e) {
      log(e.status || 0, e.message)
      throw e
    } finally {
      this.#release()
    }
  }

  #acquire() {
    if (this.inFlight < this.maxInFlight) {
      this.inFlight++
      return Promise.resolve()
    }
    return new Promise((resolve) => this.waiting.push(resolve))
  }

  #release() {
    const next = this.waiting.shift()
    if (next) next()
    else this.inFlight--
  }

  async #call(name, args) {
    const body = JSON.stringify({ jsonrpc: '2.0', id: ++this.id, method: 'tools/call', params: { name, arguments: args } })
    let res
    try {
      res = await this.fetchImpl(this.endpoint, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer ' + this.token(),
          'Content-Type': 'application/json',
          Accept: 'application/json, text/event-stream'
        },
        body,
        signal: AbortSignal.timeout(this.timeoutMs)
      })
    } catch {
      throw new McpError(Failure.network, 'Could not reach ' + hostOf(this.endpoint))
    }

    let text = await res.text()
    const jsonMessage = (fallback) => {
      try {
        const j = JSON.parse(text)
        if (j && typeof j === 'object') return String(j.message ?? j.error_description ?? j.error ?? fallback)
      } catch { /* not JSON */ }
      return fallback
    }
    if (res.status === 401) throw new McpError(Failure.unauthorized, jsonMessage('Unauthorized'), 401)
    if (res.status === 403) throw new McpError(Failure.forbidden, jsonMessage('Forbidden'), 403)
    if (res.status === 429) {
      const e = new McpError(Failure.server, 'Rate limited by the server (429), try again shortly', 429)
      const header = res.headers.get('retry-after')
      const after = header == null || header.trim() === '' ? NaN : Number(header)
      if (Number.isFinite(after) && after >= 0) e.retryAfterMs = Math.min(after, 10) * 1000
      throw e
    }
    if (res.status !== 200) throw new McpError(Failure.server, 'Server returned HTTP ' + res.status, res.status)

    if (/^(event|data):/.test(text)) {
      const line = text.split(/\r?\n/).find((l) => l.startsWith('data:'))
      text = line ? line.slice(5).trimStart() : ''
    }

    let payload
    try { payload = JSON.parse(text) } catch { throw new McpError(Failure.server, 'Unexpected response', 200) }
    if (!payload || typeof payload !== 'object') throw new McpError(Failure.server, 'Unexpected response', 200)

    if (payload.error && typeof payload.error === 'object') {
      throw new McpError(Failure.tool, String(payload.error.message ?? 'Request failed'), 200)
    }
    const result = payload.result
    const structured = result && result.structuredContent
    if (structured && typeof structured === 'object') {
      if (structured.ok === false || result.isError === true) {
        throw new McpError(Failure.tool, String(structured.error ?? structured.message ?? 'Request failed'), 200)
      }
      return structured.data && typeof structured.data === 'object' ? structured.data : structured
    }
    // Errors from the tool layer arrive as text content with isError set.
    const first = result && Array.isArray(result.content) ? result.content[0] : null
    throw new McpError(Failure.tool, first && first.text ? String(first.text) : 'Unexpected response', 200)
  }
}

function hostOf(url) {
  try { return new URL(url).host } catch { return String(url) }
}
