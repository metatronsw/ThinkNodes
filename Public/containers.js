import {displayShape, polygonVertices} from "./geometry.js?v=22";

// Positions stay in worksheet coordinates when a node changes parent.
export function ancestors(node, byID) {
  const parents = [];
  while (node.parent) {
    node = byID.get(node.parent);
    if (!node) break;
    parents.push(node);
  }
  return parents;
}

function outline(node) {
  const {x, y} = node.position;
  const w = node.width / 2, h = node.height / 2;
  const vertices = polygonVertices(node.shape, w, h);
  if (vertices) return vertices.map(([dx, dy]) => [x + dx, y + dy]);
  const shape = displayShape(node.shape);
  if (shape === "ellipse") return Array.from({length: 48}, (_, i) => {
    const angle = i * Math.PI / 24;
    return [x+w*Math.cos(angle), y+h*Math.sin(angle)];
  });
  if (shape === "rounded") {
    const r = Math.min(12, w, h);
    return [[w-r,h-r],[-w+r,h-r],[-w+r,-h+r],[w-r,-h+r]].flatMap(([cx,cy], corner) =>
      Array.from({length: 7}, (_, i) => {
        const angle = (corner + i/6) * Math.PI/2;
        return [x+cx+r*Math.cos(angle), y+cy+r*Math.sin(angle)];
      }));
  }
  return [[x-w,y-h],[x+w,y-h],[x+w,y+h],[x-w,y+h]];
}

function area(points) {
  return Math.abs(points.reduce((sum, p, i) => {
    const q = points[(i + 1) % points.length];
    return sum + p[0]*q[1] - q[0]*p[1];
  }, 0)) / 2;
}

export function overlapFraction(node, container) {
  if (Math.abs(node.position.x - container.position.x) * 2 >= node.width + container.width ||
      Math.abs(node.position.y - container.position.y) * 2 >= node.height + container.height) return 0;
  let polygon = outline(node);
  const total = area(polygon);
  const clip = outline(container);
  for (let i = 0; i < clip.length && polygon.length; i++) {
    const a = clip[i], b = clip[(i+1) % clip.length];
    const side = p => (b[0]-a[0])*(p[1]-a[1]) - (b[1]-a[1])*(p[0]-a[0]);
    const result = [];
    let previous = polygon.at(-1), previousSide = side(previous);
    for (const point of polygon) {
      const currentSide = side(point);
      if ((previousSide < 0) !== (currentSide < 0)) {
        const t = previousSide / (previousSide - currentSide);
        result.push([previous[0]+t*(point[0]-previous[0]), previous[1]+t*(point[1]-previous[1])]);
      }
      if (currentSide >= 0) result.push(point);
      previous = point;
      previousSide = currentSide;
    }
    polygon = result;
  }
  return area(polygon) / total;
}
