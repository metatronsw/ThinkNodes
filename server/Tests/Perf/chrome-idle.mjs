// Üresjárati CPU valódi Chrome-ban, változatonként (Public/bench-idle.js; ?bench=…&hold=1), vagy tetszőleges címekre.
// Használat: node Tests/Perf/chrome-idle.mjs LAP [másodperc] [változat,...]   |   node … --url URL [URL ...]
import {launch, measure, sleep} from "./chrome.mjs";

const args = process.argv.slice(2);
const base = process.env.TN_BASE ?? "http://localhost:8888";
const chrome = await launch();
const row = (name, r, note = "") => console.log(name.padEnd(18), r.total.toFixed(0).padStart(4) + "%  ",
  Object.entries(r.per).filter(([, v]) => v >= 1).sort((a, b) => b[1] - a[1]).map(([k, v]) => k + " " + v.toFixed(0) + "%").join(" | "), note);
try {
  if (args[0] === "--url") {
    for (const url of args.slice(1)) {
      await chrome.open(url, "document.readyState === 'complete'");
      await sleep(4000);
      row(url.slice(-18), await measure(chrome, Number(process.env.TN_SECONDS ?? 8)));
    }
  } else {
    const [sheet = "LiquidGlass", seconds = "8", list = "alap,smil_szunet,mind_szunet,mind_aurora,aurora_torol,css_csere,racs_torol,vaszon_none"] = args;
    console.log("Chrome", "| lap:", sheet, "|", seconds, "mp / változat");
    for (const name of list.split(",")) {
      await chrome.open(base + "/edit/" + encodeURIComponent(sheet) + "?bench=" + name + "&list=" + name + "&hold=1");
      await sleep(4000);
      const kept = await chrome.js("window.__kept ?? null");
      row(name, await measure(chrome, Number(seconds)), kept == null ? "" : "[" + kept + " animáció]");
    }
  }
} catch (error) { console.log("HIBA:", error.message); }
finally { await chrome.close(); }
