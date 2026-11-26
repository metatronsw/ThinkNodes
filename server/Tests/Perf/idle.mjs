// Üresjárati terhelés mérése fej nélküli Chromiumban (CDP): a megnyitott szerkesztő mozdulat nélkül, változatonként.
// Használat: node Tests/Perf/idle.mjs LAP [másodperc] [változat,...]
//   Mér: a Chromium összes folyamatának CPU-ideje (ps), a lap képkockái (rAF), és a Performance.getMetrics különbségei
//   (szkript, stílus, elrendezés, feladatidő). Változatok: a lapon injektált CSS / JS, ami egy-egy forrást kikapcsol.
import {spawn, execFileSync} from "node:child_process";
import {mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

const [sheet = "LiquidGlass", seconds = "8", only = ""] = process.argv.slice(2);
const base = process.env.TN_BASE ?? "http://localhost:8888";
const profile = mkdtempSync(join(tmpdir(), "tn-idle-"));
const port = 9400 + (process.pid % 400);
const chrome = spawn(process.env.HOME + "/X-Code/RunTime/Chromium/chrome-headless-shell-mac-x64/chrome-headless-shell",
  ["--remote-debugging-port=" + port, "--user-data-dir=" + profile, "--window-size=1500,950", "about:blank"], {stdio: "ignore"});
const sleep = ms => new Promise(r => setTimeout(r, ms));

// A Chromium folyamatainak összesített CPU-ideje másodpercben (a profilmappa szerint azonosítva).
function cpuByType() {
  const out = execFileSync("ps", ["-axo", "time=,command="], {encoding: "utf8", maxBuffer: 1 << 24});
  const by = {};
  for (const line of out.split("\n")) {
    if (!line.includes(profile) && !line.includes("chrome-headless-shell")) continue;
    const [time] = line.trim().split(/\s+/);
    const parts = time.split(":").map(Number);
    const type = (line.match(/--type=([a-z-]+)/) ?? [, "böngésző"])[1] + (line.match(/--utility-sub-type=([\w.]+)/) ? ":" + line.match(/--utility-sub-type=([\w.]+)/)[1].split(".").pop() : "");
    by[type] = (by[type] ?? 0) + (parts.length === 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : parts[0] * 60 + parts[1]);
  }
  return by;
}
function cpuSeconds() {
  const out = execFileSync("ps", ["-axo", "time=,command="], {encoding: "utf8", maxBuffer: 1 << 24});
  let total = 0;
  for (const line of out.split("\n")) {
    if (!line.includes(profile) && !line.includes("chrome-headless-shell")) continue;
    const [time] = line.trim().split(/\s+/);
    const parts = time.split(":").map(Number);
    total += parts.length === 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : parts[0] * 60 + parts[1];
  }
  return total;
}

let target;
for (let i = 0; i < 40 && !target; i++) { await sleep(250); try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === "page"); } catch {} }
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener("open", r));
let seq = 0; const waiting = new Map();
ws.addEventListener("message", e => { const m = JSON.parse(e.data); if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); } });
const send = (method, params = {}) => new Promise(r => { const id = ++seq; waiting.set(id, r); ws.send(JSON.stringify({id, method, params})); });
const js = async code => { const m = await send("Runtime.evaluate", {expression: code, returnByValue: true, awaitPromise: true}); return m.result?.result?.value; };
const metrics = async () => Object.fromEntries((await send("Performance.getMetrics")).result.metrics.map(m => [m.name, m.value]));

const variants = {
  alap: "",
  aurora: `.canvas-aurora{display:none!important}`,
  backdrop: `*{backdrop-filter:none!important;-webkit-backdrop-filter:none!important}`,
  cssanim: `*{animation-play-state:paused!important}`,
  smil: "js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())",
  mindanim: `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())",
  rejtett: "js:document.querySelector('.editor-workspace').style.visibility='hidden'",
  "mind+aurora": `*{animation-play-state:paused!important}.canvas-aurora{display:none!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())",
  "mind+backdrop": `*{animation-play-state:paused!important;backdrop-filter:none!important;-webkit-backdrop-filter:none!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())",
  "mind+willchange": `*{animation-play-state:paused!important;will-change:auto!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())",
  "mind+vaszon": `*{animation-play-state:paused!important}.editor-canvas{visibility:hidden!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())",
  "csakaurora": `*:not(.canvas-aurora > i){animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())",
  "m-reteg": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelector('.canvas-layer').remove()",
  "m-racs": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelector('.canvas-grid-draw')?.remove()",
  "m-aurora": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelector('.canvas-aurora').remove()",
  "m-vezerlo": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelector('.canvas-controls').remove()",
  "m-emberek": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelector('.canvas-people').remove()",
  "m-panel": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelector('.inspector-column')?.remove()",
  "m-fejlec": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelector('header, .topbar, nav')?.remove()",
  "m-defs": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelectorAll('svg defs filter').forEach(f => f.remove())",
  "m-szurok": `*{animation-play-state:paused!important}` + "|js:document.querySelectorAll('svg').forEach(s => s.pauseAnimations?.())|js:document.querySelectorAll('[filter]').forEach(e => e.removeAttribute('filter'))",
  "a-torol": "js:document.querySelector('.canvas-aurora').remove()",
  "a-rejt": "js:document.querySelector('.canvas-aurora').style.display='none'",
  "a-animnone": `.canvas-aurora > i{animation:none!important}`,
  "a-nowill": `.canvas-aurora > i{will-change:auto!important}`,
  "a-darab": "js:document.querySelectorAll('.canvas-aurora').length + ' db'",
  "na": "js:document.querySelector('.canvas-aurora').remove()",
  "na-fx": `.fx-shadow,.fx-sheen{display:none!important}` + "|js:document.querySelector('.canvas-aurora').remove()",
  "na-racs": "js:document.querySelector('.canvas-aurora').remove();document.querySelector('.canvas-grid-draw')?.remove()",
  "na-nowill": `.canvas-layer,.canvas-grid-draw{will-change:auto!important}` + "|js:document.querySelector('.canvas-aurora').remove()",
  "na-csakvonal": "js:document.querySelector('.canvas-aurora').remove();document.querySelectorAll('.node-motion').forEach(g => g.querySelectorAll('animate,animateTransform').forEach(a => a.remove()))",
  "na-csakdoboz": "js:document.querySelector('.canvas-aurora').remove();document.querySelectorAll('[data-edge] animate, [data-edge] animateMotion').forEach(a => a.remove())",
  "csend": "js:document.querySelector('.canvas-aurora').remove();document.querySelectorAll('.editor-canvas animate,.editor-canvas animateMotion,.editor-canvas animateTransform').forEach(a => a.remove());",
  "potty-vaszon": "js:document.querySelector('.canvas-aurora').remove();document.querySelectorAll('.editor-canvas animate,.editor-canvas animateMotion,.editor-canvas animateTransform').forEach(a => a.remove());const g = document.createElementNS('http://www.w3.org/2000/svg','g'); g.innerHTML = '<circle r=\"5\" fill=\"#e33\"><animateMotion dur=\"3s\" repeatCount=\"indefinite\" path=\"M0,0 L300,0\"/></circle>'; document.querySelector('.editor-canvas').append(g);",
  "potty-kulon": "js:document.querySelector('.canvas-aurora').remove();document.querySelectorAll('.editor-canvas animate,.editor-canvas animateMotion,.editor-canvas animateTransform').forEach(a => a.remove());const d = document.createElement('div'); d.style.cssText = 'position:absolute;left:300px;top:300px;width:320px;height:20px;will-change:transform;pointer-events:none'; d.innerHTML = '<svg width=\"320\" height=\"20\"><g transform=\"translate(10 10)\"><circle r=\"5\" fill=\"#e33\"><animateMotion dur=\"3s\" repeatCount=\"indefinite\" path=\"M0,0 L300,0\"/></circle></g></svg>'; document.querySelector('.canvas-area').append(d);",
  dobozok: `[data-node]{display:none!important}`,
  vonalak: `[data-edge]{display:none!important}`,
  fo: `foreignObject{display:none!important}`,
  vaszon: `.editor-canvas{visibility:hidden!important}`,
  racs: `.editor-workspace canvas{display:none!important}`,
};
try {
  await send("Emulation.setDeviceMetricsOverride", {width: 1500, height: 950, deviceScaleFactor: 2, mobile: false});
  await send("Performance.enable", {timeDomain: "threadTicks"});
  await send("Page.setBypassCSP", {enabled: true});
  await send("Page.navigate", {url: base + (sheet.startsWith("/") ? sheet : "/edit/" + sheet)});
  for (let i = 0; i < 40; i++) { await sleep(500); if (await js("document.readyState === 'complete' && (!location.pathname.startsWith('/edit/') || document.querySelectorAll('[data-node]').length)")) break; }
  await sleep(4000);
  const names = only ? only.split(",") : Object.keys(variants);
  console.log("lap:", sheet, "| dobozok:", await js("document.readyState === 'complete' && (!location.pathname.startsWith('/edit/') || document.querySelectorAll('[data-node]').length)"), "| mérés:", seconds, "mp / változat");
  console.log("változat     CPU%   fps   szkript%  stílus%  elrend.%  feladat%");
  for (const name of names) {
    await send("Page.reload");
    for (let i = 0; i < 40; i++) { await sleep(500); if (await js("document.readyState === 'complete' && (!location.pathname.startsWith('/edit/') || document.querySelectorAll('[data-node]').length)")) break; }
    await sleep(3000);
    for (const part of variants[name].split("|").filter(Boolean)) {
      if (part.startsWith("js:")) await js(part.slice(3));
      else await js(`(() => { const s = document.createElement('style'); s.textContent = ${JSON.stringify(part)}; document.head.append(s); return 1; })()`);
    }
    // Képkockaszámláló csak külön kérésre (TN_FPS=1): a rAF-ciklus maga is folyamatos képkockákat kér, ami torzít.
    if (process.env.TN_FPS) await js(`window.__frames = 0; if (!window.__ticking) { window.__ticking = 1; (function tick(){ window.__frames++; requestAnimationFrame(tick); })(); } 1`);
    await sleep(1500);
    const b0 = cpuByType(), m0 = await metrics(), c0 = cpuSeconds(), f0 = await js("window.__frames"), t0 = Date.now();
    await sleep(Number(seconds) * 1000);
    const m1 = await metrics(), c1 = cpuSeconds(), f1 = await js("window.__frames ?? 0"), dt = (Date.now() - t0) / 1000;
    const pct = key => ((m1[key] - m0[key]) / dt * 100).toFixed(1).padStart(8);
    console.log(name.padEnd(10), ((c1 - c0) / dt * 100).toFixed(0).padStart(5), ((f1 - f0) / dt).toFixed(0).padStart(5),
      pct("ScriptDuration"), pct("RecalcStyleDuration"), pct("LayoutDuration"), pct("TaskDuration"));
    if (process.env.TN_PROC) { const b1 = cpuByType(); console.log("   ", Object.keys(b1).map(k => k + " " + ((b1[k] - (b0[k] ?? 0)) / dt * 100).toFixed(0) + "%").join(" | ")); }
  }
} catch (error) { console.log("HIBA:", error.message); }
finally { ws.close(); chrome.kill(); await sleep(300); rmSync(profile, {recursive: true, force: true}); }
