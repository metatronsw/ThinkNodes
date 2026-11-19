// Reapply only local field edits onto an acknowledged server revision. Entity arrays
// use stable IDs so independent insertions, removals and edits can arrive together.
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function mergeFields(base, local, remote) {
  if (equal(base, local)) return remote;
  if (local == null || typeof local !== "object" || Array.isArray(local) || !base || !remote) return local;
  const result = {...remote};
  for (const key of new Set([...Object.keys(base), ...Object.keys(local)])) {
    if (!equal(base[key], local[key])) {
      if (local[key] === undefined) delete result[key];
      else result[key] = mergeFields(base[key], local[key], remote[key]);
    }
  }
  return result;
}
export function rebaseWorksheet(base, local, remote) {
  const {nodes, edges, ...fields} = base;
  const {nodes: localNodes, edges: localEdges, ...localFields} = local;
  const result = mergeFields(fields, localFields, {...remote});
  function mergeEdge(before, edited, latest) {
    const edge = {...mergeFields(before, edited, latest)};
    if (before.source !== edited.source || !equal(before.sourcePoint, edited.sourcePoint)) {
      edge.source = edited.source;
      edge.sourcePoint = edited.sourcePoint;
    }
    if (!equal(before.target, edited.target)) edge.target = edited.target;
    return edge;
  }
  function entities(before, edited, latest, merge = mergeFields) {
    const old = new Map(before.map(item => [item.id, item]));
    const ours = new Map(edited.map(item => [item.id, item]));
    const merged = latest.filter(item => !old.has(item.id) || ours.has(item.id)).map(item =>
      old.has(item.id) ? merge(old.get(item.id), ours.get(item.id), item) : item);
    const ids = new Set(merged.map(item => item.id));
    return merged.concat(edited.filter(item => !old.has(item.id) && !ids.has(item.id)));
  }
  result.revision = remote.revision;
  result.nodes = entities(nodes, localNodes, remote.nodes).map(node => ({...node}));
  result.edges = entities(edges, localEdges, remote.edges, mergeEdge).map(edge => ({...edge}));
  const present = new Map(result.nodes.map(n => [n.id, n]));
  const lastKnown = new Map([...nodes, ...localNodes, ...remote.nodes].map(n => [n.id, n]));
  // A concurrent deletion can race with an attachment or a container drop.
  // Keep the wire at its last known location and the surviving child on the board.
  for (const edge of result.edges) {
    if (edge.source && !present.has(edge.source)) {
      edge.sourcePoint = lastKnown.get(edge.source).position;
      delete edge.source;
    }
    if (edge.target.node && (!present.has(edge.target.node) || edge.target.node === edge.source)) {
      edge.target = {point: lastKnown.get(edge.target.node).position};
    }
  }
  for (const node of result.nodes) {
    if (!node.parent) continue;
    const visited = new Set([node.id]);
    let parent = node.parent;
    while (parent) {
      if (visited.has(parent) || present.get(parent)?.kind !== "container") {
        delete node.parent;
        break;
      }
      visited.add(parent);
      parent = present.get(parent).parent;
    }
  }
  const attached = new Set(result.edges.flatMap(edge => [edge.source, edge.target.node]));
  result.nodes = result.nodes.filter(n => n.kind !== "connectionPoint" || attached.has(n.id));
  return result;
}

export function liveConnection(path, csrf, onState, onError) {
  const client = Array.from(crypto.getRandomValues(new Uint8Array(16)), b => b.toString(16).padStart(2, "0")).join("");
  const headers = {"Content-Type": "application/json", "X-CSRF-Token": csrf, "X-Worksheet-Client": client};
  let controller;
  async function request(action, fields, options = {}) {
    const response = await fetch("/api/presence/" + path, {method: "POST", headers,
      body: JSON.stringify({action, ...fields}), ...options});
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      throw Object.assign(new Error(detail.reason || "A munkalap nem érhető el."), {status: response.status});
    }
    return response.json();
  }
  async function start() {
    controller?.abort();
    const active = controller = new AbortController();
    let since;
    while (!active.signal.aborted) {
      try {
        const state = await request("poll", {since}, {signal: active.signal});
        if (active.signal.aborted) return;
        await onState(state);
        since = state.version;
      } catch (error) {
        if (active.signal.aborted) return;
        onError(error);
        if ([401, 403, 404].includes(error.status)) return;
        await new Promise(resolve => setTimeout(resolve, 1000));
        since = undefined;
      }
    }
  }
  function stop() {
    controller?.abort();
    request("leave", {}, {keepalive: true}).catch(() => {});
  }
  return {client, start, stop, snapshot: () => request("poll", {}), select: node => request("select", {node})};
}
