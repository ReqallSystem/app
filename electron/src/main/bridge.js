// Wires a Session to the renderer: session changes and log lines go out over
// IPC, and the preload bridge's calls come in. Shared by the app (index.js)
// and the screenshot script, so both drive the renderer the same way.

import { STATUSES } from '../shared/model.js'
import { normalizeServer } from './credentials.js'

// Every handler coerces its arguments: the renderer is not trusted to send
// well-formed values.
const int = (v) => (v != null && v !== '' && Number.isInteger(Number(v)) ? Number(v) : null)
const str = (v, max = 20000) => String(v ?? '').slice(0, max)

/**
 * @param {object} o
 * @param {import('electron').IpcMain} o.ipcMain
 * @param {import('./session.js').Session} o.session
 * @param {(channel: string, payload: unknown) => void} o.send to the window, if any
 * @param {(url: string) => unknown} o.openExternal
 */
export function connect({ ipcMain, session, send, openExternal }) {
  // The log so far, so a renderer that loads (or reloads) late still has it.
  const backlog = []
  let pending = false

  // Coalesce bursts of changes (a refresh fires several) into one send.
  session.on('change', () => {
    if (pending) return
    pending = true
    setImmediate(() => {
      pending = false
      send('reqall:state', session.snapshot())
    })
  })
  session.on('log', (lines) => {
    backlog.push(...lines)
    backlog.splice(0, Math.max(0, backlog.length - 60))
    send('reqall:log', lines)
  })

  /** The dashboard, scrolled to its records when a record is given. False in the demo. */
  function openDashboard(id) {
    if (session.demo) return false
    openExternal(`${session.server}/dashboard${id == null ? '' : '#records'}`)
    return true
  }

  const handle = (channel, fn) => {
    ipcMain.removeHandler(channel)
    ipcMain.handle(channel, fn)
  }
  handle('reqall:get-state', () => session.snapshot())
  handle('reqall:get-log', () => backlog.slice())
  handle('reqall:refresh', () => { session.refresh(); return true })
  handle('reqall:load-more', () => { session.loadMore(); return true })
  handle('reqall:detail', (_e, id) => { if (int(id) != null) session.detail(int(id)); return true })
  handle('reqall:set-filter', (_e, f) => {
    const o = f && typeof f === 'object' ? f : {}
    session.setFilter({
      kind: o.kind === undefined ? undefined : (o.kind ? str(o.kind, 20) : null),
      projectId: o.projectId === undefined ? undefined : int(o.projectId)
    })
    return true
  })
  handle('reqall:remember', (_e, r) => {
    const o = r && typeof r === 'object' ? r : {}
    return session.remember({ projectId: int(o.projectId), title: str(o.title, 500), body: str(o.body, 32000), kind: o.kind ? str(o.kind, 20) : undefined })
  })
  handle('reqall:set-status', (_e, id, status) => {
    const s = str(status, 20)
    if (int(id) == null || !STATUSES.includes(s)) return 'Bad request'
    return session.setStatus(int(id), s)
  })
  handle('reqall:sign-in-key', (_e, key, server) => session.signInWithApiKey(str(key, 4096), normalizeServer(str(server, 2048))))
  handle('reqall:sign-in-oauth', (_e, server) => session.signInWithOAuth(normalizeServer(str(server, 2048))))
  handle('reqall:sign-in-cli', () => session.continueWithCli())
  handle('reqall:cancel-sign-in', () => { session.cancelSignIn(); return true })
  handle('reqall:demo', () => session.startDemo())
  handle('reqall:sign-out', () => session.signOut())
  handle('reqall:open-dashboard', (_e, id) => openDashboard(int(id)))
  handle('reqall:open-keys', (_e, server) => { openExternal(normalizeServer(str(server, 2048)) + '/dashboard#keys'); return true })

  return { openDashboard }
}
