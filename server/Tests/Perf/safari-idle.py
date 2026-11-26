#!/usr/bin/env python3
"""Üresjárati CPU-mérés valódi Safariban, WebDriver nélkül (teszt ág).

Megnyitja a szerkesztőt ?bench= paraméterrel Safariban (open -a Safari; Public/bench-idle.js), a lap `start`-tól `step` másodpercenként
vált változatot; a szkript ugyanezzel az időrenddel méri a Safari / WebKit folyamatok CPU-idejét (ps), változatonként az
első `skip` másodperc (betöltés) nélkül.
Használat: python3 Tests/Perf/safari-idle.py [LAP] [--step 15] [--skip 6] [--list alap,aurora_torol,...]
"""
import argparse, subprocess, time, urllib.parse

ap = argparse.ArgumentParser()
ap.add_argument("sheet", nargs="?", default="LiquidGlass")
ap.add_argument("--step", type=float, default=15)
ap.add_argument("--skip", type=float, default=6)
ap.add_argument("--list", default="alap,aurora_torol,aurora_all,csak_smil,smil_szunet,mind_szunet,mind_aurora,backdrop,backdrop_aurora,egy_potty,racs_torol,vaszon_rejt,rejtett")
ap.add_argument("--base", default="http://localhost:8888")
args = ap.parse_args()
names = args.list.split(",")

def cpu():
    """{folyamatnév: CPU-másodperc} a Safari és a WebKit folyamataira."""
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

start = int((time.time() + 8) * 1000)
url = args.base + "/edit/" + urllib.parse.quote(args.sheet) + "?" + urllib.parse.urlencode({"bench": names[0], "start": start, "step": args.step, "list": ",".join(names)})
subprocess.run(["open", "-a", "Safari", url])
print("Safari:", url, flush=True)
print("%-14s %7s   %s" % ("változat", "össz%", "folyamatonként"), flush=True)
for k, name in enumerate(names):
    begin = start / 1000 + k * args.step + args.skip
    end = start / 1000 + (k + 1) * args.step - 0.3
    while time.time() < begin: time.sleep(0.05)
    a, ta = cpu(), time.time()
    while time.time() < end: time.sleep(0.05)
    b, tb = cpu(), time.time()
    dt = tb - ta
    per = {key: (b.get(key, 0) - a.get(key, 0)) / dt * 100 for key in b}
    total = sum(v for key, v in per.items() if key != "WindowServer")
    detail = " | ".join("%s %.0f%%" % (key, v) for key, v in sorted(per.items(), key=lambda kv: -kv[1]) if v >= 1)
    front = subprocess.run(["lsappinfo", "info", "-only", "name", subprocess.run(["lsappinfo", "front"], capture_output=True, text=True).stdout.strip()], capture_output=True, text=True).stdout
    print("%-16s %6.0f%%   %s%s" % (name, total, detail, "" if "Safari" in front else "   [NEM a Safari van elöl!]"), flush=True)
