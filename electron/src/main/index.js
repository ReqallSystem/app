// The Reqall console: one window drawing the Console design on live data.
// This file owns the app lifecycle, the window and the menu; bridge.js wires
// the session to the renderer, session.js owns the data and auth, and the
// renderer only draws.

import { app, BrowserWindow, Menu, nativeImage, safeStorage, shell, ipcMain } from 'electron'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { Session } from './session.js'
import { FileCredentialStore, findCliCredentials } from './credentials.js'
import { connect } from './bridge.js'
import { runOAuth } from './oauth.js'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '..', '..')
const markPath = path.join(root, 'assets', 'reqall-mark.png')

let win = null
let session = null
let openDashboard = () => false

// Chromium only looks for a keyring on GNOME and KDE; on other Linux desktops
// (Hyprland, sway, …) it silently falls back to a plain-text store. Ask for
// the Secret Service, which gnome-keyring, KWallet and KeePassXC all provide.
if (process.platform === 'linux' && !app.commandLine.hasSwitch('password-store')) {
  app.commandLine.appendSwitch('password-store', 'gnome-libsecret')
}

if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (!win) return
    if (win.isMinimized()) win.restore()
    win.focus()
  })
  app.whenReady().then(main)
}

function openExternal(url) {
  if (typeof url === 'string' && /^https?:\/\//i.test(url)) return shell.openExternal(url)
  return Promise.resolve()
}

/**
 * safeStorage encrypts with the OS keychain (Keychain, DPAPI, libsecret /
 * kwallet). On Linux without a keyring it falls back to a hard-coded key,
 * which is no protection, so that counts as unavailable.
 */
const keychain = {
  available() {
    if (!safeStorage.isEncryptionAvailable()) return false
    if (process.platform === 'linux' && safeStorage.getSelectedStorageBackend() === 'basic_text') return false
    return true
  },
  encrypt: (text) => safeStorage.encryptString(text),
  decrypt: (buf) => safeStorage.decryptString(buf)
}

async function main() {
  session = new Session({
    store: new FileCredentialStore(path.join(app.getPath('userData'), 'credentials.bin'), keychain),
    findCli: () => findCliCredentials(),
    runOAuth: (api, server, opts) => runOAuth(api, server, { ...opts, openExternal })
  })
  ;({ openDashboard } = connect({ ipcMain, session, send, openExternal }))

  Menu.setApplicationMenu(buildMenu())
  createWindow()
  session.start()
}

function send(channel, payload) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload)
}

function createWindow() {
  win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 420,
    minHeight: 520,
    show: false,
    title: 'Reqall',
    icon: nativeImage.createFromPath(markPath),
    autoHideMenuBar: true,
    backgroundColor: '#140e0e',
    webPreferences: {
      preload: path.join(here, '..', 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false
    }
  })
  win.loadFile(path.join(root, 'src', 'renderer', 'index.html'))
  win.once('ready-to-show', () => win.show())
  win.on('closed', () => { win = null })
  win.webContents.setWindowOpenHandler(({ url }) => { openExternal(url); return { action: 'deny' } })
  win.webContents.on('will-navigate', (e, url) => {
    if (!url.startsWith('file://')) { e.preventDefault(); openExternal(url) }
  })
}

function buildMenu() {
  const mac = process.platform === 'darwin'
  return Menu.buildFromTemplate([
    ...(mac ? [{ role: 'appMenu' }] : []),
    {
      label: 'File',
      submenu: [
        { label: 'Refresh', accelerator: 'CmdOrCtrl+R', click: () => session.refresh() },
        { label: 'Open dashboard', accelerator: 'CmdOrCtrl+O', click: () => openDashboard() },
        { type: 'separator' },
        { label: 'Sign out', click: () => session.signOut() },
        { type: 'separator' },
        mac ? { role: 'close' } : { role: 'quit' }
      ]
    },
    { role: 'editMenu' },
    {
      label: 'View',
      submenu: [
        { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        { role: 'toggleDevTools' }
      ]
    },
    { role: 'windowMenu' }
  ])
}

app.on('window-all-closed', () => app.quit())
