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
// A téma alapértelmezett betűtípusai (Theme.swift defaultFonts).
const defaultFonts = ["system-ui, sans-serif", "Georgia, 'Times New Roman', serif", "'Chalkboard SE', 'Comic Sans MS', cursive"];
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
  return ["rect", {x: -x, y: -y, width: 2*x, height: 2*y, rx: shape === "rounded" ? (currentGraphics().boxRadius ?? 12) + padding : 0}];
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

// Vonalméret: minden vonalnak három mérete van (1 vékony – alapértelmezett, 2 közepes, 3 vastag). A vastagság a méret
// alapvastagsága szorozva a téma vonaltípusonkénti szorzójával (graphics.lineScale: vonaltípus neve → szorzó, híján 1);
// a vastag megjelenés mindig kétszeres (Model.swift Connection.scaledWidth; egyezniük kell). A régi egyedi vastagság
// (`width`) a legközelebbi méretre vált.
export const lineBaseWidths = [2, 5, 10.5];
export function lineSize(edge) {
  const size = edge.size ?? (edge.width == null || edge.width <= 3.5 ? 1 : edge.width <= 7.5 ? 2 : 3);
  return Math.min(3, Math.max(1, Math.round(size) || 1));
}
export function edgePaint(edge) {
  const appearance = edge.appearance ?? "plain";
  const color = edge.color ?? cableColor;
  // A téma szorzója vonaltípusonként egy szám, vagy megjelenésenként külön szám (Theme.swift LineScale).
  const scale = currentGraphics().lineScale?.[edge.type ?? "straight"] ?? 1;
  const width = Math.min(maximumLineWidth, lineBaseWidths[lineSize(edge) - 1]
    * (appearance === "thick" ? 2 : 1) * (typeof scale === "number" ? scale : scale[appearance] ?? 1));
  const lineWidth = Math.min(maximumLineWidth, width * (appearance === "dotted" ? 2 : 1));
  const dash = appearance === "dashed" ? `${width * 3.5} ${width * 2.5}`
    : appearance === "dotted" ? `0 ${width * 8}` : undefined;
  return {color, width, lineWidth, dash,
    labelSize: appearance === "thick" ? 18 + 2 * lineWidth : 12 + lineWidth,
    labelWeight: appearance === "thick" ? 700 : 400,
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

// Oda-vissza kötés (A → B és B → A): a két vonal ne fedje egymást. Mindkettő a saját haladási irányához képest jobbra
// tolódik (a két doboz ennyivel eltolt helyéből számolva), így egymás mellett, párhuzamosan futnak, és a csatlakozási
// pontjaik is egymás mellé kerülnek. Az eltolás a két vonal vastagságával nő, hogy vastag vonalak se érjenek össze, és
// egyik nyílhegye se lógjon rá a másik vonalra: a két középvonal távolsága az egyik nyílhegy fél szélessége (a nyílhegy
// fél hossza) + a másik vonal fél vastagsága + 4 képpont, a két irány közül a nagyobb, de legalább 12. Két 2-es vonalnál
// 12, két 12-esnél 27, két 24-esnél 45 képpont. (Rendering.swift ugyanígy számol.)
export function pairShift(width, partner) {
  const reach = (own, other) => arrowLength(own) / 2 + other / 2 + 4;
  return Math.max(12, reach(width, partner), reach(partner, width)) / 2;
}
// A lap vonalainak útvonalai ("forrás>cél" → a vonal vastagsága); ebből derül ki, van-e egy vonalnak ellenirányú párja.
export function wireRoutes(edges) {
  const routes = new Map();
  for (const edge of edges) {
    if (!edge.source || !edge.target?.node) continue;
    const route = edge.source + ">" + edge.target.node;
    routes.set(route, Math.max(routes.get(route) ?? 0, edgePaint(edge).lineWidth));
  }
  return routes;
}
// Az ellenirányú pár vastagsága, vagy 0, ha a vonalnak nincs párja.
export const reverseWidth = (edge, routes) => edge.source && edge.target?.node && edge.source !== edge.target.node
  ? routes.get(edge.target.node + ">" + edge.source) ?? 0 : 0;

// `paired`: az ellenirányú pár vastagsága (0 = nincs pár).
export function edgeGeometry(edge, findNode, nested = 0, paired = 0) {
  let sourceNode = findNode(edge.source);
  let targetNode = findNode(edge.target.node);
  if (paired && !nested && sourceNode && targetNode && !isDataLink(edge, findNode)) {
    const across = targetNode.position.x - sourceNode.position.x, down = targetNode.position.y - sourceNode.position.y;
    const length = Math.hypot(across, down);
    if (length > 0) {
      const gap = pairShift(edgePaint(edge).lineWidth, paired);
      const shift = {x: -down / length * gap, y: across / length * gap};
      sourceNode = {...sourceNode, position: {x: sourceNode.position.x + shift.x, y: sourceNode.position.y + shift.y}};
      targetNode = {...targetNode, position: {x: targetNode.position.x + shift.x, y: targetNode.position.y + shift.y}};
    }
  }
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
  // Adatvonal (táblázat ↔ grafikon): mindig a doboz másik doboz felé eső oldalának közepéhez csatlakozik.
  if (sourceNode && targetNode && isDataLink(edge, findNode)) {
    from = sideMidpoint(sourceNode, target);
    to = sideMidpoint(targetNode, source);
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

// Adatvonal: táblázatot (vagy CSV-t) és grafikont, illetve struktúra-forrást (.json) és struktúra-konténert összekötő vonal. Nem tárolt
// tulajdonság, a két végpont adja (Rendering.swift isDataLink). Nyíl helyett mindkét végén félkorong áll.
export const isGridType = type => type === "table" || type === "csv";
// Struktúra-forrás: szövegfájl-doboz a struktúra-konténer forrásformátumával (structure-boxes.js `formats`; ma .json,
// később .swift). Model.swift Idea.isStructureSource párja.
export const structureSourcePattern = /\.json$/i;
export const isStructureFileNode = node => Boolean(node?.file) && (node.type === "code" || node.type === "text")
  && structureSourcePattern.test(node.file.filename ?? node.file.asset ?? "");
export function isDataLink(edge, node) {
  const a = node(edge.source), b = node(edge.target?.node);
  return Boolean(a && b) && ((a.type === "chart" && isGridType(b.type)) || (b.type === "chart" && isGridType(a.type))
    || (Boolean(a.structure) && isStructureFileNode(b)) || (Boolean(b.structure) && isStructureFileNode(a)));
}
// A félkorong az egységnyi nyíl koordinátáiban (a csúcs az origó): a lapos oldala a doboz oldalára simul, a domború
// a vonal felé néz. A doboznak azt az oldalát követi, amelyiken a végpont van, nem a vonal irányát.
// A doboz `toward` felé eső oldalának közepe (Rendering.swift sideMidpoint).
export function sideMidpoint(node, toward) {
  const dx = (toward.x - node.position.x) / (node.width / 2), dy = (toward.y - node.position.y) / (node.height / 2);
  return Math.abs(dx) >= Math.abs(dy)
    ? {x: node.position.x + (dx < 0 ? -1 : 1) * node.width / 2, y: node.position.y}
    : {x: node.position.x, y: node.position.y + (dy < 0 ? -1 : 1) * node.height / 2};
}
export const plugPath = "M0 -.5A.5 .5 0 0 0 0 .5Z";
export const plugSize = width => Math.max(16, width * 6);
export function plugTransform(node, tip, width) {
  const dx = (tip.x - node.position.x) / (node.width / 2), dy = (tip.y - node.position.y) / (node.height / 2);
  const normal = Math.abs(dx) >= Math.abs(dy) ? {x: dx < 0 ? -1 : 1, y: 0} : {x: 0, y: dy < 0 ? -1 : 1};
  return arrowTransform(tip, {x: tip.x + normal.x, y: tip.y + normal.y}, plugSize(width));
}

export function wireArrow(tip, toward, width, visible, limit = Infinity) {
  const dx = toward.x - tip.x, dy = toward.y - tip.y;
  const distance = Math.hypot(dx, dy);
  const length = Math.min(arrowLength(width), distance, limit);
  const ratio = visible && distance ? length / distance : 0;
  return {visible, transform: arrowTransform(tip, toward, length),
    base: {x: tip.x + dx * ratio, y: tip.y + dy * ratio}};
}

// A vonal két nyílhegye és a vonal rövidített végpontjai: a vonal a nyílhegy talpáig (`base`) tart, nem a csúcsáig.
// Két nyílhegy rövid, egyenes vonalon legfeljebb a fél hosszig ér. A szerkesztő és a megtekintő közös számítása;
// a szerveroldali párja: Rendering.swift (`head`).
export function wireHeads({from, to, sourceToward, targetToward, bent}, {width, startArrow, endArrow}) {
  const limit = bent || !(startArrow && endArrow) ? Infinity : Math.hypot(to.x - from.x, to.y - from.y) / 2;
  return {source: wireArrow(from, sourceToward, width, startArrow, limit),
    target: wireArrow(to, targetToward, width, endArrow, limit)};
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

// Becsült betűszélesség em-ben; a böngészőben mért rendszer-, talpas és kézírásos betűkhöz kalibrálva,
// kis ráhagyással (Rendering.swift letterWidth párja; a két oldalnak pontosan egyeznie kell).
function letterWidth(letter, monospace = false) {
  if (monospace) return 0.62;
  if (letter === " ") return 0.28;
  if (letter === "…") return 0.85;
  if ("ilIjf.,:;!|'`".includes(letter)) return 0.3;
  if ("tr()[]-/\"".includes(letter)) return 0.38;
  if ("MW@#%&".includes(letter)) return 0.88;
  if (letter === "m" || letter === "w") return 0.82;
  if (letter >= "0" && letter <= "9") return 0.6;
  const lower = letter.toLowerCase(), upper = letter.toUpperCase();
  if (lower !== upper) return letter === lower ? 0.55 : 0.7;
  return 0.65;
}
const boldFactor = 1.07;
// A téma betűcsaládja rögzített szélességű-e (az első megnevezett család alapján).
export function isMonospaceFont(family) {
  return /mono|menlo|courier|consolas/i.test(String(family ?? "").split(",")[0]);
}
function letterMeasure(size, bold, monospace) {
  return (letter, format) => letterWidth(letter, monospace || !!format?.code) * size * (bold || format?.bold ? boldFactor : 1);
}
function textWidth(value, size, {bold = false, monospace = false} = {}) {
  const measure = letterMeasure(size, bold, monospace);
  let width = 0;
  for (const letter of value) width += measure(letter);
  return width;
}


// Tördelés becsült szélesség szerint: `width(betű, formátum)` adja egy betű szélességét, `limit` a sor szélessége.
// Alapértelmezésben minden betű 1 széles, így `limit` oszlopszám (CanvasMarkdown.swift wrapMarkdown párja).
// `limit`: a sor szélessége, vagy függvény, amely soronként ad helyet ({x, width, skip}; lásd textSlot) – ekkor a sor
// a kapott helyet a `slot` mezőben viszi tovább.
function wrapRuns(runs, limit, preformatted, width = () => 1) {
  const rows = [];
  let line = [];
  let word = [];
  let used = 0;
  let lastFormat;
  const flowing = typeof limit === "function";
  let slot = null;
  // A sor helyét az első tartalma előtt (legkésőbb a lezárásakor) kérjük el, soronként egyszer.
  const cap = () => flowing ? (slot ??= limit()).width : limit;

  function endLine(wrapped = false) {
    if (line.length) {
      if (flowing) { cap(); rows.push({pieces: line, wrapped, width: used, slot}); slot = null; }
      else rows.push({pieces: line, wrapped, width: used});
    }
    line = [];
    used = 0;
    lastFormat = undefined;
  }

  function append(letter, format, size) {
    if (line.length && lastFormat === format) line.at(-1).text += letter;
    else line.push({text: letter, format});
    lastFormat = format;
    used += size;
  }

  function endWord() {
    if (!word.length) return;
    let wordWidth = 0;
    for (const [, , size] of word) wordWidth += size;
    if (used > 0) {
      const space = width(" ", undefined);
      if (used + space + wordWidth > cap()) endLine(true);
      else append(" ", undefined, space);
    }
    for (const [letter, format, size] of word) {
      if (used > 0 && used + size > cap()) endLine(true);
      append(letter, format, size);
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
          const size = width(letter, run.format);
          if (used > 0 && used + size > cap()) endLine(true);
          append(letter, run.format, size);
        }
      } else if (letter === "\n") {
        endWord();
        endLine();
      } else if (/\s/.test(letter)) {
        endWord();
      } else {
        word.push([letter, run.format, width(letter, run.format)]);
      }
    }
  }
  endWord();
  endLine();
  return rows;
}

// Körbefuttatott szöveg egy sorának helye (Rendering.swift textSlot párja; pontosan egyezniük kell). A címketerület
// `width` széles, a sor `top`-tól `height` magas; az akadályok a címketerület bal felső sarkához mért téglalapok. A sor a
// legszélesebb szabad szakaszt kapja; ha az túl keskeny, lejjebb csúszik az útban lévő akadály alá (`skip`).
export function textSlot(obstacles, width, top, height, indent) {
  const start = top;
  const least = Math.min(width - indent, Math.max(40, height * 2));
  for (let attempt = 0; attempt <= obstacles.length; attempt++) {
    const blocking = obstacles.filter(o => o.top < top + height && o.bottom > top);
    let free = [[indent, width]];
    for (const o of blocking) {
      free = free.flatMap(([a, b]) => o.right <= a || o.left >= b ? [[a, b]]
        : [[a, Math.min(b, o.left)], [Math.max(a, o.right), b]].filter(([from, to]) => to > from));
    }
    let best = null;
    for (const part of free) if (!best || part[1] - part[0] > best[1] - best[0]) best = part;
    if (best && best[1] - best[0] >= least) return {x: best[0], width: best[1] - best[0], skip: top - start};
    if (!blocking.length) break;
    top = Math.max(top + 1, Math.min(...blocking.map(o => o.bottom)));
  }
  return {x: indent, width: width - indent, skip: top - start};
}

function shortenLine(line, width, measure) {
  let remaining = width - measure("…", undefined);
  const runs = [];
  let used = 0;
  for (const run of line.runs ?? [{text: line.text}]) {
    let prefix = "";
    for (const letter of run.text) {
      const size = measure(letter, run.format);
      remaining -= size;
      if (remaining < 0) break;
      used += size;
      prefix += letter;
    }
    if (prefix) runs.push({...run, text: prefix});
    if (remaining < 0) break;
  }
  runs.push({text: "…"});
  return {...line, text: runs.map(run => run.text).join(""), runs: line.runs ? runs : undefined, wrapped: false,
    width: used + measure("…", undefined)};
}

// Egysoros felirat (link, fájlnév, címke): ha nem fér el, „…”-tal rövidül. Nincs tördelés, nincs összenyomás.
export function fitCaption(text, size, available) {
  const measure = letterMeasure(size, false, false);
  if (textWidth(text, size) <= available) return text;
  return shortenLine({text, size}, available, measure).text;
}

// Címsor mérete az alapméret arányában (Rendering.swift headingScale).
export const headingScale = level => ({1: 1.6, 2: 1.3}[level] ?? 1.15);

// Doboz szövegének elrendezése; a Rendering.swift ideaDrawing/nodeSVG párja (docs/node-types.md, Text képesség).
// `obstacles`: a konténer szövegét kikerülendő gyermekdobozok ({x, y, width, height}; x, y a doboz közepéhez mérve).
export function labelLayout(node, blocks = [], obstacles = []) {
  // NAGYBETŰS: a tördelés előtt, mert a nagybetűs szöveg szélesebb (Rendering.swift ideaDrawing).
  if (node.uppercase) blocks = blocks.map(block => ({...block, runs: block.runs.map(run => ({...run, text: run.text.toLocaleUpperCase("hu")}))}));
  if (node.type !== "box" && node.type !== "preview") return {width: node.width, height: node.height, lines: []};
  // .web doboz: az előnézeti kép tölti ki, a szöveg csak buboréksúgóban jelenik meg (Rendering.swift ideaDrawing).
  // Linkes doboz előnézettel (Rendering.swift fillsWithPreview): .web mindig, munkalap/külső link ha nincs kikapcsolva.
  if (node.link && (node.link.kind === "web" || !node.staticPreview)) return {width: node.width, height: node.height, extentX: node.width / 2, extentY: node.height / 2,
    overflow: node.type === "preview" ? commentCollapsed(node) : Boolean(node.text?.trim()), lines: [], labelWidth: node.width, iconSpace: 0, previewSpace: node.height, webPreview: true};
  const [widthRatio, heightRatio] = shapeLabelRatios(node.shape);
  const width = node.width, height = node.height;
  const labelWidth = Math.max(12, width * widthRatio - 16);
  const iconSpace = 0;  // a link felirata a doboz alatt, a dobozon kívül áll
  const previewSpace = 0;  // előnézet csak teljes kitöltéssel
  const labelHeight = height * heightRatio - 12 - iconSpace - previewSpace;
  const strong = false;  // a Félkövér gomb megszűnt
  const fonts = currentGraphics().fonts ?? defaultFonts;
  const monospace = isMonospaceFont(fonts[Math.min(Math.max((node.font ?? 1) - 1, 0), fonts.length - 1)]);
  const measureFor = line => letterMeasure(line.size, line.weight >= 700, monospace || line.code);
  // Körbefuttatás: az akadályok a címketerület bal felső sarkához mérve, térközzel (fent és lent 8, két oldalt 18 képpont).
  const flow = obstacles.length > 0;
  const margin = 8, sideMargin = 18;
  const blocked = obstacles.map(o => ({
    left: o.x - o.width / 2 - sideMargin + labelWidth / 2, right: o.x + o.width / 2 + sideMargin + labelWidth / 2,
    top: o.y - o.height / 2 - margin + Math.max(0, labelHeight) / 2, bottom: o.y + o.height / 2 + margin + Math.max(0, labelHeight) / 2,
  }));
  const room = line => line.slotWidth ?? labelWidth - line.indent;

  // `start`: körbefuttatásnál a szöveg kezdete a címketerület tetejétől (függőleges igazítás).
  function makeLines(base, start = 0) {
    const lines = [];
    let cursor = start;
    blocks.forEach((block, index) => {
      const heading = block.kind === "heading";
      let size = heading ? base * headingScale(block.level) * (strong ? 1.1 : 1) : base;
      if (!node.fitText) size = Math.round(size);
      const weight = heading ? (strong ? 900 : 700) : (strong ? 650 : 400);
      const indent = Math.max(0, (block.indent ?? 0) - 1) * base * 1.2;
      const code = block.kind === "code";
      const runs = block.kind === "quote" ? [{text: "› "}, ...block.runs] : block.runs;
      const measure = letterMeasure(size, weight >= 700, monospace || code);
      const blank = (block.blankLines ?? 0) * base * 1.25;
      let first = true;
      const limit = !flow ? labelWidth - indent : () => {
        const lead = first ? blank : 0;
        first = false;
        const slot = textSlot(blocked, labelWidth, cursor + lead, size * 1.25, indent);
        cursor += lead + slot.skip + size * 1.25;
        return slot;
      };
      wrapRuns(runs, limit, code, measure).forEach(({pieces, wrapped, width, slot}, row) => {
        // Ahány üres sor van a forrásban, annyi üres sor marad a dobozon is.
        const gap = (row === 0 ? blank : 0) + (slot?.skip ?? 0);
        // Címsor sosem sorkizárt: a vízszintes igazítást (bal / közép / jobb) követi, sorkizárt szövegű dobozban is.
        lines.push({justify: node.justified && !code && !heading, wrapped, runs: pieces, text: pieces.map(piece => piece.text).join(""),
          size, weight, indent, code, width, color: node.textColor, step: size * 1.25 + gap, gap,
          slotX: slot?.x, slotWidth: slot?.width});
      });
    });
    if (node.hideText && lines.length > 1) {
      // Összecsukott állapot: az első sor marad, alatta egy sorközzel az ellipszis.
      const first = lines[0];
      return [first, {...first, runs: [{text: "…"}], text: "…", justify: false, wrapped: false, indent: 0, gap: 0,
        width: measureFor(first)("…", undefined),
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
          candidate.every(line => line.width <= room(line))) {
        lines = candidate;
        low = size + 1;
      } else high = size - 1;
    }
  } else lines = makeLines(node.fontSize ?? 16);

  const available = Math.max(0, labelHeight);
  const rank = {top: 0, bottom: 1}[node.verticalAlignment] ?? 0.5;
  // Körbefuttatás függőleges igazítással: a sorok helye a kezdőponttól függ (más magasságban más dobozok vannak útban),
  // ezért néhány lépésben közelítünk: a szöveg ott kezdődjön, ahonnan a magassága szerint középre / alulra kerül.
  // (Rendering.swift ideaDrawing ugyanígy számol.) Szövegillesztésnél (fitText) a szöveg felül kezdődik.
  let flowStart = 0;
  if (flow && rank > 0 && !node.fitText) {
    const tall = rows => rows.reduce((sum, line) => sum + line.step, 0);
    // 1. A kezdőpont közelítése: onnan induljon, ahonnan a saját magassága szerint középre / alulra kerül.
    for (let attempt = 0; attempt < 3; attempt++) {
      const next = Math.max(0, Math.round((available - tall(lines)) * rank));
      if (next === flowStart) break;
      flowStart = next;
      lines = makeLines(node.fontSize ?? 16, flowStart);
    }
    // 2. Ha lejjebb kezdve több akadály kerül útba és a szöveg kilógna, annyival feljebb kezdődik, amennyivel kilóg.
    for (let attempt = 0; attempt < 8 && flowStart > 0 && flowStart + tall(lines) > available; attempt++) {
      flowStart = Math.max(0, flowStart - Math.ceil(flowStart + tall(lines) - available));
      lines = makeLines(node.fontSize ?? 16, flowStart);
    }
  }
  const visible = [];
  let remaining = available - flowStart;
  for (const line of lines) {
    if (remaining < line.step) break;
    visible.push(line);
    remaining -= line.step;
  }
  const omitted = visible.length < lines.length;
  let overflow = omitted || (node.hideText && blocks.length > 1);
  for (let i = 0; i < visible.length; i++) {
    const line = visible[i];
    if (line.width > room(line) || (omitted && i === visible.length - 1)) {
      visible[i] = shortenLine(line, room(line), measureFor(line));
      overflow = true;
    }
  }
  const extra = available - visible.reduce((sum, line) => sum + line.step, 0);
  let offset = -(available + iconSpace + previewSpace) / 2 + previewSpace;
  const positioned = visible.map(line => {
    const top = offset + (flow ? flowStart : extra * rank);
    const y = top + (line.gap ?? 0) + line.size * (1.25 / 2 + 0.33);
    offset += line.step;
    const align = line.justify || line.indent > 0 ? "left" : node.alignment ?? "center";
    const left = -labelWidth / 2 + (line.slotX ?? line.indent), span = room(line);
    const x = line.slotWidth === undefined ? (align === "left" ? left : align === "right" ? labelWidth / 2 : 0)
      : align === "left" ? left : align === "right" ? left + span : left + span / 2;
    // Sorkizárás: csak a tördelt (nem bekezdés-záró) sorok érnek a doboz mindkét széléig; a rövid sor balra zárt marad.
    const justifyWidth = line.justify && line.wrapped && line.text.includes(" ") && line.width < room(line)
      ? room(line) : undefined;
    return {...line, x, y, anchor: {left: "start", center: "middle", right: "end"}[align], justifyWidth};
  });
  return {width, height, extentX: width / 2, extentY: height / 2, overflow, lines: positioned, labelWidth, iconSpace, previewSpace};
}

// Doboz szövegének elrendezése a dobozon szerkesztéshez (editor.js renderCodeEdit): a nyers szöveg sorai ugyanazzal a
// tördeléssel, betűmérettel, körbefuttatással és függőleges igazítással, mint megjelenítéskor (labelLayout), de
// - minden karakter megmarad (a sor végi szóköz és a sortörés az előző sorhoz tartozik), így a sorok a forrás
//   [from, to) szakaszai, és összefűzve a teljes szöveget adják;
// - nincs csonkítás: a dobozból kilógó sorok is megvannak (szerkesztéskor a szöveg görgethető);
// - a markdown jelölés nyersen látszik, minden sor az alapméretben.
// Eredmény: {size, labelWidth, labelHeight, top, rows: [{from, to, x, width, gap}]}; `top`: az első sor távolsága a
// címketerület tetejétől, `x` / `width`: a sor helye a címketerületen belül, `gap`: a sor fölötti térköz.
export function editLabelLayout(node, text = "", obstacles = []) {
  const [widthRatio, heightRatio] = shapeLabelRatios(node.shape);
  const labelWidth = Math.max(12, node.width * widthRatio - 16);
  const labelHeight = Math.max(0, node.height * heightRatio - 12);
  const fonts = currentGraphics().fonts ?? defaultFonts;
  const monospace = isMonospaceFont(fonts[Math.min(Math.max((node.font ?? 1) - 1, 0), fonts.length - 1)]);
  const flow = obstacles.length > 0;
  const margin = 8, sideMargin = 18;
  const blocked = obstacles.map(o => ({
    left: o.x - o.width / 2 - sideMargin + labelWidth / 2, right: o.x + o.width / 2 + sideMargin + labelWidth / 2,
    top: o.y - o.height / 2 - margin + labelHeight / 2, bottom: o.y + o.height / 2 + margin + labelHeight / 2,
  }));
  const upper = letter => node.uppercase ? letter.toLocaleUpperCase("hu") : letter;

  function makeRows(size, start = 0) {
    const measure = letterMeasure(size, false, monospace), step = size * 1.25, space = measure(" ");
    const letterSize = letter => { let total = 0; for (const part of upper(letter)) total += measure(part); return total; };
    const rows = [];
    let cursor = start, fits = true, from = 0;
    for (const source of text.split("\n")) {
      const end = from + source.length, last = end >= text.length;
      const next = last ? end : end + 1;   // a sortörés a bekezdés utolsó sorához tartozik
      if (!source.trim()) {
        // Üres sor: helyet foglal, de nem kerül ki semmit (labelLayout: a blokk előtti üres sorok).
        rows.push({from, to: next, x: 0, width: labelWidth, gap: 0, used: 0});
        cursor += step;
        from = next;
        continue;
      }
      let row = from, used = 0, slot = null;
      const place = () => {
        if (!flow) return labelWidth;
        if (!slot) { slot = textSlot(blocked, labelWidth, cursor, step, 0); cursor += slot.skip + step; }
        return slot.width;
      };
      const endRow = to => {
        const width = place();
        if (used > width) fits = false;
        rows.push({from: row, to, x: slot?.x ?? 0, width, gap: slot?.skip ?? 0, used});
        if (!flow) cursor += step;
        row = to; used = 0; slot = null;
      };
      // Szavanként, a wrapRuns szabályai szerint; `at`: a szó kezdete a forrásban.
      let at = from, word = [], wordWidth = 0;
      const endWord = () => {
        if (!word.length) return;
        if (used > 0) {
          if (used + space + wordWidth > place()) endRow(at);
          else used += space;
        }
        let index = at;
        for (const [letter, size] of word) {
          if (used > 0 && used + size > place()) endRow(index);
          used += size;
          index += letter.length;
        }
        word = []; wordWidth = 0;
      };
      let index = from;
      for (const letter of source) {
        if (/\s/.test(letter)) endWord();
        else {
          if (!word.length) at = index;
          const size = letterSize(letter);
          word.push([letter, size]);
          wordWidth += size;
        }
        index += letter.length;
      }
      endWord();
      endRow(next);
      from = next;
    }
    return {rows, fits, height: rows.reduce((sum, line) => sum + step + line.gap, 0)};
  }

  let size = node.fitText ? 1 : Math.round(node.fontSize ?? 16), made;
  if (node.fitText) {
    let low = 1, high = Math.floor(labelHeight / 1.25);
    made = makeRows(1);
    while (low <= high) {
      const middle = Math.floor((low + high) / 2), candidate = makeRows(middle);
      if (candidate.height <= labelHeight && candidate.fits) { made = candidate; size = middle; low = middle + 1; }
      else high = middle - 1;
    }
  } else made = makeRows(size);
  const rank = {top: 0, bottom: 1}[node.verticalAlignment] ?? 0.5;
  // Körbefuttatás függőleges igazítással: a kezdőpont közelítése, mint a labelLayoutban.
  let flowStart = 0;
  if (flow && rank > 0 && !node.fitText) {
    for (let attempt = 0; attempt < 3; attempt++) {
      const next = Math.max(0, Math.round((labelHeight - made.height) * rank));
      if (next === flowStart) break;
      flowStart = next;
      made = makeRows(size, flowStart);
    }
    for (let attempt = 0; attempt < 8 && flowStart > 0 && flowStart + made.height > labelHeight; attempt++) {
      flowStart = Math.max(0, flowStart - Math.ceil(flowStart + made.height - labelHeight));
      made = makeRows(size, flowStart);
    }
  }
  return {size, labelWidth, labelHeight, top: flow ? flowStart : Math.max(0, (labelHeight - made.height) * rank),
    rows: made.rows.map(({from, to, x, width, gap}) => ({from, to, x, width, gap}))};
}

// A link rövid felirata a dobozon (Rendering.swift linkCaption).
export function linkCaption(link) {
  if (link.kind === "url") { try { return new URL(link.target).host; } catch { return link.target; } }
  if (link.kind === "web") return link.target.split("/").at(-1).replace(/\.web$/, "");
  return link.target;
}

export {textWidth, wrapRuns};

// Megjegyzés (fájldoboz, előnézetes doboz) a doboz alatt: sima szöveg, minden sora (Rendering.swift visibleComment).
const commentLines = text => (text ?? "").trim().split(/\r?\n/);
// Összecsukott, többsoros megjegyzés: a teljes szöveg buboréksúgóban.
export const commentCollapsed = node => !!node.hideText && commentLines(node.text).length > 1;
export function visibleComment(node) {
  const lines = commentLines(node.text);
  return node.hideText && lines.length > 1 ? lines[0] + "\n…" : lines.join("\n");
}
