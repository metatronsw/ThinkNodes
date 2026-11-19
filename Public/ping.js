export function flashNode(canvas, id) {
  const node = canvas?.querySelector('[data-node="' + CSS.escape(id) + '"]');
  if (!node) return;
  node.querySelector(".node-ping")?.remove();
  const width = Number(node.dataset.width), height = Number(node.dataset.height);
  const frame = document.createElementNS("http://www.w3.org/2000/svg", "rect");
  const cx = Number(node.dataset.x ?? 0), cy = Number(node.dataset.y ?? 0);
  for (const [key, value] of Object.entries({class: "node-ping", "data-editor-only": "",
    x: cx-width/2-8, y: cy-height/2-8, width: width+16, height: height+16, rx: 12,
    fill: "none", stroke: "#f58a16", "stroke-width": 4, "pointer-events": "none"})) frame.setAttribute(key, value);
  node.append(frame);
  frame.addEventListener("animationend", () => frame.remove(), {once: true});
}
