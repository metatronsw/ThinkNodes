#!/usr/bin/env python3
"""A perf.py kimenetének (soronként: név JSON) vagy mentett eredményfájljainak tömör összefoglalója.
Használat: python3 Tests/Perf/perf.py ... | python3 Tests/Perf/summary.py
           python3 Tests/Perf/summary.py .build/perf-results/A-p300.json .build/perf-results/B-p300.json   (összehasonlítás)"""
import json, sys

def line(name, d):
    if not isinstance(d, dict) or "frames" not in d: return "%-18s %s" % (name, json.dumps(d, ensure_ascii=False)[:120])
    lat = d.get("latency") or {}
    c = d.get("counters") or {}
    counts = " ".join("%s=%s" % (k, c[k]) for k in ("node", "edge", "edgeHandles", "root", "inspector", "view", "table") if k in c)
    spent = d.get("spent") or {}
    if spent: counts += "  || ms: " + " ".join("%s=%s" % (k.replace("dom:", ""), v) for k, v in sorted(spent.items(), key=lambda kv: -kv[1]) if v >= 2)
    return "%-18s fps %5s  p50 %5s  p95 %5s  max %6s  >25ms %4s  >50ms %4s  akadás %5s ms%s  | %s" % (
        name, d["fps"], d["p50"], d["p95"], d["max"], d["over25"], d["over50"], d["jank"],
        ("  késés p50 %s max %s" % (lat.get("p50"), lat.get("max")) if lat else "") +
        ("  szkript p50 %s max %s" % (d["js"].get("p50"), d["js"].get("max")) if d.get("js") else "") +
        ("  kezelő p50 %s p95 %s" % (d["handlers"].get("p50"), d["handlers"].get("p95")) if d.get("handlers") else ""), counts)

def timeline(d):
    """A hosszú képkockák (kezdet → hossz) az események között, időrendben."""
    rows = [(t, "ESEMÉNY " + name) for t, name in d.get("events", [])] + [(t, "LASSÚ KÉPKOCKA %d ms" % gap) for t, gap in d.get("slow", [])]
    return "\n".join("      %6d ms  %s" % row for row in sorted(rows))

if "--timeline" in sys.argv:
    sys.argv.remove("--timeline")
    for row in sys.stdin:
        name, _, rest = row.partition(" ")
        try: d = json.loads(rest); print(line(name, d)); print(timeline(d))
        except Exception: print(row.rstrip()[:300])
elif len(sys.argv) > 1:
    runs = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:]]
    names = [k for k in runs[0] if isinstance(runs[0][k], dict)]
    for name in names:
        print(name)
        for run in runs:
            if name in run: print("   %-10s %s" % (run["label"], line("", run[name]).strip()))
else:
    for row in sys.stdin:
        name, _, rest = row.partition(" ")
        try: print(line(name, json.loads(rest)))
        except Exception: print(row.rstrip()[:300])
