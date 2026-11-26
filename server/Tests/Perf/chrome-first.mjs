// Mi fut a legelső kijelöléskor (friss Chrome)? Hálózati kérések, JS-profil (saját idő függvényenként) és a hosszú
// feladatok a kattintás körül. Használat: node Tests/Perf/chrome-first.mjs [LAP] [doboz-sorszám] [?query]
import {launch, sleep} from "./chrome.mjs";
import {readFileSync} from "node:fs";

const [sheet = "LiquidGlass", index = "0", query = ""] = process.argv.slice(2);
const chrome = await launch();
const {send, js, listeners} = chrome;
const mouse = (type, x, y, buttons = 0) => send("Input.dispatchMouseEvent", {type, x: Math.round(x), y: Math.round(y), button: type === "mouseMoved" && !buttons ? "none" : "left", buttons, clickCount: type === "mouseMoved" ? 0 : 1});
try {
  await chrome.open("http://localhost:8888/edit/" + encodeURIComponent(sheet) + query);
  await js(readFileSync(new URL("./recorder.js", import.meta.url), "utf8") + "; 1");
  await sleep(5000);
  const box = (await js("__perf.nodes('box', 12)"))[Number(index)];
  console.log("doboz:", box.id ?? "", Math.round(box.x), Math.round(box.y));
  const requests = [];
  listeners.push(m => { if (m.method === "Network.requestWillBeSent") requests.push([Date.now(), m.params.request.method + " " + m.params.request.url.replace(/^https?:\/\/[^/]+/, "")]); });
  await send("Network.enable");
  await send("Profiler.enable");
  await send("Profiler.setSamplingInterval", {interval: 200});
  const events = [];
  let done;
  listeners.push(m => { if (m.method === "Tracing.dataCollected") events.push(...m.params.value); else if (m.method === "Tracing.tracingComplete") done?.(); });
  await send("Tracing.start", {traceConfig: {includedCategories: ["devtools.timeline", "blink", "v8.execute", "disabled-by-default-devtools.timeline"]}, transferMode: "ReportEvents"});
  await send("Profiler.start");
  const t0 = Date.now();
  await js("__perf.start(), window.__lat = __perf.latencies(['pointerdown', 'pointerup']), 1");
  await mouse("mouseMoved", box.x, box.y); await mouse("mousePressed", box.x, box.y, 1); await sleep(40); await mouse("mouseReleased", box.x, box.y, 0);
  await sleep(1500);
  const frames = await js("__perf.stop()"), lat = await js("window.__lat.stop()");
  const profile = (await send("Profiler.stop")).result.profile;
  const complete = new Promise(r => { done = r; }); await send("Tracing.end"); await complete;
  console.log("késés:", lat.join(", "), "ms | leghosszabb képkocka:", frames.max, "ms");
  console.log("kérések a kattintás után:"); for (const [t, r] of requests) console.log("  +" + (t - t0) + " ms", r);
  // Saját idő függvényenként (mintavételezett profil).
  const self = new Map(), byId = new Map(profile.nodes.map(n => [n.id, n]));
  const dt = profile.timeDeltas, counts = new Map();
  profile.samples.forEach((id, i) => counts.set(id, (counts.get(id) ?? 0) + (dt[i] ?? 0) / 1000));
  for (const [id, ms] of counts) {
    const f = byId.get(id).callFrame;
    const key = (f.functionName || "(névtelen)") + " " + f.url.replace(/^.*\//, "") + ":" + (f.lineNumber + 1);
    self.set(key, (self.get(key) ?? 0) + ms);
  }
  console.log("JS saját idő (top):");
  for (const [k, ms] of [...self.entries()].filter(([k]) => !/^\((idle|program|garbage collector)\)/.test(k)).sort((a, b) => b[1] - a[1]).slice(0, 18)) console.log("  " + ms.toFixed(1).padStart(7) + " ms  " + k);
  const gc = [...self.entries()].filter(([k]) => /garbage/.test(k)).reduce((s, [, v]) => s + v, 0);
  console.log("  szemétgyűjtés:", gc.toFixed(1), "ms");
  // Hosszú feladatok és a renderelés fázisai (> 30 ms).
  const long = events.filter(e => e.ph === "X" && e.dur > 30000 && /RunTask|UpdateLayoutTree|Layout|Paint|PrePaint|Layerize|Commit|EventDispatch|FunctionCall|v8.run|ParseHTML|EvaluateScript|v8.compile|ScheduleStyleRecalculation|UpdateLifecycle|RecalcStyle/.test(e.name));
  console.log("hosszú szakaszok (> 30 ms):");
  for (const e of long.sort((a, b) => a.ts - b.ts).slice(0, 25)) console.log("  " + (e.dur / 1000).toFixed(0).padStart(5) + " ms  " + e.name + (e.args?.data?.url ? " " + e.args.data.url.replace(/^.*\//, "") : "") + (e.args?.elementCount ? " elemek: " + e.args.elementCount : ""));
} catch (error) { console.log("HIBA:", error.message); }
finally { await chrome.close(); }
