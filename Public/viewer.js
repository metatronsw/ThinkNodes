import {bindAudioPlayers, syncAudioPlayers} from "./audio-player.js";
import {objectURL, writeText} from "./canvas-files.js";
import {decodeConnection} from "./worksheet-json.js";
import {sharedMouse} from "./mouse.js";
import {contextMenu, documentEntries} from "./cards.js";
import {openExternalLink} from "./links.js";
import {flashNode, flashPoint} from "./ping.js";
import {hideTooltip, showTooltip} from "./tooltip.js";
import {liveConnection} from "./collaboration.js";

import {arrowTransform, edgeGeometry, edgePaint, selectionOutline} from "./geometry.js?v=2";
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
  const wires = [...main.querySelectorAll("[data-wire]")].map(path => ({path, edge: decodeConnection(JSON.parse(path.dataset.wire))}));
  return () => {
    const changed = new Set();
    for (const node of nodes.values()) {
      const delta = [node, ...ancestors(node, nodes)].map(n => motions.get(n.id)).find(Boolean);
      const x = node.origin.x + (delta?.x ?? 0), y = node.origin.y + (delta?.y ?? 0);
      if (x === node.position.x && y === node.position.y) continue;
      node.position = {x, y};
      changed.add(node.id);
      if (delta) node.anchor.setAttribute("transform", "translate(" + delta.x + " " + delta.y + ")");
      else node.anchor.removeAttribute("transform");
    }
    for (const {path, edge} of wires) {
      if (!changed.has(edge.source) && !changed.has(edge.target.node)) continue;
      const {d, labelPosition, angle, from, to, sourceToward, targetToward} = edgeGeometry(edge, id => nodes.get(id));
      path.setAttribute("d", d);
      if (path.parentElement.hasAttribute("data-free-arrows")) {
        for (const arrow of path.parentElement.querySelectorAll("[data-arrow-end]")) {
          const start = arrow.dataset.arrowEnd === "source";
          arrow.setAttribute("transform", arrowTransform(start ? from : to, start ? sourceToward : targetToward, edgePaint(edge).width));
        }
      }
      let underlay = path.previousElementSibling;
      while (underlay?.hasAttribute("data-wire-highlight")) {
        underlay.setAttribute("d", d);
        underlay = underlay.previousElementSibling;
      }
      const wire = path.parentElement.hasAttribute("data-free-arrows") ? path.parentElement : path;
      if (edge.label?.trim()) wire.nextElementSibling?.setAttribute("transform",
        "translate(" + labelPosition.x + " " + labelPosition.y + ") rotate(" + angle + ")");
    }
  };
}
let drawPreview = previewScene();
function receiveMotion(frame) {
  if (!frame) motions.clear();
  else if (frame.revision !== Number(main.dataset.revision)) return;
  else if (frame.ping) {
    if (frame.point) flashPoint(main.querySelector(".passive-canvas"), frame.point);
    else flashNode(main, frame.node);
    return;
  }
  else if (frame.delta) motions.set(frame.node, frame.delta);
  else motions.delete(frame.node);
  drawPreview();
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

function paint(peers) {
  roster.classList.remove("connection-lost");
  roster.replaceChildren();
  for (const peer of peers) {
    const label = document.createElement("span");
    if (peer.color) label.style.setProperty("--peer", peer.color);
    else label.className = "guest";
    label.textContent = peer.name;
    roster.append(label);
  }
  for (const frame of main.querySelectorAll("[data-selection]")) {
    if (!peers.some(peer => !peer.mine && peer.node === frame.parentElement.dataset.node && peer.color === frame.dataset.peerColor)) frame.remove();
  }
  main.querySelectorAll("[data-wire-highlight]").forEach(line => line.remove());
  for (const wire of main.querySelectorAll("[data-wire]")) {
    const id = JSON.parse(wire.dataset.wire).id;
    const owners = peers.filter(p => p.edge === id);
    for (const arrow of wire.parentElement.querySelectorAll(":scope > [data-arrow-end]")) {
      arrow.classList.toggle("selection-glow", owners.length > 0);
      arrow.style.color = owners[0]?.color ?? "";
    }
    owners.forEach((peer, i) => {
      const line = document.createElementNS(ns, "path");
      for (const [key, value] of Object.entries({"data-wire-highlight": "", class: "selection-glow", color: peer.color, d: wire.getAttribute("d"),
        stroke: peer.color, "stroke-width": Number(wire.getAttribute("stroke-width")) + (owners.length-i)*5,
        fill: "none", "pointer-events": "none"})) line.setAttribute(key, value);
      for (const key of ["stroke-dasharray", "stroke-linecap", "marker-start", "marker-end"]) {
        if (wire.hasAttribute(key)) line.setAttribute(key, wire.getAttribute(key));
      }
      wire.before(line);
    });
  }
  for (const peer of peers) {
    if (!peer.node || peer.mine) continue;
    const anchor = main.querySelector('[data-node="' + CSS.escape(peer.node) + '"]');
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
    drawPreview = previewScene();
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
        !state.participants.some(p => !p.viewing && p.node === id)) motions.delete(id);
  }
  drawPreview();
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
  peers = [];
  if (!roster.isConnected) main.prepend(roster);
}, {onMotion: receiveMotion, onCursor: mouse?.receive});
window.addEventListener("pagehide", live.stop);
window.addEventListener("pageshow", event => { if (event.persisted) live.start(); });
live.start();
