import {avatarSymbol} from "./presence.js";

// Ping hangja: rövid, csengő kéthangú szinuszjel (Web Audio, hangfájl nélkül). A böngésző csak felhasználói művelet
// után enged hangot, ezért az első kattintás / billentyű létrehozza és elindítja a hangkörnyezetet.
let audio;
function unlockAudio() {
  const Context = globalThis.AudioContext ?? globalThis.webkitAudioContext;
  if (!Context) return;
  audio ??= new Context();
  if (audio.state === "suspended") audio.resume().catch(() => {});
}
if (typeof document !== "undefined" && document.addEventListener) {
  for (const type of ["pointerdown", "keydown"]) document.addEventListener(type, unlockAudio, {capture: true, passive: true});
}
export function playPingSound() {
  if (!audio || audio.state !== "running") return;
  const start = audio.currentTime, end = start + .7;
  const volume = audio.createGain();
  volume.gain.setValueAtTime(.0001, start);
  volume.gain.exponentialRampToValueAtTime(.16, start + .012);
  volume.gain.exponentialRampToValueAtTime(.0001, end);
  volume.connect(audio.destination);
  for (const [frequency, level] of [[1318.5, 1], [1975.5, .3], [2637, .12]]) {
    const tone = audio.createOscillator(), gain = audio.createGain();
    tone.type = "sine";
    tone.frequency.setValueAtTime(frequency, start);
    tone.frequency.exponentialRampToValueAtTime(frequency * .985, end);
    gain.gain.value = level;
    tone.connect(gain).connect(volume);
    tone.start(start);
    tone.stop(end + .05);
  }
}

// A ping a küldő színével rajzolódik (`color`); szín nélkül a régi narancs.
export function flashNode(canvas, id, color) {
  const node = canvas?.querySelector('[data-node="' + CSS.escape(id) + '"]');
  if (!node) return;
  const width = Number(node.dataset.width), height = Number(node.dataset.height);
  flashPoint(node, {x: Number(node.dataset.x ?? 0), y: Number(node.dataset.y ?? 0)}, width+16, height+16, "node-ping", color);
}

// `kind`: az elem osztálya (node-ping: ping); az animáció végén eltűnik.
export function flashPoint(layer, point, width = 24, height = 24, kind = "node-ping", color = "#f58a16") {
  if (!layer) return;
  const frame = document.createElementNS("http://www.w3.org/2000/svg", "rect");
  for (const [key, value] of Object.entries({class: kind, "data-editor-only": "",
    x: point.x-width/2, y: point.y-height/2, width, height, rx: Math.min(12, width / 2),
    fill: "none", stroke: color, "stroke-width": 4, "pointer-events": "none"})) frame.setAttribute(key, value);
  frame.style.setProperty("--ping-color", color);
  layer.append(frame);
  frame.addEventListener("animationend", () => frame.remove(), {once: true});
}

// Képernyőn kívüli ping: a látható terület (`bounds`, képernyő-koordinátában) szélén nyíl mutat a ping felé, a küldő
// színével és avatarjával; a pinggel együtt halványul el. `locate()`: a ping helye a képernyőn (DOMRect), kattintáskor
// is újra lekérdezve; `jump(rect, bounds)`: a nézet odaigazítása. Ha a ping közepe jól láthatóan a területen belül
// van (a széleitől legalább `margin` pixelre), nem rajzol semmit; a szélén épp csak belógó vagy a panel alá eső ping is nyilat kap.
export function pingOffscreen(locate, bounds, {color, name, avatar}, jump, margin = 24) {
  const target = locate();
  if (!target || !bounds || bounds.width <= 0 || bounds.height <= 0) return null;
  const tx = (target.left + target.right) / 2, ty = (target.top + target.bottom) / 2;
  if (tx >= bounds.left + margin && tx <= bounds.right - margin && ty >= bounds.top + margin && ty <= bounds.bottom - margin) return null;
  const cx = bounds.left + bounds.width / 2, cy = bounds.top + bounds.height / 2;
  const dx = tx - cx, dy = ty - cy;
  const inset = 40;
  const reach = Math.min(Math.max(1, bounds.width / 2 - inset) / Math.abs(dx || 1e-9), Math.max(1, bounds.height / 2 - inset) / Math.abs(dy || 1e-9));
  const arrow = document.createElement("button");
  arrow.type = "button";
  arrow.className = "ping-arrow";
  arrow.title = (name ? name + " pingelt" : "Ping") + " – ugrás oda";
  arrow.setAttribute("aria-label", arrow.title);
  arrow.style.left = cx + dx * reach + "px";
  arrow.style.top = cy + dy * reach + "px";
  arrow.style.setProperty("--ping-color", color || "#f58a16");
  const pointer = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  pointer.setAttribute("class", "ping-arrow-pointer");
  pointer.setAttribute("viewBox", "-30 -30 60 60");
  pointer.setAttribute("aria-hidden", "true");
  pointer.innerHTML = '<path d="M29 0 17-9.5V9.5z" stroke="white" stroke-width="2" stroke-linejoin="round"/>';
  pointer.style.transform = "rotate(" + Math.atan2(dy, dx) + "rad)";
  arrow.append(pointer);
  if (avatar) arrow.append(avatarSymbol(avatar, color, "ping-arrow-avatar"));
  arrow.addEventListener("animationend", () => arrow.remove(), {once: true});
  arrow.addEventListener("click", () => {
    arrow.remove();
    const now = locate();
    if (now) jump(now, bounds);
  });
  (document.fullscreenElement ?? document.body).append(arrow);
  return arrow;
}

// A látható terület: az elem téglalapja az ablakra vágva; a megadott, fölötte lévő oldalpanelek (pl. a jobb oldali
// tulajdonságpanel) által takart sáv levonva.
export function visibleBounds(element, panels = []) {
  const rect = element?.getBoundingClientRect();
  if (!rect) return null;
  let left = Math.max(rect.left, 0), top = Math.max(rect.top, 0);
  let right = Math.min(rect.right, innerWidth), bottom = Math.min(rect.bottom, innerHeight);
  for (const panel of panels) {
    const p = panel?.getBoundingClientRect();
    if (!p || !p.width || !p.height || p.bottom <= top || p.top >= bottom) continue;
    if (p.left > (left + right) / 2 && p.left < right) right = p.left;
    else if (p.right < (left + right) / 2 && p.right > left) left = p.right;
  }
  return new DOMRect(left, top, Math.max(0, right - left), Math.max(0, bottom - top));
}
