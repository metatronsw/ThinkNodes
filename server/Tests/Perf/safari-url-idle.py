#!/usr/bin/env python3
"""Tetszőleges címek üresjárati CPU-ja valódi Safariban (WebDriver). Használat: safari-url-idle.py URL [URL ...]"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from perf import Safari
import importlib.util
spec = importlib.util.spec_from_file_location("wd", os.path.join(os.path.dirname(os.path.abspath(__file__)), "safari-idle-wd.py"))
def cpu():
    import subprocess
    out = subprocess.run(["ps", "-axo", "time=,comm="], capture_output=True, text=True).stdout
    by = {}
    for line in out.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) < 2: continue
        t, comm = parts
        name = comm.rsplit("/", 1)[-1]
        if not ("WebKit" in name or name in ("Safari", "WindowServer")): continue
        p = [float(x) for x in t.replace("-", ":").split(":")]
        by[name.replace("com.apple.WebKit.", "")] = by.get(name.replace("com.apple.WebKit.", ""), 0) + p[-1] + 60 * p[-2] + (3600 * p[-3] if len(p) > 2 else 0)
    return by
s = Safari()
try:
    for url in sys.argv[1:]:
        s.call("POST", "/url", {"url": url})
        time.sleep(6)
        a, ta = cpu(), time.time(); time.sleep(8); b, tb = cpu(), time.time()
        per = {k: (b.get(k, 0) - a.get(k, 0)) / (tb - ta) * 100 for k in b}
        print("%-60s WebContent %3.0f%% | WindowServer %3.0f%% | GPU %3.0f%%" % (url[-60:], per.get("WebContent", 0), per.get("WindowServer", 0), per.get("GPU", 0)), flush=True)
finally:
    s.close()
