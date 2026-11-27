import {avatarSymbol, cursorLabelMode, setCursorLabelMode} from "./presence.js";
import {screenMatrix} from "./screen-matrix.js";

// The layer's coordinate system is the worksheet, including the editor's pan and zoom. The markers keep their
// screen size (counter-scaled by the zoom), so the name or avatar beside them stays readable at any zoom level.
export function sharedMouse(send) {
  const ns = "http://www.w3.org/2000/svg";
  const cursors = new Map();
  let layer, root, enabled = false, pending, timer, listeners, modeList = null;
  let labelMode = cursorLabelMode();
  function hide() {
    clearTimeout(timer);
    timer = undefined;
    if (pending) send(null);
    pending = null;
  }
  function screenScale() {
    // A jelölők a vászonnal együtt skálázódnak; a képernyő-lépték a Safari-biztos leképezésből (screen-matrix.js).
    const matrix = screenMatrix(layer, root);
    return matrix?.a ? 1 / matrix.a : 1;
  }
  function place(marker, scale = screenScale()) {
    const {x, y} = marker.point;
    marker.setAttribute("transform", "translate(" + x + " " + y + ") scale(" + scale + ")");
  }
  // A kurzor melletti címke: a néző választása szerint a név (színes címkében), az avatar (a felhasználó színével), vagy
  // csak az avatar, nyíl nélkül (ilyenkor az avatar maga a mutató).
  function label(marker) {
    const {name, avatar, color} = marker.peer;
    marker.querySelector(".peer-cursor-label")?.remove();
    const only = labelMode === "avatar-only";
    marker.firstChild.style.display = only ? "none" : "";
    const group = document.createElementNS(ns, "g");
    group.setAttribute("class", "peer-cursor-label");
    if (labelMode === "avatar" || only) {
      const icon = avatarSymbol(avatar || 1, color, "peer-cursor-avatar");
      for (const [key, value] of Object.entries({x: only ? -3 : 11, y: only ? -3 : 13, width: only ? 24 : 20, height: only ? 24 : 20,
        stroke: "white", "stroke-width": 3, "paint-order": "stroke", "stroke-linejoin": "round"})) icon.setAttribute(key, value);
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
  // A többiek kurzorának megjelenése: a kurzorgomb csoportja (hosszú nyomás vagy jobb kattintás nyitja).
  const arrowIcon = '<path fill="currentColor" d="M4 2l4 19 4-7 8-3z"/>';
  const modes = [
    ["avatar-only", "Kurzorok: csak avatar", '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><use href="/icons/avatar-1.svg#a" fill="currentColor"/></svg>'],
    ["avatar", "Kurzorok: nyíl + avatar", '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><path fill="currentColor" d="M2 1l3 13 3-4.6 5.4-2z"/><svg x="9" y="9" width="15" height="15" viewBox="0 0 24 24"><use href="/icons/avatar-1.svg#a" fill="currentColor"/></svg></svg>'],
    ["name", "Kurzorok: nyíl + név", '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24"><path fill="currentColor" d="M2 1l3 13 3-4.6 5.4-2z"/><path fill="currentColor" d="M11 12h11v2.6h-4.2V23h-2.6v-8.4H11z"/></svg>'],
  ];
  function closeModes() {
    modeList?.remove();
    modeList = null;
  }
  function openModes(button) {
    closeModes();
    const list = modeList = document.createElement("div");
    list.className = "quick-flyout-list open-column cursor-modes";
    list.setAttribute("role", "group");
    list.setAttribute("aria-label", "A többiek kurzorának megjelenése");
    for (const [mode, title, svg] of modes) {
      const option = document.createElement("button");
      option.type = "button";
      option.className = "button option-icon";
      option.title = title;
      option.setAttribute("aria-label", title);
      option.setAttribute("aria-pressed", String(labelMode === mode));
      option.innerHTML = svg;
      option.addEventListener("click", () => {
        labelMode = mode;
        setCursorLabelMode(mode);
        for (const marker of cursors.values()) label(marker);
        closeModes();
      });
      list.append(option);
    }
    // A vászon területén (nem az eszköztárban: annak görgethető sávja levágná), a gomb fölött.
    (button.closest(".canvas-area, .passive-frame") ?? document.body).append(list);
    const box = button.getBoundingClientRect();
    list.style.left = box.left + "px";
    list.style.top = Math.max(8, box.top - list.offsetHeight - 6) + "px";
    list.querySelector('[aria-pressed="true"]')?.focus({preventScroll: true});
  }
  function bind(svg, parent, controls, before = null) {
    listeners?.abort();
    hide();
    listeners = new AbortController();
    const options = {signal: listeners.signal};
    root = svg;
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
    button.className = "button mouse-share quick-flyout-trigger";
    button.title = "Saját egérmutató megosztása (nyomva tartva vagy jobb kattintásra: a többiek kurzorának megjelenése)";
    button.setAttribute("aria-label", "Saját egérmutató megosztása");
    button.setAttribute("aria-haspopup", "true");
    button.setAttribute("aria-pressed", String(enabled));
    button.innerHTML = '<svg class="ui-icon" aria-hidden="true" viewBox="0 0 24 24">' + arrowIcon + '</svg><span class="quick-flyout-mark" aria-hidden="true"></span>';
    controls.insertBefore(button, before);
    // Hosszú nyomás (0,45 mp) vagy jobb kattintás: a megjelenési módok listája; ilyenkor a kattintás nem kapcsol.
    let press = null, opened = false;
    button.addEventListener("pointerdown", event => {
      if (event.button !== 0) return;
      opened = false;
      clearTimeout(press);
      press = setTimeout(() => { opened = true; openModes(button); }, 450);
    }, options);
    for (const type of ["pointerup", "pointerleave", "pointercancel"]) button.addEventListener(type, () => clearTimeout(press), options);
    button.addEventListener("contextmenu", event => { event.preventDefault(); event.stopPropagation(); openModes(button); }, options);
    button.addEventListener("click", () => {
      if (opened) { opened = false; return; }
      closeModes();
      enabled = !enabled;
      button.setAttribute("aria-pressed", String(enabled));
      if (!enabled) hide();
    }, options);
    document.addEventListener("pointerdown", event => {
      if (modeList && !modeList.contains(event.target) && event.target !== button && !button.contains(event.target)) closeModes();
    }, {...options, capture: true});
    document.addEventListener("keydown", event => { if (event.key === "Escape" && modeList) closeModes(); }, options);
    svg.addEventListener("pointermove", event => {
      // Nem aktív ablak fölött is jön pointermove (macOS): ilyenkor a kurzor nem látszik a többieknél.
      if (!enabled || event.pointerType === "touch" || document.hidden || !document.hasFocus()) return;
      const matrix = screenMatrix(layer, root);
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
  return {bind, receive, rescale, stop() { hide(); closeModes(); listeners?.abort(); receive(null); }};
}
