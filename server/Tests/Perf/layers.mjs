// Melyik réteg festődik újra üresjáratban? (CDP LayerTree.layerPainted; fej nélküli Chromium)
// Használat: node Tests/Perf/layers.mjs LAP [másodperc] [css-injektálás]
import {spawn} from "node:child_process";
import {mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

const [sheet = "LiquidGlass", seconds = "4", inject = ""] = process.argv.slice(2);
const base = process.env.TN_BASE ?? "http://localhost:8888";
const profile = mkdtempSync(join(tmpdir(), "tn-layers-"));
const port = 9800 + (process.pid % 150);
const chrome = spawn(process.env.HOME + "/X-Code/RunTime/Chromium/chrome-headless-shell-mac-x64/chrome-headless-shell",
  ["--remote-debugging-port=" + port, "--user-data-dir=" + profile, "about:blank"], {stdio: "ignore"});
const sleep = ms => new Promise(r => setTimeout(r, ms));
let target;
for (let i = 0; i < 40 && !target; i++) { await sleep(250); try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === "page"); } catch {} }
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener("open", r));
let seq = 0; const waiting = new Map(), listeners = [];
ws.addEventListener("message", e => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
  else if (m.method) listeners.forEach(fn => fn(m));
});
const send = (method, params = {}) => new Promise(r => { const id = ++seq; waiting.set(id, r); ws.send(JSON.stringify({id, method, params})); });
const js = async code => (await send("Runtime.evaluate", {expression: code, returnByValue: true, awaitPromise: true})).result?.result?.value;
try {
  await send("Emulation.setDeviceMetricsOverride", {width: 1500, height: 950, deviceScaleFactor: 2, mobile: false});
  await send("Page.setBypassCSP", {enabled: true});
  await send("Page.navigate", {url: base + "/edit/" + sheet});
  for (let i = 0; i < 40; i++) { await sleep(500); if (await js("document.querySelectorAll('[data-node]').length")) break; }
  await sleep(3000);
  if (inject) await js(`(() => { const s = document.createElement('style'); s.textContent = ${JSON.stringify(inject)}; document.head.append(s); document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.()); return 1; })()`);
  await sleep(1000);
  await send("DOM.getDocument", {depth: -1});
  let layers = new Map();
  listeners.push(m => { if (m.method === "LayerTree.layerTreeDidChange") for (const l of m.params.layers ?? []) layers.set(l.layerId, l); });
  const painted = new Map();
  listeners.push(m => {
    if (m.method !== "LayerTree.layerPainted") return;
    const entry = painted.get(m.params.layerId) ?? {count: 0, area: 0};
    entry.count++; entry.area += m.params.clip.width * m.params.clip.height; entry.clip = m.params.clip;
    painted.set(m.params.layerId, entry);
  });
  await send("LayerTree.enable");
  await sleep(Number(seconds) * 1000);
  console.log("rétegek:", layers.size, "| újrafestett rétegek:", painted.size, "|", seconds, "mp");
  const rows = [...painted.entries()].sort((a, b) => b[1].area - a[1].area).slice(0, 12);
  for (const [id, entry] of rows) {
    const layer = layers.get(id);
    let name = "?";
    if (layer?.backendNodeId) {
      const node = (await send("DOM.describeNode", {backendNodeId: layer.backendNodeId})).result?.node;
      if (node) {
        const attrs = node.attributes ?? [];
        const cls = attrs[attrs.indexOf("class") + 1];
        name = node.nodeName.toLowerCase() + (attrs.includes("class") ? "." + String(cls).split(" ").join(".") : "");
      }
    }
    console.log(String(entry.count).padStart(5), "×", ("réteg " + Math.round(layer?.width ?? 0) + "×" + Math.round(layer?.height ?? 0)).padEnd(18),
      "festés " + Math.round(entry.clip.width) + "×" + Math.round(entry.clip.height), " ", name);
  }
} catch (error) { console.log("HIBA:", error.message); }
finally { ws.close(); chrome.kill(); await sleep(300); rmSync(profile, {recursive: true, force: true}); }
