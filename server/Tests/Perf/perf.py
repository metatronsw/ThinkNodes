#!/usr/bin/env python3
"""A szerkesztő teljesítménymérése Safariban (WebDriver, valódi egéresemények + lapon belüli képkocka-rögzítő).

Előfeltétel: release szerver tesztmódban a mérő-adatmappával (Tests/Perf/make-data.mjs), Safariban engedélyezett
távoli automatizálás. Használat:
    python3 Tests/Perf/perf.py CÍMKE [--base http://localhost:8888] [--only pan,zoom,...] [--sheet p300]
Az eredmény: .build/perf-results/CÍMKE.json és egy összefoglaló a kimeneten.
"""
import json, os, subprocess, sys, time, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 4460 + os.getpid() % 400   # futásonként más kapu: a leállított illesztő kapuja egy ideig foglalt marad
ALT = ""

class Safari:
    def __init__(self):
        # A nemrég használt kapura az illesztő egy ideig nem tud ráállni ("Operation not permitted"): több kaput próbálunk.
        global PORT
        for attempt in range(12):
            PORT = 4500 + (os.getpid() * 7 + attempt * 13 + int(time.time())) % 900
            self.driver = subprocess.Popen(["/usr/bin/safaridriver", "-p", str(PORT)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            ready = False
            for _ in range(12):
                time.sleep(.5)
                if self.driver.poll() is not None: break
                try: urllib.request.urlopen("http://localhost:%d/status" % PORT, timeout=2); ready = True; break
                except urllib.error.HTTPError: ready = True; break
                except Exception: pass
            if ready: break
            self.driver.terminate()
        else: raise RuntimeError("A safaridriver nem indult el.")
        value = self.raw("POST", "http://localhost:%d/session" % PORT, {"capabilities": {"alwaysMatch": {"browserName": "safari"}}})
        self.base = "http://localhost:%d/session/%s" % (PORT, value["sessionId"])
        self.call("POST", "/window/rect", {"x": 40, "y": 40, "width": 1600, "height": 1000})
        self.call("POST", "/timeouts", {"script": 120000})

    def raw(self, method, url, body=None):
        request = urllib.request.Request(url, method=method, data=None if body is None else json.dumps(body).encode(), headers={"Content-Type": "application/json"})
        try:
            return json.load(urllib.request.urlopen(request, timeout=180))["value"]
        except urllib.error.HTTPError as error:
            raise RuntimeError(error.read().decode()[:600])

    def call(self, method, path, body=None): return self.raw(method, self.base + path, body)
    def js(self, code, *args): return self.call("POST", "/execute/sync", {"script": code, "args": list(args)})
    def wait(self, code, *args):
        """Promise-t adó kifejezés eredménye (aszinkron végrehajtás)."""
        return self.call("POST", "/execute/async", {"script": "const done = arguments[arguments.length - 1]; Promise.resolve((() => {" + code + "})()).then(done, e => done({error: String(e)}))", "args": list(args)})

    def open(self, url, options=None):
        # A teljesítmény-kapcsolók (editor.js perfOptions) a localStorage-ből jönnek: előbb egy könnyű oldal, beállítás, aztán a lap.
        self.call("POST", "/url", {"url": url.split("/edit/")[0] + "/login"})
        self.js("if (arguments[0]) localStorage.setItem('tnPerf', arguments[0]); else localStorage.removeItem('tnPerf'); return 1", options)
        self.call("POST", "/url", {"url": url})
        for _ in range(60):
            time.sleep(.5)
            if self.js("return document.querySelectorAll('[data-node]').length") > 0: break
        time.sleep(2.5)
        self.js(open(os.path.join(HERE, "recorder.js"), encoding="utf-8").read() + "; return 1")

    def pointer(self, actions, keys=None):
        sources = [{"type": "pointer", "id": "mouse", "parameters": {"pointerType": "mouse"}, "actions": actions}]
        if keys: sources.insert(0, {"type": "key", "id": "keys", "actions": keys})
        self.call("POST", "/actions", {"actions": sources})

    def close(self):
        try: self.call("DELETE", "")
        finally: self.driver.terminate()

def move(x, y, duration=16): return {"type": "pointerMove", "duration": duration, "x": max(2, min(1560, round(x))), "y": max(2, min(880, round(y)))}
DOWN, UP = {"type": "pointerDown", "button": 0}, {"type": "pointerUp", "button": 0}
def pause(ms): return {"type": "pause", "duration": ms}

def path(points, steps, duration=16):
    """Egyenes szakaszok a pontok között, szakaszonként `steps` lépésben."""
    out = []
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        out += [move(x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps, duration) for i in range(1, steps + 1)]
    return out

def recorded(safari, run, settle=.5):
    safari.js("__perf.start(); return 1")
    run()
    time.sleep(settle)
    return safari.js("return __perf.stop()")

def drag(safari, points, steps, keys_down=None, keys_up=None, hold=120):
    actions = [move(*points[0], 0), DOWN, pause(hold)] + path(points, steps) + [pause(60), UP]
    if keys_down:
        pad = [{"type": "pause"}] * (len(actions) - 1)
        safari.pointer([pause(40)] + actions, [{"type": "keyDown", "value": keys_down}] + pad + [{"type": "keyUp", "value": keys_up or keys_down}])
    else: safari.pointer(actions)

# --- forgatókönyvek ---------------------------------------------------------------------------------------------

def idle(s): return recorded(s, lambda: time.sleep(1.5), 0)

def pan_slow(s):
    p = s.js("return __perf.emptyPoint()")
    return recorded(s, lambda: drag(s, [(p["x"], p["y"]), (p["x"] + 500, p["y"] + 250), (p["x"], p["y"])], 50))

def pan_fast(s):
    """Nagy, hirtelen pásztázás: néhány képkocka alatt egy képernyőnyit, oda-vissza."""
    p = s.js("return __perf.emptyPoint()")
    far = (p["x"] + 900, p["y"] + 500)
    return recorded(s, lambda: drag(s, [(p["x"], p["y"]), far, (p["x"], p["y"]), far, (p["x"], p["y"])], 7))

def zoom(s, delta, steps, cycles):
    """Görgős nagyítás a vászon közepén: ki, majd vissza; a végén a nyugalmi (újrarajzoló) képkockákkal együtt."""
    return s.wait("""
      const {x, y} = __perf.emptyPoint();   // üres vászonpont: görgethető doboz fölött a görgő a dobozé
      const [delta, steps, cycles] = arguments;
      return __perf.drive(cycles * (2 * steps + 24), i => { const k = i % (2 * steps + 24); if (k < steps) __perf.wheel(x, y, delta); else if (k >= steps + 12 && k < 2 * steps + 12) __perf.wheel(x, y, -delta); });
    """, delta, steps, cycles)

def zoom_slow(s): return zoom(s, 30, 40, 1)
def zoom_fast(s): return zoom(s, 400, 6, 3)

def select_single(s):
    """Dobozok kijelölése egyenként: késleltetés a lenyomástól a következő kirajzolt képkockáig."""
    nodes = s.js("return __perf.nodes('box', 12)")
    s.js("window.__lat = __perf.latencies(['pointerdown', 'pointerup']); return 1")
    def run():
        for n in nodes:
            s.pointer([move(n["x"], n["y"], 0), DOWN, pause(40), UP, pause(220)])
    frames = recorded(s, run)
    lat = s.js("return window.__lat.stop()")
    frames["latency"] = s.js("return __perf.stats(arguments[0])", lat)
    frames["js"] = s.js("return __perf.stats(window.__lat.js())")
    return frames

def rectangle(s):
    """Alt+húzás: téglalapos kijelölés a látható terület nagy részén."""
    p = s.js("return __perf.emptyPoint()")
    a = s.js("const a = document.querySelector('.canvas-area').getBoundingClientRect(); return [a.left, a.top, a.right, a.bottom]")
    end = (min(a[2] - 440, p["x"] + 900), min(a[3] - 80, p["y"] + 600))
    frames = recorded(s, lambda: drag(s, [(p["x"], p["y"]), end, (p["x"] + 200, p["y"] + 150), end], 30, ALT))
    frames["selected"] = s.js("return __perf.selectedCount()")
    return frames

def batch_move(s):
    """A téglalappal kijelölt csoport húzása (a rectangle után fut)."""
    n = s.js("const g = document.querySelector('[data-node].own-selected .node-surface'); if (!g) return null; const b = g.getBoundingClientRect(); return {x: b.left + b.width / 2, y: b.top + b.height / 2}")
    if not n: return {"skipped": "nincs kijelölt csoport"}
    return recorded(s, lambda: drag(s, [(n["x"], n["y"]), (n["x"] + 200, n["y"] + 120), (n["x"], n["y"])], 30))

def deselect(s):
    p = s.js("return __perf.emptyPoint()")
    if p: s.pointer([move(p["x"], p["y"], 0), DOWN, pause(40), UP, pause(200)])

def node_move(s, kind="box"):
    nodes = s.js("return __perf.nodes(arguments[0], 3)", kind)
    if not nodes: return {"skipped": "nincs látható " + kind}
    n = nodes[-1]
    return recorded(s, lambda: drag(s, [(n["x"], n["y"]), (n["x"] + 220, n["y"] + 140), (n["x"], n["y"])], 30))

def container_move(s):
    c = s.js("""for (const g of document.querySelectorAll('[data-node^="c0"]')) { if (g.dataset.node.includes('m')) continue; const b = g.querySelector('.node-surface').getBoundingClientRect();
      const x = b.left + b.width / 2, y = b.top + 14; const a = document.querySelector('.canvas-area').getBoundingClientRect();
      if (x > a.left + 50 && x < a.right - 500 && y > a.top + 80 && y < a.bottom - 250 && document.elementFromPoint(x, y)?.closest('[data-node]') === g) return {x, y}; } return null""")
    if not c: return {"skipped": "nincs látható konténer"}
    return recorded(s, lambda: drag(s, [(c["x"], c["y"]), (c["x"] + 200, c["y"] + 120), (c["x"], c["y"])], 30))

ZOOM_TO = """
  const [selector, width] = arguments;
  const target = () => document.querySelector(selector).getBoundingClientRect();
  const a = document.querySelector('.canvas-area').getBoundingClientRect(), cx = a.left + (a.width - 420) / 2, cy = a.top + a.height / 2;
  const settle = ms => new Promise(r => setTimeout(r, ms));
  return (async () => {
    for (let i = 0; i < 80; i++) {
      const b = target();
      if (Math.abs(b.width - width) < width * .08) break;
      __perf.wheel(b.left + b.width / 2, b.top + b.height / 2, b.width < width ? -60 : 60);
      await settle(40);
    }
    await settle(400);
    // középre húzás a vászon üres pontjáról indított egérmozdulatokkal nem megbízható; a d3-zoom görgő helyett közvetlen eltolás:
    const b = target(), dx = cx - (b.left + b.width / 2), dy = cy - (b.top + b.height / 2);
    return {dx, dy, width: b.width};
  })();
"""

def focus_on(s, selector, width):
    """A megadott elem a látható terület közepére és adott képernyőszélességre (görgős nagyítás + húzás üres pontról)."""
    info = s.wait(ZOOM_TO, selector, width)
    for _ in range(4):
        b = s.js("const b = document.querySelector(arguments[0]).getBoundingClientRect(), a = document.querySelector('.canvas-area').getBoundingClientRect(); return {dx: a.left + (a.width - 420) / 2 - (b.left + b.width / 2), dy: a.top + a.height / 2 - (b.top + b.height / 2)}", selector)
        if abs(b["dx"]) < 30 and abs(b["dy"]) < 30: break
        p = s.js("return __perf.emptyPoint()")
        if not p: break
        dx, dy = max(-600, min(600, b["dx"])), max(-400, min(400, b["dy"]))
        drag(s, [(p["x"], p["y"]), (p["x"] + dx, p["y"] + dy)], 6)
        time.sleep(.4)
    return info

SCROLL = """
  const [selector, step, steps] = arguments;
  const el = document.querySelector(selector);
  if (!el) return {skipped: 'nincs ' + selector};
  el.scrollTop = 0;
  const top = el.scrollHeight - el.clientHeight;
  return __perf.drive(steps + 20, i => { if (i < steps) el.scrollTop = Math.min(top, el.scrollTop + step); }).then(r => ({...r, scrolled: Math.round(el.scrollTop), range: top}));
"""

def table_scroll_view(s, selector='[data-node^="f"][data-type="table"] .node-note'):
    return s.wait(SCROLL, selector, 40, 90)

def table_wheel(s, selector):
    """Görgő a táblázat fölött (a szerkesztő saját kezelőin át), képkockánként egy esemény."""
    return s.wait("""
      const el = document.querySelector(arguments[0]); if (!el) return {skipped: 'nincs elem'};
      const b = el.getBoundingClientRect(), x = b.left + b.width / 2, y = b.top + b.height / 2;
      return __perf.drive(80, i => { if (i < 60) { __perf.wheel(x, y, 60); el.scrollTop += 60; } });
    """, selector)

def table_edit_enter(s, selector='[data-node^="f"][data-type="table"]'):
    s.js("document.querySelector(arguments[0]).dispatchEvent(new MouseEvent('dblclick', {bubbles: true})); return 1", selector)
    time.sleep(1.2)
    return s.js("return !!document.querySelector('.tn-table-scroll')")

def table_scroll_edit(s): return s.wait(SCROLL, ".tn-table-scroll", 60, 120)

def table_cells(s):
    """Cellák kijelölése kattintással szerkesztési módban: késleltetés a következő képkockáig."""
    cells = s.js("""const out = []; for (const td of document.querySelectorAll('.tn-table.tn-editing tbody td')) { const b = td.getBoundingClientRect(); const x = b.left + b.width / 2, y = b.top + b.height / 2;
      if (b.width > 8 && document.elementFromPoint(x, y) === td) out.push({x, y}); if (out.length >= 60) break; } return out.filter((_, i) => i % 5 === 0)""")
    if not cells: return {"skipped": "nincs kattintható cella"}
    s.js("window.__lat = __perf.latencies(['pointerdown']); return 1")
    def run():
        for c in cells: s.pointer([move(c["x"], c["y"], 0), DOWN, pause(30), UP, pause(150)])
    frames = recorded(s, run)
    frames["latency"] = s.js("return __perf.stats(window.__lat.stop())")
    frames["js"] = s.js("return __perf.stats(window.__lat.js())")
    return frames

def table_range(s):
    """Tartomány kijelölése húzással szerkesztési módban."""
    c = s.js("""const tds = [...document.querySelectorAll('.tn-table.tn-editing tbody td')].filter(td => { const b = td.getBoundingClientRect(); return b.width > 8 && document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2) === td; });
      if (tds.length < 4) return null; const r = td => { const b = td.getBoundingClientRect(); return [b.left + b.width / 2, b.top + b.height / 2]; }; return [r(tds[0]), r(tds.at(-1))]""")
    if not c: return {"skipped": "nincs cella"}
    return recorded(s, lambda: drag(s, [tuple(c[0]), tuple(c[1]), tuple(c[0]), tuple(c[1])], 25))

def table_edit_exit(s):
    s.js("document.querySelector('.tn-table-editor')?.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true})); return 1")
    time.sleep(.6)

def run(label, base, sheet, only, options=None):
    s = Safari()
    results = {"label": label, "sheet": sheet, "time": time.strftime("%Y-%m-%d %H:%M:%S")}
    def step(name, fn, *args):
        if only and name.split(":")[0] not in only: return
        try: results[name] = fn(s, *args)
        except Exception as error: results[name] = {"error": str(error)[:300]}
        print(name, json.dumps(results[name], ensure_ascii=False), flush=True)
    try:
        s.open(base + "/edit/" + sheet, options)
        results["options"] = options
        results["agent"] = s.js("return navigator.userAgent")
        results["nodes"] = s.js("return [document.querySelectorAll('[data-node]').length, document.querySelectorAll('[data-edge]').length]")
        step("idle", idle)
        step("pan_slow", pan_slow)
        step("pan_fast", pan_fast)
        step("zoom_slow", zoom_slow)
        step("zoom_fast", zoom_fast)
        if not only or only & {"select", "rectangle", "move", "table"}:
            # Közelebb a dobozokhoz: egy doboz kb. 140 képpont széles legyen (olvasható nagyítás).
            focus_on(s, '[data-node="n00100"] .node-surface' if sheet != "tabla" else '[data-node="n00005"] .node-surface', 140)
        step("select", select_single)
        deselect(s)
        step("move:box", node_move, "box")
        step("move:junction", node_move, "junction")
        step("move:container", container_move)
        step("rectangle", rectangle)
        step("move:batch", batch_move)
        deselect(s)
        if not only or "table" in only:
            focus_on(s, '[data-node^="f"][data-type="table"] .node-surface', 700)
            step("table:scroll_view", table_scroll_view)
            step("table:wheel_view", table_wheel, '[data-node^="f"][data-type="table"] .node-note')
            if table_edit_enter(s):
                step("table:scroll_edit", table_scroll_edit)
                step("table:wheel_edit", table_wheel, ".tn-table-scroll")
                step("table:cells", table_cells)
                step("table:range", table_range)
                table_edit_exit(s)
            else: results["table:edit"] = {"skipped": "a szerkesztés nem indult el"}
    finally:
        s.close()
    out = os.path.join(HERE, "../../.build/perf-results")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, label + "-" + sheet + ".json"), "w", encoding="utf-8") as f: json.dump(results, f, ensure_ascii=False, indent=1)
    return results

if __name__ == "__main__":
    args = sys.argv[1:]
    label = args[0] if args and not args[0].startswith("--") else "meres"
    option = lambda name, default: args[args.index(name) + 1] if name in args else default
    only = set(option("--only", "").split(",")) - {""}
    run(label, option("--base", "http://localhost:8888"), option("--sheet", "p300"), only, option("--perf", None))
