// Buboréksúgó összecsukott / túl hosszú szöveghez (szerkesztő és megtekintő).
// Az egérmutatótól 32 px-re jelenik meg, abba az irányba, amerre több hely van; sosem lóg ki a képernyőről.
// Csak akkora, amekkora a szövegnek kell; hosszabb szövegnél görgethető (egérgörgő, jobb oldali görgetősáv).
// Áttűnéssel jelenik meg és tűnik el (0,25 s, mint a doboz alatti Text – app.css); csökkentett mozgásnál azonnal.
// A dobozt elhagyva rövid ideig nyitva marad, hogy az egérrel rá lehessen menni görgetni.
const fade = 250, grace = 400, gap = 32, margin = 8;
let timer, closing, request, tooltip, owner, pointer = {x: 0, y: 0};

const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

function track(event) { pointer = {x: event.clientX, y: event.clientY}; }

function close() {
  clearTimeout(timer);
  clearTimeout(closing);
  request?.abort();
  owner?.classList.remove("tooltip-open");
  owner?.removeEventListener("pointermove", track);
  owner = null;
  const leaving = tooltip;
  tooltip = null;
  if (!leaving) return;
  if (reducedMotion()) { leaving.remove(); return; }
  leaving.style.opacity = "0";
  leaving.style.pointerEvents = "none";
  setTimeout(() => leaving.remove(), fade);
}

export function hideTooltip(event) {
  // A doboz elhagyása: rövid türelmi idő, hogy az egér átérhessen a súgóra.
  if (event?.type === "pointerleave" && tooltip) {
    if (tooltip.contains(event.relatedTarget)) return;
    clearTimeout(closing);
    closing = setTimeout(close, grace);
    return;
  }
  close();
}

// `colors`: {background, color} – a doboz színe; ha hiányzik, a doboz rajzából olvassa ki (megtekintő).
export function showTooltip(event, render, justified, colors) {
  close();
  const {currentTarget} = event;
  track(event);
  owner = currentTarget;
  owner.addEventListener("pointermove", track);
  const signal = (request = new AbortController()).signal;
  timer = setTimeout(async () => {
    try {
      const html = await render(signal);
      if (signal.aborted || !currentTarget.isConnected) return;
      const anchor = currentTarget.querySelector?.(".node-file, .node-surface, .node-site-preview") ?? currentTarget;
      const box = anchor.getBoundingClientRect();
      tooltip = document.createElement("div");
      tooltip.className = "formatted-text canvas-tooltip";
      if (justified) tooltip.classList.add("justified-text");
      tooltip.setAttribute("role", "tooltip");
      tooltip.innerHTML = html;
      const {background, color} = colors ?? boxColors(currentTarget, anchor);
      if (background) tooltip.style.background = background;
      if (color) tooltip.style.color = color;
      // Méret: csak amennyi a szövegnek kell; felső határ a doboz mérete (de legalább olvasható) és a képernyő.
      const maxWidth = Math.min(Math.max(box.width, 360), innerWidth - 2 * margin);
      const maxHeight = Math.min(Math.max(box.height, 240), innerHeight - 2 * margin);
      Object.assign(tooltip.style, {visibility: "hidden", opacity: "0", width: "max-content",
        maxWidth: maxWidth + "px", maxHeight: maxHeight + "px"});
      document.body.append(tooltip);
      const {width, height} = tooltip.getBoundingClientRect();
      // Irány: vízszintesen és függőlegesen is arra, amerre több hely van; utána a képernyőn belülre szorítva.
      const right = innerWidth - pointer.x >= pointer.x, below = innerHeight - pointer.y >= pointer.y;
      const clamp = (value, size, limit) => Math.max(margin, Math.min(value, limit - size - margin));
      const left = clamp(right ? pointer.x + gap : pointer.x - gap - width, width, innerWidth);
      const top = clamp(below ? pointer.y + gap : pointer.y - gap - height, height, innerHeight);
      Object.assign(tooltip.style, {left: left + "px", top: top + "px", visibility: ""});
      tooltip.addEventListener("pointerenter", () => clearTimeout(closing));
      tooltip.addEventListener("pointerleave", event => { if (!owner?.contains(event.relatedTarget)) close(); });
      tooltip.addEventListener("pointerdown", () => close());
      // A doboz alatti Text elhalványul (app.css: .tooltip-open), a súgó ugyanolyan ütemben jelenik meg.
      currentTarget.classList.add("tooltip-open");
      requestAnimationFrame(() => { if (tooltip) tooltip.style.opacity = "1"; });
    } catch { /* Hover previews are optional when disconnected. */ }
  }, 350);
}

// A doboz kitöltő- és szövegszíne a rajzból (SVG felület vagy fájldoboz-teste).
function boxColors(target, anchor) {
  const usable = value => value && !/^(none|transparent|rgba\(0, 0, 0, 0\))$/.test(value) && !value.startsWith("url(") ? value : null;
  const style = getComputedStyle(anchor);
  const background = usable(anchor instanceof SVGElement ? style.fill : style.backgroundColor);
  const ink = target.querySelector?.("[data-file-ink]")?.dataset.fileInk
    ?? target.querySelector?.(".node-text tspan")?.getAttribute("fill")
    ?? target.querySelector?.(".node-below")?.style.color;
  return {background, color: usable(ink)};
}
