export const shapes = {
  rounded: "Lekerekített",
  rectangle: "Téglalap",
  ellipse: "Ellipszis",
  diamond: "Rombusz",
};

export const edgeStyles = {
  arrow: "Egyirányú nyíl",
  both: "Kétirányú nyíl",
  dashed: "Szaggatott nyíl",
  rope: "Íves kötél",
};

export const paper = "#f5f8fc";
export const cableColor = "#526982";
export const limit = (value, min, max) => Math.min(max, Math.max(min, value));

export function shapeDistance(node, point, padding = 0) {
  const x = Math.abs(point.x - node.position.x) / (node.width / 2 + padding);
  const y = Math.abs(point.y - node.position.y) / (node.height / 2 + padding);
  if (node.shape === "ellipse") return Math.hypot(x, y);
  if (node.shape === "diamond") return x + y;
  return Math.max(x, y);
}

export function borderPoint(node, toward) {
  const ratio = shapeDistance(node, toward);
  if (!ratio) return node.position;
  return {
    x: node.position.x + (toward.x - node.position.x) / ratio,
    y: node.position.y + (toward.y - node.position.y) / ratio,
  };
}

export function edgeGeometry(source, targetNode, targetPoint, style) {
  const target = targetNode?.position || targetPoint;
  const from = borderPoint(source, target);
  const to = targetNode ? borderPoint(targetNode, source.position) : target;
  const start = "M " + from.x + " " + from.y;
  const end = to.x + " " + to.y;
  if (style !== "rope") return {d: start + " L " + end, to};
  const control = {
    x: (from.x + to.x) / 2,
    y: (from.y + to.y) / 2 + Math.min(110, Math.hypot(to.x - from.x, to.y - from.y) * 0.28),
  };
  return {d: start + " Q " + control.x + " " + control.y + " " + end, to, control};
}

export function canvasBounds(board) {
  let halfWidth = 360;
  let halfHeight = 240;
  const nodes = new Map(board.nodes.map(node => [node.id, node]));
  for (const node of board.nodes) {
    halfWidth = Math.max(halfWidth, Math.abs(node.position.x) + node.width / 2 + 40);
    halfHeight = Math.max(halfHeight, Math.abs(node.position.y) + node.height / 2 + 40);
  }
  for (const edge of board.edges) {
    const {to, control} = edgeGeometry(nodes.get(edge.source), nodes.get(edge.target.node), edge.target.point, edge.style);
    halfWidth = Math.max(halfWidth, Math.abs(to.x) + 40, Math.abs(control?.x || 0) + 40);
    halfHeight = Math.max(halfHeight, Math.abs(to.y) + 40, Math.abs(control?.y || 0) + 40);
  }
  return {x: -halfWidth, y: -halfHeight, width: halfWidth * 2, height: halfHeight * 2};
}

function textWidth(value, size) {
  let width = 0;
  for (const letter of value) {
    if ("MW@#%&".includes(letter)) width += 0.95;
    else if (" ilI1.,:!|'".includes(letter)) width += 0.33;
    else width += 0.65;
  }
  return width * size;
}

export function commentColor(color) {
  return "#" + color.slice(1).match(/../g).map(channel =>
    Math.floor(parseInt(channel, 16) * 0.83).toString(16).padStart(2, "0")
  ).join("");
}

function wrap(text, columns) {
  const lines = [];
  let line = [];
  for (const word of text.trim().split(/\s+/).filter(Boolean)) {
    let letters = Array.from(word);
    if (line.length && line.length + letters.length + 1 > columns) {
      lines.push(line.join(""));
      line = [];
    }
    while (letters.length > columns) {
      lines.push(letters.slice(0, columns).join(""));
      letters = letters.slice(columns);
    }
    if (line.length) line.push(" ");
    line.push(...letters);
  }
  if (line.length) lines.push(line.join(""));
  return lines;
}

export function labelLayout(node, markdown = "") {
  const widthRatio = node.shape === "diamond" ? 0.50 : node.shape === "ellipse" ? 0.72 : 0.94;
  const heightRatio = node.shape === "diamond" ? 0.47 : node.shape === "ellipse" ? 0.72 : 0.94;
  const detailSize = Math.max(10, node.fontSize * 0.80);
  const comment = node.comment || "";
  const automatic = node.autoSize !== false;
  const targetWidth = Math.max(textWidth(node.title, node.fontSize), Math.min(245, textWidth(comment, detailSize)),
    markdown.trim() ? 200 : 0);
  const width = automatic ? limit(Math.ceil((targetWidth + 24) / widthRatio), 64, 880) : node.width;
  const labelWidth = Math.max(12, width * widthRatio - 16);
  const lines = [];

  function add(value, size, weight, color) {
    const text = value.trim().replace(/\s+/g, " ");
    if (!text) return;
    const wrapped = textWidth(text, size) <= labelWidth
      ? [text] : wrap(text, Math.max(2, Math.floor(labelWidth / (size * 0.65))));
    for (const text of wrapped) lines.push({text, size, weight, color, step: size * 1.25});
  }

  add(node.title, node.fontSize, node.bold ? 650 : 400, node.textColor);
  add(comment, detailSize, 400, commentColor(node.textColor));
  for (const paragraph of markdown.split(/\r?\n/)) add(paragraph, detailSize, 400, node.textColor);

  const heightNeeded = lines.reduce((sum, line) => sum + line.step, 0) + 16;
  const height = automatic ? limit(Math.ceil(heightNeeded / heightRatio), 40, 680) : node.height;
  const visible = [];
  let remaining = Math.max(node.fontSize * 1.25, height * heightRatio - 12);
  for (const line of lines) {
    if (remaining < line.step) break;
    visible.push(line);
    remaining -= line.step;
  }
  if (visible.length && visible.length < lines.length) visible.at(-1).text += "…";

  const x = node.alignment === "left" ? -labelWidth / 2 : node.alignment === "right" ? labelWidth / 2 : 0;
  let top = -visible.reduce((sum, line) => sum + line.step, 0) / 2;
  return {
    width, height,
    anchor: {left: "start", center: "middle", right: "end"}[node.alignment],
    lines: visible.map(line => {
      const y = top + line.step / 2 + line.size * 0.33;
      top += line.step;
      return {x, y, ...line, fit: textWidth(line.text, line.size) > labelWidth ? labelWidth : undefined};
    }),
  };
}
