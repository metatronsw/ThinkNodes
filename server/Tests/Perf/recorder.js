// A mért lapba fecskendezett képkocka-rögzítő és segédek (Tests/Perf/perf.py tölti be).
// A requestAnimationFrame-időközöket rögzíti: ami 16,7 ms-nál hosszabb, az kihagyott képkocka (akadás).
window.__perf = (() => {
  let frames = [], running = false, counters = {}, generation = 0, events = [], origin = 0;
  // Idővonal: a bemeneti események és a ritka (nézet-, gyökér-) újrarajzolások ideje, hogy a hosszú képkockák okához köthetők legyenek.
  const note = name => { if (running && events.length < 400) events.push([Math.round(performance.now() - origin), name]); };
  for (const type of ["pointerdown", "pointerup", "mousedown", "mouseup", "keydown", "keyup"]) window.addEventListener(type, () => note(type), true);
  // Eseménykezelés teljes szkriptideje: az elfogási fázis elejétől a buborékolás végéig. A Vue frissítése mikrofeladat,
  // amely a szerkesztő kezelője után, az ablak buborék-figyelője előtt lefut, így az is benne van (rajzolás + DOM-írás).
  let eventStart = 0, eventTimes = [];
  for (const type of ["pointermove", "pointerdown", "pointerup"]) {
    window.addEventListener(type, () => { eventStart = performance.now(); }, true);
    window.addEventListener(type, () => { if (running) eventTimes.push(performance.now() - eventStart); });
  }
  let moves = 0;
  window.addEventListener("pointermove", () => { if (moves++ < 2) note("pointermove#" + moves); }, true);
  window.addEventListener("pointerdown", () => { moves = 0; }, true);
  // A generáció miatt egy korábbi mérés még függő rAF-hívása nem indít második hurkot.
  const loop = mine => time => { if (!running || mine !== generation) return; frames.push(time); requestAnimationFrame(loop(mine)); };
  const stats = values => {
    const sorted = [...values].sort((a, b) => a - b), at = q => sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))] ?? 0;
    const total = values.reduce((sum, v) => sum + v, 0);
    return {frames: values.length, ms: Math.round(total), fps: values.length ? +(1000 * values.length / total).toFixed(1) : 0,
      p50: +at(.5).toFixed(1), p95: +at(.95).toFixed(1), p99: +at(.99).toFixed(1), max: +(sorted.at(-1) ?? 0).toFixed(1),
      over25: values.filter(v => v > 25).length, over50: values.filter(v => v > 50).length, over100: values.filter(v => v > 100).length,
      jank: Math.round(values.reduce((sum, v) => sum + Math.max(0, v - 17), 0))};
  };
  // Az elrendezést kikényszerítő DOM-hívások és a szerkesztő megjelölt szakaszai (editor.js `timed`) ideje, ms-ban.
  const spent = {};
  const add = (name, ms) => { spent[name] = (spent[name] ?? 0) + ms; };
  const wrap = (proto, method) => {
    const original = proto[method];
    if (!original || original.__perf) return;
    proto[method] = function (...args) { const from = performance.now(); try { return original.apply(this, args); } finally { add("dom:" + method, performance.now() - from); counters["dom:" + method] = (counters["dom:" + method] ?? 0) + 1; } };
    proto[method].__perf = true;
  };
  for (const [proto, methods] of [[Element.prototype, ["getBoundingClientRect", "getClientRects"]], [SVGGraphicsElement.prototype, ["getBBox", "getScreenCTM", "getCTM"]],
    [SVGTextContentElement.prototype, ["getComputedTextLength", "getSubStringLength"]], [SVGGeometryElement.prototype, ["getTotalLength", "getPointAtLength"]],
    [HTMLElement.prototype, ["focus"]], [SVGElement.prototype, ["focus"]], [Document.prototype, ["elementFromPoint"]]]) for (const method of methods) wrap(proto, method);
  const hit = (x, y) => document.elementFromPoint(x, y);
  const canvas = () => document.querySelector("svg.editor-canvas");
  const area = () => document.querySelector(".canvas-area").getBoundingClientRect();
  const rectOf = el => { const b = el.getBoundingClientRect(); return {x: b.left + b.width / 2, y: b.top + b.height / 2, l: b.left, t: b.top, r: b.right, b: b.bottom, w: b.width, h: b.height}; };
  const visible = b => { const a = area(); return b.l > a.left + 10 && b.r < a.right - 10 && b.t > a.top + 60 && b.b < a.bottom - 60; };
  return {
    start() { frames = []; counters = {}; events = []; eventTimes = []; origin = performance.now(); for (const key in spent) delete spent[key]; running = true; requestAnimationFrame(loop(++generation)); },
    stop() { running = false; const gaps = []; for (let i = 1; i < frames.length; i++) gaps.push(frames[i] - frames[i - 1]);
      const slow = []; for (let i = 1; i < frames.length; i++) if (frames[i] - frames[i - 1] > 30) slow.push([Math.round(frames[i - 1] - origin), Math.round(frames[i] - frames[i - 1])]);
      return {...stats(gaps), slow: slow.slice(0, 60), events, handlers: eventTimes.length ? stats(eventTimes) : undefined, counters, spent: Object.fromEntries(Object.entries(spent).map(([k, v]) => [k, Math.round(v)]))}; },
    time(name, run) { const from = performance.now(); try { return run(); } finally { add(name, performance.now() - from); } },
    count(name) { counters[name] = (counters[name] ?? 0) + 1; if (name === "view" || name === "root" || name === "scene") note(name); },
    stats,
    // Üres vászonpont a látható területen (nincs alatta doboz vagy vonal), ahonnan pásztázni / kijelölni lehet.
    emptyPoint() {
      const a = area();
      for (let y = a.top + 120; y < a.bottom - 120; y += 23) for (let x = a.left + 120; x < a.right - 420; x += 31) {
        const target = hit(x, y);
        if (target && canvas().contains(target) && !target.closest("[data-node], [data-edge], foreignObject")) return {x: Math.round(x), y: Math.round(y)};
      }
      return null;
    },
    // Látható dobozok közepe típus szerint (a kattintás valóban a dobozt éri).
    nodes(type, limit = 20) {
      const out = [];
      for (const g of document.querySelectorAll('[data-node][data-type="' + type + '"]')) {
        const b = rectOf(g.querySelector(".node-surface, .junction-surface, .node-file") ?? g);
        if (!visible(b)) continue;
        if (hit(b.x, b.y)?.closest("[data-node]") !== g) continue;
        out.push({id: g.dataset.node, x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.w), h: Math.round(b.h)});
        if (out.length >= limit) break;
      }
      return out;
    },
    rect(selector) { const el = document.querySelector(selector); return el ? rectOf(el) : null; },
    // Kattintás-késleltetés: a lenyomástól a következő kirajzolt képkockáig eltelt idő (két rAF: az első még a régi állapotot zárja).
    latencies(events = ["pointerdown"]) {
      // js: a kezelők és a Vue-frissítés (mikrofeladat) ideje – az esemény utáni első makrofeladatig; a többi stílus, elrendezés, festés.
      const out = [], js = [];
      const channel = new MessageChannel();
      let from = 0;
      channel.port1.onmessage = () => js.push(performance.now() - from);
      const listen = e => { const start = from = performance.now(); channel.port2.postMessage(0); requestAnimationFrame(() => requestAnimationFrame(() => out.push(performance.now() - start))); };
      for (const type of events) window.addEventListener(type, listen, true);
      return {stop() { for (const type of events) window.removeEventListener(type, listen, true); return out.map(v => +v.toFixed(1)); }, js() { return js.map(v => +v.toFixed(1)); }};
    },
    // Lapon belüli, képkockánként egy bemenettel hajtott forgatókönyv (görgő, görgetés): step(i) minden rAF-ben egyszer fut.
    drive(steps, step) {
      return new Promise(resolve => {
        // js: a lépés szinkron kezelői + a Vue-frissítés (a lépés után sorba állított mikrofeladatig).
        let i = 0;
        const js = [];
        this.start();
        const tick = () => {
          if (i >= steps) { requestAnimationFrame(() => resolve({...this.stop(), js: stats(js.filter(v => v > .2))})); return; }
          const from = performance.now();
          step(i++);
          Promise.resolve().then(() => Promise.resolve()).then(() => js.push(performance.now() - from));
          requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      });
    },
    wheel(x, y, deltaY, ctrlKey = false) {
      // A vászon fölötti fedőelemek (pl. állapotsor) helyett mindig a vászon vagy annak egy eleme kapja az eseményt.
      // A célpont keresése (elementFromPoint) maga is ezredmásodpercekbe kerül: pontonként egyszer keressük meg.
      const key = x + "," + y;
      if (this.wheelKey !== key || !this.wheelTarget?.isConnected) { this.wheelKey = key; this.wheelTarget = hit(x, y); }
      const target = this.wheelTarget;
      (target && canvas().contains(target) ? target : canvas()).dispatchEvent(new WheelEvent("wheel", {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, deltaY, deltaMode: 0, ctrlKey}));
    },
    selectedCount() { return document.querySelectorAll("[data-node].own-selected").length; },
  };
})();
