export const shapes = {
  rounded: "Lekerekített",
  rectangle: "Téglalap",
  ellipse: "Ellipszis",
  diamond: "Rombusz",
  triangle: "Háromszög",
  pentagon: "Ötszög",
  hexagon: "Hatszög",
  parallelogram: "Paralelogramma",
};

// Clockwise vertices in a box with half-width and half-height of one.
const polygons = {
  diamond: [[0,-1], [1,0], [0,1], [-1,0]],
  triangle: [[0,-1], [1,1], [-1,1]],
  pentagon: [[0,-1], [1,-.24], [.62,1], [-.62,1], [-1,-.24]],
  hexagon: [[-.5,-1], [.5,-1], [1,0], [.5,1], [-.5,1], [-1,0]],
  parallelogram: [[-.55,-1], [1,-1], [.55,1], [-1,1]],
};

export function polygonVertices(shape, halfWidth, halfHeight) {
  if (Object.hasOwn(polygons, shape)) return polygons[shape].map(([x, y]) => [x * halfWidth, y * halfHeight]);
}

const labelRatios = {
  diamond: [.50, .47, .45],
  ellipse: [.72, .72, .70],
  triangle: [.42, .42, .38],
  pentagon: [.58, .58, .60],
  hexagon: [.68, .76, .65],
  parallelogram: [.60, .75, .58],
};
export const shapeLabelRatios = shape => Object.hasOwn(labelRatios, shape) ? labelRatios[shape] : [.94, .94, .94];

export const edgeStyles = {
  arrow: "Egyirányú nyíl",
  both: "Kétirányú nyíl",
  dashed: "Szaggatott nyíl",
  rope: "Íves kötél",
};

export function automaticBorder(fill) {
  return "#" + [1, 3, 5].map(i => Math.floor(parseInt(fill.slice(i, i+2), 16)*2/3).toString(16).padStart(2,"0")).join("");
}

export const paper = "#f5f8fc";
export const defaultGridSpacing = 32;

export function automaticGridColor(background) {
  const rgb = [1, 3, 5].map(i => parseInt(background.slice(i, i + 2), 16));
  const darker = rgb.map(channel => Math.round(channel / 2));
  const lighter = rgb.map(channel => Math.round((channel + 255) / 2));
  const luminance = color => color.reduce((sum, channel, index) => {
    const srgb = channel / 255;
    const linear = srgb <= .04045 ? srgb / 12.92 : ((srgb + .055) / 1.055) ** 2.4;
    return sum + linear * [.2126, .7152, .0722][index];
  }, 0);
  const base = luminance(rgb) + .05;
  const best = base / (luminance(darker) + .05) >= (luminance(lighter) + .05) / base ? darker : lighter;
  return "#" + best.map(channel => channel.toString(16).padStart(2, "0")).join("");
}

export const cableColor = "#526982";
export const limit = (value, min, max) => Math.min(max, Math.max(min, value));

export function shapeGeometry(shape, width, height, padding = 0) {
  const x = width / 2 + padding, y = height / 2 + padding;
  if (shape === "ellipse") return ["ellipse", {rx: x, ry: y}];
  const vertices = polygonVertices(shape, x, y);
  if (vertices) return ["polygon", {points: vertices.map(vertex => vertex.join(",")).join(" ")}];
  return ["rect", {x: -x, y: -y, width: 2*x, height: 2*y, rx: shape === "rounded" ? 12 + padding : 0}];
}

export function selectionOutline(shape, width, height) {
  return shapeGeometry(shape, width, height, 10);
}

export function shapeDistance(node, point, padding = 0) {
  const x = (point.x - node.position.x) / (node.width / 2 + padding);
  const y = (point.y - node.position.y) / (node.height / 2 + padding);
  if (node.kind === "connectionPoint" || node.shape === "ellipse") return Math.hypot(x, y);
  if (Object.hasOwn(polygons, node.shape)) {
    const vertices = polygons[node.shape];
    // Each edge gives a linear distance from the center, normalized to one at the edge.
    return Math.max(...vertices.map(([ax, ay], i) => {
      const [bx, by] = vertices[(i + 1) % vertices.length];
      return (x * (by - ay) - y * (bx - ax)) / (ax * by - ay * bx);
    }));
  }
  return Math.max(Math.abs(x), Math.abs(y));
}

export function borderPoint(node, toward) {
  const ratio = shapeDistance(node, toward);
  if (!ratio) return node.position;
  return {
    x: node.position.x + (toward.x - node.position.x) / ratio,
    y: node.position.y + (toward.y - node.position.y) / ratio,
  };
}

export const lineTypes = {straight: "Egyenes", sCurve: "S-forma", zigzag: "Villám", lightning: "Tört", arc: "Íves", rope: "Kötél"};
export const lineAppearances = {plain: "Sima", thick: "Vastag", dashed: "Szaggatott", dotted: "Pontozott"};

export function edgePaint(edge) {
  const appearance = edge.appearance ?? "plain";
  const color = edge.color ?? cableColor;
  const width = Math.min(24, (edge.width ?? 2) * (appearance === "thick" ? 2 : 1));
  const dash = appearance === "dashed" ? `${width * 3.5} ${width * 2.5}`
    : appearance === "dotted" ? `0 ${width * 8}` : undefined;
  return {color, width, lineWidth: width * (appearance === "dotted" ? 2 : 1), dash,
    linecap: appearance === "dotted" || appearance === "thick" ? "round" : "butt",
    startArrow: edge.startArrow ?? false, endArrow: edge.endArrow ?? true};
}

export function edgeEndpoint(edge, end) {
  return end === "source" ? {node: edge.source, point: edge.sourcePoint} : edge.target;
}

function route(type, source, target) {
  const dx = target.x - source.x, dy = target.y - source.y;
  const length = Math.hypot(dx, dy);
  const x = (source.x + target.x) / 2, y = (source.y + target.y) / 2;
  switch (type) {
    case "sCurve":
      if (dx && dy) return {command: "C", points: Math.abs(dx) >= Math.abs(dy)
        ? [{x, y: source.y}, {x, y: target.y}]
        : [{x: source.x, y}, {x: target.x, y}]};
      break;
    case "lightning":
      if (length) {
        const offset = .2 * Math.tan(Math.PI / 6);
        return {command: "L", points: [
          {x: source.x + dx * .4 + dy * offset, y: source.y + dy * .4 - dx * offset},
          {x: source.x + dx * .6 - dy * offset, y: source.y + dy * .6 + dx * offset},
        ]};
      }
      break;
    case "zigzag":
      if (length) {
        const offset = .028;
        return {command: "L", points: [
          {x: source.x + dx * .515 - dy * offset, y: source.y + dy * .515 + dx * offset},
          {x: source.x + dx * .485 + dy * offset, y: source.y + dy * .485 - dx * offset},
        ]};
      }
      break;
    case "arc":
      if (length) {
        const rise = Math.min(110, length * .28);
        return {command: "Q", points: [{x: dx ? x : x + rise, y: y - rise}]};
      }
      break;
    case "rope":
      if (dx) return {command: "Q", points: [{x, y: y + Math.min(330, length * .85)}]};
      break;
  }
  return {command: "L", points: []};
}

export function edgeGeometry(edge, findNode) {
  const sourceNode = findNode(edge.source);
  const targetNode = findNode(edge.target.node);
  const source = sourceNode?.position ?? edge.sourcePoint;
  const target = targetNode?.position ?? edge.target.point;
  const {command, points} = route(edge.type, source, target);
  const from = sourceNode ? borderPoint(sourceNode, points[0] ?? target) : source;
  const to = targetNode ? borderPoint(targetNode, points.at(-1) ?? source) : target;
  const sourceToward = points[0] ?? to;
  const targetToward = points.at(-1) ?? from;
  const pair = p => `${p.x} ${p.y}`;
  const path = (start, end) => `M ${pair(start)} ${command} ${[...points, end].map(pair).join(" ")}`;
  const vertices = [from, ...points, to];
  const boundsPoints = vertices;
  const samples = command === "L" ? vertices : Array.from({length: 33}, (_, i) => {
    const t = i / 32, u = 1 - t;
    const weights = command === "Q" ? [u*u, 2*u*t, t*t] : [u**3, 3*u*u*t, 3*u*t*t, t**3];
    return {x: vertices.reduce((v,p,j) => v+p.x*weights[j],0), y: vertices.reduce((v,p,j) => v+p.y*weights[j],0)};
  });
  const lengths = samples.slice(1).map((p,i) => Math.hypot(p.x-samples[i].x,p.y-samples[i].y));
  const length = lengths.reduce((sum,n) => sum+n,0);
  let remaining = length/2;
  let index = 0;
  while (index < lengths.length-1 && remaining > lengths[index]) remaining -= lengths[index++];
  const a = samples[index], b = samples[index+1], fraction = lengths[index] ? remaining/lengths[index] : 0;
  const labelPosition = {x: a.x+(b.x-a.x)*fraction, y: a.y+(b.y-a.y)*fraction};
  let angle = Math.atan2(b.y-a.y,b.x-a.x) * 180 / Math.PI;
  if (angle > 90) angle -= 180;
  if (angle < -90) angle += 180;
  return {from, to, sourceToward, targetToward, bent: points.length > 0, boundsPoints, command, length, labelPosition, angle,
    path, d: path(from, to)};
}

export function edgeInRectangle({boundsPoints, command}, box, touching) {
  const epsilon = 1e-8;
  const minX = box.x-epsilon, minY = box.y-epsilon;
  const right = box.x+box.width+epsilon, bottom = box.y+box.height+epsilon;
  const inside = p => p.x >= minX && p.x <= right && p.y >= minY && p.y <= bottom;
  // Clip a segment to the two axis intervals, including contact at either boundary.
  function intersects(a, b) {
    let start = 0, end = 1;
    for (const [axis, min, max] of [["x",minX,right],["y",minY,bottom]]) {
      const delta = b[axis] - a[axis];
      if (!delta) {
        if (a[axis] < min || a[axis] > max) return false;
      } else {
        const first = (min-a[axis])/delta, last = (max-a[axis])/delta;
        start = Math.max(start, Math.min(first,last));
        end = Math.min(end, Math.max(first,last));
        if (start > end) return false;
      }
    }
    return true;
  }
  if (command === "L") return touching
    ? boundsPoints.some((p,i) => i > 0 && intersects(boundsPoints[i-1],p)) : boundsPoints.every(inside);

  // Subdivide only Bézier portions whose control hull straddles the rectangle.
  function visit(points, depth) {
    if (points.every(inside)) return true;
    if (points.every(p => p.x < minX) || points.every(p => p.x > right) ||
        points.every(p => p.y < minY) || points.every(p => p.y > bottom)) return false;
    const first = points[0], last = points.at(-1);
    if (touching && (inside(first) || inside(last))) return true;
    if (!touching && (!inside(first) || !inside(last))) return false;
    if (depth === 24) return touching ? intersects(first, last) : true;
    const left = [first], rightHalf = [last];
    let row = points;
    while (row.length > 1) {
      row = row.slice(1).map((p,i) => ({x: (p.x+row[i].x)/2, y: (p.y+row[i].y)/2}));
      left.push(row[0]);
      rightHalf.unshift(row.at(-1));
    }
    return touching ? visit(left, depth+1) || visit(rightHalf, depth+1)
      : visit(left, depth+1) && visit(rightHalf, depth+1);
  }
  return visit(boundsPoints, 0);
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
    const {boundsPoints, labelPosition, angle} = edgeGeometry(edge, id => nodes.get(id));
    for (const {x, y} of boundsPoints) {
      halfWidth = Math.max(halfWidth, Math.abs(x) + 40);
      halfHeight = Math.max(halfHeight, Math.abs(y) + 40);
    }
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
  const [widthRatio, heightRatio] = shapeLabelRatios(node.shape);
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
  const positioned = visible.map(line => {
    const top = offset + remaining * rank(line);
    const y = top + (line.gap ?? 0) + line.size * (1.25 / 2 + 0.33);
    offset += line.step;
    const align = line.alignment ?? node.alignment;
    const x = align === "left" ? -labelWidth / 2 : align === "right" ? labelWidth / 2 : 0;
    return {...line, x, y, anchor: {left: "start", center: "middle", right: "end"}[align],
      fit: textWidth(line.text, line.size) > labelWidth ? labelWidth : undefined};
  });
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
      y += line.step;
    }
  }
  return {width, height, extentX, extentY, overflow: visible.length < inside.length, lines: positioned};
}
