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

// The viewer receives resolved geometry from the server. The editor supplies its reactive theme.
let currentGraphics = () => ({});
export function useWorksheetGeometry(readGraphics) { currentGraphics = readGraphics; }
export function displayShape(shape) { return shape === "rounded" ? currentGraphics().box ?? shape : shape; }
function verticesFor(shape) {
  const graphics = currentGraphics();
  return graphics.box === shape && graphics.contour
    ? graphics.contour.map(({x,y}) => [x,y]) : polygons[shape];
}
export function polygonVertices(shape, halfWidth, halfHeight) {
  shape = displayShape(shape);
  const chamfer = currentGraphics().boxChamfer;
  if (shape === "rounded" && chamfer > 0) {
    const x = halfWidth, y = halfHeight, cut = Math.min(x, y, chamfer);
    return [[-x+cut,-y], [x-cut,-y], [x,-y+cut], [x,y-cut], [x-cut,y], [-x+cut,y], [-x,y-cut], [-x,-y+cut]];
  }
  if (Object.hasOwn(polygons, shape)) return verticesFor(shape).map(([x, y]) => [x * halfWidth, y * halfHeight]);
}

const labelRatios = {
  diamond: [.50, .47, .45],
  ellipse: [.72, .72, .70],
  triangle: [.42, .42, .38],
  pentagon: [.58, .58, .60],
  hexagon: [.68, .76, .65],
  parallelogram: [.60, .75, .58],
};
export const shapeLabelRatios = shape => labelRatios[displayShape(shape)] ?? [.94, .94, .94];

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
  shape = displayShape(shape);
  const x = width / 2 + padding, y = height / 2 + padding;
  if (shape === "ellipse") return ["ellipse", {rx: x, ry: y}];
  const vertices = polygonVertices(shape, x, y);
  if (vertices) return ["polygon", {points: vertices.map(vertex => vertex.join(",")).join(" ")}];
  return ["rect", {x: -x, y: -y, width: 2*x, height: 2*y, rx: shape === "rounded" ? 12 + padding : 0}];
}

export function shapeOutline(tag, geometry) {
  if (tag === "polygon") return "M" + geometry.points + "Z";
  if (tag === "ellipse") {
    const {rx, ry} = geometry;
    return `M${-rx} 0A${rx} ${ry} 0 1 0 ${rx} 0A${rx} ${ry} 0 1 0 ${-rx} 0Z`;
  }
  const {x, y, width, height, rx: r} = geometry;
  const right = x + width, bottom = y + height;
  return `M${x+r} ${y}H${right-r}Q${right} ${y} ${right} ${y+r}V${bottom-r}Q${right} ${bottom} ${right-r} ${bottom}H${x+r}Q${x} ${bottom} ${x} ${bottom-r}V${y+r}Q${x} ${y} ${x+r} ${y}Z`;
}

export function selectionOutline(shape, width, height) {
  const padding = 10;
  const vertices = polygonVertices(shape, width / 2, height / 2);
  if (!vertices) return shapeGeometry(shape, width, height, padding);

  // Uniform scaling preserves the angles. The closest edge sets the minimum gap.
  const nearestEdge = Math.min(...vertices.map(([x, y], index) => {
    const [nextX, nextY] = vertices[(index + 1) % vertices.length];
    return Math.abs(x * nextY - y * nextX) / Math.hypot(nextX - x, nextY - y);
  }));
  const scale = 1 + padding / nearestEdge;
  return shapeGeometry(shape, width * scale, height * scale);
}

export function shapeDistance(node, point, padding = 0) {
  const w = node.width / 2 + padding, h = node.height / 2 + padding;
  const dx = point.x - node.position.x, dy = point.y - node.position.y;
  const x = dx / w, y = dy / h;
  const shape = node.type === "junction" ? currentGraphics().junction ?? "ellipse" : displayShape(node.shape);
  if (shape === "ellipse") return Math.hypot(x, y);
  const vertices = polygonVertices(shape, w, h);
  if (vertices) {
    // Each edge gives a linear distance from the center, normalized to one at the edge.
    return Math.max(...vertices.map(([ax, ay], i) => {
      const [bx, by] = vertices[(i + 1) % vertices.length];
      return (dx * (by - ay) - dy * (bx - ax)) / (ax * by - ay * bx);
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

export const lineTypes = {straight: "Egyenes", sCurve: "S-forma", zigzag: "Villám", lightning: "Zigzag", arc: "Íves", rope: "Kötél"};
export const lineAppearances = {plain: "Sima", thick: "Vastag", dashed: "Szaggatott", dotted: "Pontozott"};
export const maximumLineWidth = 32;

export function edgePaint(edge) {
  const appearance = edge.appearance ?? "plain";
  const color = edge.color ?? cableColor;
  const width = Math.min(maximumLineWidth, (edge.width ?? 2) * (appearance === "thick" ? 2 : 1));
  const lineWidth = Math.min(maximumLineWidth, width * (appearance === "dotted" ? 2 : 1));
  const dash = appearance === "dashed" ? `${width * 3.5} ${width * 2.5}`
    : appearance === "dotted" ? `0 ${width * 8}` : undefined;
  return {color, width, lineWidth, dash,
    labelSize: appearance === "thick" ? 18 + 2 * lineWidth : 12 + lineWidth,
    labelWeight: appearance === "thick" ? 700 : 400,
    linecap: appearance === "dotted" || appearance === "thick" ? "round" : "butt",
    startArrow: edge.startArrow ?? false, endArrow: edge.endArrow ?? true};
}

export function wireGradientValues(from, to, {startArrow, endArrow}) {
  const first = startArrow && !endArrow ? 1 : -1;
  const directions = startArrow && endArrow ? [first, -first, first] : [first, -first];
  return directions.map(direction => (direction * (to.x - from.x)) + " " + (direction * (to.y - from.y))).join(";");
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
        const offset = Math.min(.08, 24 / length);
        return {command: "L", points: Array.from({length: 6}, (_, i) => {
          const along = (i + 1) / 7, across = i % 2 ? -offset : offset;
          return {x: source.x + dx * along + dy * across, y: source.y + dy * along - dx * across};
        })};
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

function arcControl(from, to, rise) {
  return {x: (from.x + to.x) / 2 + (to.y - from.y) * rise * 2,
    y: (from.y + to.y) / 2 - (to.x - from.x) * rise * 2};
}

function roundedCorners(start, bends, end, wide) {
  const vertices = [start, ...bends, end];
  return bends.map((corner, i) => {
    const neighbors = [vertices[i], vertices[i + 2]];
    const distances = neighbors.map(point => Math.hypot(point.x - corner.x, point.y - corner.y));
    const trim = Math.min(wide ? 24 : 5, Math.min(...distances) * (wide ? .45 : .22));
    const edges = neighbors.map((point, index) => {
      const fraction = distances[index] ? trim / distances[index] : 0;
      return {x: corner.x + (point.x - corner.x) * fraction, y: corner.y + (point.y - corner.y) * fraction};
    });
    return [edges[0], corner, edges[1]];
  });
}

export function edgeGeometry(edge, findNode, nested = 0) {
  const sourceNode = findNode(edge.source);
  const targetNode = findNode(edge.target.node);
  const source = sourceNode?.position ?? edge.sourcePoint;
  const target = targetNode?.position ?? edge.target.point;
  const graphics = currentGraphics();
  const type = edge.type === "straight" ? graphics.line ?? "straight" : edge.type;
  const dx = target.x-source.x, dy = target.y-source.y;
  const rise = type === "straight" ? graphics.lineArc : 0;
  const custom = type === graphics.line && graphics.linePoints;
  const {command, points: routed} = custom
    ? {command: "L", points: graphics.linePoints.map(p => ({x: source.x+dx*p.x-dy*p.y, y: source.y+dy*p.x+dx*p.y}))}
    : rise && (dx || dy) ? {command: "Q", points: [arcControl(source, target, rise)]} : route(type, source, target);
  const multiBend = type === "lightning" && !custom;
  let from = source, to = target;
  const centered = source.x === target.x && source.y === target.y;
  const centeredDirection = {x: source.x + 1, y: source.y};
  if (nested > 0) {
    from = borderPoint(sourceNode, centered ? centeredDirection : target);
    to = borderPoint(targetNode, from);
  } else if (nested < 0) {
    to = borderPoint(targetNode, centered ? centeredDirection : source);
    from = borderPoint(sourceNode, to);
  } else {
    if (sourceNode) from = borderPoint(sourceNode, multiBend ? target : routed[0] ?? target);
    if (targetNode) to = borderPoint(targetNode, multiBend ? source : routed.at(-1) ?? source);
  }
  const points = multiBend ? route(type, from, to).points : routed;
  if (command === "Q" && rise) points[0] = arcControl(from, to, rise);
  const sourceToward = points[0] ?? to;
  const targetToward = points.at(-1) ?? from;
  const pair = p => `${p.x} ${p.y}`;
  const rounded = graphics.roundedWires && command === "L" && points.length && ["zigzag", "lightning"].includes(type);
  const corners = rounded ? roundedCorners(from, points, to, type === "lightning") : [];
  const path = (start, end) => {
    if (!rounded) return `M ${pair(start)} ${command} ${[...points, end].map(pair).join(" ")}`;
    const bends = roundedCorners(start, points, end, type === "lightning");
    return `M ${pair(start)} ${bends.map(([entry, corner, exit]) =>
      `L ${pair(entry)} Q ${pair(corner)} ${pair(exit)}`).join(" ")} L ${pair(end)}`;
  };
  const vertices = [from, ...points, to];
  let metrics;
  function measure() {
    if (metrics) return metrics;
    const samples = rounded ? [from, ...corners.flatMap(corner => Array.from({length: 9}, (_, i) => {
      const t = i / 8, u = 1 - t;
      const [a, b, c] = corner;
      return {x: a.x*u*u + b.x*2*u*t + c.x*t*t, y: a.y*u*u + b.y*2*u*t + c.y*t*t};
    })), to] : command === "L" ? vertices : Array.from({length: 33}, (_, i) => {
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
    return metrics = {length, labelPosition, angle, samples};
  }
  const arc = !custom && (type === "arc" || rise > 0) ? points[0] ?? arcControl(from, to, 0) : null;
  return {from, to, sourceToward, targetToward, bent: points.length > 0, boundsPoints: vertices, command, corners,
    arc,
    get length() { return measure().length; },
    get labelPosition() { return measure().labelPosition; },
    get angle() { return measure().angle; },
    labelClearance(halfWidth) {
      const {samples, labelPosition, angle} = measure();
      const radians = angle * Math.PI / 180;
      const cos = Math.cos(radians), sin = Math.sin(radians);
      return samples.reduce((offset, point) => {
        const x = point.x - labelPosition.x, y = point.y - labelPosition.y;
        return Math.abs(x * cos + y * sin) <= halfWidth ? Math.min(offset, y * cos - x * sin) : offset;
      }, 0);
    },
    path, d: path(from, to)};
}

export function edgeInRectangle({boundsPoints, command, corners}, box, touching) {
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
  if (corners?.length) {
    const parts = corners.flatMap((curve, i) => [[i ? corners[i - 1][2] : boundsPoints[0], curve[0]], curve]);
    parts.push([corners.at(-1)[2], boundsPoints.at(-1)]);
    const matches = points => points.length === 2
      ? touching ? intersects(...points) : points.every(inside) : visit(points, 0);
    return touching ? parts.some(matches) : parts.every(matches);
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

export function wireLabelLayout(geometry, label, paint, inline) {
  const {labelPosition: center, angle, from, to, boundsPoints} = geometry;
  const {labelSize: fontSize, labelWeight: fontWeight, lineWidth} = paint;
  const naturalWidth = textWidth(label, fontSize) * (fontWeight === 700 ? 1.08 : 1);
  const transform = `translate(${center.x} ${center.y}) rotate(${angle})`;
  const above = () => ({transform, fontSize, fontWeight, width: naturalWidth,
    y: geometry.labelClearance(naturalWidth / 2) - lineWidth / 2 - 10 - (fontSize - 14) / 4});
  if (!inline) return above();
  const radians = angle * Math.PI / 180;
  const cosine = Math.cos(radians), sine = Math.sin(radians);
  const distanceAlongLabel = point => Math.abs((point.x - center.x) * cosine + (point.y - center.y) * sine);
  const room = Math.min(distanceAlongLabel(from), distanceAlongLabel(to));
  if (room < 2) return above();
  const padding = Math.min(8, room / 5);
  // Az eredeti betűarányokat nem nyomjuk össze: ha a vonalba nem fér el, a felirat a vonal fölé kerül.
  if (naturalWidth > 2 * (room - padding - Math.min(20, room / 3))) return above();
  const gap = naturalWidth / 2 + padding;
  const extent = Math.max(...boundsPoints.map(point => Math.hypot(point.x - center.x, point.y - center.y))) + 40 + 2 * paint.lineWidth;
  const clip = `M ${-extent} ${-extent} H ${-gap} V ${extent} H ${-extent} Z M ${gap} ${-extent} H ${extent} V ${extent} H ${gap} Z`;
  return {transform, y: 0, fontSize, fontWeight, width: naturalWidth, clip};
}

export function arrowLength(width) {
  return Math.min(width * 6.75, 13.5 + (width - 2) * 2);
}

export function arrowTransform(tip, toward, length) {
  const angle = Math.atan2(tip.y-toward.y,tip.x-toward.x)*180/Math.PI;
  return `translate(${tip.x} ${tip.y}) rotate(${angle}) scale(${length})`;
}

export function wireArrow(tip, toward, width, visible, limit = Infinity) {
  const dx = toward.x - tip.x, dy = toward.y - tip.y;
  const distance = Math.hypot(dx, dy);
  const length = Math.min(arrowLength(width), distance, limit);
  const ratio = visible && distance ? length / distance : 0;
  return {visible, transform: arrowTransform(tip, toward, length),
    base: {x: tip.x + dx * ratio, y: tip.y + dy * ratio}};
}

export function taperedArc({from, to, arc}, {width, dash, startArrow, endArrow}) {
  if (!arc || dash || !(startArrow || endArrow)) return null;
  const span = Math.hypot(to.x - from.x, to.y - from.y);
  const source = wireArrow(from, arc, width, startArrow, span * .4);
  const target = wireArrow(to, arc, width, endArrow, span * .4);
  const start = source.base, end = target.base;
  const sample = t => {
    const u = 1 - t;
    return {x: u*u*start.x + 2*u*t*arc.x + t*t*end.x, y: u*u*start.y + 2*u*t*arc.y + t*t*end.y};
  };
  const steps = 32;
  let previous = start;
  const lengths = [0];
  for (let i = 1; i <= steps; i++) {
    const point = sample(i / steps);
    lengths.push(lengths[i - 1] + Math.hypot(point.x - previous.x, point.y - previous.y));
    previous = point;
  }
  let segment = 1;
  const sections = Array.from({length: steps + 1}, (_, i) => {
    const progress = i / steps;
    const distance = progress * lengths[steps];
    while (segment < steps && lengths[segment] < distance) segment++;
    const length = lengths[segment] - lengths[segment - 1];
    const t = length ? (segment - 1 + (distance - lengths[segment - 1]) / length) / steps : progress;
    const dx = (1 - t) * (arc.x - start.x) + t * (end.x - arc.x);
    const dy = (1 - t) * (arc.y - start.y) + t * (end.y - arc.y);
    const tangent = Math.hypot(dx, dy) || 1;
    const weight = startArrow && endArrow ? Math.abs(2 * progress - 1) : startArrow ? 1 - progress : progress;
    const radius = Math.min(width, span * .3) / 2 * (.25 + .75 * weight);
    return {point: sample(t), x: -dy / tangent * radius, y: dx / tangent * radius};
  });
  function outline(scale = 1) {
    const side = direction => sections.map(({point, x, y}) =>
      `${point.x + x * scale * direction} ${point.y + y * scale * direction}`);
    return "M " + [...side(1), ...side(-1).reverse()].join(" L ") + " Z";
  }
  return {outline, ends: {source, target}};
}

export function canvasBounds(board) {
  let halfWidth = 360;
  let halfHeight = 240;
  const nodes = new Map(board.nodes.map(node => [node.id, node]));
  for (const node of board.nodes) {
    const padding = node.elevated === true ? 84 : 40;
    halfWidth = Math.max(halfWidth, Math.abs(node.position.x) + (node.extentX ?? node.width / 2) + padding);
    if (node.type === "junction" && node.text) {
      const reach = node.width / 2 + 4 + textWidth(node.text, 14);
      halfWidth = Math.max(halfWidth, Math.abs(node.position.x) + reach + 40);
      halfHeight = Math.max(halfHeight, Math.abs(node.position.y) + reach + 40);
    }
    halfHeight = Math.max(halfHeight, Math.abs(node.position.y) + (node.extentY ?? node.height / 2) + padding);
  }
  for (const edge of board.edges) {
    const geometry = edgeGeometry(edge, id => nodes.get(id));
    for (const {x, y} of geometry.boundsPoints) {
      halfWidth = Math.max(halfWidth, Math.abs(x) + 40);
      halfHeight = Math.max(halfHeight, Math.abs(y) + 40);
    }
    if (edge.label?.trim()) {
      const {labelPosition, angle} = geometry;
      const label = wireLabelLayout(geometry, edge.label, edgePaint(edge), edge.labelInLine);
      const radius = label.width / 2;
      const radians = angle * Math.PI / 180;
      const cosine = Math.cos(radians), sine = Math.sin(radians);
      const padding = Math.max(28, label.fontSize + 12);
      halfWidth = Math.max(halfWidth, Math.abs(labelPosition.x - sine * label.y) + Math.abs(cosine) * radius + padding);
      halfHeight = Math.max(halfHeight, Math.abs(labelPosition.y + cosine * label.y) + Math.abs(sine) * radius + padding);
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


function wrapRuns(runs, columns, preformatted) {
  const rows = [];
  let line = [];
  let word = [];
  let count = 0;
  let lastFormat;

  function endLine(wrapped = false) {
    if (line.length) rows.push({pieces: line, wrapped});
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
      if (count + word.length + 1 > columns) endLine(true);
      else append(" ", undefined);
    }
    for (const [letter, format] of word) {
      if (count === columns) endLine(true);
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
          if (count === columns) endLine(true);
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

function shortenLine(line, width) {
  let remaining = width - textWidth("…", line.size);
  const runs = [];
  for (const run of line.runs ?? [{text: line.text}]) {
    let prefix = "";
    for (const letter of run.text) {
      remaining -= textWidth(letter, line.size);
      if (remaining < 0) break;
      prefix += letter;
    }
    if (prefix) runs.push({...run, text: prefix});
    if (remaining < 0) break;
  }
  runs.push({text: "…"});
  return {...line, text: runs.map(run => run.text).join(""), runs: line.runs ? runs : undefined, wrapped: false};
}

// Címsor mérete az alapméret arányában (Rendering.swift headingScale).
export const headingScale = level => ({1: 1.6, 2: 1.3}[level] ?? 1.15);

// Doboz szövegének elrendezése; a Rendering.swift ideaDrawing/nodeSVG párja (docs/node-types.md, Text képesség).
export function labelLayout(node, blocks = []) {
  if (node.type !== "box") return {width: node.width, height: node.height, lines: []};
  const [widthRatio, heightRatio] = shapeLabelRatios(node.shape);
  const width = node.width, height = node.height;
  const labelWidth = Math.max(12, width * widthRatio - 16);
  const iconSpace = node.link ? 20 : 0;
  const previewSpace = node.link && node.link.kind !== "url" ? height * 0.5 : 0;
  const labelHeight = height * heightRatio - 12 - iconSpace - previewSpace;
  const strong = node.bold === true;

  function makeLines(base) {
    const lines = [];
    blocks.forEach((block, index) => {
      const heading = block.kind === "heading";
      let size = heading ? base * headingScale(block.level) * (strong ? 1.1 : 1) : base;
      if (!node.fitText) size = Math.round(size);
      const weight = heading ? (strong ? 900 : 700) : (strong ? 650 : 400);
      const indent = Math.max(0, (block.indent ?? 0) - 1) * base * 1.2;
      const columns = Math.max(2, Math.floor((labelWidth - indent) / (size * 0.65)));
      const runs = block.kind === "quote" ? [{text: "› "}, ...block.runs] : block.runs;
      wrapRuns(runs, columns, block.kind === "code").forEach(({pieces, wrapped}, row) => {
        // Bekezdések között az üres sor egy teljes sornyi térközt ad.
        const blockGap = index === 0 ? 0 : heading ? size * 0.35 : block.kind === "body" ? size * 1.25 : 3;
        const gap = row === 0 ? (node.fitText ? Math.min(blockGap, base * 0.4) : blockGap) : 0;
        lines.push({justify: node.justified && block.kind !== "code", wrapped, runs: pieces, text: pieces.map(piece => piece.text).join(""),
          size, weight, indent, color: node.textColor, step: size * 1.25 + gap, gap});
      });
    });
    if (node.hideText && lines.length > 1) {
      // Összecsukott állapot: az első sor marad, alatta egy sorközzel az ellipszis.
      const first = lines[0];
      return [first, {...first, runs: [{text: "…"}], text: "…", justify: false, wrapped: false, indent: 0, gap: 0,
        step: first.size * 1.25}];
    }
    return lines;
  }

  let lines;
  if (node.fitText) {
    let low = 1, high = Math.floor(labelHeight / 1.25);
    lines = makeLines(1);
    while (low <= high) {
      const size = Math.floor((low + high) / 2);
      const candidate = makeLines(size);
      if (candidate.reduce((sum, line) => sum + line.step, 0) <= labelHeight &&
          candidate.every(line => textWidth(line.text, line.size) + line.indent <= labelWidth)) {
        lines = candidate;
        low = size + 1;
      } else high = size - 1;
    }
  } else lines = makeLines(node.fontSize ?? 16);

  const available = Math.max(0, labelHeight);
  const visible = [];
  let remaining = available;
  for (const line of lines) {
    if (remaining < line.step) break;
    visible.push(line);
    remaining -= line.step;
  }
  const omitted = visible.length < lines.length;
  let overflow = omitted || (node.hideText && blocks.length > 1);
  for (let i = 0; i < visible.length; i++) {
    const line = visible[i];
    if (textWidth(line.text, line.size) + line.indent > labelWidth || (omitted && i === visible.length - 1)) {
      visible[i] = shortenLine(line, labelWidth - line.indent);
      overflow = true;
    }
  }
  const rank = {top: 0, bottom: 1}[node.verticalAlignment] ?? 0.5;
  const extra = available - visible.reduce((sum, line) => sum + line.step, 0);
  let offset = -(available + iconSpace + previewSpace) / 2 + previewSpace;
  const positioned = visible.map(line => {
    const top = offset + extra * rank;
    const y = top + (line.gap ?? 0) + line.size * (1.25 / 2 + 0.33);
    offset += line.step;
    const align = line.justify || line.indent > 0 ? "left" : node.alignment ?? "center";
    const x = align === "left" ? -labelWidth / 2 + line.indent : align === "right" ? labelWidth / 2 : 0;
    let wordSpacing;
    if (line.justify && line.wrapped) {
      const spaces = line.text.split(" ").length - 1;
      const lineWidth = textWidth(line.text, line.size);
      if (spaces && lineWidth < labelWidth - line.indent) wordSpacing = (labelWidth - line.indent - lineWidth) / spaces;
    }
    return {...line, x, y, anchor: {left: "start", center: "middle", right: "end"}[align], wordSpacing};
  });
  return {width, height, extentX: width / 2, extentY: height / 2, overflow, lines: positioned, labelWidth, iconSpace, previewSpace};
}

// A link rövid felirata a dobozon (Rendering.swift linkCaption).
export function linkCaption(link) {
  if (link.kind === "url") { try { return new URL(link.target).host; } catch { return link.target; } }
  if (link.kind === "web") return link.target.split("/").at(-1).replace(/\.web$/, "");
  return link.target;
}

export {textWidth};
