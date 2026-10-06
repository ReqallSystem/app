// The console. Draws the session snapshot the main process sends, owns the
// cursor, keyboard, palette and Remember form, and types the request log out
// line by line. It never talks to the network: everything goes through the
// preload bridge (window.reqall).

import { KINDS, KIND_COLORS, relativeAge, shortProject, rank } from '../shared/model.js'

const api = window.reqall
const $ = (id) => document.getElementById(id)
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
const MAC = /Mac/.test(navigator.platform)
const PALETTE_KEY = MAC ? '⌘K' : '^K'
const SPINNER = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
const DEFAULT_SERVER = 'https://www.reqall.net'

const svg = (body, fill = false) =>
  `<svg viewBox="0 0 24 24" fill="${fill ? 'currentColor' : 'none'}" stroke="${fill ? 'none' : 'currentColor'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`

const ICONS = {
  todo: svg('<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 12l3 3 5-6"/>'),
  issue: svg('<path d="M8 2l1.9 1.9M16 2l-1.9 1.9M9 8V6a3 3 0 0 1 6 0v2M3 13h3M18 13h3M4 20l2.5-2M20 20l-2.5-2"/><path d="M12 20a5 5 0 0 0 5-5v-4a5 5 0 0 0-10 0v4a5 5 0 0 0 5 5zM12 11v9"/>'),
  spec: svg('<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h8"/>'),
  arch: svg('<rect x="9" y="3" width="6" height="5" rx="1"/><rect x="2" y="16" width="6" height="5" rx="1"/><rect x="16" y="16" width="6" height="5" rx="1"/><path d="M12 8v4M5 16v-4h14v4"/>'),
  test: svg('<path d="M9 3h6M10 3v7l-5.5 9a2 2 0 0 0 1.7 3h11.6a2 2 0 0 0 1.7-3L14 10V3"/><path d="M7 16h10"/>'),
  info: svg('<path d="M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.6.4 1 1.1 1 1.8V16h5v-.3c0-.7.4-1.4 1-1.8A6 6 0 0 0 12 3z"/>'),
  work: svg('<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.4-.6-.6-2.4z"/>'),
  plus: svg('<path d="M12 5v14M5 12h14"/>'),
  refresh: svg('<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/>'),
  open: svg('<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>'),
  filterOff: svg('<path d="M3 4h18l-7 9v6l-4 2v-8z"/><path d="M4 20L20 4"/>'),
  folder: svg('<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'),
  check: svg('<path d="M5 12l5 5 9-10"/>'),
  archive: svg('<rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11h14V8M10 12h4"/>'),
  undo: svg('<path d="M9 14L4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/>'),
  logout: svg('<path d="M10 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h5M15 8l4 4-4 4M19 12H9"/>'),
  login: svg('<path d="M14 3h5a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-5M3 12h12M11 8l4 4-4 4"/>'),
  chevron: svg('<path d="M9 6l6 6-6 6"/>')
}

const ACTIONS = [
  { id: 'open', key: 'o', label: 'Open' },
  { id: 'remember', key: 'a', label: 'Remember' },
  { id: 'refresh', key: 'r', label: 'Refresh' }
]

let S = null // the latest session snapshot
const ui = {
  section: 'records',
  action: 0,
  cursor: 0,
  selectedId: null,
  peekId: null,
  scroll: false,
  palette: false,
  paletteSel: 0,
  paletteRanked: [],
  remember: false,
  rememberKind: null,
  rememberBusy: false,
  lastAddedId: null,
  login: 0,
  loginShape: '',
  signingWith: null,
  spin: 0,
  narrow: false
}

// ------------------------------------------------------------------- log
// The log types itself out: finished lines in `done`, the line in flight in
// `typing`, the rest queued in `pending`. A long queue types faster so a
// refresh never leaves the log seconds behind.

const log = { done: [], pending: [], typing: null, typed: 0, pause: 0 }
let ticker = null

function enqueue(lines) {
  log.pending.push(...lines)
  ensureTicker()
}

const busy = () => !!S && (S.loading || S.loadingMore || S.signingIn || S.phase === 'starting')

function ensureTicker() {
  if (!ticker) ticker = setInterval(tick, 16)
}

function tick() {
  ui.spin++
  if (ui.spin % 5 === 0 && busy()) renderBusy()
  if (log.pause > 0) { log.pause--; return }
  if (log.typing == null) {
    if (!log.pending.length) {
      if (!busy()) { clearInterval(ticker); ticker = null }
      return
    }
    log.typing = log.pending.shift()
    log.typed = 0
  }
  log.typed = Math.min(log.typed + 2 + log.pending.length * 2, log.typing.length)
  if (log.typed >= log.typing.length) {
    log.done.push(log.typing)
    if (log.done.length > 60) log.done.shift()
    log.typing = null
    log.pause = log.pending.length > 2 ? 0 : 4 + Math.floor(Math.random() * 12)
  }
  renderLog()
}

function logLine(line) {
  const s = String(line)
  if (s.startsWith('$')) return `<span class="cmd">${esc(s)}</span>`
  if (s.startsWith('✓')) return `<span class="done">${esc(s)}</span>`
  if (s.startsWith('✗')) return `<span class="fail">${esc(s)}</span>`
  const ok = s.indexOf('200 OK')
  if (ok >= 0) return `${esc(s.slice(0, ok))}<span class="ok200">${esc(s.slice(ok))}</span>`
  return esc(s)
}

function renderLog() {
  const lines = log.done.slice(-8).map((l) => `<div>${logLine(l)}</div>`)
  if (log.typing != null) lines.push(`<div>${logLine(log.typing.slice(0, log.typed))}<span class="cursor"></span></div>`)
  $('log').innerHTML = lines.join('')
}

const spinner = () => SPINNER[Math.floor(ui.spin / 5) % SPINNER.length]

// ------------------------------------------------------------------ data

const rows = () => (S ? S.records : [])
const detailOf = (id) => (S && S.details ? S.details[id] : null)
const lookup = (id) => rows().find((m) => m.id === id) || (detailOf(id) && detailOf(id).memory) || null

/** The record the preview shows: a peeked link target, else the cursor's row. */
function selected() {
  if (ui.peekId != null) return lookup(ui.peekId)
  const r = rows()
  return r.length ? r[Math.min(ui.cursor, r.length - 1)] : null
}

function bodyOf(m) {
  if (m.body != null) return m.body
  const d = detailOf(m.id)
  return d ? d.memory.body ?? '' : null
}

let detailTimer = null
function wantDetail() {
  clearTimeout(detailTimer)
  const m = selected()
  const id = m ? m.id : ui.peekId
  if (id == null || detailOf(id)) return
  detailTimer = setTimeout(() => api.detail(id), 120)
}

function adopt(next) {
  const prev = S
  S = next
  if (S.phase !== 'ready') {
    Object.assign(ui, { section: 'records', cursor: 0, selectedId: null, peekId: null })
    if (ui.palette) closePalette()
    if (ui.remember) closeRemember()
  } else {
    const r = rows()
    if (S.lastAddedId != null && S.lastAddedId !== ui.lastAddedId) {
      ui.selectedId = S.lastAddedId
      ui.section = 'records'
      ui.scroll = true
    }
    // Keep the cursor on the same record across refreshes and inserts.
    const i = ui.selectedId == null ? -1 : r.findIndex((m) => m.id === ui.selectedId)
    ui.cursor = i >= 0 ? i : Math.max(0, Math.min(ui.cursor, r.length - 1))
    ui.selectedId = r[ui.cursor] ? r[ui.cursor].id : null
  }
  ui.lastAddedId = S.lastAddedId
  if (!S.signingIn) ui.signingWith = null
  if (prev && prev.phase !== S.phase && S.phase === 'signedOut') ui.login = 0
  if (busy()) ensureTicker()
  render()
  wantDetail()
}

// --------------------------------------------------------------- actions

function run(id) {
  if (id === 'open') openDashboard()
  else if (id === 'remember') openRemember()
  else if (id === 'refresh') api.refresh()
}

async function openDashboard() {
  if (await api.openDashboard(null)) enqueue([`$ open ${S.server}/dashboard`, '✓ opened the dashboard in your browser'])
  else enqueue(['✗ demo mode · sign in to open the dashboard'])
}

async function openRecord(m) {
  if (!m) return
  if (await api.openDashboard(m.id)) enqueue([`$ open ${S.server}/dashboard#records`, `✓ opened the dashboard for #${m.id}`])
  else enqueue(['✗ demo mode · sign in to open the dashboard'])
}

function setStatus(m, status) {
  if (m && rows().some((r) => r.id === m.id)) api.setStatus(m.id, status)
  else if (m) enqueue([`✗ #${m.id} is not in the loaded list`])
}

/** x: resolve what is live, reopen what is done. */
function toggleResolve(m) {
  if (!m) return
  setStatus(m, m.status === 'open' || m.status === 'active' ? 'resolved' : 'open')
}

function setFilter(f) {
  Object.assign(ui, { section: 'records', cursor: 0, selectedId: null, peekId: null, scroll: true })
  api.setFilter(f)
}

const hasFilter = () => !!S && (S.filter.kind || S.filter.projectId != null)

function clearFilters() {
  setFilter({ kind: null, projectId: null })
}

function goto(id) {
  const i = rows().findIndex((m) => m.id === id)
  if (i >= 0) {
    Object.assign(ui, { section: 'records', cursor: i, selectedId: id, peekId: null, scroll: true })
  } else {
    ui.peekId = id
    api.detail(id)
  }
  render()
  wantDetail()
}

// ---------------------------------------------------------------- cursor

function move(dx, dy) {
  const r = rows()
  ui.peekId = null
  if (ui.section === 'actions') {
    if (dx) ui.action = Math.max(0, Math.min(ACTIONS.length - 1, ui.action + dx))
    if (dy > 0 && r.length) { ui.section = 'records'; ui.cursor = 0 }
  } else if (dy < 0) {
    if (ui.cursor > 0) ui.cursor--
    else ui.section = 'actions'
  } else if (dy > 0 && ui.cursor < r.length - 1) {
    ui.cursor++
  }
  if (ui.section === 'records' && dy > 0 && ui.cursor >= r.length - 5) api.loadMore()
  ui.selectedId = r[ui.cursor] ? r[ui.cursor].id : null
  ui.scroll = true
  render()
  wantDetail()
}

function activate() {
  if (ui.section === 'actions') run(ACTIONS[ui.action].id)
  else openRecord(selected())
}

// ---------------------------------------------------------------- render

function render() {
  if (!S) return
  $('login').hidden = S.phase !== 'signedOut'
  $('console').hidden = S.phase !== 'ready'
  renderStatus()
  renderKeys()
  if (S.phase === 'signedOut') renderLogin()
  if (S.phase === 'ready') {
    renderActions()
    renderRecords()
    renderPreview()
  }
  if (ui.palette) renderPalette()
}

/** Only what animates while a request is in flight. */
function renderBusy() {
  renderStatus()
  if (S.phase === 'ready' && S.loadingMore) renderRecords()
  if (S.phase === 'signedOut') renderLoginMessage()
}

function renderStatus() {
  let state
  if (S.phase === 'starting') state = `<span class="warn">${spinner()} starting</span>`
  else if (S.phase === 'signedOut') state = S.signingIn ? `<span class="warn">${spinner()} signing in</span>` : '<span class="muted">○ signed out</span>'
  else if (S.loading || S.loadingMore) state = `<span class="warn">${spinner()} sync</span>`
  else if (S.problem === 'paused') state = `<span class="warn" title="${esc(S.problemMessage)}">● paused</span>`
  else if (S.problem === 'offline') state = `<span class="bad" title="${esc(S.problemMessage)}">● offline</span>`
  else state = '<span class="ok">● ok</span>'

  const stat = (n, label) => `<span class="stat"><b>${Number(n).toLocaleString('en-US')}</b> <span>${label}</span></span>`
  const ready = S.phase === 'ready'
  const parts = [`<span><span class="glow b">reqall</span><span class="soft">@${esc(S.host)}</span></span>`, state]
  if (ready) {
    parts.push(stat(S.summary.memories, 'memories'), stat(S.summary.openTodos, 'todo'), stat(S.summary.openIssues, 'issues'), stat(S.summary.projects, 'projects'))
    if (!ui.narrow && S.keySource) parts.push(`<span class="key">key: ${esc(S.keySource)}</span>`)
  }
  const account = !ready ? ''
    : S.demo ? `<button class="chip-button" data-do="sign-out">${ICONS.login}sign in</button>`
      : `<button class="chip-button" data-do="sign-out">${ICONS.logout}sign out</button>`
  $('status').innerHTML = `<div class="stats">${parts.join('')}</div>${account}`
}

function renderActions() {
  $('actions-box').classList.toggle('active', ui.section === 'actions')
  $('actions').innerHTML = ACTIONS.map((a, i) => {
    const on = ui.section === 'actions' && ui.action === i
    return `<button class="action${on ? ' on' : ''}" data-action="${i}">[<span class="k">${a.key}</span>] ${a.label}</button>`
  }).join('')
  $('palette-button').textContent = ui.narrow ? PALETTE_KEY : `${PALETTE_KEY} palette`
}

function renderRecords() {
  const r = rows()
  const box = $('records-box')
  box.classList.toggle('active', ui.section === 'records' && ui.peekId == null)
  box.dataset.trail = `${r.length}/${S.total}`

  const project = S.projects.find((p) => p.id === S.filter.projectId)
  const chips = [
    S.filter.kind && `<button class="chip" data-clear="kind">kind:${esc(S.filter.kind)} ×</button>`,
    S.filter.projectId != null && `<button class="chip" data-clear="project">project:${esc(shortProject(project ? project.name : '#' + S.filter.projectId))} ×</button>`
  ].filter(Boolean)
  $('chips').hidden = !chips.length
  $('chips').innerHTML = chips.join('')

  const list = $('rows')
  if (!r.length) {
    list.innerHTML = `<div class="empty">${S.loading ? `${spinner()} loading…` : hasFilter() ? 'no records match · esc clears filters' : 'no records yet · a to remember one'}</div>`
    return
  }
  const now = Date.now()
  const html = r.map((m, i) => {
    const sel = ui.cursor === i
    const on = sel && ui.section === 'records' && ui.peekId == null
    const cls = ['row', sel && 'sel', on && 'on', m.status === 'archived' && 'archived', m.id === S.lastAddedId && 'added'].filter(Boolean).join(' ')
    const color = KIND_COLORS[m.kind]
    return `<div class="${cls}" data-i="${i}">` +
      `<span class="c-kind" style="color:${color}">${ICONS[m.kind]}${m.kind}</span>` +
      `<span class="c-id">#${m.id}</span>` +
      `<span class="c-title">${esc(m.title)}</span>` +
      `<span class="c-project">${esc(shortProject(m.project))}</span>` +
      `<span class="c-age">${relativeAge(now - m.updatedAt)}</span></div>`
  })
  if (S.hasMore) {
    html.push(`<div class="row more" data-more="1">${S.loadingMore ? `${spinner()} loading more…` : `▾ ${(S.total - r.length).toLocaleString('en-US')} more · scroll to load`}</div>`)
  }
  list.innerHTML = html.join('')
  if (ui.scroll) {
    ui.scroll = false
    const el = list.children[ui.cursor]
    if (el) el.scrollIntoView({ block: 'nearest' })
  }
}

function renderPreview() {
  const box = $('preview-box')
  const out = $('preview')
  const m = selected()
  box.classList.toggle('active', ui.peekId != null)
  if (!m) {
    delete box.dataset.trail
    const failed = ui.peekId != null && S.detailErrors ? S.detailErrors[ui.peekId] : null
    out.innerHTML = `<div class="empty">${ui.peekId == null ? 'nothing selected'
      : failed ? `#${ui.peekId}: ${esc(failed)} · esc back` : `${spinner()} loading #${ui.peekId}…`}</div>`
    return
  }
  box.dataset.trail = ui.peekId != null ? `#${m.id} · esc back` : `#${m.id}`
  const stateClass = m.status === 'open' ? 'warn' : m.status === 'active' ? 'ok' : 'muted'
  const body = bodyOf(m)
  const d = detailOf(m.id)
  const linkRow = (l) => {
    const t = lookup(l.otherId)
    const rel = l.relationship && l.relationship !== 'related' ? `<span class="rel">${esc(l.relationship)} </span>` : ''
    const target = t
      ? `<span style="color:${KIND_COLORS[t.kind]}">${t.kind}</span> <span class="t">${esc(t.title)}</span>`
      : '<span class="muted t">(not loaded · ⏎ to peek)</span>'
    return `<button class="link" data-goto="${l.otherId}"><span class="a">${l.outgoing ? '→' : '←'}</span> ${rel}<span class="id">#${l.otherId}</span> ${target}</button>`
  }
  out.innerHTML =
    `<div class="meta" style="color:${KIND_COLORS[m.kind]}">${ICONS[m.kind]}<span class="kind">${m.kind}</span>` +
    `<span class="state ${stateClass}">[${esc(m.status)}]</span><span class="age">${relativeAge(Date.now() - m.updatedAt)} ago</span></div>` +
    `<h2 class="glow">${esc(m.title)}</h2>` +
    `<div class="project">${esc(m.project)}</div>` +
    `<p class="body${body ? '' : ' none'}">${body != null ? (body ? esc(body) : '(no body)') : S.detailErrors && S.detailErrors[m.id] ? `(${esc(S.detailErrors[m.id])})` : 'loading…'}<span class="cursor"></span></p>` +
    (d && d.links.length ? `<div class="links-title">links</div>${d.links.map(linkRow).join('')}` : '')
}

function renderKeys() {
  const k = (key, what) => `<span><b>${key}</b> ${what}</span>`
  let keys
  if (!S || S.phase !== 'ready') {
    keys = S && S.signingIn ? [k('esc', 'cancel')]
      : [k('j/k', 'move'), k('⏎', 'choose'), ...(S ? loginOptions() : []).map((o) => k(o.key, o.id === 'key' ? 'api key' : o.id))]
  } else if (ui.narrow) {
    keys = [k('click', 'select'), k('click again', 'open'), k(PALETTE_KEY, 'palette')]
  } else {
    keys = [k('j/k', 'move'), k('h/l', 'actions'), k('⏎', 'open'), k('x', 'resolve'), k('r', 'refresh'), k('o', 'dashboard'), k('a', 'remember'), k(':', 'palette'), k('esc', 'back')]
  }
  $('keys').innerHTML = keys.join('')
}

// ----------------------------------------------------------------- login

function loginOptions() {
  return [
    { id: 'browser', key: 'b', label: 'sign in with the browser' },
    S.cli && { id: 'cli', key: 'c', label: 'continue with CLI login', hint: `${S.cli.host} · ${S.cli.origin}` },
    { id: 'key', key: 'a', label: 'api key' },
    { id: 'demo', key: 'd', label: 'try the demo', hint: 'mock account · offline' }
  ].filter(Boolean)
}

const serverValue = () => $('server').value.trim() || DEFAULT_SERVER

function renderLogin() {
  const opts = loginOptions()
  const shape = opts.map((o) => o.id + (o.hint || '')).join('|')
  // Built once per shape, so the API key field keeps its value and focus.
  if (shape !== ui.loginShape) {
    ui.loginShape = shape
    $('login-options').innerHTML = opts.map((o) => o.id === 'key'
      ? `<div class="option" data-login="key"><span class="k">[${o.key}]</span><span class="label">${o.label}</span>` +
        '<input id="api-key" type="password" spellcheck="false" autocomplete="off" placeholder="paste your key">' +
        '<button class="primary" data-do="connect">connect</button><button class="link-button" data-do="get-key">get one ↗</button></div>'
      : `<button class="option" data-login="${o.id}"><span class="k">[${o.key}]</span><span class="label">${o.label}</span>` +
        `${o.id === 'browser' ? '<span class="hint" id="browser-hint"></span>' : o.hint ? `<span class="hint">${esc(o.hint)}</span>` : ''}</button>`
    ).join('')
  }
  ui.login = Math.min(ui.login, opts.length - 1)
  ;[...$('login-options').children].forEach((el, i) => el.classList.toggle('on', i === ui.login))
  const hint = $('browser-hint')
  if (hint) hint.textContent = hostLabel(serverValue())
  const note = $('login-note')
  note.hidden = S.credentialsPersist
  note.textContent = 'No OS keychain found: a sign-in lasts until you quit.'
  renderLoginMessage()
}

function hostLabel(server) {
  try { return new URL(server.includes('://') ? server : 'https://' + server).host } catch { return server }
}

function renderLoginMessage() {
  const msg = $('login-message')
  if (S.signingIn) {
    msg.hidden = false
    msg.className = 'login-message busy'
    msg.textContent = ui.signingWith === 'browser'
      ? `${spinner()} waiting for the browser… finish signing in there, or esc to cancel`
      : `${spinner()} checking credentials…`
  } else {
    msg.hidden = !S.signInError
    msg.className = 'login-message'
    msg.textContent = S.signInError || ''
  }
}

function chooseLogin(id) {
  if (S.signingIn) return
  ui.login = Math.max(0, loginOptions().findIndex((o) => o.id === id))
  if (id === 'browser') { ui.signingWith = 'browser'; api.signInWithBrowser(serverValue()) }
  else if (id === 'cli') { ui.signingWith = 'cli'; api.continueWithCli() }
  else if (id === 'demo') api.startDemo()
  else if (id === 'key') {
    const input = $('api-key')
    if (input.value.trim()) { ui.signingWith = 'key'; api.signInWithKey(input.value.trim(), serverValue()) }
    else input.focus()
  }
  renderLogin()
}

function loginKey(e) {
  const inField = e.target.matches('input, textarea, select')
  if (e.key === 'Escape') {
    if (S.signingIn) api.cancelSignIn()
    else if (inField) e.target.blur()
    else return
    e.preventDefault()
    return
  }
  if (inField) {
    if (e.key === 'Enter' && e.target.id === 'api-key') { e.preventDefault(); chooseLogin('key') }
    if (e.key === 'Enter' && e.target.id === 'server') { e.preventDefault(); e.target.blur() }
    return
  }
  if (e.ctrlKey || e.metaKey || e.altKey) return
  const opts = loginOptions()
  const byKey = opts.find((o) => o.key === e.key)
  if (e.key === 'j' || e.key === 'ArrowDown') ui.login = Math.min(opts.length - 1, ui.login + 1)
  else if (e.key === 'k' || e.key === 'ArrowUp') ui.login = Math.max(0, ui.login - 1)
  else if (e.key === 'Enter' && !e.repeat) chooseLogin(opts[ui.login].id)
  else if (byKey && !e.repeat) chooseLogin(byKey.id)
  else return
  e.preventDefault()
  renderLogin()
}

// --------------------------------------------------------------- palette

function paletteItems() {
  const m = selected()
  const items = [
    { label: 'remember', hint: 'a · add a memory', icon: ICONS.plus, run: openRemember },
    { label: 'refresh', hint: 'r · re-fetch', icon: ICONS.refresh, run: () => api.refresh() },
    { label: 'open dashboard', hint: `o · ${S.host}`, icon: ICONS.open, run: openDashboard }
  ]
  if (m) {
    if (m.status === 'open' || m.status === 'active') items.push({ label: `resolve #${m.id}`, hint: 'x · status resolved', icon: ICONS.check, run: () => setStatus(m, 'resolved') })
    if (m.status !== 'open') items.push({ label: `reopen #${m.id}`, hint: 'status open', icon: ICONS.undo, run: () => setStatus(m, 'open') })
    if (m.status !== 'archived') items.push({ label: `archive #${m.id}`, hint: 'status archived', icon: ICONS.archive, run: () => setStatus(m, 'archived') })
  }
  if (hasFilter()) items.push({ label: 'clear filters', hint: 'esc', icon: ICONS.filterOff, run: clearFilters })
  items.push(S.demo
    ? { label: 'sign in', hint: 'leave the demo', icon: ICONS.login, run: () => api.signOut() }
    : { label: 'sign out', hint: S.host, icon: ICONS.logout, run: () => api.signOut() })
  for (const k of KINDS) items.push({ label: `kind:${k}`, hint: 'filter', icon: ICONS[k], color: KIND_COLORS[k], run: () => setFilter({ kind: k }) })
  for (const p of S.projects) items.push({ label: `project:${p.name}`, hint: String(p.count), icon: ICONS.folder, run: () => setFilter({ projectId: p.id }) })
  for (const r of rows()) items.push({ label: `#${r.id} ${r.title}`, hint: `goto · ${r.kind}`, icon: ICONS[r.kind], color: KIND_COLORS[r.kind], run: () => goto(r.id) })
  return items
}

function openPalette() {
  ui.palette = true
  ui.paletteSel = 0
  $('palette-input').value = ''
  $('palette').hidden = false
  renderPalette()
  $('palette-input').focus()
}

function closePalette() {
  ui.palette = false
  $('palette').hidden = true
  $('palette-input').blur()
}

function highlight(label, hits) {
  if (!hits.length) return esc(label)
  const marks = new Set(hits)
  let out = ''
  let open = false
  for (let i = 0; i < label.length; i++) {
    const h = marks.has(i)
    if (h !== open) { out += h ? '<b>' : '</b>'; open = h }
    out += esc(label[i])
  }
  return open ? out + '</b>' : out
}

function renderPalette() {
  const ranked = rank($('palette-input').value, paletteItems())
  ui.paletteRanked = ranked
  ui.paletteSel = Math.max(0, Math.min(ui.paletteSel, ranked.length - 1))
  $('palette-box').dataset.trail = String(ranked.length)
  const list = $('palette-rows')
  list.innerHTML = ranked.length
    ? ranked.map(({ item, hits }, i) =>
      `<button class="prow${i === ui.paletteSel ? ' on' : ''}" data-p="${i}"><span style="color:${item.color || 'var(--muted)'}">${item.icon || ICONS.chevron}</span>` +
      `<span class="label">${highlight(item.label, hits)}</span><span class="hint">${esc(item.hint)}</span></button>`).join('')
    : '<div class="none">no matches</div>'
  const el = list.children[ui.paletteSel]
  if (el) el.scrollIntoView({ block: 'nearest' })
}

function runPalette(i = ui.paletteSel) {
  const hit = ui.paletteRanked[i]
  if (!hit) return
  closePalette()
  hit.item.run()
}

function paletteKey(e) {
  const mod = e.ctrlKey || e.metaKey
  if (e.key === 'Escape') closePalette()
  else if (e.key === 'ArrowDown' || (mod && e.key === 'j')) { ui.paletteSel++; renderPalette() }
  else if (e.key === 'ArrowUp' || (mod && e.key === 'k')) { ui.paletteSel = Math.max(0, ui.paletteSel - 1); renderPalette() }
  else if (e.key === 'Enter' && !e.repeat) runPalette()
  else return
  e.preventDefault()
}

// -------------------------------------------------------------- remember

const LAST_PROJECT = 'reqall.lastProject'

function openRemember() {
  if (!S.projects.length) { enqueue(['✗ no projects loaded yet · refresh first']); return }
  let last = null
  try { last = Number(localStorage.getItem(LAST_PROJECT)) } catch { /* storage may be unavailable */ }
  const pick = S.filter.projectId ?? (S.projects.some((p) => p.id === last) ? last : S.projects[0].id)
  $('remember-project').innerHTML = S.projects.map((p) => `<option value="${p.id}"${p.id === pick ? ' selected' : ''}>${esc(p.name)}</option>`).join('')
  ui.rememberKind = S.filter.kind || null
  renderKinds()
  setRememberStatus('ctrl+⏎ to save')
  ui.remember = true
  $('remember').hidden = false
  $('remember-title').focus()
}

function closeRemember() {
  ui.remember = false
  $('remember').hidden = true
  document.activeElement && document.activeElement.blur()
}

function renderKinds() {
  const chip = (k, label, color) =>
    `<button type="button" class="kind-chip${ui.rememberKind === k ? ' on' : ''}" data-kind="${k || ''}"${color ? ` style="--c:${color}"` : ''}>${label}</button>`
  $('remember-kinds').innerHTML = chip(null, 'auto') + KINDS.map((k) => chip(k, k, KIND_COLORS[k])).join('')
}

function setRememberStatus(text, bad = false) {
  const s = $('remember-status')
  s.textContent = text
  s.className = bad ? 'bad' : ''
}

async function saveRemember() {
  if (ui.rememberBusy) return
  const title = $('remember-title').value.trim()
  if (!title) { setRememberStatus('give it a title', true); $('remember-title').focus(); return }
  const projectId = Number($('remember-project').value)
  ui.rememberBusy = true
  $('remember-save').disabled = true
  setRememberStatus('saving…')
  const error = await api.remember({ projectId, title, body: $('remember-body').value, kind: ui.rememberKind })
  ui.rememberBusy = false
  $('remember-save').disabled = false
  if (error) { setRememberStatus(error, true); return }
  try { localStorage.setItem(LAST_PROJECT, String(projectId)) } catch { /* storage may be unavailable */ }
  $('remember-title').value = ''
  $('remember-body').value = ''
  closeRemember()
}

// ---------------------------------------------------------------- events

document.addEventListener('keydown', (e) => {
  if (!S) return
  const mod = e.ctrlKey || e.metaKey
  if (ui.palette) return paletteKey(e)
  if (ui.remember) {
    if (e.key === 'Escape') { e.preventDefault(); closeRemember() }
    else if (mod && e.key === 'Enter') { e.preventDefault(); saveRemember() }
    return
  }
  if (S.phase === 'signedOut') return loginKey(e)
  if (S.phase !== 'ready') return
  if (mod && e.key.toLowerCase() === 'k') { e.preventDefault(); openPalette(); return }
  if (mod || e.altKey || e.target.matches('input, textarea, select')) return // menu accelerators pass through

  const key = e.key
  if (key === ':' || key === '/') openPalette()
  else if (key === 'j' || key === 'ArrowDown') move(0, 1)
  else if (key === 'k' || key === 'ArrowUp') move(0, -1)
  else if (key === 'h' || key === 'ArrowLeft') move(-1, 0)
  else if (key === 'l' || key === 'ArrowRight') move(1, 0)
  else if (e.repeat) return
  else if (key === 'Enter') activate()
  else if (key === 'r') api.refresh()
  else if (key === 'o') openDashboard()
  else if (key === 'a') openRemember()
  else if (key === 'x') toggleResolve(selected())
  else if (key === 'Escape') {
    if (ui.peekId != null) { ui.peekId = null; render() }
    else if (hasFilter()) clearFilters()
    else return
  } else return
  e.preventDefault()
})

// Buttons never take focus, so Enter always means the console's Enter.
document.addEventListener('mousedown', (e) => {
  if (e.target.closest('input, textarea, select')) return
  if (e.target.closest('button, .row, .option')) e.preventDefault()
})

document.addEventListener('click', (e) => {
  const t = e.target
  const act = t.closest('[data-action]')
  const row = t.closest('[data-i]')
  const more = t.closest('[data-more]')
  const link = t.closest('[data-goto]')
  const clear = t.closest('[data-clear]')
  const doit = t.closest('[data-do]')
  const opt = t.closest('[data-login]')
  const prow = t.closest('[data-p]')
  const kind = t.closest('[data-kind]')
  if (prow) return runPalette(Number(prow.dataset.p))
  if (kind) { ui.rememberKind = kind.dataset.kind || null; renderKinds(); return }
  if (doit) {
    const d = doit.dataset.do
    if (d === 'sign-out') api.signOut()
    else if (d === 'connect') chooseLogin('key')
    else if (d === 'get-key') api.openKeys(serverValue())
    return
  }
  if (opt) {
    if (t.closest('input')) { ui.login = loginOptions().findIndex((o) => o.id === 'key'); renderLogin(); return }
    return chooseLogin(opt.dataset.login)
  }
  if (act) {
    ui.section = 'actions'
    ui.action = Number(act.dataset.action)
    render()
    return run(ACTIONS[ui.action].id)
  }
  if (more) return api.loadMore()
  if (row) {
    const i = Number(row.dataset.i)
    if (ui.section === 'records' && ui.cursor === i && ui.peekId == null) return openRecord(rows()[i])
    Object.assign(ui, { section: 'records', cursor: i, selectedId: rows()[i].id, peekId: null })
    render()
    wantDetail()
    return
  }
  if (link) return goto(Number(link.dataset.goto))
  if (clear) return setFilter(clear.dataset.clear === 'kind' ? { kind: null } : { projectId: null })
})

$('palette-button').addEventListener('click', openPalette)
$('palette-input').addEventListener('input', () => { ui.paletteSel = 0; renderPalette() })
$('palette').addEventListener('click', (e) => { if (e.target.id === 'palette') closePalette() })
$('remember').addEventListener('click', (e) => { if (e.target.id === 'remember') closeRemember() })
$('remember-form').addEventListener('submit', (e) => { e.preventDefault(); saveRemember() })
$('server').addEventListener('input', () => { const h = $('browser-hint'); if (h) h.textContent = hostLabel(serverValue()) })
$('rows').addEventListener('scroll', (e) => {
  const el = e.target
  if (S && S.hasMore && el.scrollTop + el.clientHeight > el.scrollHeight - 84) api.loadMore()
})

const wide = matchMedia('(min-width: 820px)')
const applyWidth = () => {
  ui.narrow = !wide.matches
  $('app').classList.toggle('narrow', ui.narrow)
  render()
}
wide.addEventListener('change', applyWidth)
setInterval(() => { if (S && S.phase === 'ready') { renderRecords(); renderPreview() } }, 30_000)

api.onState(adopt)
api.onLog(enqueue)
Promise.all([api.getState(), api.getLog()]).then(([state, lines]) => {
  enqueue(lines)
  ui.narrow = !wide.matches
  $('app').classList.toggle('narrow', ui.narrow)
  if (!S) adopt(state)
})
