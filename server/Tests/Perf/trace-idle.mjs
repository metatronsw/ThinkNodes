// Üresjárati nyomkövetés (CDP Tracing, fej nélküli Chromium): mely események futnak képkockánként, és mennyi idő alatt.
// Használat: node Tests/Perf/trace-idle.mjs LAP [másodperc] [css-injektálás]
import {spawn} from "node:child_process";
import {mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

const [sheet = "LiquidGlass", seconds = "3", inject = ""] = process.argv.slice(2);
const profile = mkdtempSync(join(tmpdir(), "tn-trace-"));
const port = 9700 + (process.pid % 90);
const chrome = spawn(process.env.HOME + "/X-Code/RunTime/Chromium/chrome-headless-shell-mac-x64/chrome-headless-shell",
  ["--remote-debugging-port=" + port, "--user-data-dir=" + profile, "about:blank"], {stdio: "ignore"});
const sleep = ms => new Promise(r => setTimeout(r, ms));
let target;
for (let i = 0; i < 40 && !target; i++) { await sleep(250); try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === "page"); } catch {} }
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener("open", r));
let seq = 0; const waiting = new Map(), events = [];
let done;
ws.addEventListener("message", e => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
  else if (m.method === "Tracing.dataCollected") events.push(...m.params.value);
  else if (m.method === "Tracing.tracingComplete") done?.();
});
const send = (method, params = {}) => new Promise(r => { const id = ++seq; waiting.set(id, r); ws.send(JSON.stringify({id, method, params})); });
const js = async code => (await send("Runtime.evaluate", {expression: code, returnByValue: true, awaitPromise: true})).result?.result?.value;
try {
  await send("Emulation.setDeviceMetricsOverride", {width: 1500, height: 950, deviceScaleFactor: 2, mobile: false});
  await send("Page.setBypassCSP", {enabled: true});
  await send("Page.navigate", {url: "http://localhost:8888/edit/" + sheet});
  for (let i = 0; i < 40; i++) { await sleep(500); if (await js("document.querySelectorAll('[data-node]').length")) break; }
  await sleep(3000);
  if (inject) await js(inject.startsWith("js:") ? inject.slice(3) : `(() => { const s = document.createElement('style'); s.textContent = ${JSON.stringify(inject)}; document.head.append(s); return 1; })()`);
  await sleep(1000);
  await send("Tracing.start", {traceConfig: {includedCategories: ["devtools.timeline", "blink", "cc", "viz", "disabled-by-default-devtools.timeline", "benchmark"]}, transferMode: "ReportEvents"});
  await sleep(Number(seconds) * 1000);
  const complete = new Promise(r => { done = r; });
  await send("Tracing.end");
  await complete;
  // Összesítés: eseménynév → darab és összidő (ms), a teljes (X) és a kezdő/záró (B/E) eseményekből.
  const total = new Map(), open = new Map();
  for (const ev of events) {
    const key = ev.name;
    if (ev.ph === "X") { const t = total.get(key) ?? {n: 0, ms: 0}; t.n++; t.ms += (ev.dur ?? 0) / 1000; total.set(key, t); }
    else if (ev.ph === "B") open.set(ev.tid + key, ev.ts);
    else if (ev.ph === "E" && open.has(ev.tid + key)) { const t = total.get(key) ?? {n: 0, ms: 0}; t.n++; t.ms += (ev.ts - open.get(ev.tid + key)) / 1000; total.set(key, t); open.delete(ev.tid + key); }
  }
  const rows = [...total.entries()].sort((a, b) => b[1].ms - a[1].ms).slice(0, 28);
  console.log("lap:", sheet, "|", seconds, "mp | események:", events.length);
  for (const [name, t] of rows) console.log(t.ms.toFixed(0).padStart(7), "ms", String(t.n).padStart(6), "×", name);
  // SMIL / animáció és festés: hány képkocka és mekkora festési terület.
  const paints = events.filter(ev => ev.name === "Paint" && ev.args?.data?.clip);
  const area = paints.reduce((sum, ev) => { const c = ev.args.data.clip; const w = Math.abs(c[2] - c[0]), h = Math.abs(c[5] - c[1]); return sum + w * h; }, 0);
  console.log("Paint események:", paints.length, "| össz. festett terület:", (area / 1e6).toFixed(1), "Mpx");
} catch (error) { console.log("HIBA:", error.message); }
finally { ws.close(); chrome.kill(); await sleep(300); rmSync(profile, {recursive: true, force: true}); }
