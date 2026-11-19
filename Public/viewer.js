import {liveConnection} from "./collaboration.js";

import {edgeGeometry} from "./geometry.js";
import {ancestors} from "./containers.js";

let main = document.querySelector("#worksheet-view");
const {path, csrf} = main.dataset;
const ns = "http://www.w3.org/2000/svg";
const roster = document.createElement("div");
roster.className = "participants";
roster.setAttribute("aria-label", "Jelenlévők");
document.querySelector(".site-header").append(roster);

const motions = new Map();
function previewScene() {
  const nodes = new Map([...main.querySelectorAll("[data-node]")].map(anchor => {
    const {node, x, y, width, height, shape, parent} = anchor.dataset;
    return [node, {id: node, anchor, parent, shape, width: +width, height: +height,
      origin: {x: +x, y: +y}, position: {x: +x, y: +y}}];
  }));
  const wires = [...main.querySelectorAll("[data-wire]")].map(path => ({path, edge: JSON.parse(path.dataset.wire)}));
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
      const {d, labelPosition, angle} = edgeGeometry(edge, id => nodes.get(id));
      path.setAttribute("d", d);
      if (edge.label?.trim()) path.nextElementSibling?.setAttribute("transform",
        "translate(" + labelPosition.x + " " + labelPosition.y + ") rotate(" + angle + ")");
    }
  };
}
let drawPreview = previewScene();
function receiveMotion(frame) {
  if (!frame) motions.clear();
  else if (frame.revision !== Number(main.dataset.revision)) return;
  else if (frame.delta) motions.set(frame.node, frame.delta);
  else motions.delete(frame.node);
  drawPreview();
}

function paint(peers) {
  roster.replaceChildren();
  for (const peer of new Map(peers.map(p => [p.name, p])).values()) {
    const label = document.createElement("span");
    label.style.setProperty("--peer", peer.color);
    label.textContent = peer.name;
    roster.append(label);
  }
  main.querySelectorAll("[data-selection]").forEach(frame => frame.remove());
  for (const peer of peers) {
    if (!peer.node) continue;
    const anchor = main.querySelector('[data-node="' + CSS.escape(peer.node) + '"]');
    if (!anchor) continue;
    const box = anchor.getBBox();
    const frame = document.createElementNS(ns, "rect");
    for (const [name, value] of Object.entries({"data-selection": "", x: box.x-10, y: box.y-10,
      width: box.width+20, height: box.height+20, rx: 14, stroke: peer.color,
      "stroke-width": 3, fill: "none", "pointer-events": "none"})) frame.setAttribute(name, value);
    anchor.prepend(frame);
  }
}

// Anchors retain keyboard activation and work without JavaScript.
document.addEventListener("click", event => {
  const box = event.target.closest?.(".passive-canvas [data-node]");
  if (box && event.detail && (box.hasAttribute("data-link") || event.ctrlKey && main.dataset.editable === "true")) {
    event.preventDefault();
  }
});
document.addEventListener("dblclick", event => {
  const box = event.target.closest?.(".passive-canvas [data-node]");
  if (!box) return;
  if (event.ctrlKey && main.dataset.editable === "true") {
    location.assign("/edit/" + path + "?node=" + encodeURIComponent(box.dataset.node));
  } else if (box.hasAttribute("data-link")) location.assign(box.getAttribute("href"));
});
const live = liveConnection(path, csrf, async state => {
  if (Number(main.dataset.revision) !== state.revision) {
    const response = await fetch(location.href, {cache: "no-store"});
    if (!response.ok) throw new Error("A munkalap nem érhető el.");
    const page = new DOMParser().parseFromString(await response.text(), "text/html");
    const next = page.querySelector("#worksheet-view");
    if (!next) { location.reload(); return; }
    main.replaceWith(next);
    main = next;
    motions.clear();
    drawPreview = previewScene();
    document.title = page.title;
    const header = page.querySelector(".site-header");
    document.querySelector(".site-header").replaceWith(header);
    header.append(roster);
  }
  for (const id of motions.keys()) {
    if (!state.participants.some(p => p.node === id)) motions.delete(id);
  }
  drawPreview();
  paint(state.participants);
}, error => {
  if ([401, 403, 404].includes(error.status)) main.textContent = error.message;
  roster.textContent = "Kapcsolat megszakadt";
}, {onMotion: receiveMotion});
window.addEventListener("pagehide", live.stop);
window.addEventListener("pageshow", event => { if (event.persisted) live.start(); });
live.start();
