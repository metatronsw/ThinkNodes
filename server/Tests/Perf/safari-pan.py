#!/usr/bin/env python3
"""Összetett pásztázás valódi Safariban (WebDriver, valódi egéresemények), 100%-os nagyításon (Tests/Perf/pan-plan.js).
Kör 1: friss betöltés (a Safari folyamata már meleg lehet); kör 2: újratöltés után.
Használat: python3 Tests/Perf/safari-pan.py [LAP] [körök] [query]
"""
import math, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from perf import Safari, move, DOWN, UP, pause

sheet = sys.argv[1] if len(sys.argv) > 1 else "LiquidGlass"
rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 2
query = sys.argv[3] if len(sys.argv) > 3 else ""
recorder = open(os.path.join(HERE, "recorder.js"), encoding="utf-8").read()
planner = open(os.path.join(HERE, "pan-plan.js"), encoding="utf-8").read()

def zoom_to_100(s):
    # d3-zoom: k · 2^(−deltaY · 0,002); szintetikus görgőesemény a vászon közepén (a d3 JS-figyelője kezeli).
    for _ in range(12):
        k = s.js("return document.querySelector('.canvas-area').__zoom.k")
        if abs(k - 1) < .005: return k
        s.js("""const a = document.querySelector('.canvas-area'), r = a.getBoundingClientRect(), total = Math.log2(arguments[0]) / .002;
          const steps = Math.max(1, Math.ceil(Math.abs(total) / 120));
          for (let i = 0; i < steps; i++) a.querySelector('svg').dispatchEvent(new WheelEvent('wheel', {deltaY: total / steps, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, bubbles: true, cancelable: true}));
          return 1""", k)
        time.sleep(.8)
    return s.js("return document.querySelector('.canvas-area').__zoom.k")

def pan(s, dx, dy):
    p = s.js("return __perf.emptyPoint()")
    if not p: return False
    x0, y0 = p["x"], p["y"]
    acts = [move(x0, y0, 0), DOWN, pause(30)]
    acts += [move(x0 + dx * .6 * i / 4, y0 + dy * .6 * i / 4, 16) for i in range(1, 5)]
    xs, ys = x0 + dx * .6, y0 + dy * .6
    acts += [move(xs + dx * .4 * i / 40, ys + dy * .4 * i / 40, 16) for i in range(1, 41)]
    acts += [UP, pause(120)]
    s.pointer(acts)
    return True

s = Safari()
try:
    for rnd in range(1, rounds + 1):
        s.call("POST", "/url", {"url": "http://localhost:8888/edit/" + sheet + query})
        for _ in range(60):
            time.sleep(.5)
            if s.js("return document.querySelectorAll('[data-node]').length") > 0: break
        s.js(recorder + "; return 1")
        time.sleep(4)
        k = zoom_to_100(s)
        time.sleep(1.5)
        plan = s.js(planner + "; return window.__panPlan")
        s.js("__perf.start(); return 1")
        t0 = time.time(); done = 0
        for d in plan["drags"]:
            if pan(s, d["dx"], d["dy"]): done += 1
        time.sleep(.6)
        r = s.js("return __perf.stop()")
        slow = sorted([f for f in (r.get("slow") or []) if f[1] > 34], key=lambda f: -f[1])[:10]
        print("— Safari kör %d | nagyítás %.0f%% | húzás %d/%d | %.1f mp" % (rnd, k * 100, done, len(plan["drags"]), time.time() - t0), flush=True)
        print("   fps %s | p95 %s ms | max %s ms | >25 ms: %s | >50 ms: %s | >100 ms: %s | jank %s ms" % (r["fps"], r["p95"], r["max"], r["over25"], r["over50"], r["over100"], r["jank"]), flush=True)
        print("   leglassabb képkockák (idő/hossz ms):", "  ".join("%d/%d" % (a, b) for a, b in slow), flush=True)
finally:
    s.close()
