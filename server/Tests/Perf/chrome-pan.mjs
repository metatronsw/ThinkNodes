// Összetett pásztázás valódi Chrome-ban, 100%-os nagyításon (Tests/Perf/pan-plan.js), hideg és meleg körben.
// Használat: node Tests/Perf/chrome-pan.mjs [LAP] [körök] [?query]
import {launch, sleep} from "./chrome.mjs";
import {readFileSync} from "node:fs";

const [sheet = "LiquidGlass", rounds = "2", query = ""] = process.argv.slice(2);
const chrome = await launch();
const {send, js} = chrome;
const recorder = readFileSync(new URL("./recorder.js", import.meta.url), "utf8");
const planner = readFileSync(new URL("./pan-plan.js", import.meta.url), "utf8");
const mouse = (type, x, y, buttons = 0, extra = {}) => send("Input.dispatchMouseEvent", {type, x: Math.round(x), y: Math.round(y),
  button: type === "mouseMoved" && !buttons ? "none" : "left", buttons, clickCount: type === "mouseMoved" || type === "mouseWheel" ? 0 : 1, ...extra});

// 100%: valódi görgőeseményekkel (d3-zoom: k · 2^(−deltaY · 0,002)), a vászon közepén.
async function zoomTo100() {
  for (let i = 0; i < 12; i++) {
    const k = await js("document.querySelector('.canvas-area').__zoom.k");
    if (Math.abs(k - 1) < .005) return k;
    const c = await js("(() => { const r = document.querySelector('.canvas-area').getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; })()");
    const total = Math.log2(k) / .002, steps = Math.max(1, Math.ceil(Math.abs(total) / 120));
    for (let s = 0; s < steps; s++) { await mouse("mouseWheel", c[0], c[1], 0, {deltaX: 0, deltaY: total / steps}); await sleep(30); }
    await sleep(700);
  }
  return js("document.querySelector('.canvas-area').__zoom.k");
}
async function pan(dx, dy) {
  const p = await js("__perf.emptyPoint()");
  if (!p) return false;
  // Hirtelen rántás (60% / 4 képkocka), majd lassú finomhúzás (40% / 40 képkocka).
  await mouse("mouseMoved", p.x, p.y); await mouse("mousePressed", p.x, p.y, 1); await sleep(30);
  let x = p.x, y = p.y;
  for (let i = 1; i <= 4; i++) { x = p.x + dx * .6 * i / 4; y = p.y + dy * .6 * i / 4; await mouse("mouseMoved", x, y, 1); await sleep(16); }
  for (let i = 1; i <= 40; i++) { await mouse("mouseMoved", x + dx * .4 * i / 40, y + dy * .4 * i / 40, 1); await sleep(16); }
  await mouse("mouseReleased", p.x + dx, p.y + dy, 0);
  await sleep(120);
  return true;
}
try {
  for (let round = 1; round <= Number(rounds); round++) {
    await chrome.open("http://localhost:8888/edit/" + encodeURIComponent(sheet) + query);
    await js(recorder + "; 1");
    await sleep(4000);
    const k = await zoomTo100();
    await sleep(1500);
    const plan = await js(planner + "; window.__panPlan");
    // TN_TRACE=1: nyomkövetés, JS-profil és hálózati napló a hideg körben (a hosszú feladatok oka).
    const trace = process.env.TN_TRACE && round === 1, events = [], requests = [];
    let traced;
    if (trace) {
      chrome.listeners.push(m => {
        if (m.method === "Tracing.dataCollected") { for (const e of m.params.value) if (e.ph === "X" && e.dur > 2000) events.push(e); }
        else if (m.method === "Tracing.tracingComplete") traced?.();
        else if (m.method === "Network.requestWillBeSent") requests.push([performance.now(), m.params.request.url.replace(/^https?:\/\/[^/]+/, "")]);
      });
      await send("Network.enable");
      await send("Tracing.start", {traceConfig: {includedCategories: ["devtools.timeline", "blink", "v8.execute", "disabled-by-default-devtools.timeline", "disabled-by-default-v8.cpu_profiler", "v8", "disabled-by-default-v8.gc", "cc"]}, transferMode: "ReportEvents"});
    }
    await js("__perf.start(), 1");
    const t0 = Date.now(), p0 = performance.now();
    let done = 0;
    for (const d of plan.drags) if (await pan(d.dx, d.dy)) done++;
    await sleep(600);
    const r = await js("__perf.stop()");
    if (trace) {
      const complete = new Promise(res => { traced = res; }); await send("Tracing.end"); await complete;
      const start = events.reduce((min, e) => e.ts > 0 && e.ts < min ? e.ts : min, Infinity);
      // A főszál hosszú feladatai (> 40 ms) és a bennük futó legnagyobb részfolyamatok.
      const main = events.filter(e => e.ph === "X" && e.name === "RunTask" && e.dur > 40000);
      console.log("   hosszú főszál-feladatok:");
      for (const task of main.sort((a, b) => a.ts - b.ts)) {
        const inner = events.filter(e => e.ph === "X" && e.tid === task.tid && e.ts >= task.ts && e.ts + e.dur <= task.ts + task.dur && e.dur > 2000 && e !== task && !/RunTask|ThreadControllerImpl/.test(e.name))
          .sort((a, b) => b.dur - a.dur).slice(0, 7).map(e => e.name + (e.args?.data?.url ? "(" + e.args.data.url.replace(/^.*\//, "") + ":" + (e.args.data.lineNumber ?? "") + ")" : e.args?.data?.functionName ? "(" + e.args.data.functionName + ")" : "") + " " + (e.dur / 1000).toFixed(0));
        console.log("    @" + ((task.ts - start) / 1000).toFixed(0).padStart(6) + " ms  " + (task.dur / 1000).toFixed(0).padStart(4) + " ms  " + inner.join(" | "));
      }
      console.log("   kérések a kör alatt:", requests.map(([t, u]) => "+" + Math.round(t - p0) + " " + u).join("  "));
    }
    console.log(`— kör ${round}${round === 1 ? " (hideg)" : " (meleg)"} | nagyítás ${(+k * 100).toFixed(0)}% | húzás ${done}/${plan.drags.length} | ${((Date.now() - t0) / 1000).toFixed(1)} mp`);
    console.log(`   fps ${r.fps} | p95 ${r.p95} ms | max ${r.max} ms | >25 ms: ${r.over25} | >50 ms: ${r.over50} | >100 ms: ${r.over100} | jank ${r.jank} ms`);
    console.log("   leglassabb képkockák (idő ms, hossz ms):", (r.slow ?? []).filter(f => f[1] > 34).sort((a, b) => b[1] - a[1]).slice(0, 10).map(f => f.map(Math.round).join("/")).join("  "));
  }
} catch (error) { console.log("HIBA:", error.message); }
finally { await chrome.close(); }
