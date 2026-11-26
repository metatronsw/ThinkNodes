#!/usr/bin/env python3
"""Kapcsolat nélküli viselkedés valódi Safariban (WebDriver): a lap nyitva, a szerver leáll (kívülről), és mérjük a DOM-
változásokat és a képkockákat a kapcsolat nélküli idő alatt; közben képernyőképek (villogás). Használat:
  python3 Tests/Perf/safari-offline.py edit|view [LAP] [mp]     (a futás közben állítsd le a szervert)
"""
import base64, json, os, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from perf import Safari

kind = sys.argv[1] if len(sys.argv) > 1 else "view"
sheet = sys.argv[2] if len(sys.argv) > 2 else "LiquidGlass"
seconds = float(sys.argv[3]) if len(sys.argv) > 3 else 8
shots = os.environ.get("TN_SHOTS")
base = "http://localhost:8888"
PROBE = """
window.__mut = {}; window.__seq = [];
const key = n => { const e = n.nodeType === 1 ? n : n.parentElement; if (!e) return "?";
  const c = (e.getAttribute("class") || "").toString().split(/\\s+/).slice(0, 2).join("."); return e.tagName.toLowerCase() + (c ? "." + c : "") + (e.closest("[data-node]") ? " @doboz" : ""); };
new MutationObserver(list => { for (const m of list) { const k = m.type + " " + key(m.target) + (m.attributeName ? "[" + m.attributeName + "]" : "");
  window.__mut[k] = (window.__mut[k] || 0) + 1; if (window.__seq.length < 30) window.__seq.push(Math.round(performance.now()) + " " + k); } })
  .observe(document.documentElement, {subtree: true, childList: true, attributes: true, characterData: true});
window.__frames = []; (function tick(t) { window.__frames.push(t); if (window.__frames.length < 4000) requestAnimationFrame(tick); })(performance.now());
return 1"""

def up():
    try: urllib.request.urlopen(base + "/health", timeout=.8); return True
    except Exception: return False

s = Safari()
try:
    url = base + ("/edit/" if kind == "edit" else "/") + sheet
    s.call("POST", "/url", {"url": url})
    for _ in range(60):
        time.sleep(.5)
        if s.js("return document.querySelectorAll('[data-node]').length") > 0: break
    time.sleep(2)
    print("Lap nyitva (%s). Most állítsd le a szervert…" % kind, flush=True)
    while up(): time.sleep(.5)
    print("A szerver nem érhető el; mérés %.0f mp." % seconds, flush=True)
    s.js(PROBE)
    t0 = time.time(); n = 0
    while time.time() - t0 < seconds:
        if shots and n < 12:
            open(os.path.join(shots, "%s-%02d.png" % (kind, n)), "wb").write(base64.b64decode(s.call("GET", "/screenshot"))); n += 1
        time.sleep(.25)
    mut = s.js("return window.__mut"); seq = s.js("return window.__seq")
    frames = s.js("return window.__frames")
    gaps = [b - a for a, b in zip(frames, frames[1:])]
    print("DOM-változás összesen %d; képkockák %d (leghosszabb %.0f ms)" % (sum(mut.values()), len(frames), max(gaps or [0])), flush=True)
    for k, v in sorted(mut.items(), key=lambda kv: -kv[1])[:12]: print("  %5d  %s" % (v, k))
    for line in seq[:14]: print("     " + line)
finally:
    s.close()
