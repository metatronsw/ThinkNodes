// Valódi Google Chrome vezérlése CDP-n (teszt ág): külön, ideiglenes profillal indított példány (a felhasználó Chrome-ját
// és profilját nem érinti), valódi GPU-val; a takart ablak sem fojtódik vissza. CPU-mérés a példány folyamatfáján.
import {spawn, execFileSync} from "node:child_process";
import {mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

export const CHROME = process.env.TN_CHROME ?? "/Applications/Downloaded/Google Chrome.app/Contents/MacOS/Google Chrome";
export const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function launch({width = 1600, height = 1000} = {}) {
  const profile = mkdtempSync(join(tmpdir(), "tn-chrome-"));
  // Folyamatonként több példány is indulhat: mindegyik saját vezérlőportot kap.
  const port = 9300 + ((process.pid + (launch.count = (launch.count ?? 0) + 1) * 37) % 600);
  const proc = spawn(CHROME, ["--remote-debugging-port=" + port, "--user-data-dir=" + profile, "--no-first-run", "--no-default-browser-check",
    "--disable-backgrounding-occluded-windows", "--disable-renderer-backgrounding", "--disable-background-timer-throttling",
    "--window-position=40,40", "--window-size=" + width + "," + height, "about:blank"], {stdio: "ignore"});
  let target;
  for (let i = 0; i < 80 && !target; i++) { await sleep(250); try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === "page"); } catch {} }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener("open", r));
  let seq = 0; const waiting = new Map(), listeners = [];
  ws.addEventListener("message", e => {
    const m = JSON.parse(e.data);
    if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
    else if (m.method) listeners.forEach(fn => fn(m));
  });
  const send = (method, params = {}) => new Promise(r => { const id = ++seq; waiting.set(id, r); ws.send(JSON.stringify({id, method, params})); });
  const js = async code => {
    const m = await send("Runtime.evaluate", {expression: code, returnByValue: true, awaitPromise: true});
    if (m.result?.exceptionDetails) throw new Error(m.result.exceptionDetails.exception?.description ?? JSON.stringify(m.result.exceptionDetails));
    return m.result?.result?.value;
  };
  await send("Page.enable");
  await send("Page.setBypassCSP", {enabled: true});
  // A példány folyamatai: a gyökér és minden leszármazottja; típus a parancssor --type= kapcsolójából.
  const cpu = () => {
    const rows = execFileSync("ps", ["-axo", "pid=,ppid=,time=,command="], {encoding: "utf8", maxBuffer: 1 << 25}).split("\n")
      .map(line => line.trim().match(/^(\d+)\s+(\d+)\s+(\S+)\s+(.*)$/)).filter(Boolean)
      .map(([, pid, ppid, time, command]) => ({pid: +pid, ppid: +ppid, time, command}));
    const tree = new Set([proc.pid]);
    for (let changed = true; changed;) { changed = false; for (const r of rows) if (!tree.has(r.pid) && tree.has(r.ppid)) { tree.add(r.pid); changed = true; } }
    const by = {};
    for (const r of rows) {
      if (!tree.has(r.pid)) continue;
      const parts = r.time.replace("-", ":").split(":").map(Number);
      const seconds = parts.at(-1) + 60 * parts.at(-2) + (parts.length > 2 ? 3600 * parts.at(-3) : 0);
      const type = (r.command.match(/--type=([a-z-]+)/) ?? [, "böngésző"])[1] + (/--utility-sub-type=[\w.]*network/i.test(r.command) ? ":net" : "");
      by[type] = (by[type] ?? 0) + seconds;
    }
    return by;
  };
  const open = async (url, ready = "document.querySelectorAll('[data-node]').length") => {
    await send("Page.navigate", {url});
    for (let i = 0; i < 60; i++) { await sleep(500); try { if (await js(ready)) break; } catch {} }
  };
  const close = async () => { try { ws.close(); } catch {} proc.kill(); await sleep(500); rmSync(profile, {recursive: true, force: true}); };
  return {send, js, cpu, open, close, listeners};
}

// CPU-százalék folyamattípusonként `seconds` alatt.
export async function measure(chrome, seconds) {
  const a = chrome.cpu(), t0 = Date.now();
  await sleep(seconds * 1000);
  const b = chrome.cpu(), dt = (Date.now() - t0) / 1000;
  const per = Object.fromEntries(Object.keys(b).map(k => [k, (b[k] - (a[k] ?? 0)) / dt * 100]));
  return {total: Object.values(per).reduce((s, v) => s + v, 0), per};
}
