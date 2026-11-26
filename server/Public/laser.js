// Lézer pointer: bekapcsolt állapotban (eszköztár gomb) az egérrel húzott vonal a felhasználó színével látszik
// mindenkinél, és rövid idő alatt elhalványul (csóva: a vonal vége folyamatosan fogy). Nem mentődik; a pontok a
// meglévő WebSocketen mennek (`{laser, stroke, points: [x, y, …], end}`), a munkalap koordinátáiban. A vonal
// vastagsága a nagyítástól független (non-scaling-stroke).
const ns = "http://www.w3.org/2000/svg";
const lifetime = 1200;      // ms: ennyi idő után tűnik el egy pont
const batch = 16;           // pont / üzenet (a szerver 512 bájtos üzenethatára alatt)

export function sharedLaser(send, ownColor) {
  const strokes = new Map();   // kulcs: "küldő:vonás" → {color, points: [{x, y, t}], ended, glow, core}
  let layer, listeners, button, enabled = false, frame = 0, drawing = null, pending = [], timer, counter = 0;
  function path(points) {
    return points.length ? "M" + points.map(p => p.x.toFixed(1) + " " + p.y.toFixed(1)).join("L") + (points.length === 1 ? "l.1 0" : "") : "";
  }
  function strokeElements(color) {
    const group = document.createElementNS(ns, "g");
    group.setAttribute("class", "laser-stroke");
    const make = (width, opacity) => {
      const line = document.createElementNS(ns, "path");
      for (const [key, value] of Object.entries({fill: "none", stroke: color, "stroke-width": width, "stroke-opacity": opacity,
        "stroke-linecap": "round", "stroke-linejoin": "round", "vector-effect": "non-scaling-stroke"})) line.setAttribute(key, value);
      group.append(line);
      return line;
    };
    const glow = make(9, .28), core = make(3.5, 1);
    const shine = make(1.2, .85);
    shine.setAttribute("stroke", "white");
    return {group, glow, core, shine};
  }
  function add(key, color, points, end) {
    let stroke = strokes.get(key);
    if (!stroke) {
      stroke = {color, points: [], ended: false, ...strokeElements(color)};
      strokes.set(key, stroke);
      layer?.append(stroke.group);
    }
    const now = performance.now();
    for (let i = 0; i + 1 < points.length; i += 2) stroke.points.push({x: points[i], y: points[i + 1], t: now});
    if (end) stroke.ended = true;
    if (!frame) frame = requestAnimationFrame(tick);
  }
  function tick() {
    frame = 0;
    const now = performance.now();
    for (const [key, stroke] of strokes) {
      stroke.points = stroke.points.filter(p => now - p.t < lifetime);
      if (!stroke.points.length && (stroke.ended || now - (stroke.last ?? now) > 5000)) {
        stroke.group.remove();
        strokes.delete(key);
        continue;
      }
      if (stroke.points.length) stroke.last = now;
      const d = path(stroke.points);
      for (const line of [stroke.glow, stroke.core, stroke.shine]) line.setAttribute("d", d);
    }
    if (strokes.size) frame = requestAnimationFrame(tick);
  }
  function receive(message) {
    if (!message) {
      for (const stroke of strokes.values()) stroke.group.remove();
      strokes.clear();
      return;
    }
    add(message.laser + ":" + message.stroke, message.color || "#e5484d", message.points ?? [], message.end);
  }
  function flush(end = false) {
    clearTimeout(timer);
    timer = undefined;
    if (!drawing) return;
    while (pending.length > batch * 2) send({laser: true, stroke: drawing.id, points: pending.splice(0, batch * 2)});
    if (pending.length || end) send({laser: true, stroke: drawing.id, points: pending.splice(0), ...(end ? {end: true} : {})});
  }
  function world(event) {
    const matrix = layer?.getScreenCTM();
    if (!matrix) return null;
    const {x, y} = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
    return {x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10};
  }
  function showButton() {
    if (!button) return;
    button.setAttribute("aria-pressed", String(enabled));
    button.closest(".canvas-area, .passive-frame")?.toggleAttribute("data-laser", enabled);
  }
  // `svg`: a vászon; `parent`: a munkalap-koordinátás réteg szülője; `area`: a vászon tárolója (itt fogjuk el az
  // eseményeket, mielőtt a szerkesztő kijelölne / pásztázna); `controls`: az eszköztár (a gomb ide kerül).
  function bind(svg, parent, area, controls, before = null) {
    listeners?.abort();
    listeners = new AbortController();
    const options = {signal: listeners.signal};
    layer?.remove();
    layer = document.createElementNS(ns, "g");
    layer.setAttribute("data-editor-only", "");
    layer.setAttribute("pointer-events", "none");
    layer.setAttribute("aria-hidden", "true");
    layer.setAttribute("class", "laser-layer");
    parent.append(layer);
    for (const stroke of strokes.values()) layer.append(stroke.group);
    if (!controls) return;
    button = document.createElement("button");
    button.type = "button";
    button.className = "button laser-tool";
    button.title = "Lézer pointer (húzással rajzol, a vonal elhalványul)";
    button.setAttribute("aria-label", button.title);
    button.innerHTML = '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><path fill="currentColor" d="M3.3 19.3 13.6 9l1.4 1.4L4.7 20.7zM16 2.5l1.1 2.4 2.4 1.1-2.4 1.1L16 9.5l-1.1-2.4L12.5 6l2.4-1.1zM20 10l.7 1.3 1.3.7-1.3.7L20 14l-.7-1.3L18 12l1.3-.7z"/></svg>';
    controls.insertBefore(button, before);
    showButton();
    button.addEventListener("click", () => { enabled = !enabled; showButton(); }, options);
    const inCanvas = event => svg.contains(event.target);
    let suppressClick = false;
    area.addEventListener("pointerdown", event => {
      if (!enabled || event.button !== 0 || !inCanvas(event)) return;
      event.preventDefault();
      event.stopPropagation();
      const point = world(event);
      if (!point) return;
      area.setPointerCapture?.(event.pointerId);
      drawing = {id: ++counter, pointer: event.pointerId};
      suppressClick = true;
      add("own:" + drawing.id, ownColor() || "#e5484d", [point.x, point.y]);
      pending.push(point.x, point.y);
      flush();
    }, {...options, capture: true});
    area.addEventListener("pointermove", event => {
      if (!drawing || event.pointerId !== drawing.pointer) return;
      event.stopPropagation();
      const point = world(event);
      if (!point) return;
      add("own:" + drawing.id, ownColor() || "#e5484d", [point.x, point.y]);
      pending.push(point.x, point.y);
      if (pending.length >= batch * 2) flush();
      else if (!timer) timer = setTimeout(flush, 33);
    }, {...options, capture: true});
    const finish = event => {
      if (!drawing || event.pointerId !== drawing.pointer) return;
      event.stopPropagation();
      flush(true);
      const own = strokes.get("own:" + drawing.id);
      if (own) own.ended = true;
      drawing = null;
      // A felengedés utáni kattintás szinkron jön; ha nem jön (húzás), a tiltás ne maradjon meg.
      setTimeout(() => { suppressClick = false; });
    };
    area.addEventListener("pointerup", finish, {...options, capture: true});
    area.addEventListener("pointercancel", finish, {...options, capture: true});
    // A rajzolás végén keletkező kattintás ne jelöljön ki / ne nyisson meg semmit.
    area.addEventListener("click", event => {
      if (!suppressClick) return;
      suppressClick = false;
      event.preventDefault();
      event.stopPropagation();
    }, {...options, capture: true});
    area.addEventListener("dblclick", event => { if (enabled && inCanvas(event)) event.stopPropagation(); }, {...options, capture: true});
  }
  return {bind, receive, stop() { listeners?.abort(); receive(null); }};
}
