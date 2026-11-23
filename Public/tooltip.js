// Buboréksúgó összecsukott / túl hosszú szöveghez (szerkesztő és megtekintő).
// A doboz helyén jelenik meg és kitakarja azt; a teljes szöveg görgethető (egérgörgő, jobb oldali görgetősáv).
// Nyitva marad, amíg az egér a buboréksúgón van; elhagyásakor bezárul.
let timer, request, tooltip;

export function hideTooltip(event) {
  // A doboz elhagyása a buboréksúgóra (ami a dobozt takarja): nyitva marad.
  if (tooltip && event?.relatedTarget && tooltip.contains(event.relatedTarget)) return;
  clearTimeout(timer);
  request?.abort();
  tooltip?.remove();
  tooltip = null;
}

export function showTooltip(event, render, justified) {
  hideTooltip();
  const {currentTarget} = event;
  const signal = (request = new AbortController()).signal;
  timer = setTimeout(async () => {
    try {
      const html = await render(signal);
      if (signal.aborted || !currentTarget.isConnected) return;
      // A látható doboz (fájldoboz teste, illetve a doboz felülete), nem a felette/alatta lévő feliratok.
      const anchor = currentTarget.querySelector?.(".node-file, .node-surface, .node-site-preview") ?? currentTarget;
      const box = anchor.getBoundingClientRect();
      tooltip = document.createElement("div");
      tooltip.className = "formatted-text canvas-tooltip";
      if (justified) tooltip.classList.add("justified-text");
      tooltip.setAttribute("role", "tooltip");
      tooltip.innerHTML = html;
      // Méret: csak amennyi a szövegnek kell; felső határ a doboz mérete (de legalább olvasható), és a képernyő.
      // Ha a szöveg ennél hosszabb, görgethető. A doboz közepére kerül.
      const margin = 8;
      const maxWidth = Math.min(Math.max(box.width, 360), innerWidth - 2 * margin);
      const maxHeight = Math.min(Math.max(box.height, 240), innerHeight - 2 * margin);
      Object.assign(tooltip.style, {visibility: "hidden", width: "max-content", maxWidth: maxWidth + "px", maxHeight: maxHeight + "px"});
      document.body.append(tooltip);
      const {width, height} = tooltip.getBoundingClientRect();
      const left = Math.max(margin, Math.min(box.left + box.width / 2 - width / 2, innerWidth - width - margin));
      const top = Math.max(margin, Math.min(box.top + box.height / 2 - height / 2, innerHeight - height - margin));
      Object.assign(tooltip.style, {left: left + "px", top: top + "px", visibility: ""});
      tooltip.addEventListener("pointerleave", () => hideTooltip());
      tooltip.addEventListener("pointerdown", () => hideTooltip());
    } catch { /* Hover previews are optional when disconnected. */ }
  }, 350);
}
