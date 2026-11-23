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
      // Méret: legalább a doboz, a szöveghez legalább olvasható szélesség; mindig a képernyőn belül.
      const margin = 8;
      const width = Math.min(Math.max(box.width, 260), innerWidth - 2 * margin);
      const height = Math.min(Math.max(box.height, 160), innerHeight - 2 * margin);
      const left = Math.max(margin, Math.min(box.left + box.width / 2 - width / 2, innerWidth - width - margin));
      const top = Math.max(margin, Math.min(box.top, innerHeight - height - margin));
      Object.assign(tooltip.style, {left: left + "px", top: top + "px", width: width + "px", maxHeight: height + "px",
        minHeight: Math.min(box.height, height) + "px"});
      tooltip.addEventListener("pointerleave", () => hideTooltip());
      tooltip.addEventListener("pointerdown", () => hideTooltip());
      document.body.append(tooltip);
    } catch { /* Hover previews are optional when disconnected. */ }
  }, 350);
}
