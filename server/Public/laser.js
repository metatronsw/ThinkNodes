import {screenMatrix as screenMatrixOf} from "./screen-matrix.js";

// Lézer pointer: bekapcsolt állapotban (eszköztár gomb) az egérrel húzott vonal a felhasználó színével látszik
// mindenkinél, és rövid idő alatt elhalványul (csóva: a vonal vége folyamatosan fogy és elvékonyodik). Nem mentődik; a
// pontok a meglévő WebSocketen mennek (`{laser, stroke, points: [x, y, …], end}`), a munkalap koordinátáiban.
// Mintavétel (hibrid): új pont csak legalább `minDistance` képpontnyi elmozdulás után, és legalább `minInterval` ms-onként;
// gyors mozgásnál ez az idő `fastInterval`-ig nő (ritkább pontok, a görbe kisimítja). A pontok `sendInterval` ms-onként
// csomagban mennek. Rajzolás: a pontokon átmenő Catmull-Rom (Bézier) görbe kitöltött körvonalként, a vége (a legrégebbi
// pont felé) elvékonyodik; a vastagság a nagyítástól független (képernyő-képpont).
// A rajz a látható terület méretű <canvas>-on van a munkalap fölött (app.css .laser-overlay), képkockánként a munkalap
// aktuális képernyő-mátrixával (pásztázás és nagyítás közben is követi). Az SVG-ben rajzolt vonal minden képkockában
// újrafestést és újrarétegezést okozott (p1000: rajzolás közben ~38 fps); a canvas tartalma ezek nélkül frissül.
// Amíg nincs látható vonal, a canvasnak nincs háttértára, és nincs képkockánkénti munka.
const lifetime = 2200;      // ms: ennyi idő után tűnik el egy pont
const maxPoints = 48;       // vonásonként legfeljebb ennyi pont látszik (a legrégebbi kiesik)
const minDistance = 12;     // képpont: ennél kisebb elmozdulás nem ad új pontot
const minInterval = 40;     // ms: két pont között legalább ennyi idő (lassú mozgásnál)
const fastInterval = 100;   // ms: nagyon gyors mozgásnál ennyi
const slowSpeed = .5, fastSpeed = 2.5;  // képpont / ms: a két idő közti átmenet sebességhatárai
const sendInterval = 100;   // ms: ennyi időnként megy egy csomag a szerverre
const batch = 16;           // pont / üzenet (a szerver 512 bájtos üzenethatára alatt)
const widths = [[9, .28], [3.5, 1], [1.2, .85]];  // képpont, átlátszóság: fény, mag, csillanás (fehér)
const cornerTolerance = 3; // képpont: ha a mozgás ennyinél jobban eltér két pont egyenesétől, a fordulópont is pont lesz
const taperLength = 240;    // képpont: ekkora szakaszon vékonyodik el a vonal vége (rövid vonásnál a hossz 70%-án)

export function sharedLaser(send, ownColor) {
  const strokes = new Map();   // kulcs: "küldő:vonás" → {color, points: [{x, y, t}], tip, ended, last}
  let layer, root, overlay, context, listeners, button, enabled = false, frame = 0, drawing = null, pending = [], timer, counter = 0;
  function add(key, color, points, end, spread = 0) {
    let stroke = strokes.get(key);
    if (!stroke) {
      stroke = {color, points: [], tip: null, ended: false};
      strokes.set(key, stroke);
    }
    // Egy csomag pontjai a csomag idejére elosztva kapnak időt, így a vége a küldőnél látott ütemben fogy.
    const now = performance.now(), count = points.length >> 1;
    for (let i = 0; i < count; i++) stroke.points.push({x: points[2 * i], y: points[2 * i + 1], t: now - (count - 1 - i) * spread / count});
    if (stroke.points.length > maxPoints) stroke.points.splice(0, stroke.points.length - maxPoints);
    if (end) { stroke.ended = true; stroke.tip = null; }
    if (!frame) frame = requestAnimationFrame(tick);
    return stroke;
  }
  // A pontokon átmenő görbe mintái (centripetális Catmull-Rom → köbös Bézier), szakaszonként a képernyőn ~10 képpontonként.
  // A centripetális változat egyenetlen pontközöknél sem csúcsosodik és nem lő túl (az egyenletes változat a ritka
  // mintavétel mellett sarkos vonalat adott).
  function curve(points, scale) {
    if (points.length < 3) return points;
    const out = [points[0]];
    const span = (a, b) => Math.sqrt(Math.hypot(b.x - a.x, b.y - a.y));
    for (let i = 0; i + 1 < points.length; i++) {
      const p0 = points[i - 1] ?? points[i], p1 = points[i], p2 = points[i + 1], p3 = points[i + 2] ?? p2;
      const d1 = span(p0, p1), d2 = span(p1, p2), d3 = span(p2, p3);
      if (!d2) continue;
      const c1 = d1 ? {x: (d1 * d1 * p2.x - d2 * d2 * p0.x + (2 * d1 * d1 + 3 * d1 * d2 + d2 * d2) * p1.x) / (3 * d1 * (d1 + d2)),
        y: (d1 * d1 * p2.y - d2 * d2 * p0.y + (2 * d1 * d1 + 3 * d1 * d2 + d2 * d2) * p1.y) / (3 * d1 * (d1 + d2))} : p1;
      const c2 = d3 ? {x: (d3 * d3 * p1.x - d2 * d2 * p3.x + (2 * d3 * d3 + 3 * d3 * d2 + d2 * d2) * p2.x) / (3 * d3 * (d3 + d2)),
        y: (d3 * d3 * p1.y - d2 * d2 * p3.y + (2 * d3 * d3 + 3 * d3 * d2 + d2 * d2) * p2.y) / (3 * d3 * (d3 + d2))} : p2;
      const steps = Math.max(1, Math.min(8, Math.ceil(d2 * d2 * scale / 10)));
      for (let k = 1; k <= steps; k++) {
        const t = k / steps, u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
        out.push({x: a * p1.x + b * c1.x + c * c2.x + d * p2.x, y: a * p1.y + b * c1.y + c * c2.y + d * p2.y});
      }
    }
    return out;
  }
  // A görbe mentén az egységnyi normálisok és a vastagság szorzója (a vége felé 0-ra fogy); a három réteg közös.
  function geometry(samples, taperWorld) {
    const n = samples.length, normals = new Float64Array(2 * n), factors = new Float64Array(n);
    let length = 0;
    for (let i = 1; i < n; i++) length += Math.hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y);
    const taper = Math.min(length * .7, taperWorld) || 1;
    let along = 0;
    for (let i = 0; i < n; i++) {
      if (i) along += Math.hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y);
      const a = samples[Math.max(0, i - 1)], b = samples[Math.min(n - 1, i + 1)];
      const dx = b.x - a.x, dy = b.y - a.y, len = Math.hypot(dx, dy) || 1;
      normals[2 * i] = -dy / len; normals[2 * i + 1] = dx / len;
      factors[i] = Math.pow(Math.min(1, along / taper), .75);
    }
    return {samples, normals, factors, length};
  }
  // Kitöltött körvonal: a görbe két oldala a helyi vastagsággal eltolva, a fején félkör, a vége hegyes.
  function fillOutline({samples, normals, factors, length}, half) {
    const n = samples.length;
    context.beginPath();
    if (n === 1 || length < 1e-6) {
      context.arc(samples[n - 1].x, samples[n - 1].y, half, 0, 2 * Math.PI);
      context.fill();
      return;
    }
    for (let i = 0; i < n; i++) {
      const w = half * factors[i];
      context.lineTo(samples[i].x + normals[2 * i] * w, samples[i].y + normals[2 * i + 1] * w);
    }
    // A fej félköre a haladási irány felé (a normális szögétől fél fordulat, csökkenő szöggel).
    const head = samples[n - 1], angle = Math.atan2(normals[2 * n - 1], normals[2 * n - 2]);
    context.arc(head.x, head.y, half * factors[n - 1], angle, angle + Math.PI, true);
    for (let i = n - 2; i >= 0; i--) {
      const w = half * factors[i];
      context.lineTo(samples[i].x - normals[2 * i] * w, samples[i].y - normals[2 * i + 1] * w);
    }
    context.closePath();
    context.fill();
  }
  // A canvas háttértára a látható terület méretében (eszközképpontban); vonal nélkül felszabadul.
  function resize(width, height) {
    if (overlay.width !== width || overlay.height !== height) { overlay.width = width; overlay.height = height; }
  }
  function tick() {
    frame = 0;
    // Kötés előtt (vagy leválasztott rétegnél) nincs hová rajzolni; a bind újraindítja.
    if (!overlay || !layer?.isConnected) return;
    const now = performance.now();
    // Egyszeri olvasás a képkocka elején, írás előtt: a munkalap képernyő-mátrixa és a canvas helye.
    const matrix = screenMatrix(), box = overlay.getBoundingClientRect(), ratio = devicePixelRatio || 1;
    if (!matrix) { if (strokes.size) frame = requestAnimationFrame(tick); return; }
    const scale = Math.hypot(matrix.a, matrix.b) || 1;
    resize(Math.round(box.width * ratio), Math.round(box.height * ratio));
    context.setTransform(1, 0, 0, 1, 0, 0);
    context.clearRect(0, 0, overlay.width, overlay.height);
    context.setTransform(ratio * matrix.a, ratio * matrix.b, ratio * matrix.c, ratio * matrix.d,
      ratio * (matrix.e - box.left), ratio * (matrix.f - box.top));
    for (const [key, stroke] of strokes) {
      const points = stroke.points;
      // A lejárt pontokból egy marad: a vége ehhez képest fogy folyamatosan (nem pontonként ugrik).
      while (points.length > 1 && now - points[1].t >= lifetime) points.shift();
      const expired = points.length && now - points[0].t >= lifetime;
      if ((!points.length || (expired && points.length === 1)) && !stroke.tip && (stroke.ended || now - (stroke.last ?? now) > 5000)) {
        strokes.delete(key);
        continue;
      }
      if (points.length && !expired) stroke.last = now;
      const visible = points.slice();
      if (expired && visible.length > 1) {
        const [a, b] = visible, span = b.t - a.t, part = span > 0 ? Math.min(1, (now - lifetime - a.t) / span) : 1;
        visible[0] = {x: a.x + (b.x - a.x) * part, y: a.y + (b.y - a.y) * part, t: a.t};
      } else if (expired) visible.length = 0;
      if (stroke.tip) visible.push(stroke.tip);
      if (!visible.length) continue;
      const shape = geometry(curve(visible, scale), taperLength / scale);
      widths.forEach(([width, opacity], index) => {
        context.globalAlpha = opacity;
        context.fillStyle = index === 2 ? "white" : stroke.color;
        fillOutline(shape, width / 2 / scale);
      });
    }
    context.globalAlpha = 1;
    if (strokes.size) frame = requestAnimationFrame(tick);
    else resize(0, 0);
  }
  function receive(message) {
    if (!message) {
      strokes.clear();
      if (!frame && overlay) frame = requestAnimationFrame(tick);
      return;
    }
    add(message.laser + ":" + message.stroke, message.color || "#e5484d", message.points ?? [], message.end, sendInterval);
  }
  function flush(end = false) {
    clearTimeout(timer);
    timer = undefined;
    if (!drawing) return;
    while (pending.length > batch * 2) send({laser: true, stroke: drawing.id, points: pending.splice(0, batch * 2)});
    if (pending.length || end) send({laser: true, stroke: drawing.id, points: pending.splice(0), ...(end ? {end: true} : {})});
  }
  // Új pont a saját vonásba (és a küldendők közé). A mintavétel a képernyő koordinátáiban dönt.
  function sample(event, force = false) {
    const point = world(event);
    if (!point) return;
    const key = "own:" + drawing.id, now = performance.now(), x = event.clientX, y = event.clientY;
    const stroke = strokes.get(key);
    if (stroke) { stroke.tip = point; if (!frame) frame = requestAnimationFrame(tick); }
    if (!drawing.last) { accept(key, x, y, point, now); return; }
    // Fordulópont: az utolsó pont óta bejárt (ki nem küldött) helyek közül a jelenlegi egyenestől legtávolabbi, ha
    // jobban eltér a tűrésnél. Így a ritka mintavétel nem vágja le a sarkokat és a hirtelen irányváltásokat.
    const apex = farthest(drawing.raw, drawing.last, x, y);
    if (apex) { accept(key, apex.x, apex.y, apex.point, apex.t); drawing.raw = drawing.raw.slice(apex.index + 1); }
    const last = drawing.last, distance = Math.hypot(x - last.x, y - last.y), elapsed = now - last.t;
    const speed = distance / Math.max(1, elapsed);
    const wait = minInterval + (fastInterval - minInterval) * Math.min(1, Math.max(0, (speed - slowSpeed) / (fastSpeed - slowSpeed)));
    if (force ? distance < .5 : distance < minDistance || elapsed < wait) {
      drawing.raw.push({x, y, point, t: now});
      return;
    }
    accept(key, x, y, point, now);
  }
  function farthest(raw, from, x, y) {
    const dx = x - from.x, dy = y - from.y, length = Math.hypot(dx, dy);
    let best = null, most = cornerTolerance;
    raw.forEach((p, index) => {
      const deviation = length ? Math.abs((p.x - from.x) * dy - (p.y - from.y) * dx) / length : Math.hypot(p.x - from.x, p.y - from.y);
      if (deviation > most) { most = deviation; best = {...p, index}; }
    });
    return best;
  }
  function accept(key, x, y, point, t) {
    drawing.last = {x, y, t};
    drawing.raw = [];
    add(key, ownColor() || "#e5484d", [point.x, point.y]);
    pending.push(point.x, point.y);
    if (pending.length >= batch * 2) flush();
    else if (!timer) timer = setTimeout(flush, sendInterval);
  }
  function screenMatrix() { return screenMatrixOf(layer, root); }
  function world(event) {
    const matrix = screenMatrix();
    if (!matrix) return null;
    const {x, y} = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
    return {x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10};
  }
  // Kurzor: a vászon a [data-laser] CSS-szabálytól kapja a varázspálcát; a saját kurzort adó elemek (doboz, vonal,
  // fogantyú) közül csak az éppen mutatott kap inline felülírást. Így a váltás nem számoltatja újra az összes doboz és
  // vonal stílusát (p1000-en egy leszármazott-szabály 50 → 100–200 ms-os képkockát adott), rámutatáskor pedig egyetlen
  // elem stílusa változik.
  const cursor = 'url("/laser-cursor.svg") 5 5, crosshair';
  let cursorTarget = null, cursorBefore = null;
  function markCursor(target) {
    if (target === cursorTarget) return;
    if (cursorTarget) {
      if (cursorBefore?.value) cursorTarget.style.setProperty("cursor", cursorBefore.value, cursorBefore.priority);
      else cursorTarget.style.removeProperty("cursor");
    }
    cursorTarget = target?.style ? target : null;
    if (!cursorTarget) return;
    cursorBefore = {value: cursorTarget.style.getPropertyValue("cursor"), priority: cursorTarget.style.getPropertyPriority("cursor")};
    cursorTarget.style.setProperty("cursor", cursor, "important");
  }
  function showButton() {
    if (!button) return;
    button.setAttribute("aria-pressed", String(enabled));
    button.closest(".canvas-area, .passive-frame")?.toggleAttribute("data-laser", enabled);
    if (!enabled) markCursor(null);
  }
  // `svg`: a vászon; `parent`: a munkalap-koordinátás réteg szülője; `area`: a vászon tárolója (itt fogjuk el az
  // eseményeket, mielőtt a szerkesztő kijelölne / pásztázna); `controls`: az eszköztár (a gomb ide kerül).
  function bind(svg, parent, area, controls, before = null) {
    listeners?.abort();
    markCursor(null);
    listeners = new AbortController();
    const options = {signal: listeners.signal};
    // A munkalap-koordinátás csoport csak a képernyő-mátrixhoz kell; a rajz a vászon burkolója mögé tett canvasra kerül.
    layer = parent;
    root = svg;
    overlay?.remove();
    overlay = document.createElement("canvas");
    overlay.className = "laser-overlay";
    overlay.setAttribute("aria-hidden", "true");
    overlay.width = overlay.height = 0;
    context = overlay.getContext("2d");
    const holder = [...area.children].find(child => child.contains(svg));
    if (holder) holder.after(overlay); else area.append(overlay);
    if (strokes.size && !frame) frame = requestAnimationFrame(tick);
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
    // A vászon gyökere a CSS-szabályból kap kurzort; a mutatott leszármazott egyenként (markCursor).
    area.addEventListener("pointerover", event => {
      if (enabled) markCursor(event.target !== svg && inCanvas(event) ? event.target : null);
    }, options);
    let suppressClick = false;
    area.addEventListener("pointerdown", event => {
      if (!enabled || event.button !== 0 || !inCanvas(event)) return;
      event.preventDefault();
      event.stopPropagation();
      if (!world(event)) return;
      // Ha az előző rajz felengedése elveszett, az most lezárul (különben a régi vonal az új kezdőpontig húzódna).
      if (drawing) end(null);
      area.setPointerCapture?.(event.pointerId);
      drawing = {id: ++counter, pointer: event.pointerId, last: null, raw: []};
      suppressClick = true;
      sample(event);
    }, {...options, capture: true});
    area.addEventListener("pointermove", event => {
      if (!drawing || event.pointerId !== drawing.pointer) return;
      event.stopPropagation();
      // A gomb már nincs lenyomva, de a felengedés nem jutott el ide (pl. a vásznon kívül, elveszett egérelfogással):
      // a rajz itt lezárul, nem követi tovább a mutatót.
      if (event.pointerType === "mouse" && !(event.buttons & 1)) { end(null); return; }
      sample(event);
    }, {...options, capture: true});
    // Lezárás: a felengedés helye bekerül (ha nem esik egybe az utolsó ponttal); elveszett felengedésnél (event = null)
    // a vonal az utolsó pontnál ér véget.
    function end(event) {
      if (event?.type === "pointerup") sample(event, true);
      flush(true);
      const own = strokes.get("own:" + drawing.id);
      if (own) { own.ended = true; own.tip = null; }
      drawing = null;
      // A felengedés utáni kattintás szinkron jön; ha nem jön (húzás), a tiltás ne maradjon meg.
      setTimeout(() => { suppressClick = false; });
    }
    const finish = event => {
      if (!drawing || event.pointerId !== drawing.pointer) return;
      if (area.contains(event.target)) event.stopPropagation();
      end(event);
    };
    // A vásznon kívüli felengedés (ablakszinten) és az elveszett egérelfogás is lezárja a rajzot.
    addEventListener("pointerup", finish, {...options, capture: true});
    area.addEventListener("lostpointercapture", event => { if (drawing && event.pointerId === drawing.pointer) end(null); }, options);
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
  return {bind, receive, stop() { listeners?.abort(); markCursor(null); receive(null); }};
}
