// Jelenlét megjelenítése: a felhasználók avatarja a saját színükkel. Az avatarok fekete alakzatok
// (/icons/avatar-N.svg, benne a `#a` csoport), a színt a `fill` öröklése adja (stílus-attribútum nélkül).
const ns = "http://www.w3.org/2000/svg";

export function avatarSymbol(avatar, color, className = "peer-avatar") {
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("class", className);
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  if (color) svg.setAttribute("fill", color);
  const use = document.createElementNS(ns, "use");
  use.setAttribute("href", "/icons/avatar-" + avatar + ".svg#a");
  svg.append(use);
  return svg;
}

// A kurzorok mellett a név vagy az avatar látszik; ezt mindenki maga választja (eszköztár), a böngészőben tárolva.
const labelKey = "thinknodes:cursor-label";
export function cursorLabelMode() {
  // "name": nyíl + név, "avatar": nyíl + avatar, "avatar-only": csak az avatar (az a mutató).
  try { const mode = localStorage.getItem(labelKey); return ["avatar", "avatar-only"].includes(mode) ? mode : "name"; } catch { return "name"; }
}
export function setCursorLabelMode(mode) {
  try { localStorage.setItem(labelKey, mode); } catch {}
}
