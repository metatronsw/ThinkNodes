import {openPresentation} from "./web-presentations.js";
import {refreshWebPreviews} from "./web-preview-refresh.js";
import {fetchPage, updateSection, watchPageUpdates} from "./page-updates.js";
import {bindAudioPlayers, syncAudioPlayers} from "./audio-player.js";
import {objectURL, writeText} from "./canvas-files.js";
import {decodeConnection} from "./worksheet-json.js";
import {sharedMouse} from "./mouse.js";
import {contextMenu, documentEntries} from "./cards.js";
import {openExternalLink} from "./links.js";
import {flashNode, flashPoint} from "./ping.js";
import {hideTooltip, showTooltip} from "./tooltip.js";
import {justifyRows} from "./justify.js?v=7";
import {attachScrollbars} from "./scrollbar-drag.js";
import {liveConnection} from "./collaboration.js";

import {useWorksheetGeometry, arrowLength, arrowTransform, plugTransform, edgeGeometry, edgePaint, maximumLineWidth, selectionOutline, taperedArc, wireGradientValues, wireLabelLayout} from "./geometry.js?v=26";
import {ancestors} from "./containers.js?v=5";
import {ensureGlow, glowReach} from "./glow.js";

let selection;
let peers = [];
let selectionRequest = Promise.resolve();
const main = document.querySelector("#worksheet-view");
const {path, csrf} = main.dataset;
let graphics = JSON.parse(main.dataset.graphics || "null") ?? {};
useWorksheetGeometry(() => graphics);
const ns = "http://www.w3.org/2000/svg";
const roster = main.querySelector(".participants");
const mouse = sharedMouse(point => live.cursor(point));
function bindCanvas() {
  // A háttérben renderelt .web előnézetek elkészültükkor újratöltődnek.
  refreshWebPreviews(document);
  const svg = main.querySelector(".passive-canvas");
  svg.style.setProperty("--sheet-glow", (graphics.glow ?? 3) + "px");
  main.querySelector(".passive-frame > .mouse-share")?.remove();
  mouse?.bind(svg, svg, main.dataset.member === "true" ? main.querySelector(".passive-frame") : null);
  // A szerver által a fájldobozokba írt stílusok (a doboz magassága, a táblázat oszlopszélességei és cellaformázása):
  // az oldal tartalombiztonsági szabálya (style-src 'self') a style attribútumot nem engedi érvényesülni, ezért innen
  // állítjuk be. Enélkül a szövegfájl-, CSV- és táblázatdoboz tartalma kilógott a dobozból.
  for (const element of svg.querySelectorAll(".node-file-frame [style]")) element.style.cssText = element.getAttribute("style");
  for (const element of svg.querySelectorAll("[data-file-ink]")) {
    element.style.color = element.dataset.fileInk;
  }
  // Safari: a fájldobozok natív görgetősávja nem húzható, saját sávot kapnak (scrollbar-drag.js).
  for (const element of svg.querySelectorAll(".node-body > .node-note")) attachScrollbars(element);
  for (const element of svg.querySelectorAll("[data-font-size]")) {
    element.style.fontSize = element.dataset.fontSize + "px";
  }
  justifyRows(svg);
  // Mentett görgetési helyzet (a szerkesztőben a dobozt kijelölve görgető résztvevő állítja).
  for (const element of svg.querySelectorAll(".node-note[data-scroll-y]")) {
    element.scrollLeft = Number(element.dataset.scrollX) || 0;
    element.scrollTop = Number(element.dataset.scrollY) || 0;
  }
  for (const preview of svg.querySelectorAll(".node-web-preview")) {
    if (preview.complete && preview.naturalWidth) preview.dataset.ready = "";
    else preview.addEventListener("load", () => { preview.dataset.ready = ""; }, {once: true});
  }
  hideTooltip();
  bindTooltips(svg);
  drawCharts(svg);
}

// Grafikonként megjelenő táblázat- és CSV-dobozok: a rajzoló modul (chart.js és a d3 rajzoló része) csak akkor töltődik
// le, ha a lapon van grafikon. Az adat a doboz fájlja; a szerkesztő ugyanebből, ugyanezzel a modullal rajzol.
async function drawCharts(svg) {
  const boxes = [...svg.querySelectorAll(".node-chart[data-chart]")];
  if (!boxes.length) return;
  let chart;
  try { chart = await import("./chart.js"); } catch { return; }
  await Promise.all(boxes.map(async box => {
    try {
      const response = await fetch(box.dataset.chartSource);
      if (!response.ok) throw Error("A fájl nem olvasható.");
      const rows = chart.fileRows(box.dataset.chartType, await response.text(), box.dataset.chartName);
      const surface = box.dataset.chartSurface || undefined;
      const dark = chart.darkSurface(surface, box.closest("[data-file-ink]")?.dataset.fileInk);
      if (!box.isConnected) return;
      box.innerHTML = chart.chartSVG(rows, JSON.parse(box.dataset.chart), {width: box.clientWidth, height: box.clientHeight, dark, surface});
    } catch {
      box.textContent = "A grafikon nem tölthető be.";
    }
  }));
}

// Élő görgetés: a szerkesztőben a dobozt fogó résztvevő görgetését a megtekintő is követi.
function receiveScroll(frame) {
  const note = main.querySelector('[data-node="' + CSS.escape(frame.node) + '"] .node-note');
  if (!note) return;
  note.scrollLeft = frame.x;
  note.scrollTop = frame.y;
}

const tooltipBoxes = new WeakSet();
function bindTooltips(svg) {
  for (const template of main.querySelectorAll("template[data-tooltip]")) {
    const id = template.dataset.tooltip;
    const box = svg.querySelector('[data-node="' + CSS.escape(id) + '"]');
    if (!box || tooltipBoxes.has(box)) continue;
    tooltipBoxes.add(box);
    box.addEventListener("pointerenter", event => {
      const current = main.querySelector('template[data-tooltip="' + CSS.escape(id) + '"]');
      if (current) showTooltip(event, () => current.innerHTML, current.hasAttribute("data-justified"), undefined, current.dataset.align);
    });
    box.addEventListener("pointerleave", hideTooltip);
    box.addEventListener("pointerdown", hideTooltip);
  }
}

bindCanvas();
bindAudioPlayers(main);

const motions = new Map();
function previewScene() {
  const nodes = new Map([...main.querySelectorAll("[data-node]")].map(anchor => {
    const {node, type, x, y, width, height, shape, parent} = anchor.dataset;
    return [node, {id: node, type, anchor, parent, shape, width: +width, height: +height,
      origin: {x: +x, y: +y}, position: {x: +x, y: +y}}];
  }));
  const wires = new Map(), nodesByMover = new Map(), wiresByNode = new Map();
  function index(map, id, item) {
    if (!id) return;
    if (!map.has(id)) map.set(id, []);
    map.get(id).push(item);
  }
  for (const node of nodes.values()) {
    node.movers = [node.id, ...ancestors(node, nodes).map(parent => parent.id)];
    for (const id of node.movers) index(nodesByMover, id, node);
  }
  for (const path of main.querySelectorAll("[data-wire]")) {
    const edge = decodeConnection(JSON.parse(path.dataset.wire));
    const frame = path.parentElement;
    const gradient = edge.animated && (edge.appearance ?? "plain") === "plain"
      ? document.getElementById("wire-gradient-" + edge.id) : null;
    const wire = {path, frame, edge, gradient, sweep: gradient?.querySelector("animateTransform"), paint: edgePaint(edge),
      marker: document.getElementById("arrow-" + edge.id), arrows: [...frame.querySelectorAll("[data-arrow-end]")],
      label: edge.label?.trim() ? frame.nextElementSibling : null,
      clip: document.getElementById("wire-gap-" + edge.id)?.firstElementChild,
      taper: path.hasAttribute("data-wire-taper"), pulse: path.querySelector('animate[attributeName="d"]')};
    wires.set(edge.id, wire);
    index(wiresByNode, edge.source, wire);
    index(wiresByNode, edge.target.node, wire);
  }
  function draw(changedMovers) {
    const affectedNodes = new Set();
    const affectedWires = new Set();
    for (const id of changedMovers) {
      for (const node of nodesByMover.get(id) ?? []) affectedNodes.add(node);
    }
    for (const node of affectedNodes) {
      const mover = node.movers.find(id => motions.has(id));
      const delta = motions.get(mover);
      const x = node.origin.x + (delta?.x ?? 0), y = node.origin.y + (delta?.y ?? 0);
      if (x === node.position.x && y === node.position.y) continue;
      node.position = {x, y};
      for (const wire of wiresByNode.get(node.id) ?? []) affectedWires.add(wire);
      if (delta) node.anchor.setAttribute("transform", "translate(" + delta.x + " " + delta.y + ")");
      else node.anchor.removeAttribute("transform");
    }
    for (const {path, edge, gradient, sweep, paint, arrows, label, clip, taper, pulse} of affectedWires) {
      const source = nodes.get(edge.source), target = nodes.get(edge.target.node);
      const nested = source && target && (target.movers.includes(source.id) ? 1 : source.movers.includes(target.id) ? -1 : 0);
      const geometry = edgeGeometry(edge, id => nodes.get(id), nested || 0);
      const {d, from, to, sourceToward, targetToward} = geometry;
      const profile = taper ? taperedArc(geometry, paint) : null;
      const outline = profile?.outline();
      path.setAttribute("d", outline ?? d);
      if (pulse && profile) {
        const scale = Math.min(1.45, maximumLineWidth / paint.lineWidth);
        pulse.setAttribute("values", [outline, profile.outline(scale), outline].join(";"));
      }
      if (sweep) {
        for (const [key, value] of Object.entries({x1: from.x, y1: from.y, x2: to.x, y2: to.y})) {
          gradient.setAttribute(key, value);
        }
        sweep.setAttribute("values", wireGradientValues(from, to, paint));
      }
      for (const arrow of arrows) {
        const end = arrow.dataset.arrowEnd;
        const start = end === "source";
        // Adatvonal félkorongja (data-plug): a doboz oldalához igazodik, nem a vonal irányához.
        const plugged = arrow.dataset.plug !== undefined && (start ? source : target);
        arrow.setAttribute("transform", plugged ? plugTransform(plugged, start ? from : to, paint.width) : profile?.ends[end].transform ??
          arrowTransform(start ? from : to, start ? sourceToward : targetToward, arrowLength(paint.width)));
      }
      if (label) {
        const layout = wireLabelLayout(geometry, edge.label, paint, edge.labelInLine);
        label.setAttribute("transform", layout.transform);
        label.setAttribute("y", layout.y);
        label.setAttribute("font-size", layout.fontSize);
        label.setAttribute("font-weight", layout.fontWeight);
        if (layout.clip && clip) {
          clip.setAttribute("d", layout.clip);
          clip.setAttribute("transform", layout.transform);
          path.setAttribute("clip-path", "url(#wire-gap-" + edge.id + ")");
          label.setAttribute("textLength", layout.textLength);
          label.setAttribute("lengthAdjust", "spacingAndGlyphs");
          label.setAttribute("dominant-baseline", "central");
        } else if (clip) {
          path.removeAttribute("clip-path");
          label.removeAttribute("textLength");
          label.removeAttribute("lengthAdjust");
          label.removeAttribute("dominant-baseline");
        }
      }
    }
  }
  return {nodes, wires, draw};
}
let scene = previewScene();
const changedMovers = new Set();
let motionFrame;
function scheduleMotion() {
  if (motionFrame !== undefined || !changedMovers.size) return;
  motionFrame = requestAnimationFrame(() => {
    motionFrame = undefined;
    scene.draw(changedMovers);
    changedMovers.clear();
  });
}

function receiveMotion(frame) {
  if (!frame) {
    for (const id of motions.keys()) changedMovers.add(id);
    motions.clear();
  } else if (frame.revision !== Number(main.dataset.revision)) return;
  else if (frame.ping) {
    if (frame.point) flashPoint(main.querySelector(".passive-canvas"), frame.point);
    else flashNode(main, frame.node);
    return;
  } else {
    if (frame.delta) motions.set(frame.node, frame.delta);
    else motions.delete(frame.node);
    changedMovers.add(frame.node);
  }
  scheduleMotion();
}

function outline(box, marker, color) {
  const {x, y, width, height, shape} = box.dataset;
  const [tag, geometry] = selectionOutline(shape, +width, +height);
  const frame = document.createElementNS(ns, tag);
  for (const [key, value] of Object.entries({...geometry, [marker]: "", transform: `translate(${x} ${y})`,
    stroke: color, "stroke-width": 3, fill: "none", "pointer-events": "none"})) frame.setAttribute(key, value);
  frame.setAttribute("class", "selection-glow");
  frame.setAttribute("filter", ensureGlow(main.querySelector(".passive-canvas"), "peer", color, graphics.glow ?? 3));
  frame.style.color = color;
  frame.dataset.peerColor = color;
  box.prepend(frame);
}

let rosterSignature;
let paintedWireOwners = new Map();
function paint(peers) {
  roster.classList.remove("connection-lost");
  const signature = JSON.stringify(peers.map(({name, avatar}) => [name, avatar]));
  if (signature !== rosterSignature) {
    rosterSignature = signature;
    // A jelenlévők gombok; egyelőre nem csinálnak semmit (később: chatüzenet küldése).
    roster.replaceChildren(...peers.map(peer => {
      const label = document.createElement("button");
      label.type = "button";
      label.className = "button tool-button participant";
      label.title = peer.name;
      label.textContent = peer.name;
      if (peer.avatar) {
        const img = document.createElement("img");
        img.src = "/icons/avatar-" + peer.avatar + ".svg";
        img.className = "peer-avatar";
        img.alt = "";
        label.prepend(img);
      }
      return label;
    }));
  }
  for (const frame of main.querySelectorAll("[data-selection]")) {
    if (!peers.some(peer => !peer.mine && peer.node === frame.parentElement.dataset.node && peer.color === frame.dataset.peerColor)) frame.remove();
  }
  const wireOwners = new Map();
  for (const peer of peers) {
    if (peer.edge && (peer.mine || !wireOwners.has(peer.edge))) wireOwners.set(peer.edge, peer.color);
  }
  for (const id of new Set([...paintedWireOwners.keys(), ...wireOwners.keys()])) {
    const color = wireOwners.get(id) ?? "";
    if (color === (paintedWireOwners.get(id) ?? "")) continue;
    const wire = scene.wires.get(id);
    if (!wire) continue;
    const {frame, gradient, path, marker, arrows, taper} = wire;
    frame.classList.toggle("wire-selected", !!color);
    frame.style.color = color;
    // Glow SVG-szűrővel (Public/glow.js). A szűrőterület a csoport befoglaló téglalapjához mér, ami vízszintes
    // vonalnál nulla vastag: egy láthatatlan helytartó a glow kiterjedésével megnöveli.
    frame.querySelector(":scope > [data-glow-padding]")?.remove();
    if (color) {
      const box = frame.getBBox(), reach = glowReach("peer", graphics.glow ?? 3) + maximumLineWidth;
      const padding = document.createElementNS(ns, "rect");
      for (const [key, value] of Object.entries({x: box.x - reach, y: box.y - reach, width: box.width + 2 * reach,
        height: box.height + 2 * reach, fill: "none", stroke: "none", "pointer-events": "none", "data-glow-padding": ""}))
        padding.setAttribute(key, value);
      frame.prepend(padding);
      frame.setAttribute("filter", ensureGlow(main.querySelector(".passive-canvas"), "peer", color, graphics.glow ?? 3));
    } else frame.removeAttribute("filter");
    if (gradient) gradient.style.color = color;
    else if (taper) path.style.fill = color;
    else path.style.stroke = color;
    if (marker) marker.style.color = color;
    for (const arrow of arrows) arrow.style.fill = color;
  }
  paintedWireOwners = wireOwners;
  for (const peer of peers) {
    if (!peer.node || peer.mine) continue;
    const anchor = scene.nodes.get(peer.node)?.anchor;
    if (!anchor || [...anchor.querySelectorAll("[data-selection]")].some(frame => frame.dataset.peerColor === peer.color)) continue;
    outline(anchor, "data-selection", peer.color);
  }
}

function selectBox(box, broadcast = false) {
  main.querySelector("[data-view-selection]")?.remove();
  selection = box?.dataset.node;
  if (broadcast && main.dataset.member === "true") {
    const node = selection ?? null;
    selectionRequest = selectionRequest.then(() => live.viewSelect(node)).catch(() => {});
  }
  if (!box) return;
  outline(box, "data-view-selection", main.dataset.selection || "#526982");
}

document.addEventListener("click", async event => {
  if (event.target.closest("audio, [data-audio-player], .node-file a, .node-download")) return;
  const linked = event.target.closest(".passive-canvas a[data-link]");
  if (linked && event.detail) {
    // Linkes objektum a megtekintőben kattintásra nyílik (docs/node-types.md, link képesség).
    event.preventDefault();
    if (linked.hasAttribute("data-web-presentation")) openPresentation(linked.getAttribute("href"));
    else if (linked.getAttribute("target") === "_blank") openExternalLink(linked.getAttribute("href"));
    else location.assign(linked.getAttribute("href"));
    return;
  }
  const box = event.target.closest(".passive-canvas [data-node]");
  if (box && event.detail) {
    event.preventDefault();
    if (selection !== box.dataset.node) selectBox(box, true);
  } else if (selection && event.target.closest(".passive-canvas")) selectBox(null, true);
  if (event.target.closest(".fullscreen")) {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await main.querySelector(".passive-frame").requestFullscreen();
    } catch (error) { alert(error.message); }
  }

});
document.addEventListener("click", event => {
  const download = event.target.closest(".node-download[data-download]");
  if (download && event.detail === 0) location.assign(download.dataset.download);
});
document.addEventListener("dblclick", event => {
  const download = event.target.closest(".node-download[data-download]");
  if (download) {
    event.preventDefault();
    location.assign(download.dataset.download);
    return;
  }
  const box = event.target.closest(".passive-canvas a[data-link]");
  if (event.target.closest("button, audio, [data-audio-player], .node-file a")) return;
  if (!box) {
    if (event.target.closest(".passive-frame") && !event.target.closest("a[href]")) {
      const edit = main.querySelector("a.viewer-edit");
      if (edit) location.assign(edit.href);
    }
    return;
  }
  event.preventDefault();
  if (box.hasAttribute("data-web-presentation")) openPresentation(box.getAttribute("href"));
  else if (box.getAttribute("target") === "_blank") openExternalLink(box.getAttribute("href"));
  else location.assign(box.getAttribute("href"));
});
document.addEventListener("contextmenu", event => {
  const canvas = event.target.closest(".passive-canvas");
  if (!canvas) return;
  const box = event.target.closest("[data-node]");
  const copyLink = box?.querySelector(".node-file, .node-image") ? ["Link másolása", () => writeText(objectURL(path, box.dataset.node)).catch(error => alert(error.message)), "link"] : null;
  if (main.dataset.member !== "true" && main.dataset.editable !== "true") {
    if (copyLink) contextMenu(event,[copyLink]);
    return;
  }
  const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(canvas.getScreenCTM().inverse());
  const entries = [["Ping", () => {
    if (box) flashNode(canvas, box.dataset.node);
    else flashPoint(canvas, point);
    live.ping(box ? {node: box.dataset.node} : {point: {x: point.x, y: point.y}}).catch(error => alert(error.message));
  }, "center"]];
  if (copyLink) entries.unshift(copyLink);
  if (main.dataset.editable === "true") {
    const wire = event.target.closest("[data-wire]");
    const target = box ? {node: box.dataset.node} : wire ? {edge: JSON.parse(wire.dataset.wire).id} : null;
    entries.push(["Szerkesztés", () => location.assign("/edit/" + path + (target ? "?" + new URLSearchParams(target) : "")), "edit"]);
  }
  const documentLink = main.querySelector("[data-current-document]");
  if (documentLink) entries.push(...documentEntries(documentLink).slice(1));
  contextMenu(event, entries);
});
let pageRequest = Promise.resolve();
let presenceStopped = false;
function refreshPage(signal, incoming) {
  const nextRequest = pageRequest.then(async () => {
    const {response, page} = incoming ?? await fetchPage(signal);
    if (signal?.aborted) return;
    const next = page.querySelector("#worksheet-view");
    if (response.status >= 500) throw new Error("A munkalap nem érhető el.");
    if (response.redirected || !next || next.dataset.csrf !== csrf) { location.reload(); return; }
    if (Number(next.dataset.revision) < Number(main.dataset.revision)) return;
    const updatedCanvas = next.dataset.revision !== main.dataset.revision || next.dataset.siteMode !== main.dataset.siteMode;
    const frame = main.querySelector(".passive-frame");
    const nextFrame = next.querySelector(".passive-frame");
    for (const selector of updatedCanvas ? ["svg:not(.canvas-background)", ".canvas-background"] : []) {
      const previous = frame.querySelector(":scope > " + selector);
      const updated = nextFrame.querySelector(":scope > " + selector);
      if (!previous || !updated) continue;
      if (!previous.querySelector("audio")) { previous.replaceWith(updated); continue; }
      previous.before(updated);
      for (const player of previous.querySelectorAll("audio")) {
        const id = player.closest("[data-node]").dataset.node;
        const nextPlayer = updated.querySelector('[data-node="' + CSS.escape(id) + '"] audio');
        if (!nextPlayer || nextPlayer.getAttribute("src") !== player.getAttribute("src")) continue;
        if (nextPlayer.parentElement.moveBefore) {
          nextPlayer.parentElement.moveBefore(player,nextPlayer);
          nextPlayer.remove();
        } else {
          const time = player.currentTime, playing = !player.paused;
          nextPlayer.addEventListener("loadedmetadata", () => {
            nextPlayer.currentTime = time;
            if (playing) nextPlayer.play().catch(() => {});
          }, {once: true});
        }
      }
      previous.remove();
    }
    for (const selector of ["[data-current-document]", "[data-viewer-notes]", "[data-viewer-sections]"]) {
      updateSection(main, next, selector);
    }
    for (const selector of [".viewer-heading", ".viewer-credits", ".viewer-edit-slot"]) {
      updateSection(main, next, selector);
    }
    Object.assign(main.dataset, next.dataset);
    graphics = JSON.parse(main.dataset.graphics || "null") ?? {};
    if (updatedCanvas) {
      motions.clear();
      changedMovers.clear();
      scene = previewScene();
      paintedWireOwners.clear();
    }
    if (document.title !== page.title) document.title = page.title;
    const header = document.querySelector(".worksheet-nav");
    const nextHeader = page.querySelector(".worksheet-nav");
    for (const selector of [".header-left", ".header-parent", ".header-actions"]) {
      updateSection(header, nextHeader, selector);
    }
    if (updatedCanvas) {
      bindCanvas();
      syncAudioPlayers(main);
      if (selection) selectBox(main.querySelector('[data-node="' + CSS.escape(selection) + '"]'));
    } else {
      bindTooltips(main.querySelector(".passive-canvas"));
    }
    paint(peers);
  });
  pageRequest = nextRequest.catch(() => {});
  return nextRequest;
}

const live = liveConnection(path, csrf, async state => {
  if (Number(main.dataset.revision) < state.revision) await refreshPage();
  for (const id of motions.keys()) {
    if (peers.some(p => !p.viewing && p.node === id) &&
        !state.participants.some(p => !p.viewing && p.node === id)) {
      motions.delete(id);
      changedMovers.add(id);
    }
  }
  scheduleMotion();
  const previousMine = peers.find(peer => peer.mine);
  peers = state.participants;
  const mine = peers.find(peer => peer.mine);
  if (selection && main.dataset.member === "true" && !mine?.node && !previousMine) {
    selectBox(main.querySelector('[data-node="' + CSS.escape(selection) + '"]'), true);
  }
  paint(peers);
}, error => {
  if ([401, 403, 404, 410, 423].includes(error.status)) {
    presenceStopped = true;
    refreshPage().catch(() => {});
  }
  roster.classList.add("connection-lost");
  roster.textContent = "Kapcsolat megszakadt";
  rosterSignature = undefined;
  peers = [];
  if (!roster.isConnected) main.prepend(roster);
}, {onMotion: receiveMotion, onCursor: mouse?.receive, onScroll: receiveScroll});
window.addEventListener("pagehide", live.stop);
window.addEventListener("pageshow", event => { if (event.persisted) live.start(); });
live.start();

watchPageUpdates(async (signal, incoming) => {
  await refreshPage(signal, incoming);
  if (presenceStopped && !signal.aborted) {
    presenceStopped = false;
    live.start();
  }
});
