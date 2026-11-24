// Saját görgetősáv a vászon HTML-dobozaihoz (szövegfájl, CSV, táblázat) Safariban.
//
// A Safari (WebKit) nem húzza a natív görgetősávot, ha a görgethető elem SVG foreignObject-ben van, és fölötte
// SVG-transzform áll (eltolásnál a függőleges, nagyításnál mindkét sáv halott; a görgő működik). A vásznon minden
// doboz ilyen. A natív sávra nyomott egér mozgását a WebKit a sávnak adja, a lapnak nem, ezért kívülről sem
// pótolható. Megoldás: WebKitben a natív sáv rejtve van, helyette a görgethető elem mellé (nem fölé) saját sávok
// kerülnek. Normál elrendezésben állnak (rács, margó), mert a foreignObject-beli pozicionált elemeket a Safari
// rossz helyre teszi. Más böngészőben a natív sáv működik, ott nem történik semmi.
const webkit = typeof window !== "undefined" && "GestureEvent" in window;
const attached = new WeakMap();

function bar(axis) {
  const track = document.createElement("div"), thumb = document.createElement("div");
  track.className = "tn-sb tn-sb-" + axis;
  thumb.className = "tn-sb-thumb";
  track.append(thumb);
  return {track, thumb};
}

// A görgethető elem (el) szülője csak ezt az egy elemet tartalmazhatja; a sávok mellé kerülnek.
// Többször is hívható (pl. újrarajzolás után): frissíti a hüvelykek méretét és helyét.
export function attachScrollbars(el) {
  if (!webkit || !el?.parentElement) return;
  let state = attached.get(el);
  if (!state) {
    const host = el.parentElement;
    for (const old of host.querySelectorAll(":scope > .tn-sb")) old.remove();
    host.classList.add("tn-sb-host");
    el.classList.add("tn-sb-native-off");
    state = {host, y: bar("y"), x: bar("x")};
    host.append(state.y.track, state.x.track);
    attached.set(el, state);
    const update = () => attachScrollbars(el);
    el.addEventListener("scroll", update, {passive: true});
    state.observer = new ResizeObserver(update);
    state.observer.observe(el);
    for (const [axis, {track}] of [["y", state.y], ["x", state.x]]) {
      track.addEventListener("pointerdown", event => press(event, el, state, axis));
      for (const type of ["mousedown", "touchstart", "click", "dblclick", "contextmenu"]) track.addEventListener(type, event => event.stopPropagation());
    }
  }
  for (const axis of ["y", "x"]) {
    const vertical = axis === "y", {track, thumb} = state[axis];
    const view = vertical ? el.clientHeight : el.clientWidth, full = vertical ? el.scrollHeight : el.scrollWidth;
    const range = full - view;
    track.hidden = range <= 0;
    if (range <= 0) continue;
    const length = vertical ? track.clientHeight : track.clientWidth;
    const size = Math.max(20, Math.min(length, length * view / full)), travel = Math.max(0, length - size);
    const offset = travel * (vertical ? el.scrollTop : el.scrollLeft) / range;
    thumb.style[vertical ? "height" : "width"] = size + "px";
    thumb.style[vertical ? "marginTop" : "marginLeft"] = offset + "px";
    state[axis].metrics = {range, size, travel};
  }
}

export function detachScrollbars(el) {
  const state = attached.get(el);
  if (!state) return;
  state.observer.disconnect();
  state.y.track.remove();
  state.x.track.remove();
  state.host.classList.remove("tn-sb-host");
  attached.delete(el);
}

function press(event, el, state, axis) {
  event.stopPropagation();
  if (event.button) return;
  event.preventDefault();
  attachScrollbars(el);
  const vertical = axis === "y", {track, metrics} = state[axis];
  if (!metrics) return;
  // A hely a sáv saját (nagyítás előtti) képpontjaiban; a vászon nagyítása a mért és a tényleges méret aránya.
  const along = e => {
    const bounds = track.getBoundingClientRect();
    return vertical ? (e.clientY - bounds.top) / (bounds.height / (track.offsetHeight || 1) || 1)
      : (e.clientX - bounds.left) / (bounds.width / (track.offsetWidth || 1) || 1);
  };
  const read = () => vertical ? el.scrollTop : el.scrollLeft;
  const write = value => { if (vertical) el.scrollTop = value; else el.scrollLeft = value; };
  const {range, size, travel} = metrics;
  if (travel <= 0) return;
  // A hüvelyken kívül (a sínen) lenyomva a hüvelyk közepe a kattintás alá ugrik, és onnan húzható tovább.
  const start = along(event), thumbStart = read() / range * travel;
  if (start < thumbStart || start > thumbStart + size) write((start - size / 2) / travel * range);
  const scrolled = read();
  const move = e => { e.preventDefault(); write(scrolled + (along(e) - start) / travel * range); };
  const end = () => {
    window.removeEventListener("pointermove", move, true);
    window.removeEventListener("pointerup", end, true);
    window.removeEventListener("pointercancel", end, true);
  };
  window.addEventListener("pointermove", move, true);
  window.addEventListener("pointerup", end, true);
  window.addEventListener("pointercancel", end, true);
}
