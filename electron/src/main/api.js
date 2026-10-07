// A small client for the Reqall REST API under `{server}/api/v1`. Every
// request carries the bearer read at call time, and every one is reported to
// `onLog`, which feeds the console's request log as `GET /api/v1/records?…`.
//
// The server rate-limits bursts, and a refresh plus detail prefetch is one,
// so at most `maxInFlight` requests run at once and a 429 is retried after its
// Retry-After (or a short backoff) before it counts as a failure.

export const Failure = Object.freeze({
  unauthorized: 'unauthorized',
  forbidden: 'forbidden',
  network: 'network',
  server: 'server',
  request: 'request' // 400 / 404 / other 4xx: this request was refused, the account is fine
})

export class ApiError extends Error {
  /** `code` is the server's `error` field, e.g. not_found, trial_expired, key_paused. */
  constructor(failure, message, status = 0, code = '') {
    super(message)
    this.failure = failure
    this.status = status
    this.code = code
  }
}

export const API_PREFIX = '/api/v1'

/** `/api/v1/records` plus a query string of the defined values, in order. */
export function apiPath(path, query = {}) {
  const q = new URLSearchParams()
  for (const [k, v] of Object.entries(query || {})) if (v !== undefined && v !== null && v !== '') q.set(k, String(v))
  const s = q.toString()
  return API_PREFIX + path + (s ? '?' + s : '')
}

const STATUS_TEXT = { 200: 'OK', 201: 'Created', 204: 'No Content' }
export const statusText = (status) => STATUS_TEXT[status] || ''

export class ApiClient {
  /**
   * @param {object} o
   * @param {string} o.server normalized server URL, e.g. https://www.reqall.net
   * @param {() => string} o.token read on every request, so a refreshed token applies at once
   */
  constructor({ server, token, fetchImpl = fetch, timeoutMs = 20000, onLog = () => {}, maxInFlight = 4, retries = 2, backoffMs = 1000 }) {
    this.server = server
    this.token = token
    this.fetchImpl = fetchImpl
    this.timeoutMs = timeoutMs
    this.onLog = onLog
    this.maxInFlight = maxInFlight
    this.retries = retries
    this.backoffMs = backoffMs
    this.inFlight = 0
    this.waiting = []
  }

  get(path, query) { return this.request('GET', path, { query }) }
  post(path, body) { return this.request('POST', path, { body }) }
  patch(path, body) { return this.request('PATCH', path, { body }) }

  /** `path` is relative to /api/v1, e.g. '/records/7'. Resolves to the parsed JSON body. */
  async request(method, path, { query, body } = {}) {
    const target = apiPath(path, query)
    await this.#acquire()
    const started = Date.now()
    const log = (status, error) => this.onLog({ method, path: target, status, ms: Date.now() - started, error })
    try {
      for (let attempt = 0; ; attempt++) {
        try {
          const { status, data } = await this.#send(method, target, body)
          log(status)
          return data
        } catch (e) {
          if (!(e instanceof ApiError) || e.status !== 429 || attempt >= this.retries) throw e
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

  async #send(method, target, body) {
    const headers = { Authorization: 'Bearer ' + this.token(), Accept: 'application/json' }
    if (body !== undefined) headers['Content-Type'] = 'application/json'
    let res
    try {
      res = await this.fetchImpl(this.server + target, {
        method,
        headers,
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
        signal: AbortSignal.timeout(this.timeoutMs)
      })
    } catch {
      throw new ApiError(Failure.network, 'Could not reach ' + hostOf(this.server))
    }

    const text = await res.text()
    let json
    try { json = text ? JSON.parse(text) : null } catch { json = undefined }
    const status = res.status

    if (status >= 200 && status < 300) {
      if (json === undefined || (text && (json === null || typeof json !== 'object'))) {
        throw new ApiError(Failure.server, 'Unexpected response', status)
      }
      return { status, data: json }
    }

    const err = json && typeof json === 'object' && !Array.isArray(json) ? json : {}
    const code = typeof err.error === 'string' ? err.error : ''
    const message = (fallback) => String(err.message ?? err.error_description ?? fallback)
    if (status === 401) throw new ApiError(Failure.unauthorized, message('Unauthorized'), status, code)
    if (status === 403) throw new ApiError(Failure.forbidden, message(code === 'key_paused' ? 'This API key is paused' : code === 'trial_expired' ? 'Your trial has expired' : 'Forbidden'), status, code)
    if (status === 429) {
      const e = new ApiError(Failure.server, 'Rate limited by the server (429), try again shortly', status, code)
      const header = res.headers.get('retry-after')
      const after = header == null || header.trim() === '' ? NaN : Number(header)
      if (Number.isFinite(after) && after >= 0) e.retryAfterMs = Math.min(after, 10) * 1000
      throw e
    }
    if (status === 404) throw new ApiError(Failure.request, message('Not found'), status, code)
    if (status >= 400 && status < 500) throw new ApiError(Failure.request, message(code || 'Bad request (HTTP ' + status + ')'), status, code)
    throw new ApiError(Failure.server, 'Server returned HTTP ' + status, status, code)
  }
}

function hostOf(url) {
  try { return new URL(url).host } catch { return String(url) }
}
