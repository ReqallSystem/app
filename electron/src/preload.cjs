// The only bridge between the renderer and the main process. The renderer
// gets a small surface; it never sees Node or Electron directly.
const { contextBridge, ipcRenderer } = require('electron')

function on(channel, handler) {
  const listener = (_event, payload) => handler(payload)
  ipcRenderer.on(channel, listener)
  return () => ipcRenderer.removeListener(channel, listener)
}

const invoke = (channel) => (...args) => ipcRenderer.invoke(channel, ...args)

contextBridge.exposeInMainWorld('reqall', {
  getState: invoke('reqall:get-state'),
  getLog: invoke('reqall:get-log'),
  refresh: invoke('reqall:refresh'),
  loadMore: invoke('reqall:load-more'),
  detail: invoke('reqall:detail'),
  setFilter: invoke('reqall:set-filter'),
  remember: invoke('reqall:remember'),
  setStatus: invoke('reqall:set-status'),
  signInWithKey: invoke('reqall:sign-in-key'),
  signInWithBrowser: invoke('reqall:sign-in-oauth'),
  cancelSignIn: invoke('reqall:cancel-sign-in'),
  startDemo: invoke('reqall:demo'),
  signOut: invoke('reqall:sign-out'),
  openDashboard: invoke('reqall:open-dashboard'),
  openKeys: invoke('reqall:open-keys'),
  onState: (handler) => on('reqall:state', handler),
  onLog: (handler) => on('reqall:log', handler)
})
