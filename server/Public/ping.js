export function flashNode(canvas, id) {
  const node = canvas?.querySelector('[data-node="' + CSS.escape(id) + '"]');
  if (!node) return;
  const width = Number(node.dataset.width), height = Number(node.dataset.height);
  flashPoint(node, {x: Number(node.dataset.x ?? 0), y: Number(node.dataset.y ?? 0)}, width+16, height+16);
}

// `kind`: az elem osztálya (node-ping: ping; fx-ripple: a látványcsomag kattintásgyűrűje); az animáció végén eltűnik.
export function flashPoint(layer, point, width = 24, height = 24, kind = "node-ping") {
  if (!layer) return;
  const frame = document.createElementNS("http://www.w3.org/2000/svg", "rect");
  for (const [key, value] of Object.entries({class: kind, "data-editor-only": "",
    x: point.x-width/2, y: point.y-height/2, width, height, rx: Math.min(12, width / 2),
    fill: "none", stroke: "#f58a16", "stroke-width": 4, "pointer-events": "none"})) frame.setAttribute(key, value);
  layer.append(frame);
  frame.addEventListener("animationend", () => frame.remove(), {once: true});
}
