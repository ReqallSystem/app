// Renders the console offscreen on the demo account and saves screenshots,
// the way designs/screenshots were made for the concepts. Needs no display
// to be awake and never touches real credentials.
//
//   npm run screenshots              # → screenshots/*.png
//   electron scripts/screenshots.mjs --out=/some/dir

import { app, BrowserWindow, ipcMain } from 'electron'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { Session } from '../src/main/session.js'
import { DemoRepository } from '../src/main/demo.js'
import { connect } from '../src/main/bridge.js'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const outArg = process.argv.find((a) => a.startsWith('--out='))
const out = outArg ? path.resolve(outArg.slice(6)) : path.join(root, 'screenshots')
app.setPath('userData', fs.mkdtempSync(path.join(os.tmpdir(), 'reqall-shots-')))

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// Keys go to <body>, as real ones do when nothing has focus.
const key = (k, mods = {}) => `document.body.dispatchEvent(new KeyboardEvent('keydown', { key: ${JSON.stringify(k)}, bubbles: true, ...${JSON.stringify(mods)} }))`
const type = (id, text) => `(() => { const el = document.getElementById(${JSON.stringify(id)}); el.value = ${JSON.stringify(text)}; el.dispatchEvent(new Event('input', { bubbles: true })) })()`

const SHOTS = [
  { name: 'sign-in', width: 1440, height: 900, phase: 'signedOut', steps: [] },
  { name: 'console-desktop', width: 1440, height: 900, phase: 'ready', steps: [key('j'), key('j')] },
  { name: 'console-palette', width: 1440, height: 900, phase: 'ready', steps: [key(':'), type('palette-input', 'kind')] },
  { name: 'console-remember', width: 1440, height: 900, phase: 'ready', steps: [key('a'), type('remember-title', 'Electron console ships with the Console design')] },
  { name: 'console-narrow', width: 640, height: 900, phase: 'ready', steps: [key('j')] }
]

// Each shot destroys its window; that must not end the run.
app.on('window-all-closed', () => {})

app.whenReady().then(async () => {
  let win = null
  const session = new Session({ demo: (o) => new DemoRepository({ ...o, latencyMs: 40 }) })
  connect({ ipcMain, session, send: (c, p) => { if (win && !win.isDestroyed()) win.webContents.send(c, p) }, openExternal: () => {} })
  await session.start()
  fs.mkdirSync(out, { recursive: true })

  for (const shot of SHOTS) {
    if (shot.phase === 'ready' && session.phase !== 'ready') await session.startDemo()
    win = new BrowserWindow({
      width: shot.width,
      height: shot.height,
      show: false,
      backgroundColor: '#140e0e',
      webPreferences: { offscreen: true, preload: path.join(root, 'src', 'preload.cjs'), contextIsolation: true, sandbox: true }
    })
    await win.loadFile(path.join(root, 'src', 'renderer', 'index.html'))
    await win.webContents.executeJavaScript('document.fonts.ready.then(() => true)')
    await sleep(400)
    for (const step of shot.steps) {
      await win.webContents.executeJavaScript(step)
      await sleep(250)
    }
    await sleep(3500) // let the log finish typing
    const image = await win.webContents.capturePage()
    const file = path.join(out, `${shot.name}.png`)
    fs.writeFileSync(file, image.toPNG())
    console.log('wrote', path.relative(process.cwd(), file))
    win.destroy()
    win = null
  }
  app.quit()
})
