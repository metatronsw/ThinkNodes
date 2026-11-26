// Kapcsolat nélküli viselkedés (valódi Chrome): a szerkesztő és a megtekintő nyitva, a szerver leáll (kívülről), és
// mérjük, mi változik a lapokon a kapcsolat nélküli `seconds` alatt: DOM-változások elemenként, képek újratöltése,
// kérések. Használat: node Tests/Perf/chrome-offline.mjs [LAP] [mp]   (a futás közben állítsd le a szervert; a szkript
// maga figyeli, mikor nem érhető el, és csak attól kezdve mér).
import {launch, sleep} from "./chrome.mjs";

const [sheet = "LiquidGlass", seconds = "12"] = process.argv.slice(2);
const base = process.env.TN_BASE ?? "http://localhost:8888";
const probe = `(() => {
  window.__mut = {}; window.__imgLoads = 0;
  const key = n => { const e = n.nodeType === 1 ? n : n.parentElement; if (!e) return "?";
    const c = (e.getAttribute("class") || "").toString().split(/\\s+/).slice(0, 2).join("."); return e.tagName.toLowerCase() + (c ? "." + c : "") + (e.closest?.("[data-node]") ? " @doboz" : ""); };
  new MutationObserver(list => { for (const m of list) { const k = m.type + " " + key(m.target) + (m.attributeName ? "[" + m.attributeName + "]" : "");
    window.__mut[k] = (window.__mut[k] ?? 0) + 1;
    if ((window.__seq ??= []).length < 40) window.__seq.push(Math.round(performance.now()) + " " + k + (m.attributeName ? " " + JSON.stringify(m.oldValue) + "→" + JSON.stringify(m.target.getAttribute(m.attributeName)) : " +" + m.addedNodes.length + "/-" + m.removedNodes.length + " " + JSON.stringify((m.target.textContent || "").slice(0, 40)))); } }).observe(document.documentElement, {subtree: true, childList: true, attributes: true, characterData: true, attributeOldValue: true});
  document.addEventListener("load", e => { if (e.target.tagName === "IMG" || e.target.tagName === "image") window.__imgLoads++; }, true);
  return 1; })()`;
const report = async (chrome, label) => {
  const mut = await chrome.js("JSON.stringify(window.__mut ?? null)"), loads = await chrome.js("window.__imgLoads");
  if (mut === "null") { console.log("== " + label + ": A LAP ÚJRATÖLTŐDÖTT (a figyelő elveszett)"); return; }
  const rows = Object.entries(JSON.parse(mut)).sort((a, b) => b[1] - a[1]).slice(0, 14);
  console.log("== " + label + ": DOM-változás összesen " + rows.reduce((s, r) => s + r[1], 0) + ", képbetöltés " + loads);
  for (const [k, n] of rows) console.log("   " + String(n).padStart(5) + "  " + k);
  if (process.env.TN_SEQ) for (const line of JSON.parse(await chrome.js("JSON.stringify(window.__seq ?? [])")).slice(0, 16)) console.log("     " + line);
};
const editor = await launch(), viewer = await launch();
const requests = {editor: {}, viewer: {}};
for (const [chrome, name] of [[editor, "editor"], [viewer, "viewer"]]) {
  chrome.listeners.push(m => { if (m.method === "Network.requestWillBeSent") { const u = m.params.request.url.replace(/^https?:\/\/[^/]+/, "").replace(/\?.*/, "").replace(/[0-9A-F-]{36}/g, "…"); requests[name][u] = (requests[name][u] ?? 0) + 1; } });
}
try {
  await editor.open(base + "/edit/" + encodeURIComponent(sheet));
  await viewer.open(base + "/" + encodeURIComponent(sheet), "document.readyState === 'complete' && document.querySelectorAll('[data-node]').length");
  await sleep(2000);
  console.log("Lapok nyitva. Most állítsd le a szervert…");
  for (let i = 0; i < 600; i++) { try { await fetch(base + "/health", {signal: AbortSignal.timeout(800)}); await sleep(500); } catch { break; } }
  console.log("A szerver nem érhető el; mérés " + seconds + " mp.");
  await editor.send("Network.enable"); await viewer.send("Network.enable");
  await editor.js(probe); await viewer.js(probe);
  await sleep(Number(seconds) * 1000);
  await report(editor, "SZERKESZTŐ"); console.log("   kérések:", JSON.stringify(requests.editor));
  await report(viewer, "MEGTEKINTŐ"); console.log("   kérések:", JSON.stringify(requests.viewer));
  // Visszatérés: a szerver újraindul (kívülről); a következő `seconds` mp-ben mi változik a lapokon.
  if (process.env.TN_RETURN) {
    console.log("Most indítsd újra a szervert…");
    for (let i = 0; i < 1200; i++) { try { await fetch(base + "/health", {signal: AbortSignal.timeout(800)}); break; } catch { await sleep(500); } }
    console.log("A szerver újra elérhető; mérés " + seconds + " mp.");
    for (const r of [requests.editor, requests.viewer]) for (const k of Object.keys(r)) delete r[k];
    await editor.js(probe); await viewer.js(probe);
    await sleep(Number(seconds) * 1000);
    await report(editor, "SZERKESZTŐ (visszatérés után)"); console.log("   kérések:", JSON.stringify(requests.editor));
    await report(viewer, "MEGTEKINTŐ (visszatérés után)"); console.log("   kérések:", JSON.stringify(requests.viewer));
  }
  console.log("   szerkesztő állapota:", await editor.js(`JSON.stringify({problema: document.querySelector('.error, .problem, [role=alert]')?.textContent?.slice(0, 80) ?? null, dobozok: document.querySelectorAll('[data-node]').length})`));
} catch (error) { console.log("HIBA:", error.message); }
finally { await editor.close(); await viewer.close(); }
