import {screenMatrix as screenMatrixOf} from "./screen-matrix.js";
import {registerOneShot, oneShotUsed, oneShotArmed} from "./one-shot.js";

// Rajzeszközök a vászon fölött: lézer pointer és filctoll, közös motorral. Bekapcsolt állapotban (eszköztár csoportgomb,
// hosszan nyomva vagy jobb kattintásra választható) az egérrel húzott vonal a felhasználó színével látszik mindenkinél.
// Nem mentődik; a pontok a meglévő WebSocketen mennek (`{laser, stroke, points: [x, y, …], end, kind, clear}`), a
// munkalap koordinátáiban.
// - Lézer: a vonal rövid idő alatt elhalványul (csóva: a vége folyamatosan fogy és elvékonyodik).
// - Filctoll: a rajz megmarad. Ha az előző filcvonás vége óta `markerJoin` ms-nál kevesebb telt el, az új vonás
//   ugyanahhoz a rajzhoz adódik; különben az új vonás mindenkinél törli az előző rajzot (`clear`). A rajzoló kilépésekor
//   a többieknél eltűnik (retain), a saját lapon az újratöltéssel.
// Pontkorlát: lézernél vonásonként, filcnél rajzonként legfeljebb ennyi pont látszik; fölötte a legrégebbi pontok kiesnek.
// Mintavétel (hibrid): új pont csak legalább `minDistance` képpontnyi elmozdulás után, és legalább `minInterval` ms-onként;
// gyors mozgásnál ez az idő `fastInterval`-ig nő; a fordulópontok megmaradnak (`cornerTolerance`). A pontok
// `sendInterval` ms-onként csomagban mennek. Rajzolás: centripetális Catmull-Rom (Bézier) görbe kitöltött körvonalként, a
// vastagság a nagyítástól független (képernyő-képpont).
// A rajz a látható terület méretű <canvas>-on van a munkalap fölött (app.css .laser-overlay), a munkalap aktuális
// képernyő-mátrixával (screen-matrix.js). Az SVG-ben rajzolt vonal minden képkockában újrafestést és újrarétegezést okozott
// (p1000: rajzolás közben ~38 fps); a canvas tartalma ezek nélkül frissül. Képkocka csak változáskor kell (új pont, a
// nézet változása: invalidate), folyamatosan csak amíg lézervonal fogy; vonal nélkül a canvasnak nincs háttértára.
const minDistance = 12;     // képpont: ennél kisebb elmozdulás nem ad új pontot
const minInterval = 40;     // ms: két pont között legalább ennyi idő (lassú mozgásnál)
const fastInterval = 100;   // ms: nagyon gyors mozgásnál ennyi
const slowSpeed = .5, fastSpeed = 2.5;  // képpont / ms: a két idő közti átmenet sebességhatárai
const sendInterval = 100;   // ms: ennyi időnként megy egy csomag a szerverre
const batch = 16;           // pont / üzenet (a szerver 512 bájtos üzenethatára alatt)
const cornerTolerance = 3;  // képpont: ha a mozgás ennyinél jobban eltér két pont egyenesétől, a fordulópont is pont lesz
const markerJoin = 3000;    // ms: filcnél ennyin belül kezdett vonás az előző rajzhoz adódik, később törli azt

const wand = '<path fill="currentColor" d="M3.3 19.3 13.6 9l1.4 1.4L4.7 20.7zM16 2.5l1.1 2.4 2.4 1.1-2.4 1.1L16 9.5l-1.1-2.4L12.5 6l2.4-1.1zM20 10l.7 1.3 1.3.7-1.3.7L20 14l-.7-1.3L18 12l1.3-.7z"/>';
const pen = '<path fill="currentColor" d="M3 21l1.6-4.8L16.4 4.4a2.3 2.3 0 0 1 3.2 0 2.3 2.3 0 0 1 0 3.2L7.8 19.4zm3-3.2-.7 2 2-.7z"/>';
// Eszközleírások. `layers`: [vastagság képpontban, átlátszóság, szín (alapból a felhasználóé)]; `lifetime`: ms, amíg egy
// pont látszik (filcnél nincs); `taper`: képpont, amelyen a vonal vége elvékonyodik; `pointLimit`: pontkorlát.
const tools = {
  laser: {label: "Lézer pointer", hint: "húzással rajzol, a vonal elhalványul", icon: wand,
    cursor: 'url("/laser-cursor.svg") 5 5, crosshair', layers: [[9, .28], [3.5, 1], [1.2, .85, "white"]],
    lifetime: 2200, taper: 240, pointLimit: 48},
  marker: {label: "Filctoll", hint: "húzással rajzol, a rajz megmarad; 3 mp-en belül folytatható, utána az új rajz törli az előzőt",
    icon: pen, cursor: 'url("/marker-cursor.svg") 3 29, crosshair', layers: [[6, .22], [3.5, 1]],
    lifetime: 0, taper: 0, pointLimit: 1500},
};
const toolOf = kind => tools[kind] ?? tools.laser;

export function sharedLaser(send, ownColor) {
  // kulcs: "küldő:vonás" → {kind, owner, color, points: [{x, y, t}], tip, ended, last}; a saját vonások küldője "own".
  const strokes = new Map();
  let layer, root, overlay, context, listeners, button, frame = 0, drawing = null, pending = [], timer, counter = 0;
  let tool = "laser", enabled = false, once = false, markerEnded = -Infinity, menu = null, oneShot = null, unregister = null;
  const active = () => enabled || once;
  function invalidate() { if (!frame && overlay && strokes.size + (overlay.width ? 1 : 0)) frame = requestAnimationFrame(tick); }
  // Filc: a küldő rajzának pontjai együtt a pontkorláton belül (a legrégebbi vonás eleje fogy).
  function limitMarker(owner) {
    const own = [...strokes].filter(([, s]) => s.kind === "marker" && s.owner === owner);
    let total = own.reduce((sum, [, s]) => sum + s.points.length, 0);
    for (const [key, s] of own) {
      if (total <= tools.marker.pointLimit) break;
      const drop = Math.min(s.points.length, total - tools.marker.pointLimit);
      s.points.splice(0, drop);
      total -= drop;
      if (!s.points.length && s.ended) strokes.delete(key);
    }
  }
  function clearMarker(owner, keep) {
    for (const [key, s] of strokes) if (s.kind === "marker" && s.owner === owner && key !== keep) strokes.delete(key);
  }
  function add(key, owner, kind, color, points, end, spread = 0) {
    let stroke = strokes.get(key);
    if (!stroke) strokes.set(key, stroke = {kind, owner, color, points: [], tip: null, ended: false});
    // Egy csomag pontjai a csomag idejére elosztva kapnak időt, így a lézer vége a küldőnél látott ütemben fogy.
    const now = performance.now(), count = points.length >> 1;
    for (let i = 0; i < count; i++) stroke.points.push({x: points[2 * i], y: points[2 * i + 1], t: now - (count - 1 - i) * spread / count});
    if (kind === "marker") limitMarker(owner);
    else if (stroke.points.length > tools.laser.pointLimit) stroke.points.splice(0, stroke.points.length - tools.laser.pointLimit);
    if (end) { stroke.ended = true; stroke.tip = null; }
    invalidate();
    return stroke;
  }
  // A pontokon átmenő görbe mintái (centripetális Catmull-Rom → köbös Bézier), szakaszonként a képernyőn ~10 képpontonként.
  // A centripetális változat egyenetlen pontközöknél sem csúcsosodik és nem lő túl.
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
  // A görbe mentén az egységnyi normálisok és a vastagság szorzója (elvékonyodásnál a vége felé 0-ra fogy).
  function geometry(samples, taperWorld) {
    const n = samples.length, normals = new Float64Array(2 * n), factors = new Float64Array(n).fill(1);
    let length = 0;
    for (let i = 1; i < n; i++) length += Math.hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y);
    const taper = taperWorld ? Math.min(length * .7, taperWorld) || 1 : 0;
    let along = 0;
    for (let i = 0; i < n; i++) {
      if (i) along += Math.hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y);
      const a = samples[Math.max(0, i - 1)], b = samples[Math.min(n - 1, i + 1)];
      const dx = b.x - a.x, dy = b.y - a.y, len = Math.hypot(dx, dy) || 1;
      normals[2 * i] = -dy / len; normals[2 * i + 1] = dx / len;
      if (taper) factors[i] = Math.pow(Math.min(1, along / taper), .75);
    }
    return {samples, normals, factors, length, taper};
  }
  // Kitöltött körvonal: a görbe két oldala a helyi vastagsággal eltolva, a fején félkör; a vége elvékonyodásnál hegyes,
  // különben szintén félkör.
  function fillOutline({samples, normals, factors, length, taper}, half) {
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
    if (!taper) context.arc(samples[0].x, samples[0].y, half, Math.atan2(-normals[1], -normals[0]), Math.atan2(normals[1], normals[0]), true);
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
    if (!strokes.size) { resize(0, 0); return; }
    const now = performance.now();
    // Egyszeri olvasás a képkocka elején, írás előtt: a munkalap képernyő-mátrixa és a canvas helye.
    const matrix = screenMatrix(), box = overlay.getBoundingClientRect(), ratio = devicePixelRatio || 1;
    if (!matrix) return;   // a vászon nem látszik; a következő változás (invalidate) újrapróbálja
    const scale = Math.hypot(matrix.a, matrix.b) || 1;
    resize(Math.round(box.width * ratio), Math.round(box.height * ratio));
    context.setTransform(1, 0, 0, 1, 0, 0);
    context.clearRect(0, 0, overlay.width, overlay.height);
    context.setTransform(ratio * matrix.a, ratio * matrix.b, ratio * matrix.c, ratio * matrix.d,
      ratio * (matrix.e - box.left), ratio * (matrix.f - box.top));
    let fading = false;
    for (const [key, stroke] of strokes) {
      const kind = toolOf(stroke.kind), points = stroke.points, lifetime = kind.lifetime;
      let visible = points;
      if (lifetime) {
        // A lejárt pontokból egy marad: a vége ehhez képest fogy folyamatosan (nem pontonként ugrik).
        while (points.length > 1 && now - points[1].t >= lifetime) points.shift();
        const expired = points.length && now - points[0].t >= lifetime;
        if ((!points.length || (expired && points.length === 1)) && !stroke.tip && (stroke.ended || now - (stroke.last ?? now) > 5000)) {
          strokes.delete(key);
          continue;
        }
        if (points.length && !expired) stroke.last = now;
        visible = points.slice();
        if (expired && visible.length > 1) {
          const [a, b] = visible, span = b.t - a.t, part = span > 0 ? Math.min(1, (now - lifetime - a.t) / span) : 1;
          visible[0] = {x: a.x + (b.x - a.x) * part, y: a.y + (b.y - a.y) * part, t: a.t};
        } else if (expired) visible.length = 0;
        fading = true;
      } else if (!points.length && !stroke.tip) {
        if (stroke.ended) strokes.delete(key);
        continue;
      }
      if (stroke.tip) visible = [...visible, stroke.tip];
      if (!visible.length) continue;
      const shape = geometry(curve(visible, scale), kind.taper / scale);
      for (const [width, opacity, color] of kind.layers) {
        context.globalAlpha = opacity;
        context.fillStyle = color ?? stroke.color;
        fillOutline(shape, width / 2 / scale);
      }
    }
    context.globalAlpha = 1;
    // Folyamatos képkocka csak amíg lézervonal fogy; a filcrajz csak változáskor rajzolódik újra.
    if (fading) frame = requestAnimationFrame(tick);
    else if (!strokes.size) resize(0, 0);
  }
  // Más résztvevő üzenete; `null`: megszakadt a kapcsolat – a többiek rajza eltűnik, a saját megmarad.
  function receive(message) {
    if (!message) {
      for (const [key, s] of strokes) if (s.owner !== "own") strokes.delete(key);
      invalidate();
      return;
    }
    const kind = message.kind === "marker" ? "marker" : "laser", key = message.laser + ":" + message.stroke;
    if (kind === "marker" && message.clear) clearMarker(message.laser, key);
    add(key, message.laser, kind, message.color || "#e5484d", message.points ?? [], message.end, kind === "laser" ? sendInterval : 0);
  }
  // A jelenlévők listája változott: aki kilépett, annak a rajza (filc is) eltűnik.
  function retain(ids) {
    const present = new Set(ids);
    let removed = false;
    for (const [key, s] of strokes) if (s.owner !== "own" && !present.has(s.owner)) { strokes.delete(key); removed = true; }
    if (removed) invalidate();
  }
  function flush(end = false) {
    clearTimeout(timer);
    timer = undefined;
    if (!drawing) return;
    // Filcnél a fajta, és a rajzot kezdő vonás első üzenetében a törlés jelzése (az előző rajz eltűnik a többieknél is).
    const message = (points, last = false) => {
      send({laser: true, stroke: drawing.id, points, ...(drawing.kind === "marker" ? {kind: "marker"} : {}),
        ...(drawing.clear ? {clear: true} : {}), ...(last ? {end: true} : {})});
      drawing.clear = false;
    };
    while (pending.length > batch * 2) message(pending.splice(0, batch * 2));
    if (pending.length || end) message(pending.splice(0), end);
  }
  // Új pont a saját vonásba (és a küldendők közé). A mintavétel a képernyő koordinátáiban dönt.
  function sample(event, force = false) {
    const point = world(event);
    if (!point) return;
    const key = "own:" + drawing.id, now = performance.now(), x = event.clientX, y = event.clientY;
    const stroke = strokes.get(key);
    if (stroke) { stroke.tip = point; invalidate(); }
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
    add(key, "own", drawing.kind, ownColor() || "#e5484d", [point.x, point.y]);
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
  // Rajzmód (az eszköz bármelyik módon aktív): a canvas fogja el az egeret a vászon fölött (app.css
  // .laser-overlay[data-tool]), így a dobozok és vonalak nem kapnak egéreseményt – nincs rámutatási effekt, tooltip,
  // kijelölés –, és a kurzort is ez az egy elem adja (laser-cursor.svg / marker-cursor.svg). A váltás csak ennek az egy
  // elemnek a stílusát érinti (a vászon gyökerén változó kurzor p1000-en ~35 ms stílusszámítás volt, a dobozonkénti
  // felülírás rámutatáskor is számolt). A szerkesztő a canvast a vászon részének tekinti: jobb gombos pásztázás, görgős
  // nagyítás, helyi menü (editor.js).
  // A gomb: az aria-pressed a tartós bekapcsolást mutatja (az egyszeri élesítést a fényes keret, one-shot.js).
  function showButton() {
    if (active()) overlay?.setAttribute("data-tool", tool); else overlay?.removeAttribute("data-tool");
    if (!button) return;
    const current = toolOf(tool);
    button.setAttribute("aria-pressed", String(enabled));
    button.title = current.label + " (" + current.hint + "; nyomva tartva vagy jobb kattintásra: lézer / filc; D: egyszeri rajz)";
    button.setAttribute("aria-label", current.label);
    button.querySelector(".ui-icon").innerHTML = current.icon;
  }
  function closeMenu() { menu?.remove(); menu = null; }
  // Választó (hosszú nyomás vagy jobb kattintás): lézer / filc; a választott eszköz bekapcsol.
  function openMenu() {
    closeMenu();
    const list = menu = document.createElement("div");
    list.className = "quick-flyout-list open-column draw-tools";
    list.setAttribute("role", "group");
    list.setAttribute("aria-label", "Rajzeszköz");
    for (const [kind, item] of Object.entries(tools)) {
      const option = document.createElement("button");
      option.type = "button";
      option.className = "button option-icon";
      option.title = item.label;
      option.setAttribute("aria-label", item.label);
      option.setAttribute("aria-pressed", String(tool === kind));
      option.innerHTML = '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24">' + item.icon + "</svg>";
      option.addEventListener("click", () => { tool = kind; enabled = true; closeMenu(); showButton(); });
      list.append(option);
    }
    // A vászon területén (nem az eszköztárban: annak görgethető sávja levágná), a gomb fölött.
    (button.closest(".canvas-area, .passive-frame") ?? document.body).append(list);
    const box = button.getBoundingClientRect();
    list.style.left = box.left + "px";
    list.style.top = Math.max(8, box.top - list.offsetHeight - 6) + "px";
    list.querySelector('[aria-pressed="true"]')?.focus({preventScroll: true});
  }
  // `svg`: a vászon; `parent`: a munkalap-koordinátás réteg szülője; `area`: a vászon tárolója (itt fogjuk el az
  // eseményeket, mielőtt a szerkesztő kijelölne / pásztázna); `controls`: az eszköztár (a gomb ide kerül).
  function bind(svg, parent, area, controls, before = null) {
    listeners?.abort();
    unregister?.();
    unregister = null;
    closeMenu();
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
    showButton();
    // Méretváltáskor (ablak, panelek) a filcrajz újrarajzolódik.
    if (window.ResizeObserver) {
      const observer = new ResizeObserver(() => invalidate());
      observer.observe(overlay);
      listeners.signal.addEventListener("abort", () => observer.disconnect());
    }
    invalidate();
    if (!controls) return;
    button = document.createElement("button");
    button.type = "button";
    button.className = "button laser-tool quick-flyout-trigger";
    button.innerHTML = '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"></svg><span class="quick-flyout-mark" aria-hidden="true"></span>';
    button.setAttribute("aria-haspopup", "true");
    controls.insertBefore(button, before);
    showButton();
    // Hosszú nyomás (0,45 mp) vagy jobb kattintás: a választó; ilyenkor a kattintás nem kapcsol.
    let press = null, opened = false;
    button.addEventListener("pointerdown", event => {
      if (event.button !== 0) return;
      opened = false;
      clearTimeout(press);
      press = setTimeout(() => { opened = true; openMenu(); }, 450);
    }, options);
    for (const type of ["pointerup", "pointerleave", "pointercancel"]) button.addEventListener(type, () => clearTimeout(press), options);
    button.addEventListener("contextmenu", event => { event.preventDefault(); event.stopPropagation(); openMenu(); }, options);
    button.addEventListener("click", () => {
      if (opened) { opened = false; return; }
      closeMenu();
      enabled = !enabled;
      showButton();
    }, options);
    document.addEventListener("pointerdown", event => {
      if (menu && !menu.contains(event.target) && event.target !== button && !button.contains(event.target)) closeMenu();
    }, {...options, capture: true});
    document.addEventListener("keydown", event => { if (event.key === "Escape" && menu) closeMenu(); }, options);
    // Esc rajzmódban (vagy vonás közben): a saját rajz törlése mindenkinél – a folyó vonás is, a lézer halványuló vonala és
    // a filcrajz. Ha a rajzeszköz nincs bekapcsolva, az Esc a szokásos (nem töröl).
    document.addEventListener("keydown", event => {
      if (event.key !== "Escape" || !(active() || drawing) || event.target?.closest?.("input, textarea, select, [contenteditable]")) return;
      if (drawing) end(null);
      let marked = false;
      for (const [key, s] of strokes) if (s.owner === "own") { marked ||= s.kind === "marker"; strokes.delete(key); }
      markerEnded = -Infinity;
      // A többieknél: üres, lezárt filcvonás `clear` jelzéssel (a szerver a pontok nélküli üzenetet is továbbítja).
      if (marked) send({laser: true, stroke: ++counter, points: [], kind: "marker", clear: true, end: true});
      invalidate();
    }, {...options, capture: true});
    // D: egyszeri rajz a választott eszközzel (one-shot.js); a gomb csak fényes keretet kap, egy vonás után visszaáll.
    oneShot = {button, arm() { if (enabled) return false; once = true; showButton(); return true; },
      disarm() { once = false; showButton(); }};
    unregister = registerOneShot("d", oneShot);
    const inCanvas = event => event.target === overlay || svg.contains(event.target);
    let suppressClick = false;
    area.addEventListener("pointerdown", event => {
      if (!active() || event.button !== 0 || !inCanvas(event)) return;
      event.preventDefault();
      event.stopPropagation();
      if (!world(event)) return;
      // Ha az előző rajz felengedése elveszett, az most lezárul (különben a régi vonal az új kezdőpontig húzódna).
      if (drawing) end(null);
      area.setPointerCapture?.(event.pointerId);
      drawing = {id: ++counter, kind: tool, pointer: event.pointerId, last: null, raw: [], clear: false};
      // Filc: az előző rajz folytatása, ha az előző vonás vége óta kevesebb mint markerJoin telt el; különben az új vonás
      // törli az előző rajzot (nálunk most, a többieknél az első üzenet `clear` jelzésére).
      if (tool === "marker" && performance.now() - markerEnded >= markerJoin) {
        clearMarker("own");
        drawing.clear = true;
        invalidate();
      }
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
    // a vonal az utolsó pontnál ér véget. Egyszeri rajznál (D) az eszköz itt visszaáll.
    function end(event) {
      if (event?.type === "pointerup") sample(event, true);
      flush(true);
      const own = strokes.get("own:" + drawing.id);
      if (own) { own.ended = true; own.tip = null; }
      if (drawing.kind === "marker") markerEnded = performance.now();
      drawing = null;
      invalidate();
      if (oneShotArmed(oneShot)) oneShotUsed(oneShot);
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
    area.addEventListener("dblclick", event => { if (active() && inCanvas(event)) event.stopPropagation(); }, {...options, capture: true});
  }
  return {bind, receive, retain, invalidate,
    stop() { listeners?.abort(); unregister?.(); unregister = null; closeMenu(); receive(null); }};
}
