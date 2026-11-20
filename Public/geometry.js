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

export function selectionOutline(shape, width, height) {
  const x = width / 2 + 10, y = height / 2 + 10;
  if (shape === "ellipse") return ["ellipse", {rx: x, ry: y}];
  if (shape === "diamond") return ["polygon", {points: `0,${-y} ${x},0 0,${y} ${-x},0`}];
  return ["rect", {x: -x, y: -y, width: 2*x, height: 2*y, rx: shape === "rounded" ? 22 : 0}];
}

export function shapeDistance(node, point, padding = 0) {
  const x = Math.abs(point.x - node.position.x) / (node.width / 2 + padding);
  const y = Math.abs(point.y - node.position.y) / (node.height / 2 + padding);
  if (node.kind === "connectionPoint" || node.shape === "ellipse") return Math.hypot(x, y);
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

export const lineStyles = {solid: "Folytonos", dashed: "Szaggatott", rope: "Íves"};

export function edgePaint(edge) {
  const color = edge.color ?? cableColor;
  const width = edge.width ?? 2;
  const startArrow = edge.startArrow ?? edge.style === "both";
  const endArrow = edge.endArrow ?? (edge.style !== "rope" && edge.style !== "solid");
  return {color, width, startArrow, endArrow};
}

export function edgeEndpoint(edge, end) {
  return end === "source" ? {node: edge.source, point: edge.sourcePoint} : edge.target;
}

export function edgeGeometry(edge, findNode) {
  const sourceNode = findNode(edge.source);
  const targetNode = findNode(edge.target.node);
  const source = sourceNode?.position ?? edge.sourcePoint;
  const target = targetNode?.position ?? edge.target.point;
  const control = edge.style === "rope"
    ? {x: (source.x + target.x)/2, y: (source.y + target.y)/2 + Math.min(110, Math.hypot(target.x-source.x, target.y-source.y)*0.28)} : null;
  const from = sourceNode ? borderPoint(sourceNode, control ?? target) : source;
  const to = targetNode ? borderPoint(targetNode, control ?? source) : target;
  const start = "M " + from.x + " " + from.y;
  const end = to.x + " " + to.y;
  const midpoint = {x: (from.x + to.x) / 2, y: (from.y + to.y) / 2};
  const labelPosition = control
    ? {x: (from.x + 2 * control.x + to.x) / 4, y: (from.y + 2 * control.y + to.y) / 4} : midpoint;
  let angle = Math.atan2(to.y - from.y, to.x - from.x) * 180 / Math.PI;
  if (angle > 90) angle -= 180;
  if (angle < -90) angle += 180;
  return {
    from, to, control, labelPosition, angle,
    d: control ? start + " Q " + control.x + " " + control.y + " " + end : start + " L " + end,
  };
}

export function arrowTransform(tip, toward, width) {
  const angle = Math.atan2(tip.y-toward.y,tip.x-toward.x)*180/Math.PI;
  return `translate(${tip.x} ${tip.y}) rotate(${angle}) scale(${width*6.75})`;
}

export function canvasBounds(board) {
  let halfWidth = 360;
  let halfHeight = 240;
  const nodes = new Map(board.nodes.map(node => [node.id, node]));
  for (const node of board.nodes) {
    halfWidth = Math.max(halfWidth, Math.abs(node.position.x) + (node.extentX ?? node.width / 2) + 40);
    if (node.kind === "connectionPoint" && node.title) {
      const labelEnd = node.position.x + node.width / 2 + 4 + textWidth(node.title, 14);
      halfWidth = Math.max(halfWidth, labelEnd + 40);
    }
    halfHeight = Math.max(halfHeight, Math.abs(node.position.y) + (node.extentY ?? node.height / 2) + 40);
  }
  for (const edge of board.edges) {
    const {from, to, control, labelPosition, angle} = edgeGeometry(edge, id => nodes.get(id));
    halfWidth = Math.max(halfWidth, Math.abs(from.x) + 40, Math.abs(to.x) + 40, Math.abs(control?.x || 0) + 40);
    halfHeight = Math.max(halfHeight, Math.abs(from.y) + 40, Math.abs(to.y) + 40, Math.abs(control?.y || 0) + 40);
    if (edge.label?.trim()) {
      const radius = textWidth(edge.label, 14) / 2;
      const radians = angle * Math.PI / 180;
      halfWidth = Math.max(halfWidth, Math.abs(labelPosition.x) + Math.abs(Math.cos(radians)) * radius + 28);
      halfHeight = Math.max(halfHeight, Math.abs(labelPosition.y) + Math.abs(Math.sin(radians)) * radius + 28);
    }
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

function wrapRuns(runs, columns, preformatted) {
  const rows = [];
  let line = [];
  let word = [];
  let count = 0;
  let lastFormat;

  function endLine() {
    if (line.length) rows.push(line);
    line = [];
    count = 0;
    lastFormat = undefined;
  }

  function append(letter, format) {
    if (line.length && lastFormat === format) line.at(-1).text += letter;
    else line.push({text: letter, format});
    lastFormat = format;
    count += 1;
  }

  function endWord() {
    if (!word.length) return;
    if (count > 0) {
      if (count + word.length + 1 > columns) endLine();
      else append(" ", undefined);
    }
    for (const [letter, format] of word) {
      if (count === columns) endLine();
      append(letter, format);
    }
    word = [];
  }

  for (const run of runs) {
    for (const letter of run.text) {
      if (preformatted) {
        if (letter === "\n") {
          if (!line.length) line.push({text: "", format: run.format});
          endLine();
        } else {
          if (count === columns) endLine();
          append(letter, run.format);
        }
      } else if (letter === "\n") {
        endWord();
        endLine();
      } else if (/\s/.test(letter)) {
        endWord();
      } else {
        word.push([letter, run.format]);
      }
    }
  }
  endWord();
  endLine();
  return rows;
}

export function labelLayout(node, blocks = []) {
  if (node.kind === "connectionPoint") return {width: node.width, height: node.height, lines: []};
  const widthRatio = node.shape === "diamond" ? 0.50 : node.shape === "ellipse" ? 0.72 : 0.94;
  const heightRatio = node.shape === "diamond" ? 0.47 : node.shape === "ellipse" ? 0.72 : 0.94;
  const textStyle = node.textStyle ?? {};
  const bodySize = textStyle.size ?? 13;
  const hiddenText = node.hideText && !!node.text?.trim();
  if (hiddenText) blocks = [{kind: "body", runs: [{text: "•••"}]}];
  const width = node.width;
  const labelWidth = Math.max(12, width * widthRatio - 16);
  const lines = [];

  function add(value, size, weight, color, style, section) {
    const text = value.trim().replace(/\s+/g, " ");
    if (!text) return;
    const wrapped = textWidth(text, size) <= labelWidth
      ? [text] : wrap(text, Math.max(2, Math.floor(labelWidth / (size * 0.65))));
    for (const text of wrapped) lines.push({section, text, size, weight, color, italic: style.italic, underline: style.underline, alignment: style.alignment, vertical: style.verticalAlignment, step: size * 1.25});
  }

  add(node.title, node.fontSize, node.bold ? 650 : 400, node.textColor, node, "title");
  blocks.forEach((block, index) => {
    const size = block.kind === "heading" ? Math.round(bodySize * 1.15) : bodySize;
    const weight = block.kind === "heading" || textStyle.bold ? 700 : 400;
    const runs = block.kind === "quote" ? [{text: "› "}, ...block.runs] : block.runs;
    wrapRuns(runs, Math.max(hiddenText ? 3 : 2, Math.floor(labelWidth / (size * 0.65))), block.kind === "code").forEach((pieces, row) => {
      const gap = row === 0 ? (index === 0 ? 8 : 3) : 0;
      lines.push({section: "textStyle", runs: pieces, text: pieces.map(piece => piece.text).join(""), size, weight,
        color: textStyle.color ?? node.textColor, italic: textStyle.italic, underline: textStyle.underline, alignment: textStyle.alignment, vertical: textStyle.verticalAlignment, step: size * 1.25 + gap, gap});
    });
  });

  const external = new Map();
  const inside = lines.filter(line => {
    if (line.runs || !node.titleOutside) return true;
    const horizontal = node.alignment;
    let vertical = node.verticalAlignment ?? "middle";
    if (vertical === "middle" && horizontal === "center") vertical = "top";
    const key = horizontal + "/" + vertical;
    if (!external.has(key)) external.set(key, {horizontal, vertical, rows: []});
    external.get(key).rows.push(line);
    return false;
  });
  const iconSpace = node.link ? 18 : 0;
  const height = node.height;
  const visible = [];
  let remaining = Math.max(node.fontSize * 1.25, height * heightRatio - 12 - iconSpace);
  const available = remaining;
  for (const line of inside) {
    if (remaining < line.step) break;
    visible.push(line);
    remaining -= line.step;
  }
  if (visible.length && visible.length < inside.length) {
    const last = visible.at(-1);
    last.text += "…";
    last.runs?.push({text: "…"});
  }

  if (hiddenText && !visible.some(line => line.runs)) {
    const marker = inside.at(-1);
    while (visible.length && remaining < marker.step) remaining += visible.pop().step;
    visible.push(marker);
    remaining = Math.max(0, remaining-marker.step);
  }

  const rank = line => ({top: 0, bottom: 1}[line.vertical] ?? 0.5);
  visible.sort((a, b) => rank(a) - rank(b));
  let offset = -(available + iconSpace) / 2;
  let bodyEnd;
  let bodyTop;
  const positioned = visible.map(line => {
    const top = offset + remaining * rank(line);
    if (line.runs) bodyEnd = top + line.step;
    if (line.runs && bodyTop === undefined) bodyTop = top + line.gap - 3;
    const y = top + (line.gap ?? 0) + line.size * (1.25 / 2 + 0.33);
    offset += line.step;
    const align = line.alignment ?? node.alignment;
    const x = align === "left" ? -labelWidth / 2 : align === "right" ? labelWidth / 2 : 0;
    return {...line, x, y, anchor: {left: "start", center: "middle", right: "end"}[align],
      fit: textWidth(line.text, line.size) > labelWidth ? labelWidth : undefined};
  });
  let bodyX = 0;
  let extentX = width / 2, extentY = Math.max(height, available + iconSpace) / 2;
  for (const {horizontal, vertical, rows} of external.values()) {
    const total = rows.reduce((sum, line) => sum + line.step, 0);
    const side = horizontal === "left" ? -1 : horizontal === "right" ? 1 : 0;
    const centerX = side * (width / 2 + 8 + labelWidth / 2);
    let y = vertical === "top" ? -height/2-8-total : vertical === "bottom" ? height/2+8 : -total/2;
    extentX = Math.max(extentX, Math.abs(centerX) + labelWidth/2 + 4);
    extentY = Math.max(extentY, Math.abs(y), Math.abs(y + total));
    for (const line of rows) {
      const anchor = horizontal === "left" ? "end" : horizontal === "right" ? "start" : "middle";
      positioned.push({...line, anchor, x: centerX - side * labelWidth/2,
        y: y + (line.gap ?? 0) + line.size * .955, fit: textWidth(line.text, line.size) > labelWidth ? labelWidth : undefined});
      if (line.runs) { bodyX = centerX; bodyTop ??= y + line.gap - 3; bodyEnd = y + line.step; }
      y += line.step;
    }
  }
  const fill = node.textFill ?? node.fill;
  const border = node.textBorder ?? node.border;
  const framed = bodyTop !== undefined && (fill.toLowerCase() !== node.fill.toLowerCase() || border.toLowerCase() !== node.border.toLowerCase());
  const frame = framed ? {x: bodyX-labelWidth / 2 - 3, y: bodyTop, width: labelWidth + 6, height: bodyEnd + 3 - bodyTop,
    fill, stroke: border.toLowerCase() === node.border.toLowerCase() ? "none" : border} : null;
  return {width, height, extentX, extentY, lines: positioned, frame};
}
