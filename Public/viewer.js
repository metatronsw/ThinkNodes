import {bindAudioPlayers, syncAudioPlayers} from "./audio-player.js";
import {objectURL, writeText} from "./canvas-files.js";
import {decodeConnection} from "./worksheet-json.js";
import {sharedMouse} from "./mouse.js";
import {contextMenu, documentEntries} from "./cards.js";
import {openExternalLink} from "./links.js";
import {flashNode, flashPoint} from "./ping.js";
import {hideTooltip, showTooltip} from "./tooltip.js";
import {liveConnection} from "./collaboration.js";

import {arrowTransform, edgeGeometry, edgePaint, selectionOutline, wireGradientValues} from "./geometry.js?v=9";
import {ancestors} from "./containers.js";

let selection;
let peers = [];
let selectionRequest = Promise.resolve();
const main = document.querySelector("#worksheet-view");
const {path, csrf} = main.dataset;
const ns = "http://www.w3.org/2000/svg";
const roster = document.createElement("div");
roster.className = "participants";
roster.setAttribute("aria-label", "Jelenlévők");
const mouse = sharedMouse(point => live.cursor(point));
function bindCanvas() {
  const svg = main.querySelector(".passive-canvas");
  main.querySelector(".passive-frame > .mouse-share")?.remove();
  mouse?.bind(svg, svg, main.dataset.member === "true" ? main.querySelector(".passive-frame") : null);
  hideTooltip();
  main.querySelector(".passive-frame").append(roster);
  for (const template of main.querySelectorAll("template[data-tooltip]")) {
    const box = main.querySelector('[data-node="' + CSS.escape(template.dataset.tooltip) + '"]');
    box?.addEventListener("pointerenter", event => showTooltip(event, () => template.innerHTML, template.hasAttribute("data-justified")));
    box?.addEventListener("pointerleave", hideTooltip);
    box?.addEventListener("pointerdown", hideTooltip);
  }
}
bindCanvas();
bindAudioPlayers(main);

const motions = new Map();
function previewScene() {
  const nodes = new Map([...main.querySelectorAll("[data-node]")].map(anchor => {
    const {node, x, y, width, height, shape, parent} = anchor.dataset;
    return [node, {id: node, anchor, parent, shape, width: +width, height: +height,
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
      label: edge.label?.trim() ? frame.nextElementSibling : null};
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
    for (const {path, edge, gradient, sweep, paint, arrows, label} of affectedWires) {
      const geometry = edgeGeometry(edge, id => nodes.get(id));
      const {d, from, to, sourceToward, targetToward} = geometry;
      path.setAttribute("d", d);
      if (sweep) {
        for (const [key, value] of Object.entries({x1: from.x, y1: from.y, x2: to.x, y2: to.y})) {
          gradient.setAttribute(key, value);
        }
        sweep.setAttribute("values", wireGradientValues(from, to, paint));
      }
      for (const arrow of arrows) {
        const start = arrow.dataset.arrowEnd === "source";
        arrow.setAttribute("transform", arrowTransform(start ? from : to, start ? sourceToward : targetToward, paint.width));
      }
      if (label) {
        const {labelPosition, angle} = geometry;
        label.setAttribute("transform", "translate(" + labelPosition.x + " " + labelPosition.y + ") rotate(" + angle + ")");
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
  frame.style.color = color;
  frame.dataset.peerColor = color;
  box.prepend(frame);
}

let rosterSignature;
let paintedWireOwners = new Map();
function paint(peers) {
  roster.classList.remove("connection-lost");
  const signature = JSON.stringify(peers.map(({name, color}) => [name, color]));
  if (signature !== rosterSignature) {
    rosterSignature = signature;
    roster.replaceChildren(...peers.map(peer => {
      const label = document.createElement("span");
      if (peer.color) label.style.setProperty("--peer", peer.color);
      else label.className = "guest";
      label.textContent = peer.name;
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
    const {frame, gradient, path, marker, arrows} = wire;
    frame.classList.toggle("wire-selected", !!color);
    frame.style.color = color;
    if (gradient) gradient.style.color = color;
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
  outline(box, "data-view-selection", peers.find(peer => peer.mine)?.color || "#526982");
}

document.addEventListener("click", async event => {
  if (event.target.closest("audio, [data-audio-player], .canvas-file a")) return;
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
document.addEventListener("dblclick", event => {
  const box = event.target.closest(".passive-canvas a[data-link]");
  if (!box) return;
  event.preventDefault();
  if (box.getAttribute("target") === "_blank") openExternalLink(box.getAttribute("href"));
  else location.assign(box.getAttribute("href"));
});
document.addEventListener("contextmenu", event => {
  const canvas = event.target.closest(".passive-canvas");
  if (!canvas) return;
  const box = event.target.closest("[data-node]");
  const copyLink = box?.querySelector(".canvas-file, .canvas-image") ? ["Link másolása", () => writeText(objectURL(path, box.dataset.node)).catch(error => alert(error.message)), "link"] : null;
  if (main.dataset.member !== "true") {
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
function updateSection(current, incoming, selector) {
  const existing = current.querySelector(selector);
  const replacement = incoming.querySelector(selector);
  if (existing && replacement && existing.outerHTML !== replacement.outerHTML) existing.replaceWith(replacement);
}

const live = liveConnection(path, csrf, async state => {
  if (Number(main.dataset.revision) < state.revision) {
    const response = await fetch(location.href, {cache: "no-store"});
    if (!response.ok) throw new Error("A munkalap nem érhető el.");
    const page = new DOMParser().parseFromString(await response.text(), "text/html");
    const next = page.querySelector("#worksheet-view");
    if (!next) { location.reload(); return; }
    const frame = main.querySelector(".passive-frame");
    const nextFrame = next.querySelector(".passive-frame");
    for (const selector of ["svg:not(.passive-backdrop)", ".passive-backdrop"]) {
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
    const downloadBar = ".viewer-downloads";
    const oldCredits = main.querySelectorAll(downloadBar + " .card-meta");
    const newCredits = next.querySelectorAll(downloadBar + " .card-meta");
    oldCredits.forEach((credit, index) => {
      const replacement = newCredits[index];
      if (replacement && !credit.isEqualNode(replacement)) credit.replaceWith(replacement);
    });
    const oldEdit = frame.querySelector(".viewer-edit"), newEdit = nextFrame.querySelector(".viewer-edit");
    if (!newEdit) oldEdit?.remove();
    else if (!oldEdit) frame.append(newEdit);
    Object.assign(main.dataset, next.dataset);
    motions.clear();
    changedMovers.clear();
    scene = previewScene();
    paintedWireOwners.clear();
    if (document.title !== page.title) document.title = page.title;
    const header = document.querySelector(".site-header");
    const nextHeader = page.querySelector(".site-header");
    for (const selector of [".header-left", ".header-parent", ".header-actions"]) {
      updateSection(header, nextHeader, selector);
    }
    bindCanvas();
    syncAudioPlayers(main);
    if (selection) selectBox(main.querySelector('[data-node="' + CSS.escape(selection) + '"]'));
  }
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
  if ([401, 403, 404, 423].includes(error.status)) main.textContent = error.message;
  roster.classList.add("connection-lost");
  roster.textContent = "Kapcsolat megszakadt";
  rosterSignature = undefined;
  peers = [];
  if (!roster.isConnected) main.prepend(roster);
}, {onMotion: receiveMotion, onCursor: mouse?.receive});
window.addEventListener("pagehide", live.stop);
window.addEventListener("pageshow", event => { if (event.persisted) live.start(); });
live.start();
