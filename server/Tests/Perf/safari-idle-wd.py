#!/usr/bin/env python3
"""Üresjárati CPU-mérés valódi Safariban WebDriverrel (teszt ág; Public/bench-idle.js változatai).

Változatonként betölti a szerkesztőt (?bench=VÁLTOZAT&hold=1), vár, majd `--seconds` ideig méri a Safari / WebKit
folyamatok CPU-idejét (ps). Használat: python3 Tests/Perf/safari-idle-wd.py [LAP] [--seconds 10] [--list a,b,...]
"""
import argparse, os, subprocess, sys, time, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from perf import Safari

ap = argparse.ArgumentParser()
ap.add_argument("sheet", nargs="?", default="LiquidGlass")
ap.add_argument("--seconds", type=float, default=10)
ap.add_argument("--settle", type=float, default=4)
ap.add_argument("--list", default="alap,aurora_torol,aurora_all,csak_smil,smil_szunet,mind_szunet,mind_aurora,backdrop,egy_potty,racs_torol,vaszon_rejt,rejtett")
ap.add_argument("--base", default="http://localhost:8888")
args = ap.parse_args()

def cpu():
    out = subprocess.run(["ps", "-axo", "time=,comm="], capture_output=True, text=True).stdout
    by = {}
    for line in out.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) < 2: continue
        t, comm = parts
        name = comm.rsplit("/", 1)[-1]
        if not ("WebKit" in name or name in ("Safari", "WindowServer")): continue
        p = [float(x) for x in t.replace("-", ":").split(":")]
        sec = p[-1] + 60 * p[-2] + (3600 * p[-3] if len(p) > 2 else 0)
        key = name.replace("com.apple.WebKit.", "")
        by[key] = by.get(key, 0) + sec
    return by

s = Safari()
try:
    print("%-16s %7s   %s" % ("változat", "össz%", "folyamatonként (WindowServer nélkül összegezve)"), flush=True)
    for name in args.list.split(","):
        url = args.base + "/edit/" + urllib.parse.quote(args.sheet) + "?" + urllib.parse.urlencode({"bench": name, "list": name, "hold": 1})
        s.call("POST", "/url", {"url": url})
        for _ in range(60):
            time.sleep(0.5)
            if s.js("return document.querySelectorAll('[data-node]').length") > 0: break
        time.sleep(args.settle)
        a, ta = cpu(), time.time()
        time.sleep(args.seconds)
        b, tb = cpu(), time.time()
        per = {k: (b.get(k, 0) - a.get(k, 0)) / (tb - ta) * 100 for k in b}
        total = sum(v for k, v in per.items() if k != "WindowServer")
        detail = " | ".join("%s %.0f%%" % (k, v) for k, v in sorted(per.items(), key=lambda kv: -kv[1]) if v >= 1)
        kept = s.js("return window.__kept ?? null")
        print("%-16s %6.0f%%   %s%s" % (name, total, detail, "" if kept is None else "   [%d animáció]" % kept), flush=True)
finally:
    s.close()
