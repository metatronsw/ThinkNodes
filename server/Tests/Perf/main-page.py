#!/usr/bin/env python3
"""A főoldal betöltési ideje Safariban (WebDriver): a projektkártyák előnézeti képei mennyi idő alatt jelennek meg.

Előfeltétel: futó szerver (pl. `run.sh --http --port:8888 --test`), Safariban engedélyezett távoli automatizálás.
Használat:
    python3 Tests/Perf/main-page.py CÍMKE [--base http://localhost:8888] [--runs 10] [--svg]
      --svg: a régi háttérkép (SVG-előnézet + CSS-elmosás, a főoldal ?previews=svg kapcsolója) az összehasonlításhoz
    python3 Tests/Perf/main-page.py --compare RÉGI ÚJ
Az eredmény: .build/perf-results/main-CÍMKE.json; a --compare a két mérés mediánjait és a különbséget írja ki.

Mért értékek betöltésenként (a navigáció kezdetétől, ms):
  load         – a `load` esemény vége (a nem lusta képek letöltése és a dokumentum feldolgozása)
  images       – minden előnézeti kép letöltve és dekódolva (img.decode())
  frame        – a dekódolás utáni első két képkocka (itt festődik a CSS-elmosás, ha van)
  ready        – images + frame: a kártyák képei a képernyőn
  bytes        – az előnézeti képek átvitt mérete összesen (KB)
"""
import json, os, statistics, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
RESULTS = os.path.join(HERE, "..", "..", ".build", "perf-results")

MEASURE = """
const done = arguments[arguments.length - 1];
(async () => {
  const start = performance.timeOrigin;
  const images = [...document.querySelectorAll('.project-card img.project-background')];
  await Promise.all(images.map(img => img.decode().catch(() => null)));
  const decoded = performance.now();
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  const painted = performance.now();
  const nav = performance.getEntriesByType('navigation')[0];
  const previews = performance.getEntriesByType('resource').filter(e => e.name.includes('/api/preview/'));
  // A Safari a forrásidőzítésben nem adja meg a méretet: az időmérés után a képeket újra lekérjük, és megszámoljuk.
  const sizes = await Promise.all(images.map(img => fetch(img.currentSrc || img.src).then(r => r.arrayBuffer()).then(b => b.byteLength).catch(() => 0)));
  done({load: nav.loadEventEnd, images: decoded, frame: painted - decoded, ready: painted,
        bytes: sizes.reduce((sum, size) => sum + size, 0) / 1024,
        count: images.length, loaded: images.filter(img => img.naturalWidth > 0).length,
        kinds: [...new Set(previews.map(e => (e.name.match(/format=(\\w+)/) || [, 'svg'])[1]))]});
})().catch(error => done({error: String(error)}));
"""

def measure(label, base, runs, query=""):
    from perf import Safari
    safari = Safari()
    results = []
    try:
        # Bemelegítés: a szerver gyorsítótára (előnézetek a lemezen) elkészül, a mérés a meleg állapotot nézi.
        for _ in range(2):
            safari.call("POST", "/url", {"url": base + "/" + (("?" + query) if query else "")})
            time.sleep(3)
        for i in range(runs):
            safari.call("POST", "/url", {"url": base + "/?run=" + str(i) + (("&" + query) if query else "")})
            value = safari.call("POST", "/execute/async", {"script": MEASURE, "args": []})
            results.append(value)
            print(f"{i + 1:2d}. " + "  ".join(f"{k}={v:.1f}" if isinstance(v, (int, float)) else f"{k}={v}" for k, v in value.items()), flush=True)
            time.sleep(.5)
    finally:
        safari.close()
    os.makedirs(RESULTS, exist_ok=True)
    with open(os.path.join(RESULTS, "main-" + label + ".json"), "w") as out:
        json.dump(results, out, indent=1)
    summary(label, results)

def medians(results):
    keys = ["load", "images", "frame", "ready", "bytes"]
    return {key: statistics.median(r[key] for r in results if key in r) for key in keys}

def summary(label, results):
    print(f"\n{label}: medián ({len(results)} betöltés)")
    for key, value in medians(results).items():
        print(f"  {key:7s} {value:9.1f}" + (" KB" if key == "bytes" else " ms"))

def compare(old, new):
    load = lambda name: json.load(open(os.path.join(RESULTS, "main-" + name + ".json")))
    a, b = medians(load(old)), medians(load(new))
    print(f"{'':8s}{old:>12s}{new:>12s}{'különbség':>14s}")
    for key in a:
        unit = " KB" if key == "bytes" else " ms"
        change = (b[key] - a[key]) / a[key] * 100 if a[key] else 0
        print(f"  {key:6s}{a[key]:10.1f}{unit}{b[key]:9.1f}{unit}{change:+11.0f} %")

if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--compare"]:
        compare(args[1], args[2])
    else:
        base = args[args.index("--base") + 1] if "--base" in args else "http://localhost:8888"
        runs = int(args[args.index("--runs") + 1]) if "--runs" in args else 10
        measure(args[0], base, runs, "previews=svg" if "--svg" in args else "")
