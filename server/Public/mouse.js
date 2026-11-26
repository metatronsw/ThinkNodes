import {avatarSymbol, cursorLabelMode, setCursorLabelMode} from "./presence.js";

// The layer's coordinate system is the worksheet, including the editor's pan and zoom. The markers keep their
// screen size (counter-scaled by the zoom), so the name or avatar beside them stays readable at any zoom level.
export function sharedMouse(send) {
  const ns = "http://www.w3.org/2000/svg";
  const cursors = new Map();
  let layer, enabled = false, pending, timer, listeners, labelButton;
  let labelMode = cursorLabelMode();
  function hide() {
    clearTimeout(timer);
    timer = undefined;
    if (pending) send(null);
    pending = null;
  }
  function screenScale() {
    const matrix = layer?.isConnected ? layer.getScreenCTM() : null;
    return matrix?.a ? 1 / matrix.a : 1;
  }
  function place(marker, scale = screenScale()) {
    const {x, y} = marker.point;
    marker.setAttribute("transform", "translate(" + x + " " + y + ") scale(" + scale + ")");
  }
  // A kurzor melletti címke: a néző választása szerint a név (színes címkében) vagy az avatar (a felhasználó színével).
  function label(marker) {
    const {name, avatar, color} = marker.peer;
    marker.querySelector(".peer-cursor-label")?.remove();
    const group = document.createElementNS(ns, "g");
    group.setAttribute("class", "peer-cursor-label");
    if (labelMode === "avatar") {
      const icon = avatarSymbol(avatar || 1, color, "peer-cursor-avatar");
      for (const [key, value] of Object.entries({x: 11, y: 13, width: 20, height: 20, stroke: "white", "stroke-width": 3,
        "paint-order": "stroke", "stroke-linejoin": "round"})) icon.setAttribute(key, value);
      group.append(icon);
    } else {
      const pill = document.createElementNS(ns, "rect");
      const text = document.createElementNS(ns, "text");
      text.textContent = name;
      for (const [key, value] of Object.entries({x: 19, y: 28, "font-size": 11, "font-weight": 650, fill: "white"})) text.setAttribute(key, value);
      for (const [key, value] of Object.entries({x: 13, y: 16, height: 17, rx: 4, fill: color})) pill.setAttribute(key, value);
      group.append(pill, text);
      marker.append(group);
      // A szöveg szélessége csak a dokumentumban mérhető; ha nincs ott, becsült.
      const width = (text.isConnected && text.getComputedTextLength()) || name.length * 6.4;
      pill.setAttribute("width", Math.ceil(width) + 12);
      return;
    }
    marker.append(group);
  }
  function receive(frame) {
    if (!frame) {
      cursors.clear();
      layer?.replaceChildren();
      return;
    }
    let marker = cursors.get(frame.cursor);
    if (!frame.point) {
      marker?.remove();
      cursors.delete(frame.cursor);
      return;
    }
    const peer = {name: frame.name ?? "", avatar: frame.avatar, color: frame.color};
    if (!marker) {
      marker = document.createElementNS(ns, "g");
      marker.setAttribute("class", "peer-cursor");
      const arrow = document.createElementNS(ns, "path");
      arrow.setAttribute("d", "M0 0L4 18L8 12L15 10Z");
      arrow.setAttribute("stroke", "white");
      marker.append(arrow);
      cursors.set(frame.cursor, marker);
      layer?.append(marker);
    }
    marker.point = frame.point;
    if (JSON.stringify(marker.peer) !== JSON.stringify(peer)) {
      marker.peer = peer;
      marker.firstChild.setAttribute("fill", peer.color);
      label(marker);
    }
    place(marker);
  }
  // A nézet (nagyítás) változásakor a kurzorok mérete a képernyőn változatlan marad.
  function rescale() {
    const scale = screenScale();
    for (const marker of cursors.values()) place(marker, scale);
  }
  function showLabelMode() {
    if (!labelButton) return;
    const avatar = labelMode === "avatar";
    labelButton.title = avatar ? "Kurzorok mellett: avatar (váltás névre)" : "Kurzorok mellett: név (váltás avatarra)";
    labelButton.setAttribute("aria-label", labelButton.title);
    labelButton.innerHTML = avatar
      ? '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><use href="/icons/avatar-1.svg#a" fill="currentColor"/></svg>'
      : '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><path fill="currentColor" d="M4 4h16v3.4h-6.3V20h-3.4V7.4H4z"/></svg>';
  }
  function bind(svg, parent, controls, before = null) {
    listeners?.abort();
    hide();
    listeners = new AbortController();
    const options = {signal: listeners.signal};
    layer?.remove();
    layer = document.createElementNS(ns, "g");
    layer.setAttribute("data-editor-only", "");
    layer.setAttribute("pointer-events", "none");
    layer.setAttribute("aria-hidden", "true");
    parent.append(layer);
    layer.append(...cursors.values());
    for (const marker of cursors.values()) label(marker);
    rescale();
    if (!controls) return;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "button mouse-share";
    button.title = "Saját egérmutató megosztása";
    button.setAttribute("aria-label", button.title);
    button.setAttribute("aria-pressed", String(enabled));
    button.innerHTML = '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><path fill="currentColor" d="M4 2l4 19 4-7 8-3z"/></svg>';
    controls.insertBefore(button, before);
    labelButton = document.createElement("button");
    labelButton.type = "button";
    labelButton.className = "button cursor-label";
    showLabelMode();
    controls.insertBefore(labelButton, before);
    labelButton.addEventListener("click", () => {
      labelMode = labelMode === "avatar" ? "name" : "avatar";
      setCursorLabelMode(labelMode);
      showLabelMode();
      for (const marker of cursors.values()) label(marker);
    }, options);
    button.addEventListener("click", () => {
      enabled = !enabled;
      button.setAttribute("aria-pressed", String(enabled));
      if (!enabled) hide();
    }, options);
    svg.addEventListener("pointermove", event => {
      // Nem aktív ablak fölött is jön pointermove (macOS): ilyenkor a kurzor nem látszik a többieknél.
      if (!enabled || event.pointerType === "touch" || document.hidden || !document.hasFocus()) return;
      const matrix = layer.getScreenCTM();
      if (!matrix) return;
      const {x, y} = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
      pending = {x, y};
      if (!timer) timer = setTimeout(() => { timer = undefined; send(pending); }, 50);
    }, options);
    svg.addEventListener("pointerleave", hide, options);
    window.addEventListener("blur", hide, options);
    document.addEventListener("visibilitychange", () => { if (document.hidden) hide(); }, options);
    window.addEventListener("pagehide", hide, options);
  }
  return {bind, receive, rescale, stop() { hide(); listeners?.abort(); receive(null); }};
}
