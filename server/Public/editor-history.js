// Entries contain only changed worksheet properties and entities, keyed by stable ID.
const collections = ["nodes", "edges"];
const metadata = new Set(["revision", "schemaVersion", "resetRevision", ...collections]);
const equal = (a, b) => {
  if (a === b) return true;
  if (!a || !b || typeof a !== "object" || typeof b !== "object") return false;
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every(k => equal(a[k], b[k]));
};
export {equal as sameValue};

export function worksheetChanges(before, after) {
  const changes = [];
  function fields(group, id, old, next) {
    for (const key of new Set([...Object.keys(old), ...Object.keys(next)])) {
      if (!group && metadata.has(key)) continue;
      if (["text", "label", "link"].includes(key) && !old[key] && !next[key]) continue;
      if (!equal(old[key], next[key])) changes.push({group, id, key, before: old[key], after: next[key]});
    }
  }
  fields(null, null, before, after);
  for (const group of collections) {
    const old = new Map(before[group].map((item, index) => [item.id, {item, index}]));
    const next = new Map(after[group].map((item, index) => [item.id, {item, index}]));
    for (const id of new Set([...old.keys(), ...next.keys()])) {
      const a = old.get(id), b = next.get(id);
      if (a && b) fields(group, id, a.item, b.item);
      else changes.push({group, id, before: a?.item, after: b?.item, index: (a || b).index});
    }
  }
  return changes;
}

export function replayChanges(sheet, changes, redo, occupied) {
  const result = structuredClone(sheet);
  for (const change of changes) {
    const {group, id, key} = change;
    const item = group ? result[group].find(entry => entry.id === id) : result;
    const expected = redo ? change.before : change.after;
    const value = redo ? change.after : change.before;
    if ((group === "nodes" && occupied(id)) || (key && !item) ||
        !equal(key ? item[key] : item, expected)) return null;
    if (key) {
      if (value === undefined) delete item[key];
      else item[key] = structuredClone(value);
    } else if (value) result[group].splice(change.index, 0, structuredClone(value));
    else result[group].splice(result[group].indexOf(item), 1);
  }
  const nodes = new Map(result.nodes.map(node => [node.id, node]));
  const connections = new Set();
  const degrees = new Map();
  for (const edge of result.edges) {
    const target = edge.target.node;
    if ((edge.source && !nodes.has(edge.source)) || (target && !nodes.has(target))) return null;
    for (const id of [edge.source, target]) {
      if (id) degrees.set(id, (degrees.get(id) ?? 0) + 1);
    }
    if (!edge.source || !target) continue;
    const pair = JSON.stringify([edge.source, target]);
    if (edge.source === target || connections.has(pair)) return null;
    connections.add(pair);
  }
  const checked = new Set();
  for (const node of result.nodes) {
    if (node.type === "junction" && (degrees.get(node.id) ?? 0) < 2) return null;
    if (node.elevated === true && (node.parent || node.type === "junction")) return null;
    const path = new Set();
    let current = node;
    while (current.parent && !checked.has(current.id)) {
      const parent = nodes.get(current.parent);
      if (parent?.type !== "box" || path.has(current.id)) return null;
      path.add(current.id);
      current = parent;
    }
    for (const id of path) checked.add(id);
  }
  return result;
}
