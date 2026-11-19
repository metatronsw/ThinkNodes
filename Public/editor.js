import {canvasBounds, commentColor, edgeEndpoint, edgeGeometry, edgePaint, edgeStyles, labelLayout, limit, lineStyles, paper, shapeDistance, shapes} from "./geometry.js";

import {ancestors, containerOrder, overlapFraction} from "./containers.js";

const mount = document.querySelector("#editor");
const {path, csrf, role, user} = mount.dataset;
const d3 = window.d3;
const {createApp, computed, h, nextTick, onMounted, onUnmounted, ref, shallowRef, watch} = window.Vue;
const endpoint = "/api/worksheet/" + path;
const svgNamespace = "http://www.w3.org/2000/svg";

function icon(name) {
  return h("svg", {class: "ui-icon", "aria-hidden": "true", viewBox: "0 0 24 24"}, [
    h("use", {href: "/icons.svg#" + name}),
  ]);
}

function button(label, onClick, props = {}) {
  const {symbol = "file", ...attributes} = props;
  return h("button", {type: "button", class: "button", onClick, ...attributes}, [icon(symbol), label]);
}

function link(label, href, symbol) {
  return h("a", {class: "button", href}, [icon(symbol), label]);
}

const ColorPicker = {
  props: {label: String, color: String},
  emits: ["update"],
  setup(props, {emit}) {
    const expanded = ref(false);
    const draft = ref(props.color);
    watch(() => props.color, color => { draft.value = color; });
    const valid = value => /^#?[\da-f]{6}$/i.test(value);
    function apply(color) {
      draft.value = color;
      emit("update", color);
    }
    function typed(event) {
      draft.value = event.target.value;
      if (valid(draft.value)) emit("update", "#" + draft.value.replace(/^#/, "").toLowerCase());
    }
    function swatch(color) {
      return h("svg", {viewBox: "0 0 40 12", preserveAspectRatio: "none", "aria-hidden": "true"},
        [h("rect", {width: 40, height: 12, fill: color})]);
    }
    const presets = ["#ffffff", "#000000", "#e95c59", "#f3ae49", "#f3df65", "#60b77a", "#5aaed2", "#657ace", "#a375be", "#e198ad"];
    return () => h("div", {class: "color-field"}, [
      h("span", props.label),
      h("button", {type: "button", class: "color-sample", "aria-label": props.label + " színválasztó",
        "aria-expanded": expanded.value, onClick: () => { expanded.value = !expanded.value; }}, [swatch(props.color)]),
      h("input", {type: "text", value: draft.value, maxlength: 7, spellcheck: false, autocomplete: "off",
        "aria-label": props.label + " HEX", "aria-invalid": valid(draft.value) ? undefined : "true",
        onInput: typed, onChange: typed, onKeydown: e => { if (e.key === "Escape") draft.value = props.color; }}),
      expanded.value ? h("div", {class: "color-tools"}, [
        h("div", {class: "color-presets"}, presets.map(color => h("button", {type: "button", key: color,
          "aria-label": props.label + " " + color, title: color, onClick: () => apply(color)}, [swatch(color)]))),
        ...["Piros", "Zöld", "Kék"].map((label, i) => {
          const offset = 1 + i * 2;
          const change = event => apply(props.color.slice(0, offset) +
            Number(event.target.value).toString(16).padStart(2, "0") + props.color.slice(offset + 2));
          return field(label, h("input", {type: "range", min: 0, max: 255, step: 1,
            value: parseInt(props.color.slice(offset, offset+2), 16), onInput: change, onChange: change}));
        }),
        field("Rendszerpaletta", h("input", {type: "color", value: props.color,
          onInput: e => apply(e.target.value), onChange: e => apply(e.target.value)})),
      ]) : null,
    ]);
  },
};

function colorPicker(label, value, change, key) {
  return h(ColorPicker, {key, label, color: value, onUpdate: change});
}

function select(value, choices, onChange, props = {}) {
  return h("select", {
    value,
    onChange: event => onChange(event.target.value), ...props,
  }, Object.entries(choices).map(([key, label]) => h("option", {key, value: key}, label)));
}

function field(label, control) {
  return h("label", [h("span", label), control]);
}

function input(value, change, props = {}) {
  return h("input", {value, onInput: event => change(event.target.value), ...props});
}

function numeric(value, change, min, max, props = {}) {
  return input(value, next => {
    const parsed = Number(next);
    if (next !== "" && parsed >= min && parsed <= max) change(parsed);
  }, {
    type: "number", min, max, step: "any",
    onBlur: event => { event.target.value = value; },
    ...props,
  });
}

function checkbox(label, checked, change) {
  return h("label", {class: "check"}, [
    h("input", {type: "checkbox", checked, onChange: event => change(event.target.checked)}),
    label,
  ]);
}

function textarea(value, change) {
  return h("textarea", {value, maxlength: 30000, rows: 7, onInput: event => change(event.target.value)});
}

function draftMarkdown(source) {
  return source.slice(0, 6000).split(/\r?\n/).filter(line => line.trim()).map(line => {
    const heading = /^\s{0,3}#{1,6}[ \t]+/;
    const text = line.replace(heading, "").replace(/\*\*([^*]+)\*\*/g, "$1").replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
    return {kind: heading.test(line) ? "heading" : "body", runs: [{text}]};
  });
}

function shape(node) {
  const x = node.width / 2;
  const y = node.height / 2;
  if (node.kind === "connectionPoint") return h("circle", {r: 7, fill: node.fill});
  const style = {fill: node.fill, stroke: node.border, "stroke-width": 1.6};
  if (node.shape === "ellipse") return h("ellipse", {...style, rx: x, ry: y});
  if (node.shape === "diamond") return h("polygon", {...style, points: ["0," + -y, x + ",0", "0," + y, -x + ",0"].join(" ")});
  return h("rect", {...style, x: -x, y: -y, width: node.width, height: node.height, rx: node.shape === "rounded" ? 12 : 0});
}

function arrowDefinition(id, color) {
  return h("marker", {key: id, id, viewBox: "0 0 10 10", markerWidth: 4.5, markerHeight: 4.5, refX: 9, refY: 5,
    orient: "auto-start-reverse"}, [
    h("path", {d: "M 0 0 L 10 5 L 0 10 z", fill: color}),
  ]);
}

function edgeAppearance(edge, marker) {
  const {color, width, startArrow, endArrow} = edgePaint(edge);
  return {
    stroke: color, "stroke-width": width,
    "marker-start": startArrow ? "url(#" + marker + ")" : undefined,
    "marker-end": endArrow ? "url(#" + marker + ")" : undefined,
    "stroke-dasharray": edge.style === "dashed" ? (width * 3.5) + " " + (width * 2.5) : undefined,
  };
}

function setEndpoint(edge, end, endpoint) {
  if (end === "source") {
    edge.source = endpoint.node;
    edge.sourcePoint = endpoint.point;
  } else {
    edge.target = endpoint;
  }
}

function otherEnd(end) {
  return end === "source" ? "target" : "source";
}

async function checked(response) {
  if (response.ok) return response;
  const detail = await response.json().catch(() => ({}));
  throw new Error(detail.reason || "A kérés nem sikerült (" + response.status + ").");
}

createApp({
  setup() {
    const board = ref(null);
    const nodeMap = computed(() => new Map(board.value?.nodes.map(node => [node.id, node])));
    const edgeMap = computed(() => new Map(board.value?.edges.map(edge => [edge.id, edge])));
    const containers = computed(() => containerOrder(board.value?.nodes ?? [], nodeMap.value));
    const ctrl = ref(false);
    const alt = ref(false);
    const accounts = ref(null);
    const canManage = computed(() => role === "admin" || Boolean(user && board.value?.owner === user));
    const canvasMarkdown = shallowRef(new Map());
    const markdownSources = computed(() => [...new Set(
      board.value?.nodes.filter(node => node.showMarkdown && node.markdown).map(node => node.markdown)
    )]);
    const drawings = computed(() => new Map(board.value?.nodes.map(node => {
      const markdown = node.showMarkdown && node.markdown
        ? canvasMarkdown.value.get(node.markdown) ?? draftMarkdown(node.markdown) : [];
      const layout = labelLayout(node, markdown);
      return [node.id, {node: {...node, width: layout.width, height: layout.height}, layout}];
    })));
    const drawnNode = id => drawings.value.get(id)?.node;
    const drawnBounds = () => canvasBounds({
      nodes: [...drawings.value.values()].map(drawing => drawing.node), edges: board.value.edges,
    });
    const selected = ref(null);
    const pendingStyle = ref("arrow");
    const reconnect = ref(null);
    const menu = ref(null);
    const inspector = ref(null);
    const note = ref(null);
    const canvas = ref(null);
    const view = shallowRef(d3.zoomIdentity);
    const size = ref({width: 0, height: 0});
    const gesture = ref(null);
    const preview = ref(null);
    const status = ref("");
    const problem = ref("");
    const saving = ref(false);
    const generation = ref(0);
    const savedGeneration = ref(0);
    const dirty = computed(() => generation.value !== savedGeneration.value);
    let zoom;
    let resizeObserver;
    let lastClick;
    let rightPress = false;
    let noteRequest = 0;

    async function loadCanvasMarkdown(sources, signal) {
      const missing = sources.filter(source => !canvasMarkdown.value.has(source));
      let blocks = [];
      if (missing.length) {
        const result = await checked(await fetch("/api/markdown/canvas", {
          method: "POST", signal,
          headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf},
          body: JSON.stringify({sources: missing}),
        }));
        ({blocks} = await result.json());
      }
      if (signal?.aborted) return;
      const current = new Set(markdownSources.value);
      const updated = new Map([...canvasMarkdown.value].filter(([source]) => current.has(source)));
      missing.forEach((source, index) => {
        if (current.has(source)) updated.set(source, blocks[index]);
      });
      canvasMarkdown.value = updated;
    }

    watch(markdownSources, (sources, _, onCleanup) => {
      const controller = new AbortController();
      const timer = setTimeout(() => loadCanvasMarkdown(sources, controller.signal).catch(() => {
        // Keep the immediate draft visible if a preview request fails.
      }), 80);
      onCleanup(() => {
        clearTimeout(timer);
        controller.abort();
      });
    });

    function modified() {
      generation.value += 1;
      problem.value = "";
      status.value = "";
    }

    const center = () => [size.value.width / 2, size.value.height / 2];
    const worldAtCenter = () => {
      const [centerX, centerY] = center();
      const [x, y] = view.value.invert([centerX, centerY]);
      return {x: x - centerX, y: y - centerY};
    };

    function world(event) {
      const [px, py] = d3.pointer(event, canvas.value);
      const [x, y] = view.value.invert([px, py]);
      const [centerX, centerY] = center();
      return {x: x - centerX, y: y - centerY};
    }

    function clampPoint(point) {
      return {x: limit(point.x, -100000, 100000), y: limit(point.y, -100000, 100000)};
    }

    function measure() {
      const svg = canvas.value;
      if (svg) size.value = {width: svg.clientWidth, height: svg.clientHeight};
    }

    function initializeZoom() {
      if (!canvas.value || zoom) return;
      measure();
      zoom = d3.zoom().scaleExtent([0.0005, 4])
        .filter(event => {
          if (event.type === "wheel") return !gesture.value;
          return !event.button && !event.ctrlKey && !reconnect.value && !gesture.value
            && !event.target.closest("[data-node], [data-edge]");
        })
        .on("start", event => { menu.value = null; if (event.sourceEvent) lastClick = null; })
        .on("zoom", event => { view.value = event.transform; });
      d3.select(canvas.value).call(zoom).on("dblclick.zoom", null);
      resizeObserver = new ResizeObserver(measure);
      resizeObserver.observe(canvas.value);
      fit();
    }

    function fit() {
      if (!zoom || !board.value) return;
      const bounds = drawnBounds();
      const [x, y] = center();
      const scale = limit(Math.min((x * 2 - 40) / bounds.width, (y * 2 - 40) / bounds.height, 1), 0.0005, 1);
      d3.select(canvas.value).call(zoom.transform, d3.zoomIdentity.translate(x * (1 - scale), y * (1 - scale)).scale(scale));
    }

    function centerOrigin() {
      if (!zoom) return;
      d3.select(canvas.value).call(zoom.transform, d3.zoomIdentity);
    }

    function zoomBy(multiplier) {
      if (zoom) d3.select(canvas.value).call(zoom.scaleBy, multiplier);
    }

    function id() {
      // randomUUID is unavailable on plain HTTP at a LAN address.
      return Array.from(crypto.getRandomValues(new Uint8Array(16)), byte => byte.toString(16).padStart(2, "0")).join("");
    }

    async function deleteBoard() {
      if (!confirm("Lomtárba helyezed a munkalapot? Az útvonal egy újabb megnyitása üres lapot hozhat létre.")) return;
      try {
        await checked(await fetch(endpoint, {
          method: "DELETE",
          headers: {"X-CSRF-Token": csrf, "If-Match": '"' + board.value.revision + '"'},
        }));
        savedGeneration.value = generation.value;
        location.assign("/");
      } catch (error) {
        problem.value = error.message;
      }
    }

    function makeNode(position) {
      return {id: id(), title: "Új ötlet", comment: "", markdown: "", autoSize: true, showMarkdown: false, position: clampPoint(position), width: 176, height: 80,
        shape: "rounded", fill: "#dce9ff", textColor: "#182335", border: "#839bbc", fontSize: 16, bold: true, alignment: "center"};
    }

    function addNode(position = worldAtCenter()) {
      if (!board.value) return;
      const node = makeNode(position);
      board.value.nodes.push(node);
      modified();
      selected.value = {kind: "node", id: node.id};
      if (inspector.value || note.value) openProperties("node", node.id);
    }

    async function loadAccounts() {
      try {
        const result = await checked(await fetch("/api/worksheet-users/" + path));
        accounts.value = await result.json();
      } catch (error) {
        problem.value = error.message;
      }
    }

    function openProperties(kind, itemID) {
      if (kind === "worksheet" && canManage.value && !accounts.value) loadAccounts();
      if (kind !== "worksheet") selected.value = {kind, id: itemID};
      inspector.value = {kind, id: itemID};
      note.value = null;
      menu.value = null;
    }

    function deleteNode(node) {
      if (!confirm("Törlöd ezt a dobozt? A kábelek végpontjai a helyükön maradnak.")) return;
      for (const edge of board.value.edges) {
        if (edge.source === node.id) detach(edge, "source");
        if (edge.target.node === node.id) detach(edge, "target");
      }
      releaseChildren(node);
      board.value.nodes = board.value.nodes.filter(item => item.id !== node.id);
      selected.value = null;
      inspectNothing();
      modified();
    }

    function removeEdge(edge) {
      board.value.edges = board.value.edges.filter(item => item.id !== edge.id);
      pruneJunctions();
      selected.value = null;
      inspectNothing();
      modified();
    }

    function detach(edge, end) {
      if (!edgeEndpoint(edge, end).node) return;
      const {from, to} = edgeGeometry(edge, drawnNode);
      setEndpoint(edge, end, {point: clampPoint(end === "source" ? from : to)});
      pruneJunctions();
      modified();
    }

    function openSidebar() {
      const item = selected.value;
      if (!item) openProperties("worksheet");
      else openProperties(item.kind === "endpoint" ? "edge" : item.kind, item.id);
    }

    function inspectNothing() {
      inspector.value = null;
      note.value = null;
      menu.value = null;
    }

    function releaseChildren(node) {
      for (const child of board.value.nodes) {
        if (child.parent === node.id) child.parent = node.parent;
      }
    }

    function toggleContainer(node) {
      if (node.kind === "container") {
        releaseChildren(node);
        delete node.kind;
        delete node.locked;
      } else {
        node.kind = "container";
        for (const child of board.value.nodes) {
          if (child.id !== node.id && child.parent === node.parent &&
              overlapFraction(drawnNode(child.id), drawnNode(node.id)) > 0) child.parent = node.id;
        }
      }
      modified();
    }

    function moveGroup(node) {
      return [node, ...board.value.nodes.filter(n => ancestors(n, nodeMap.value).some(p => p.id === node.id))]
        .map(n => ({id: n.id, x: n.position.x, y: n.position.y}));
    }

    function translateGroup(group, dx, dy) {
      for (const {x, y} of group) {
        dx = limit(dx, -100000-x, 100000-x);
        dy = limit(dy, -100000-y, 100000-y);
      }
      for (const {id, x, y} of group) nodeMap.value.get(id).position = {x: x+dx, y: y+dy};
    }

    function dropParent(node) {
      const target = containers.value.slice().reverse().find(c => c.id !== node.id &&
        !ancestors(c, nodeMap.value).some(p => p.id === node.id) &&
        overlapFraction(drawnNode(node.id), drawnNode(c.id)) > 0.5);
      node.parent = target?.id;
    }

    function pruneJunctions() {
      const attached = new Set(board.value.edges.flatMap(e => [e.source, e.target.node]));
      const orphan = n => n.kind === "connectionPoint" && !attached.has(n.id);
      if (!board.value.nodes.some(orphan)) return;
      board.value.nodes = board.value.nodes.filter(n => !orphan(n));
      if (selected.value?.kind === "node" && !nodeMap.value.has(selected.value.id)) selected.value = null;
      if ((inspector.value?.kind === "node" && !nodeMap.value.has(inspector.value.id)) ||
          (note.value && !nodeMap.value.has(note.value.id))) inspectNothing();
    }

    function snap(point, exclude) {
      const hit = node => node.id !== exclude && shapeDistance(drawnNode(node.id), point, 8 / view.value.k) <= 1;
      return board.value.nodes.slice().reverse().find(n => n.kind !== "container" && hit(n))
        ?? containers.value.slice().reverse().find(hit);
    }

    function nearbyEnd(point, edge) {
      let best, distance = 10 / view.value.k;
      for (const candidate of board.value.edges) {
        if (candidate.id === edge.id) continue;
        for (const end of ["source", "target"]) {
          const free = edgeEndpoint(candidate, end).point;
          if (!free) continue;
          const delta = Math.hypot(free.x - point.x, free.y - point.y);
          if (delta <= distance) {
            best = {edge: candidate, end, point: free};
            distance = delta;
          }
        }
      }
      return best;
    }

    function pressNode(event, node) {
      const controlClick = event.ctrlKey && (event.button === 0 || event.button === 2);
      if ((event.button !== 0 && !controlClick) || reconnect.value) return;
      event.preventDefault();
      event.stopPropagation();
      menu.value = null;
      selected.value = {kind: "node", id: node.id};
      event.currentTarget.focus({preventScroll: true});
      const initial = world(event);
      const cabling = controlClick;
      if (cabling) lastClick = null;
      const locked = ancestors(node, nodeMap.value).some(parent => parent.locked);
      gesture.value = {group: cabling || locked ? [] : moveGroup(node), locked, type: cabling ? "cable" : "move", pointer: event.pointerId, nodeID: node.id,
        position: {...node.position}, initial, screen: [event.clientX, event.clientY], moved: false};
      if (cabling) preview.value = {edge: {source: node.id, target: {point: initial}, style: pendingStyle.value}};
      canvas.value.setPointerCapture(event.pointerId);
    }

    function pressEndpoint(event, edge, end) {
      if ((event.button !== 0 && !(event.ctrlKey && event.button === 2)) || reconnect.value) return;
      const original = edgeEndpoint(edge, end);
      if (original.node && !event.ctrlKey) return;
      const geometry = edgeGeometry(edge, drawnNode);
      const position = end === "source" ? geometry.from : geometry.to;
      event.preventDefault();
      event.stopPropagation();
      menu.value = null;
      lastClick = null;
      selected.value = {kind: "endpoint", id: edge.id, end};
      gesture.value = {type: "endpoint", original: {...original}, pointer: event.pointerId, edgeID: edge.id, end,
        position: {...position}, initial: world(event), screen: [event.clientX, event.clientY], moved: false};
      canvas.value.setPointerCapture(event.pointerId);
    }

    function endpointAt(point, edge, end, commit = false) {
      const free = nearbyEnd(point, edge);
      if (free) {
        if (!commit) return {point: free.point};
        const node = {...makeNode(free.point), title: "Csomópont", kind: "connectionPoint",
          shape: "ellipse", fill: edgePaint(free.edge).color, width: 14, height: 14, autoSize: false};
        board.value.nodes.push(node);
        dropParent(node);
        setEndpoint(free.edge, free.end, {node: node.id});
        return {node: node.id};
      }
      const node = snap(point, edgeEndpoint(edge, otherEnd(end)).node);
      return node ? {node: node.id} : {point: clampPoint(point)};
    }

    function pressCorner(event, node, sx, sy) {
      if (!event.altKey || event.button !== 0 || ancestors(node, nodeMap.value).some(n => n.locked)) return;
      event.preventDefault();
      event.stopPropagation();
      lastClick = null;
      menu.value = null;
      selected.value = {kind: "node", id: node.id};
      const drawn = drawnNode(node.id);
      gesture.value = {type: "resize", pointer: event.pointerId, nodeID: node.id, sx, sy,
        original: JSON.parse(JSON.stringify(node)), width: drawn.width, height: drawn.height,
        initial: world(event), screen: [event.clientX, event.clientY], moved: false};
      canvas.value.setPointerCapture(event.pointerId);
    }

    function resizeCorner(operation, point) {
      const {original, width, height, sx, sy} = operation;
      const node = nodeMap.value.get(operation.nodeID);
      const w = limit(width + sx * (point.x-operation.initial.x), 64, 880);
      const h = limit(height + sy * (point.y-operation.initial.y), 40, 680);
      if (node.autoSize !== false) {
        const scale = Math.max(0.1, (w*width + h*height)/(width*width + height*height));
        node.fontSize = limit(original.fontSize*scale, 10, 60);
        for (const key of ["commentStyle", "markdownStyle"]) {
          if (original[key]?.size) node[key].size = limit(original[key].size*scale, 10, 60);
        }
        node.autoMinWidth = w;
        node.autoMinHeight = h;
      }
      node.width = w;
      node.height = h;
      const drawn = drawnNode(node.id);
      node.position = clampPoint({x: original.position.x + sx*(drawn.width-width)/2,
        y: original.position.y + sy*(drawn.height-height)/2});
    }

    function updatePointer(event) {
      if (!board.value) return;
      modifiers(event);
      const operation = gesture.value;
      if (!operation && !reconnect.value) return;
      if (operation && operation.pointer !== event.pointerId) return;
      const point = world(event);
      if (operation) {
        operation.moved ||= Math.hypot(event.clientX - operation.screen[0], event.clientY - operation.screen[1]) > 3;
        if (operation.type === "resize") {
          if (operation.moved) resizeCorner(operation, point);
          return;
        }
        if (operation.type === "move" || operation.type === "endpoint") {
          if (!operation.moved) return;
          const position = clampPoint({x: operation.position.x + point.x - operation.initial.x,
            y: operation.position.y + point.y - operation.initial.y});
          if (operation.type === "move") {
            if (!operation.locked) translateGroup(operation.group, position.x-operation.position.x, position.y-operation.position.y);
          } else {
            const edge = edgeMap.value.get(operation.edgeID);
            setEndpoint(edge, operation.end, {point: position});
            preview.value = {target: endpointAt(position, edge, operation.end).node};
          }
          return;
        }
        const edge = {source: operation.nodeID, target: {point}, style: pendingStyle.value};
        edge.target = endpointAt(point, edge, "target");
        preview.value = {edge, target: edge.target.node};
      } else {
        const {edgeID, end} = reconnect.value;
        const edge = {...edgeMap.value.get(edgeID)};
        const endpoint = endpointAt(point, edge, end);
        setEndpoint(edge, end, endpoint);
        preview.value = {edge, target: endpoint.node};
      }
    }

    function finishPointer(event, cancel = false) {
      const operation = gesture.value;
      if (!operation || operation.pointer !== event.pointerId) return;
      if (!cancel) updatePointer(event);
      if (operation.type === "resize" && operation.moved) {
        if (cancel) {
          const index = board.value.nodes.findIndex(n => n.id === operation.nodeID);
          board.value.nodes[index] = operation.original;
        } else modified();
      } else if (operation.type === "move" && operation.moved) {
        lastClick = null;
        const node = nodeMap.value.get(operation.nodeID);
        if (cancel) translateGroup(operation.group, 0, 0);
        else if (!operation.locked) { dropParent(node); modified(); }
      } else if (operation.type === "move" && !cancel) {
        const time = performance.now();
        const [x, y] = operation.screen;
        if (lastClick?.id === operation.nodeID && time - lastClick.time < 450
            && Math.hypot(x - lastClick.x, y - lastClick.y) < 10) {
          lastClick = null;
          openProperties("node", operation.nodeID);
        } else {
          lastClick = {id: operation.nodeID, time, x, y};
          if (inspector.value || note.value) showNote(nodeMap.value.get(operation.nodeID));
        }
      } else if (operation.type === "cable" && operation.moved && !cancel) {
        const edge = {id: id(), ...preview.value.edge};
        edge.target = endpointAt(world(event), edge, "target", true);
        board.value.edges.push(edge);
        modified();
        selected.value = {kind: "edge", id: edge.id};
      } else if (operation.type === "endpoint" && operation.moved) {
        const edge = edgeMap.value.get(operation.edgeID);
        const endpoint = cancel ? operation.original
          : endpointAt(edgeEndpoint(edge, operation.end).point, edge, operation.end, true);
        setEndpoint(edge, operation.end, endpoint);
        if (!cancel) {
          pruneJunctions();
          if (endpoint.node) selected.value = {kind: "edge", id: edge.id};
          modified();
        }
      }
      gesture.value = null;
      preview.value = null;
    }

    function retarget(edge, end) {
      menu.value = null;
      reconnect.value = {edgeID: edge.id, end};
      preview.value = null;
    }

    function pressCanvas(event) {
      rightPress = event.button === 2 && !event.ctrlKey;
      if (event.button !== 0 || event.ctrlKey || !reconnect.value) return;
      event.preventDefault();
      event.stopPropagation();
      const {edgeID, end} = reconnect.value;
      const edge = edgeMap.value.get(edgeID);
      setEndpoint(edge, end, endpointAt(world(event), edge, end, true));
      pruneJunctions();
      reconnect.value = null;
      preview.value = null;
      modified();
    }

    function context(event, kind = "canvas", itemID) {
      event.preventDefault();
      event.stopPropagation();
      if (!rightPress || event.ctrlKey || event.button !== 2 || gesture.value?.type === "cable") return;
      rightPress = false;
      lastClick = null;
      menu.value = {
        kind, id: itemID, x: Math.max(8, Math.min(event.clientX, innerWidth - 244)),
        y: Math.max(8, Math.min(event.clientY, innerHeight - 195)), position: world(event),
      };
    }

    function updateItem(item, key, value) {
      if (item[key] === value) return;
      item[key] = value;
      modified();
    }

    async function showNote(node) {
      if (!node || reconnect.value) return;
      selected.value = {kind: "node", id: node.id};
      menu.value = null;
      inspector.value = null;
      const request = ++noteRequest;
      note.value = {id: node.id, request, loading: Boolean(node.markdown)};
      if (!node.markdown) return;
      try {
        const rendered = await checked(await fetch("/api/markdown", {method: "POST", headers: {
          "Content-Type": "application/json", "X-CSRF-Token": csrf,
        }, body: JSON.stringify({markdown: node.markdown})}));
        const html = await rendered.text();
        if (note.value?.request === request) note.value = {id: node.id, html, loading: false};
      } catch (error) {
        if (note.value?.request === request) note.value = {id: node.id, error: error.message, loading: false};
      }
    }

    async function save() {
      if (saving.value || gesture.value || !dirty.value) return;
      saving.value = true;
      problem.value = "";
      const version = generation.value;
      const payload = JSON.stringify({...board.value, schemaVersion: 2});
      try {
        const result = await checked(await fetch(endpoint, {
          method: "PUT",
          headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf, "If-Match": '"' + board.value.revision + '"'},
          body: payload,
        }));
        const saved = await result.json();
        if (generation.value === version && !gesture.value) board.value = saved;
        else board.value.revision = saved.revision;
        savedGeneration.value = version;
        status.value = "Mentve";
      } catch (error) {
        problem.value = error.message;
      } finally {
        saving.value = false;
      }
    }

    async function exportSVG() {
      if (!board.value || !canvas.value) return;
      await loadCanvasMarkdown(markdownSources.value).catch(() => {});
      await nextTick();
      const bounds = drawnBounds();
      const output = document.createElementNS(svgNamespace, "svg");
      output.setAttribute("viewBox", [bounds.x, bounds.y, bounds.width, bounds.height].join(" "));
      output.setAttribute("width", bounds.width);
      output.setAttribute("height", bounds.height);
      const title = document.createElementNS(svgNamespace, "title");
      title.textContent = board.value.title;
      const background = document.createElementNS(svgNamespace, "rect");
      for (const [key, value] of Object.entries({...bounds, fill: board.value.background ?? paper})) background.setAttribute(key, value);
      const scene = canvas.value.querySelector("[data-scene]").cloneNode(true);
      scene.removeAttribute("data-scene");
      scene.querySelectorAll("[data-editor-only]").forEach(element => element.remove());
      scene.querySelectorAll("[tabindex], [data-node], [data-edge]").forEach(element => {
        for (const attribute of ["tabindex", "data-node", "data-edge", "class"]) element.removeAttribute(attribute);
      });
      output.append(title, canvas.value.querySelector("defs").cloneNode(true), background);
      if (board.value.gridVisible !== false) {
        const grid = background.cloneNode(false);
        grid.setAttribute("fill", "url(#worksheet-grid)");
        output.append(grid);
      }
      output.append(scene);
      const file = new Blob([new XMLSerializer().serializeToString(output)], {type: "image/svg+xml"});
      const url = URL.createObjectURL(file);
      const link = Object.assign(document.createElement("a"), {href: url, download: decodeURIComponent(path.split("/").at(-1)) + ".svg"});
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30000);
    }

    function modifiers(event) {
      ctrl.value = event.ctrlKey;
      alt.value = event.altKey;
    }
    function clearModifiers() { ctrl.value = false; alt.value = false; }

    function keyboard(event) {
      modifiers(event);
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        save();
      }
      if (event.key === "Escape") {
        const active = gesture.value;
        if (active) {
          finishPointer({pointerId: active.pointer}, true);
          if (canvas.value.hasPointerCapture(active.pointer)) canvas.value.releasePointerCapture(active.pointer);
        }
        menu.value = null;
        reconnect.value = null;
        preview.value = null;
      }
    }

    function beforeUnload(event) {
      if (!dirty.value) return;
      event.preventDefault();
      event.returnValue = "";
    }

    onMounted(async () => {
      window.addEventListener("keydown", keyboard);
      window.addEventListener("keyup", modifiers);
      window.addEventListener("blur", clearModifiers);
      window.addEventListener("beforeunload", beforeUnload);
      try {
        const response = await checked(await fetch(endpoint));
        board.value = await response.json();
        await nextTick();
        initializeZoom();
      } catch (error) {
        problem.value = error.message;
      }
    });

    onUnmounted(() => {
      resizeObserver?.disconnect();
      window.removeEventListener("keydown", keyboard);
      window.removeEventListener("keyup", modifiers);
      window.removeEventListener("blur", clearModifiers);
      window.removeEventListener("beforeunload", beforeUnload);
    });

    function renderNode(node) {
      const {node: drawn, layout} = drawings.value.get(node.id);
      const highlighted = selected.value?.kind === "node" && selected.value.id === node.id;
      const snapTarget = preview.value?.target === node.id;
      return h("g", {key: node.id, "data-node": node.id, tabindex: 0, role: "button",
        "aria-label": node.title, class: "idea",
        transform: "translate(" + node.position.x + " " + node.position.y + ")",
        onPointerdown: event => pressNode(event, node),
        onContextmenu: event => context(event, "node", node.id),
        onKeydown: event => {
          if (event.key === "Enter") {
            if (event.shiftKey) openProperties("node", node.id);
            else showNote(node);
          }
        },
      }, [
        node.kind === "connectionPoint" ? null : h("title", node.title),
        highlighted || snapTarget ? h("rect", {"data-editor-only": "", x: -drawn.width / 2 - 4, y: -drawn.height / 2 - 4,
          width: drawn.width + 8, height: drawn.height + 8, rx: 15, fill: "none",
          stroke: snapTarget ? "#16a085" : "#4168e9", "stroke-width": 2, "pointer-events": "none"}) : null,
        shape(drawn),
        layout.frame ? h("rect", {...layout.frame, "pointer-events": "none"}) : null,
        h("text", {"font-family": "system-ui, sans-serif", "pointer-events": "none"},
          layout.lines.map(line => h("tspan", {
            x: line.x, y: line.y, "text-anchor": line.anchor, "font-style": line.italic ? "italic" : undefined,
            "text-decoration": line.underline ? "underline" : undefined, fill: line.color, "font-size": line.size, "font-weight": line.weight,
            textLength: line.fit, lengthAdjust: line.fit ? "spacingAndGlyphs" : undefined,
          }, line.runs ? line.runs.map(run => {
            const format = run.format || {};
            if (!format.bold && !format.italic && !format.code && !format.link) return run.text;
            return h("tspan", {"font-weight": format.bold ? 700 : undefined,
              "font-style": format.italic ? "italic" : undefined, "font-family": format.code ? "monospace" : undefined,
              "text-decoration": format.link ? "underline" : undefined}, run.text);
          }) : line.text))),
        ...(alt.value && node.kind !== "connectionPoint" && !ancestors(node, nodeMap.value).some(n => n.locked)
          ? [[-1,-1], [1,-1], [1,1], [-1,1]].map(([sx, sy]) => {
            const r = 5/view.value.k;
            return h("rect", {"data-editor-only": "", x: sx*drawn.width/2-r, y: sy*drawn.height/2-r,
              width: 2*r, height: 2*r, fill: "#ffffff", stroke: "#4168e9", "stroke-width": 1/view.value.k,
              cursor: sx === sy ? "nwse-resize" : "nesw-resize", onPointerdown: e => pressCorner(e, node, sx, sy)});
          }) : []),
      ]);
    }

    function renderEndpoint(edge, end, point) {
      const attached = Boolean(edgeEndpoint(edge, end).node);
      if (attached && !ctrl.value) return null;
      return h("circle", {
        key: edge.id + end, "data-edge": edge.id, "data-endpoint": end, cx: point.x, cy: point.y,
        r: (attached ? 7 : 6) / view.value.k, fill: "transparent", "pointer-events": "all",
        class: attached ? "detach-endpoint" : "edge-endpoint",
        onPointerdown: event => pressEndpoint(event, edge, end),
        onContextmenu: event => context(event, "edge", edge.id),
        onClick: event => event.stopPropagation(),
      });
    }

    function renderEdge(edge) {
      const {d, labelPosition, angle} = edgeGeometry(edge, drawnNode);
      const paint = edgePaint(edge);
      const highlighted = (selected.value?.kind === "edge" || selected.value?.kind === "endpoint") && selected.value.id === edge.id;
      return h("g", {key: edge.id, "data-edge": edge.id, tabindex: 0, role: "button", "aria-label": edge.label || "Vonal",
        onClick: () => { selected.value = {kind: "edge", id: edge.id}; },
        onDblclick: event => {
          event.stopPropagation();
          openProperties("edge", edge.id);
        },
        onContextmenu: event => context(event, "edge", edge.id),
        onKeydown: event => { if (event.key === "Enter") openProperties("edge", edge.id); },
      }, [
        highlighted ? h("path", {"data-editor-only": "", d, stroke: "#aab9fc", "stroke-width": paint.width + 5}) : null,
        h("path", {d, ...edgeAppearance(edge, "arrow-" + edge.id)}),
        h("path", {"data-editor-only": "", d, stroke: "transparent", "stroke-width": Math.max(paint.width + 10, 14 / view.value.k),
          "pointer-events": "stroke", class: "edge-hit"}),
        edge.label?.trim() ? h("text", {transform: "translate(" + labelPosition.x + " " + labelPosition.y + ") rotate(" + angle + ")",
          y: -paint.width / 2 - 6, "font-family": "system-ui, sans-serif", "font-size": 14, "text-anchor": "middle",
          stroke: "none", fill: paint.color, class: "edge-label"}, edge.label) : null,
      ]);
    }

    function renderCanvas() {
      const [centerX, centerY] = center();
      const spacing = board.value.gridSpacing ?? 20;
      const [left, top] = view.value.invert([0, 0]);
      const cable = preview.value?.edge;
      const shown = cable ? edgeGeometry(cable, drawnNode) : null;
      return h("div", {class: "canvas-area"}, [
        h("svg", {ref: canvas, class: ctrl.value ? "editor-canvas ctrl-held" : "editor-canvas", "aria-label": "Ötletvászon",
          onContextmenu: event => context(event),
          onPointerdownCapture: pressCanvas,
          onPointermove: updatePointer,
          onPointerup: event => finishPointer(event),
          onPointercancel: event => finishPointer(event, true),
          onLostpointercapture: event => finishPointer(event, true),
          onClick: event => {
            if (!event.target.closest("[data-node], [data-edge]")) menu.value = null;
          },
        }, [
          h("defs", [
            h("pattern", {id: "worksheet-grid", patternUnits: "userSpaceOnUse", width: spacing, height: spacing}, [
              h("circle", {cx: spacing/2, cy: spacing/2, r: 1.1, fill: board.value.gridColor ?? "#ccd7eb"}),
            ]),
            arrowDefinition("arrow-preview", "#4168e9"),
            ...board.value.edges.flatMap(edge => {
              const paint = edgePaint(edge);
              return paint.startArrow || paint.endArrow ? [arrowDefinition("arrow-" + edge.id, paint.color)] : [];
            })]),
          h("rect", {width: "100%", height: "100%", fill: board.value.background ?? paper, "pointer-events": "none"}),
          h("g", {transform: view.value + " translate(" + centerX + " " + centerY + ")"}, [
            board.value.gridVisible !== false ? h("rect", {x: left-centerX, y: top-centerY, width: size.value.width/view.value.k,
              height: size.value.height/view.value.k, fill: "url(#worksheet-grid)", "pointer-events": "none"}) : null,
            h("path", {"data-editor-only": "", "pointer-events": "none", stroke: "#aab9cf", "stroke-width": 1,
              d: "M -8 0 H 8 M 0 -8 V 8"}),
            h("g", {"data-scene": ""}, [
              ...containers.value.map(renderNode),
              h("g", {fill: "none", "stroke-linecap": "round"}, board.value.edges.map(renderEdge)),
              ...board.value.nodes.filter(n => n.kind !== "container").map(renderNode),
            ]),
            h("g", {"data-editor-only": ""}, board.value.edges.flatMap(edge => {
              if (edge.source && edge.target.node && !ctrl.value) return [];
              const {from, to} = edgeGeometry(edge, drawnNode);
              return [renderEndpoint(edge, "source", from), renderEndpoint(edge, "target", to)];
            })),
            shown ? h("path", {d: shown.d, ...edgeAppearance({...cable, color: "#4168e9"}, "arrow-preview"), fill: "none", "pointer-events": "none"}) : null,
          ]),
        ]),
        h("div", {class: "canvas-controls"}, [
          button("", () => zoomBy(0.8), {"aria-label": "Kicsinyítés", title: "Kicsinyítés", symbol: "minus"}),
          h("span", Math.round(view.value.k * 100) + "%"),
          button("", () => zoomBy(1.25), {"aria-label": "Nagyítás", title: "Nagyítás", symbol: "plus"}),
          button("Közép", centerOrigin, {title: "Középre állítás, (0, 0)", symbol: "center"}),
          button("Mind", fit, {title: "A teljes vászon megjelenítése", symbol: "fit"}),
          button("", () => updateItem(board.value, "gridVisible", board.value.gridVisible === false), {
            title: "Pontrács", "aria-label": "Pontrács", "aria-pressed": board.value.gridVisible !== false, symbol: "grid"}),

        ]),
        board.value && !board.value.nodes.length ? h("p", {class: "canvas-empty"}, "A vászon üres. Adj hozzá egy ötletet.") : null,
      ]);
    }

    function renderMenu() {
      const open = menu.value;
      if (!open) return null;
      const node = nodeMap.value.get(open.id);
      const edge = board.value?.edges.find(item => item.id === open.id);
      const type = open.kind;
      const entries = type === "node" && node ? [
        button("Szerkesztés", () => openProperties("node", node.id), {symbol: "edit"}),
        button("Markdown megnyitása", () => showNote(node), {symbol: "eye"}),
        button("Törlés", () => { menu.value = null; deleteNode(node); }, {class: "button danger", symbol: "trash"}),
      ] : type === "edge" && edge ? [
        button("Szerkesztés", () => openProperties("edge", edge.id), {symbol: "edit"}),
        ...endpointActions(edge),
        button("Kapcsolat törlése", () => removeEdge(edge), {class: "button danger", symbol: "trash"}),
      ] : [
        button("Új ötlet ide", () => { menu.value = null; addNode(open.position); }, {disabled: !board.value, symbol: "plus"}),
        button("Középre állítás", () => { menu.value = null; centerOrigin(); }, {symbol: "center"}),
      ];
      return h("div", {class: "context-menu panel", "aria-label": "Műveletek",
        style: {left: open.x + "px", top: open.y + "px"}}, entries);
    }

    function sidebar(label, contents) {
      return h("aside", {class: "inspector", "aria-label": label}, [
        h("div", {class: "inspector-content stack"}, contents),
        h("div", {class: "inspector-footer"}, [
          button("", inspectNothing, {"aria-label": "Oldalsáv bezárása", title: "Oldalsáv bezárása", symbol: "right"}),
        ]),
      ]);
    }

    function endpointActions(edge) {
      return [["source", "Kezdőpont"], ["target", "Végpont"]].map(([end, label]) => {
        if (edgeEndpoint(edge, end).node) {
          return button(label + " leválasztása", () => { detach(edge, end); menu.value = null; }, {symbol: "unlink"});
        }
        return button(label + " újrakötése", () => retarget(edge, end), {symbol: "right"});
      });
    }

    function changeLineStyle(edge, style) {
      const {startArrow, endArrow} = edgePaint(edge);
      Object.assign(edge, {style, startArrow, endArrow});
      modified();
    }

    function worksheetAccess(sheet) {
      const available = accounts.value || [];
      const ownerChoices = Object.fromEntries([...new Set([sheet.owner, ...available].filter(Boolean))]
        .map(name => [name, name]));
      const editorChoices = [...new Set([...(sheet.editors || []), ...available])].filter(name => name !== sheet.owner);
      return [
        role === "admin" ? field("Tulajdonos", select(sheet.owner ?? "", {"": "Nincs kijelölve", ...ownerChoices},
          name => { if (name) updateItem(sheet, "owner", name); })) : h("p", "Tulajdonos · " + sheet.owner),
        checkbox("Nyilvános munkalap", sheet.isPublic !== false, value => updateItem(sheet, "isPublic", value)),
        h("fieldset", {class: "access-editors"}, [
          h("legend", "Szerkesztők"),
          ...editorChoices.map(name => checkbox(name, (sheet.editors || []).includes(name), checked => {
            const editors = (sheet.editors || []).filter(editor => editor !== name);
            if (checked) editors.push(name);
            updateItem(sheet, "editors", editors);
          })),
          !editorChoices.length && accounts.value ? h("p", {class: "muted"}, "Nincs másik fiók.") : null,
        ]),
      ];
    }

    function renderInspector() {
      if (note.value) {
        const reading = note.value;
        const node = nodeMap.value.get(reading.id);
        if (!node) return null;
        return sidebar("Markdown", [
          h("h2", node.title),
          node.comment ? h("p", {class: "comment", style: {color: node.commentStyle?.color ?? commentColor(node.textColor)}}, node.comment) : null,
          reading.loading ? h("p", "Betöltés…") : null,
          reading.error ? h("p", {class: "error"}, reading.error) : null,
          !reading.loading && !reading.error ? h("div", {class: "markdown", innerHTML: reading.html || "<p>Még nincs leírás.</p>"}) : null,
          button("Szerkesztés", () => openProperties("node", node.id), {symbol: "edit"}),
        ]);
      }
      if (!inspector.value) return null;
      if (inspector.value.kind === "worksheet") {
        const sheet = board.value;
        return sidebar("Munkalap", [
          field("Cím", input(sheet.title, value => updateItem(sheet, "title", value), {maxlength: 120})),
          field("Megjegyzés", input(sheet.comment || "", value => updateItem(sheet, "comment", value), {maxlength: 500})),
          field("Markdown", textarea(sheet.markdown || "", value => updateItem(sheet, "markdown", value))),
          colorPicker("Munkalap háttérszíne", sheet.background ?? paper, value => updateItem(sheet, "background", value), "worksheet/background"),
          colorPicker("Rácspontok színe", sheet.gridColor ?? "#ccd7eb", value => updateItem(sheet, "gridColor", value), "worksheet/grid"),
          field("Rácsköz", numeric(sheet.gridSpacing ?? 20, value => updateItem(sheet, "gridSpacing", value), 6, 160)),
          ...(canManage.value ? worksheetAccess(sheet) : []),
          h("div", {class: "inspector-links"}, [
            link("Mentett JSON letöltése", "/export/json/" + path, "download"),
            link("Mentett Markdown letöltése", "/export/markdown/" + path, "download"),
          ]),
          role === "admin" ? button("Munkalap törlése", deleteBoard, {class: "button danger", symbol: "trash"}) : null,
        ]);
      }
      if (inspector.value.kind === "edge") {
        const edge = board.value.edges.find(item => item.id === inspector.value.id);
        if (!edge) return null;
        const paint = edgePaint(edge);
        const style = edge.style === "dashed" || edge.style === "rope" ? edge.style : "solid";
        return sidebar("Vonal szerkesztése", [
          field("Címke", input(edge.label || "", value => updateItem(edge, "label", value), {maxlength: 120})),
          colorPicker("Vonal színe", paint.color, value => updateItem(edge, "color", value), edge.id + "/line"),
          field("Vastagság", numeric(paint.width, value => updateItem(edge, "width", value), 0.5, 24)),
          field("Vonaltípus", select(style, lineStyles, value => changeLineStyle(edge, value))),
          checkbox("Nyíl a vonal elején", paint.startArrow, value => updateItem(edge, "startArrow", value)),
          checkbox("Nyíl a vonal végén", paint.endArrow, value => updateItem(edge, "endArrow", value)),
          ...endpointActions(edge),
          button("Kapcsolat törlése", () => removeEdge(edge), {class: "button danger", symbol: "trash"}),
        ]);
      }
      const node = nodeMap.value.get(inspector.value.id);
      if (!node) return null;
      const change = (key, value) => updateItem(node, key, value);
      const autoSize = node.autoSize !== false;
      const drawn = drawnNode(node.id);
      const dimension = (key, min, max) => numeric(drawn[key], value => change(key, value), min, max, {disabled: autoSize});
      const title = field("Címke", input(node.title, value => change("title", value), {maxlength: 120}));
      const color = (label, key, fallback) => colorPicker(label, node[key] ?? fallback, v => change(key, v), node.id + "/" + key);
      if (node.kind === "connectionPoint") return sidebar("Csomópont", [
        title, color("Szín", "fill"), button("Törlés", () => deleteNode(node), {symbol: "trash"}),
      ]);
      const alignments = {left: "Balra", center: "Középre", right: "Jobbra"};
      function typography(section) {
        const isTitle = section === "title";
        const style = isTitle ? node : node[section] ?? {};
        const sizeKey = isTitle ? "fontSize" : "size";
        const colorKey = isTitle ? "textColor" : "color";
        const update = (key, value) => isTitle ? change(key, value) : change(section, {...node[section], [key]: value});
        return [
          colorPicker("Szövegszín", style[colorKey] ?? (section === "commentStyle" ? commentColor(node.textColor) : node.textColor),
            v => update(colorKey, v), node.id + "/" + section + "/text"),
          h("div", {class: "fields-two"}, [
            field("Betűméret", numeric(style[sizeKey] ?? Math.max(10, node.fontSize*.8), v => update(sizeKey, v), 10, 60)),
            field("Igazítás", select(style.alignment ?? node.alignment, alignments, v => update("alignment", v))),
          ]),
          h("div", {class: "font-switches"}, [["bold","Félkövér"],["italic","Dőlt"],["underline","Aláhúzott"]]
            .map(([key, label]) => checkbox(label, !!style[key], v => update(key, v)))),
        ];
      }
      const group = (label, children) => h("fieldset", {class: "property-group stack"}, [h("legend", label), ...children]);
      const locked = ancestors(node, nodeMap.value).some(n => n.locked);
      function coordinate(axis) {
        return numeric(node.position[axis], v => {
          const delta = v - node.position[axis];
          translateGroup(moveGroup(node), axis === "x" ? delta : 0, axis === "y" ? delta : 0);
          modified();
        }, -100000, 100000, {disabled: locked});
      }
      return sidebar("Ötlet szerkesztése", [
        group("Doboz", [
          field("Forma", select(node.shape, shapes, value => change("shape", value))),
          checkbox("Auto size", autoSize, value => {
            node.width = drawn.width; node.height = drawn.height;
            delete node.autoMinWidth; delete node.autoMinHeight;
            change("autoSize", value);
          }),
          h("div", {class: "fields-two"}, [field("Szélesség", dimension("width", 64, 880)), field("Magasság", dimension("height", 40, 680))]),
          h("div", {class: "fields-two"}, [field("X", coordinate("x")), field("Y", coordinate("y"))]),
          h("div", {class: "fields-two"}, [color("Háttér", "fill"), color("Keret", "border")]),
          button(node.kind === "container" ? "Konténer feloldása" : "Konténer", () => toggleContainer(node), {symbol: "folder", disabled: locked}),
          node.kind === "container" ? checkbox("Lock · tartalom rögzítése", !!node.locked, v => change("locked", v)) : null,
        ]),
        group("Cím", [title, ...typography("title")]),
        group("Megjegyzés", [field("Megjegyzés", input(node.comment || "", v => change("comment", v), {maxlength: 500})),
          ...typography("commentStyle")]),
        group("Markdown", [
          checkbox("Show Markdown", Boolean(node.showMarkdown), value => change("showMarkdown", value)),
          field("Markdown", textarea(node.markdown, value => change("markdown", value))),
          ...typography("markdownStyle"),
          h("div", {class: "fields-two"}, [color("Markdown háttér", "markdownFill", node.fill),
            color("Markdown keret", "markdownBorder", node.border)]),
          button("Előnézet", () => showNote(node), {symbol: "eye"}),
        ]),
      ]);
    }

    function renderHeader() {
      return h("header", {class: "editor-header"}, [
        h("a", {class: "brand", href: "/"}, "ThinkNodes"),
        h("h1", {title: board.value.title}, board.value.title),
        button("", () => addNode(), {class: "button soft icon-button", symbol: "plus", "aria-label": "Új ötlet", title: "Új ötlet"}),
        select(pendingStyle.value, edgeStyles, value => { pendingStyle.value = value; }, {"aria-label": "Új vonal típusa"}),
        button("Munkalap", () => openProperties("worksheet"), {
          "aria-pressed": inspector.value?.kind === "worksheet", symbol: "settings",
        }),
        button("SVG letöltése", exportSVG, {symbol: "download"}),
        link("Megtekintés", "/" + path, "eye"),
        button(saving.value ? "Mentés…" : "Mentés", save, {class: "button primary", symbol: "save", disabled: saving.value || !dirty.value}),
        role === "admin" ? link("Admin", "/admin", "settings") : null,
        h("form", {method: "post", action: "/logout"}, [
          h("input", {type: "hidden", name: "csrf", value: csrf}),
          h("button", {class: "button", type: "submit"}, [icon("logout"), "Kijelentkezés"]),
        ]),
      ]);
    }

    return () => {
      if (!board.value) return h("p", {class: problem.value ? "error editor-loading" : "editor-loading"}, problem.value || "Szerkesztő betöltése…");
      const currentStatus = reconnect.value ? "Kattints az új célra vagy a vászonra. Esc a megszakításhoz."
        : dirty.value ? "Mentetlen változtatások" : status.value;
      return [
        renderHeader(),
        h("div", {class: "editor-workspace"}, [
          renderCanvas(),
          problem.value || currentStatus ? h("p", {class: ["canvas-status", {error: problem.value}], role: "status"}, problem.value || currentStatus) : null,
          renderInspector(),
          !inspector.value && !note.value ? button("", openSidebar, {class: "button sidebar-open",
            "aria-label": "Oldalsáv megnyitása", title: "Oldalsáv megnyitása", symbol: "left"}) : null,
        ]),
        renderMenu(),
      ];
    };
  },
}).mount(mount);
