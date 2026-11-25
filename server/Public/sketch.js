// Szabadkézi (filc) rajz a téma `graphics.sketch` beállításához. A doboz körvonala helyett kissé remegő,
// a sarkoknál túlfutó, egyszer-kétszer átrajzolt vonal; a remegés a doboz azonosítójából számolódik (álvéletlen),
// így minden újrarajzoláskor és az SVG-exportban is ugyanaz. A szerveroldali pár: Rendering.swift `SketchPen`
// (ugyanaz az algoritmus és ugyanaz az álvéletlen-sorozat; a két oldal a Tests/Fixtures/sketch.json mintáin egyezik).
// A kattintható terület és a szöveg helye a szabályos alak marad (editor.js shape), csak a rajz szabálytalan.

// Az azonosító 32 bites hash-e (FNV-1a, a slug ASCII karakterein).
export function sketchSeed(text) {
  let hash = 2166136261;
  for (let i = 0; i < text.length; i++) { hash ^= text.charCodeAt(i) & 255; hash = Math.imul(hash, 16777619); }
  return hash >>> 0;
}

// Mulberry32 álvéletlen-generátor (Rendering.swift SketchRandom).
function generator(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6D2B79F5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const round = value => Math.round(value * 10) / 10;
const pair = (x, y) => round(x) + " " + round(y);

// A lekerekített doboz szabadkézi változata enyhén letört sarkú: így a remegő vonal „kerekítettnek” hat.
export function sketchOutline(shape, width, height, vertices) {
  const x = width / 2, y = height / 2;
  if (shape === "ellipse") return {ellipse: [x, y]};
  if (vertices) return {points: vertices};
  const cut = shape === "rounded" ? Math.min(x, y, 9) : 0;
  return {points: cut ? [[-x+cut,-y], [x-cut,-y], [x,-y+cut], [x,y-cut], [x-cut,y], [-x+cut,y], [-x,y-cut], [-x,-y+cut]]
    : [[-x,-y], [x,-y], [x,y], [-x,y]]};
}

// Egy oldal: köbös görbe két, egymástól függetlenül kitérített segédponttal (enyhe kettős hullám), a végein
// túlfutással (`over`) és elmozdulással.
function side(random, [ax, ay], [bx, by], rough, over) {
  const dx = bx - ax, dy = by - ay, length = Math.hypot(dx, dy) || 1;
  const ux = dx / length, uy = dy / length, nx = -uy, ny = ux;
  const bow = rough * Math.min(3.2, .6 + length / 90);
  const jitter = () => (random() - .5) * 2 * rough;
  const start = over ? (.4 + random() * .8) * over : 0, end = over ? (.4 + random() * .8) * over : 0;
  const a = [ax - ux * start + jitter() * .6, ay - uy * start + jitter() * .6];
  const b = [bx + ux * end + jitter() * .6, by + uy * end + jitter() * .6];
  const k1 = (random() - .5) * 2 * bow, k2 = (random() - .5) * 2 * bow;
  const c1 = [ax + dx / 3 + nx * k1, ay + dy / 3 + ny * k1];
  const c2 = [ax + dx * 2 / 3 + nx * k2, ay + dy * 2 / 3 + ny * k2];
  return {a, b, c1, c2};
}

// Ellipszis: másodfokú szakaszok a felezőpontokon át. A körvonal (`open`) egyetlen vonal, amely a bal oldalon indul,
// és ott nem ér össze pontosan: a sugara körbe haladva kicsit nő vagy fogy, a vége kicsit túlfut vagy elmarad.
function loop(random, rx, ry, rough, open) {
  const steps = Math.max(12, Math.min(28, Math.round((rx + ry) / 14)));
  let start = random() * Math.PI * 2, sweep = Math.PI * 2, drift = 0;
  if (open) {
    start = Math.PI + (start / (Math.PI * 2) - .5) * .5;
    sweep += (random() - .35) * .3;
    const size = rough * (1.2 + random() * 1.8);
    drift = random() < .5 ? -size : size;
  }
  const points = [];
  for (let i = 0; i <= steps; i++) {
    const angle = start + sweep * i / steps, wobble = (random() - .5) * 2 * rough + drift * i / steps;
    points.push([Math.cos(angle) * (rx + wobble), Math.sin(angle) * (ry + wobble)]);
  }
  const middle = (p, q) => [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2];
  let d = "M" + pair(...points[0]);
  for (let i = 1; i < points.length - 1; i++) d += " Q" + pair(...points[i]) + " " + pair(...middle(points[i], points[i + 1]));
  return d + " L" + pair(...points.at(-1));
}

// Sarkos alak körvonala egyetlen folytonos vonalként: a bal felső saroktól körbe, oldalanként enyhén hajló görbével;
// a vége kicsit túlfut a kezdőponton és mellé csúszik (nem zárul tökéletesen).
function line(random, points, rough) {
  const jitter = () => (random() - .5) * 2 * rough * .6;
  let x = points[0][0] + jitter(), y = points[0][1] + jitter();
  let d = "M" + pair(x, y);
  for (let i = 0; i < points.length; i++) {
    const last = i === points.length - 1;
    const over = last ? rough * (2 + random() * 3) : 0, aside = last ? rough * (random() - .2) * 2 : 0;
    const [tx, ty] = points[(i + 1) % points.length];
    const dx = tx - x, dy = ty - y, length = Math.hypot(dx, dy) || 1, nx = -dy / length, ny = dx / length;
    const ex = tx + dx / length * over + nx * aside + jitter(), ey = ty + dy / length * over + ny * aside + jitter();
    const bow = rough * Math.min(3.2, .6 + length / 90);
    const k1 = (random() - .5) * 2 * bow, k2 = (random() - .5) * 2 * bow;
    d += " C" + pair(x + dx / 3 + nx * k1, y + dy / 3 + ny * k1) + " " + pair(x + dx * 2 / 3 + nx * k2, y + dy * 2 / 3 + ny * k2) + " " + pair(ex, ey);
    x = ex; y = ey;
  }
  return d;
}

const cache = new Map();
// {fill, strokes}: a kitöltés zárt alakja és a `passes` darab körvonal-útvonal. Gyorsítótárazott (a doboz húzásakor a
// mérete nem változik, a rajzot nem kell újraszámolni).
export function sketchPaths(seed, outline, rough = 1.2, passes = 2) {
  const key = seed + "|" + rough + "|" + passes + "|" + JSON.stringify(outline);
  const known = cache.get(key);
  if (known) return known;
  if (cache.size > 4000) cache.clear();
  const random = generator(seed);
  let fill, strokes = [];
  if (outline.ellipse) {
    const [rx, ry] = outline.ellipse;
    fill = loop(random, rx, ry, rough * .5, false) + "Z";
    for (let pass = 0; pass < passes; pass++) strokes.push(loop(random, rx, ry, rough, true));
  } else {
    const points = outline.points;
    const edges = points.map((point, i) => side(random, point, points[(i + 1) % points.length], rough * .5, 0));
    fill = "M" + pair(...edges[0].a) + edges.map(e => " C" + pair(...e.c1) + " " + pair(...e.c2) + " " + pair(...e.b)).join("") + "Z";
    for (let pass = 0; pass < passes; pass++) strokes.push(line(random, points, rough));
  }
  const result = {fill, strokes};
  cache.set(key, result);
  return result;
}

// A vonal második, kissé elcsúsztatott húzása (szabadkézi hatás); az eltolás a vonal azonosítójából.
export function sketchShift(seed, rough) {
  const random = generator(seed ^ 0x9E3779B9);
  return [round((random() - .5) * 2.4 * rough), round((random() - .5) * 2.4 * rough)];
}

// A cetli színe: a doboz saját színe fehérrel félig keverve (papírszín); alapszínnél (2) a paletta sárgája (6).
export function stickyColor(hex) {
  const value = parseInt(hex.slice(1), 16);
  return "#" + [16, 8, 0].map(shift => Math.round(((value >> shift) & 255) * .5 + 255 * .5).toString(16).padStart(2, "0")).join("");
}
