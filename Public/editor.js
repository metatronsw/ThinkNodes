import {decodeWorksheet, encodeWorksheet} from "./worksheet-json.js";
import {sharedMouse} from "./mouse.js";
import {worksheetChanges, replayChanges} from "./editor-history.js";
import {flashNode, flashPoint} from "./ping.js";
import {showTooltip, hideTooltip} from "./tooltip.js";
import {liveConnection, rebaseWorksheet} from "./collaboration.js";
import {worksheetLink, linkIcons, openExternalLink} from "./links.js";
import {arrowTransform, canvasBounds, edgeEndpoint, edgeGeometry, edgePaint, labelLayout, limit, lineStyles, paper, selectionOutline, shapeDistance, shapes} from "./geometry.js?v=2";

import {ancestors, containerOrder, overlapFraction} from "./containers.js";

const mount = document.querySelector("#editor");
const {path, csrf, role, user, motionRate} = mount.dataset;
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
    function swatch(color) {
      return h("svg", {viewBox: "0 0 4 3", preserveAspectRatio: "none", "aria-hidden": "true"},
        [h("rect", {width: 4, height: 3, fill: color})]);
    }
    const presets = ["#ffffff", "#000000", "#e95c59", "#f3ae49", "#f3df65", "#60b77a", "#5aaed2", "#657ace", "#a375be", "#e198ad"];
    return () => h("div", {class: "color-field"}, [
      h("span", props.label),
      h("button", {type: "button", class: "color-sample", "aria-label": props.label + " színválasztó",
        "aria-expanded": expanded.value, onClick: () => { expanded.value = !expanded.value; }}, [swatch(props.color)]),
      expanded.value ? h("div", {class: "color-tools"}, [
        h("div", {class: "color-presets"}, presets.map(color => h("button", {type: "button", key: color,
          "aria-label": props.label + " " + color, title: color, onClick: () => emit("update", color)}, [swatch(color)]))),
        ...["Piros", "Zöld", "Kék"].map((label, i) => {
          const offset = 1 + i * 2;
          const change = event => emit("update", props.color.slice(0, offset) +
            Number(event.target.value).toString(16).padStart(2, "0") + props.color.slice(offset + 2));
          return field(label, h("input", {type: "range", min: 0, max: 255, step: 1,
            value: parseInt(props.color.slice(offset, offset+2), 16), onInput: change, onChange: change}));
        }),
        field("Rendszerpaletta", h("input", {type: "color", value: props.color,
          onInput: e => emit("update", e.target.value), onChange: e => emit("update", e.target.value)})),
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
    h("span", label),
  ]);
}

function textarea(value, change) {
  return h("textarea", {"aria-label": "Text", value, maxlength: 30000, rows: 7, onInput: event => change(event.target.value)});
}

const FormattedText = {
  props: {source: String},
  setup(props) {
    const html = ref(""), error = ref("");
    watch(() => props.source, (source, _, cleanup) => {
      const controller = new AbortController();
      error.value = "";
      if (!source) { html.value = ""; return; }
      const timer = setTimeout(async () => {
        try {
          const response = await checked(await fetch("/api/text", {method: "POST", signal: controller.signal,
            headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify({text: source})}));
          const rendered = await response.text();
          if (!controller.signal.aborted) html.value = rendered;
        } catch (failure) { if (!controller.signal.aborted) error.value = failure.message; }
      }, 80);
      cleanup(() => { clearTimeout(timer); controller.abort(); });
    }, {immediate: true});
    return () => error.value ? h("p", {class: "error"}, error.value) : h("div", {class: "formatted-text", innerHTML: html.value});
  },
};

function shape(node, linked) {
  const x = node.width / 2;
  const y = node.height / 2;
  if (node.kind === "connectionPoint") return h("circle", {r: node.width / 2, fill: node.fill});
  const style = {fill: node.fill, stroke: node.border, "stroke-width": node.kind === "container" && node.locked ? 3.2 : 1.6,
    "stroke-dasharray": linked ? "7 4" : undefined};
  if (node.shape === "ellipse") return h("ellipse", {...style, rx: x, ry: y});
  if (node.shape === "diamond") return h("polygon", {...style, points: ["0," + -y, x + ",0", "0," + y, -x + ",0"].join(" ")});
  return h("rect", {...style, x: -x, y: -y, width: node.width, height: node.height, rx: node.shape === "rounded" ? 12 : 0});
}

// The stored endpoints are the tips. Stop the shaft at each triangle's base.
function wireDrawing(edge, findNode) {
  const geometry = edgeGeometry(edge, findNode);
  const {from, to, control} = geometry;
  const paint = edgePaint(edge);
  const ends = {};
  for (const [end, tip, toward, visible] of [
    ["source", from, control ?? to, paint.startArrow], ["target", to, control ?? from, paint.endArrow],
  ]) {
    const dx = toward.x-tip.x, dy = toward.y-tip.y;
    const distance = Math.hypot(dx,dy);
    const available = control || !(paint.startArrow && paint.endArrow) ? distance : distance/2;
    const length = visible ? Math.min(paint.width*6.75, available) : paint.width*6.75;
    const ratio = visible && distance ? length/distance : 0;
    ends[end] = {visible, transform: arrowTransform(tip,toward,length/6.75),
      base: {x: tip.x+dx*ratio, y: tip.y+dy*ratio}};
  }
  const a = ends.source.base, b = ends.target.base;
  const d = `M ${a.x} ${a.y} ` + (control ? `Q ${control.x} ${control.y} ` : "L ") + `${b.x} ${b.y}`;
  const stroke = {d, fill: "none", stroke: paint.color, "stroke-width": paint.width, "stroke-linecap": "butt",
    "stroke-dasharray": edge.style === "dashed" ? (paint.width*3.5)+" "+(paint.width*2.5) : undefined};
  return {...geometry, ends, stroke, paint};
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
  throw Object.assign(new Error(detail.reason || "A kérés nem sikerült (" + response.status + ")."), {status: response.status});
}

createApp({
  setup() {
    const board = ref(null);
    const insertion = ref(null);
    const sceneNodes = computed(() => {
      const nodes = board.value?.nodes ?? [];
      return insertion.value ? nodes.concat(insertion.value.nodes) : nodes;
    });
    const sceneEdges = computed(() => {
      const edges = board.value?.edges ?? [];
      const draft = insertion.value;
      return draft ? edges.filter(e => e.id !== draft.original?.id).concat(draft.edges) : edges;
    });
    const layers = computed(() => {
      const ordered = [...sceneNodes.value].sort((a,b) => Number(b.kind === "container")-Number(a.kind === "container") ||
        b.width*b.height-a.width*a.height);
      const firstBox = ordered.findIndex(n => n.kind !== "container");
      const split = firstBox < 0 ? ordered.length : firstBox;
      return {ordered, back: ordered.slice(0,split), front: ordered.slice(split)};
    });
    const nodeMap = computed(() => new Map(sceneNodes.value.map(node => [node.id, node])));
    const edgeMap = computed(() => new Map(board.value?.edges.map(edge => [edge.id, edge])));
    const containers = computed(() => containerOrder(board.value?.nodes ?? [], nodeMap.value));
    const ctrl = ref(false);
    const alt = ref(false);
    const accounts = ref(null);
    const canManage = computed(() => role === "admin" || Boolean(user && (board.value?.owner === user || board.value?.creator === user)));
    const canvasText = shallowRef(new Map());
    const textSources = computed(() => [...new Set(
      board.value?.nodes.filter(node => !node.hideText && node.text).map(node => node.text)
    )]);
    const motions = shallowRef(new Map());
    function receiveMotion(frame) {
      if (!frame) { motions.value = new Map(); return; }
      if (frame.revision !== board.value?.revision) return;
      if (frame.ping) {
        if (frame.point) flashPoint(canvas.value?.querySelector("[data-scene]"), frame.point);
        else flashNode(canvas.value, frame.node);
        return;
      }
      const next = new Map(motions.value);
      if (frame.delta) next.set(frame.node, frame);
      else next.delete(frame.node);
      motions.value = next;
    }
    const drawings = computed(() => new Map(sceneNodes.value.map(node => {
      const text = !node.hideText && node.text
        ? canvasText.value.get(node.text) ?? [] : [];
      const layout = labelLayout(node, text);
      return [node.id, {node: {...node, width: layout.width, height: layout.height}, layout}];
    })));
    function displayPosition(node) {
      const drag = gesture.value;
      if (drag?.type === "batch" && drag.members.has(node.id)) return shifted(node.position, drag.delta);
      if (motions.value.size) {
        const motion = [node, ...ancestors(node, nodeMap.value)].map(n => motions.value.get(n.id))
          .find(m => m && m.revision === board.value.revision);
        if (motion) return {x: node.position.x + motion.delta.x, y: node.position.y + motion.delta.y};
      }
      return node.position;
    }
    function drawnNode(id) {
      const node = drawings.value.get(id)?.node;
      return node && (motions.value.size || gesture.value?.type === "batch") ? {...node, position: displayPosition(node)} : node;
    }
    const drawnBounds = () => canvasBounds({
      nodes: [...drawings.value.values()].map(({node, layout}) => ({...node, extentX: layout.extentX, extentY: layout.extentY})), edges: board.value.edges,
    });
    const gridOverride = ref(null);
    const gridVisible = computed(() => gridOverride.value ?? (board.value?.gridVisible !== false));
    const snapToGrid = ref(false);
    const selected = ref(null);
    const batch = ref(null);
    const editingPanel = ref(false);
    const searchQuery = ref(null);
    const searchInput = ref(null);
    const manuallyClosed = ref(false);
    const reconnect = ref(null);
    const menu = ref(null);
    const inspector = ref(null);
    const note = ref(null);
    const canvas = ref(null);
    const view = shallowRef(d3.zoomIdentity);
    const size = ref({width: 0, height: 0});
    const gesture = ref(null);
    const preview = ref(null);
    const checkpointState = ref({revision: 0, changed: false});
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

    const peers = ref([]);
    const held = ref(null);
    let heldEdge = null;
    const online = ref(false);
    let baseline;
    let checkpointRevision;
    function receiveCheckpoint(state) {
      checkpointRevision = state.checkpointRevision;
      checkpointState.value = {revision: state.revision, changed: state.checkpointChanged};
    }
    const checkpointBusy = ref(false);
    function discardDrafts(latest) {
      insertion.value = null;
      batch.value = null;
      generation.value = savedGeneration.value;
      gesture.value = null;
      reconnect.value = null;
      preview.value = null;
      motions.value = new Map();
      selected.value = null;
      held.value = null;
      heldEdge = null;
      selectionRequest++;
      inspectNothing();
      editingField = fieldChanged = false;
      undo.value = [];
      redo.value = [];
      historyBase = copy(latest);
      board.value = copy(latest);
      baseline = copy(latest);
    }
    let queued = Promise.resolve();
    let saveTimer;
    let selectionRequest = 0;
    const params = new URLSearchParams(window.location?.search);
    let initialNode = params.get("node"), initialEdge = params.get("edge");
    const copy = value => JSON.parse(JSON.stringify(value));
    const occupied = id => peers.value.find(p => !p.mine && !p.viewing && p.node === id);
    const groupBlocked = node => moveGroup(node).some(member => occupied(member.id));
    function enqueue(task) {
      const next = queued.then(task);
      queued = next.catch(() => {});
      return next;
    }

    async function refresh() {
      const latest = decodeWorksheet(await (await checked(await fetch(endpoint))).json());
      if (latest.revision <= baseline.revision) return;
      if (latest.resetRevision > baseline.revision) { discardDrafts(latest); return; }
      historyBase = rebaseWorksheet(baseline, historyBase, latest);
      board.value = rebaseWorksheet(baseline, copy(board.value), latest);
      baseline = copy(latest);
      if ((gesture.value?.nodeID && !nodeMap.value.has(gesture.value.nodeID)) ||
          (gesture.value?.edgeID && !edgeMap.value.has(gesture.value.edgeID))) {
        gesture.value = null;
        insertion.value = null;
        preview.value = null;
      }
      if (reconnect.value && !edgeMap.value.has(reconnect.value.edgeID)) {
        reconnect.value = null;
        preview.value = null;
      }
      if (selected.value && !(selected.value.kind === "node" ? nodeMap : edgeMap).value.has(selected.value.id)) clearSelection();
      else if (note.value) showNote(nodeMap.value.get(note.value.id), false);
    }

    const mouse = sharedMouse(point => live.cursor(point));
    const live = liveConnection(path, csrf, async state => {
      if (!online.value) {
        problem.value = "";
        const mine = state.participants.find(p => p.mine);
        held.value = mine?.node ?? null;
        heldEdge = mine?.edge ?? null;
      }
      online.value = true;
      receiveCheckpoint(state);
      peers.value = state.participants;
      if (state.revision > baseline.revision) await enqueue(async () => {
        if (state.revision > baseline.revision) await refresh();
      });
      motions.value = new Map([...motions.value].filter(([id, frame]) =>
        frame.revision === board.value.revision && occupied(id)));
      if (initialNode) {
        const id = initialNode;
        initialNode = null;
        if (nodeMap.value.has(id)) openProperties("node", id);
      } else if (initialEdge) {
        const id = initialEdge;
        initialEdge = null;
        if (edgeMap.value.has(id)) openProperties("edge", id);
      }
      if (dirty.value && !saveTimer && !saving.value && !problem.value) scheduleSave();
    }, error => {
      online.value = false;
      held.value = null;
      if (gesture.value) finishPointer({pointerId: gesture.value.pointer}, true);
      if (inspector.value?.kind === "node") inspectNothing();
      problem.value = error.message;
    }, {editing: true, onCursor: mouse?.receive, onMotion: receiveMotion, rate: Number(motionRate) || 33});

    function scheduleSave() {
      if (saveTimer) return;
      saveTimer = setTimeout(() => { saveTimer = null; save(); }, 70);
    }

    async function selectNode(id, edge = null) {
      batch.value = null;
      const ticket = ++selectionRequest;
      if (!online.value) return false;
      if (id && occupied(id)) {
        problem.value = occupied(id).name + " már kijelölte ezt a dobozt.";
        return false;
      }
      try {
        return await enqueue(async () => {
          if (ticket !== selectionRequest) return false;
          if (held.value !== id || heldEdge !== edge) {
            if (dirty.value) await commit();
            const state = await live.select(id, edge);
            heldEdge = edge;
            held.value = id;
            peers.value = state.participants;
            if (state.revision > baseline.revision) await refresh();
          }
          if (ticket !== selectionRequest) return false;
          if (id) selected.value = {kind: "node", id};
          return true;
        });
      } catch (error) {
        problem.value = error.message;
        return false;
      }
    }

    watch(selected, item => {
      if (!item || manuallyClosed.value) return;
      if (item.kind === "node") {
        if (editingPanel.value) {
          inspector.value = item;
          note.value = null;
        } else if (note.value?.id !== item.id) showNote(nodeMap.value.get(item.id), false);
      } else {
        inspector.value = {kind: "edge", id: item.id};
        note.value = null;
      }
    });
    watch(() => editingPanel.value && !manuallyClosed.value && !selected.value && canManage.value, visible => {
      if (visible && !accounts.value) loadAccounts();
    });
    function clearSelection() {
      finishField();
      selected.value = null;
      inspectNothing();
      selectNode(null);
    }

    async function loadCanvasText(sources, signal) {
      const missing = sources.filter(source => !canvasText.value.has(source));
      let blocks = [];
      if (missing.length) {
        const result = await checked(await fetch("/api/text/canvas", {
          method: "POST", signal,
          headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf},
          body: JSON.stringify({sources: missing}),
        }));
        ({blocks} = await result.json());
      }
      if (signal?.aborted) return;
      const current = new Set(textSources.value);
      const updated = new Map([...canvasText.value].filter(([source]) => current.has(source)));
      missing.forEach((source, index) => {
        if (current.has(source)) updated.set(source, blocks[index]);
      });
      canvasText.value = updated;
    }

    watch(textSources, (sources, _, onCleanup) => {
      const controller = new AbortController();
      const timer = setTimeout(() => loadCanvasText(sources, controller.signal).catch(error => {
        if (!controller.signal.aborted) problem.value = error.message;
      }), 80);
      onCleanup(() => {
        clearTimeout(timer);
        controller.abort();
      });
    });

    const undo = shallowRef([]), redo = shallowRef([]);
    let historyBase;
    let editingField = false;
    let fieldChanged = false;

    function recordChanges() {
      const current = copy(board.value);
      const entry = worksheetChanges(historyBase, current);
      historyBase = current;
      if (!entry.length) return;
      undo.value = [...undo.value.slice(-99), entry];
      redo.value = [];
    }

    function finishField() {
      editingField = false;
      if (fieldChanged) recordChanges();
      fieldChanged = false;
    }

    function replay(forward) {
      if (gesture.value || !online.value || checkpointBusy.value) return;
      finishField();
      const source = forward ? redo : undo, destination = forward ? undo : redo;
      const entry = source.value.at(-1);
      if (!entry) return;
      const next = replayChanges(copy(board.value), entry, forward, occupied);
      if (!next) {
        problem.value = "A művelet ütközik a munkalap jelenlegi állapotával vagy egy másik szerkesztő foglalásával.";
        return;
      }
      board.value = next;
      historyBase = copy(next);
      destination.value = [...destination.value, entry];
      source.value = source.value.slice(0, -1);
      markDirty();
      const item = selected.value;
      if (item && !(item.kind === "node" ? nodeMap : edgeMap).value.has(item.id)) clearSelection();
    }

    function modified() {
      if (editingField) fieldChanged = true;
      else recordChanges();
      markDirty();
    }

    function markDirty() {
      generation.value += 1;
      scheduleSave();
      problem.value = "";
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
          return !event.button && !event.altKey && !event.ctrlKey && !reconnect.value && !gesture.value
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
      return {id: id(), title: "Új ötlet", text: "", hideText: false, position: clampPoint(position), width: 176, height: 80,
        shape: "rounded", fill: "#dce9ff", textColor: "#182335", border: "#839bbc", fontSize: 16, bold: true, alignment: "center"};
    }

    function addNode(position = worldAtCenter(), properties = {}) {
      if (!board.value || !online.value) return;
      const node = {...makeNode(position), ...properties};
      board.value.nodes.push(node);
      modified();
      selectNode(node.id);
    }

    async function addSubworksheet(position) {
      menu.value = null;
      const name = window.prompt("Új munkalap útvonalneve")?.trim();
      if (!name) return;
      if (!/^[\p{L}\p{M}\p{Nd}_-]+$/u.test(name)) {
        problem.value = "A név betűt, számot, kötőjelet és aláhúzást tartalmazhat.";
        return;
      }
      try {
        await enqueue(commit);
        const response = await checked(await fetch("/api/subworksheet/" + path + "/" + encodeURIComponent(name), {
          method: "POST", headers: {"X-CSRF-Token": csrf},
        }));
        const sheet = await response.json();
        addNode(position, {title: sheet.title, link: name});
      } catch (error) { problem.value = error.message; }
    }

    async function loadAccounts() {
      try {
        const result = await checked(await fetch("/api/worksheet-users/" + path));
        accounts.value = await result.json();
      } catch (error) {
        problem.value = error.message;
      }
    }

    async function openProperties(kind, itemID, focusLabel = false) {
      if (kind === "node" && !(await selectNode(itemID))) return;
      manuallyClosed.value = false;
      editingPanel.value = true;
      if (kind !== "node") selectNode(null, kind === "edge" ? itemID : null);
      selected.value = kind === "worksheet" ? null : {kind, id: itemID};
      inspector.value = {kind, id: itemID};
      note.value = null;
      menu.value = null;
      if (focusLabel) {
        await nextTick();
        const field = mount.querySelector?.(focusLabel === "text" ? ".inspector textarea" : ".inspector [data-object-label]");
        if (selected.value?.id === itemID && field) {
          field.focus();
          field.select();
        }
      }
    }

    async function deleteNode(node, cascade = false) {
      if (!(await selectNode(node.id)) || groupBlocked(node)) return;
      const ids = new Set(cascade && node.kind === "container" ? moveGroup(node).map(n => n.id) : [node.id]);
      const connected = board.value.edges.filter(edge => ids.has(edge.source) || ids.has(edge.target.node));
      if (!connected.length && node.kind !== "connectionPoint" && !confirm("Törlöd a kijelölt objektumot?")) return;
      if (cascade && ["connectionPoint", "container"].includes(node.kind)) {
        board.value.edges = board.value.edges.filter(edge => !connected.includes(edge));
      } else {
        for (const edge of connected) {
          const {from, to} = edgeGeometry(edge, drawnNode);
          if (ids.has(edge.source)) setEndpoint(edge, "source", {point: clampPoint(from)});
          if (ids.has(edge.target.node)) setEndpoint(edge, "target", {point: clampPoint(to)});
        }
      }
      releaseChildren(node);
      board.value.nodes = board.value.nodes.filter(item => !ids.has(item.id));
      pruneJunctions();
      modified();
      clearSelection();
    }

    function removeEdge(edge) {
      board.value.edges = board.value.edges.filter(item => item.id !== edge.id);
      pruneJunctions();
      clearSelection();
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
      manuallyClosed.value = false;
      const item = selected.value;
      if (!item) return;
      if (item.kind === "node" && !editingPanel.value) showNote(nodeMap.value.get(item.id));
      else inspector.value = {kind: item.kind === "endpoint" ? "edge" : item.kind, id: item.id};
    }

    function inspectNothing() {
      finishField();
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
        if (groupBlocked(node)) return;
        releaseChildren(node);
        delete node.kind;
        delete node.locked;
      } else {
        node.kind = "container";
        for (const child of board.value.nodes) {
          if (!occupied(child.id) && child.id !== node.id && child.parent === node.parent &&
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
      const counts = new Map();
      for (const edge of board.value.edges) {
        for (const id of new Set([edge.source, edge.target.node])) {
          if (id) counts.set(id, (counts.get(id) ?? 0) + 1);
        }
      }
      const removed = new Map(board.value.nodes.filter(n => n.kind === "connectionPoint" && (counts.get(n.id) ?? 0) < 2)
        .map(n => [n.id, n.position]));
      if (!removed.size) return;
      for (const edge of board.value.edges) {
        for (const end of ["source", "target"]) {
          const point = removed.get(edgeEndpoint(edge, end).node);
          if (point) setEndpoint(edge, end, {point: {...point}});
        }
      }
      board.value.nodes = board.value.nodes.filter(n => !removed.has(n.id));
      if (selected.value?.kind === "node" && !nodeMap.value.has(selected.value.id)) selected.value = null;
      if ((inspector.value?.kind === "node" && !nodeMap.value.has(inspector.value.id)) ||
          (note.value && !nodeMap.value.has(note.value.id))) inspectNothing();
    }

    function snap(point, exclude) {
      const hit = node => node.id !== exclude && shapeDistance(drawnNode(node.id), point, 8 / view.value.k) <= 1;
      return layers.value.ordered.findLast(hit);
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

    function cloneBox(source) {
      const originals = moveGroup(source).map(member => nodeMap.value.get(member.id));
      const ids = new Map(originals.map(n => [n.id,id()]));
      const nodes = originals.map(n => ({...copy(n), id: ids.get(n.id), parent: ids.get(n.parent) ?? n.parent}));
      const edges = board.value.edges.filter(e => ids.has(e.source) || ids.has(e.target.node)).map(e => {
        const clone = {...copy(e), id: id()};
        if (ids.has(e.source)) clone.source = ids.get(e.source);
        if (ids.has(e.target.node)) clone.target.node = ids.get(e.target.node);
        return clone;
      });
      return {nodes,edges};
    }

    function stageInsertion(draft) {
      const points = draft.nodes.map(n => n.position);
      if (!draft.original) {
        for (const edge of draft.edges) {
          if (edge.sourcePoint) points.push(edge.sourcePoint);
          if (edge.target.point) points.push(edge.target.point);
        }
      }
      insertion.value = {...draft, points: points.map(point => ({point, x:point.x, y:point.y}))};
    }

    function moveInsertion(operation, point) {
      const draft = insertion.value;
      let dx = point.x-operation.initial.x, dy = point.y-operation.initial.y;
      for (const origin of draft.points) {
        dx = limit(dx,-100000-origin.x,100000-origin.x);
        dy = limit(dy,-100000-origin.y,100000-origin.y);
      }
      for (const origin of draft.points) {
        origin.point.x = origin.x+dx;
        origin.point.y = origin.y+dy;
      }
    }

    function commitInsertion() {
      const draft = insertion.value;
      insertion.value = null;
      if (!online.value || draft.original && JSON.stringify(edgeMap.value.get(draft.original.id)) !== JSON.stringify(draft.original)) return;
      if (board.value.nodes.length + draft.nodes.length > 2000 ||
          board.value.edges.length + draft.edges.length - (draft.original ? 1 : 0) > 4000) {
        problem.value = "A művelettel a munkalap túllépné a dobozok vagy vonalak számának korlátját.";
        return;
      }
      const ids = new Set([...nodeMap.value.keys(), ...draft.nodes.map(n => n.id)]);
      if (draft.edges.some(e => e.source && !ids.has(e.source) || e.target.node && !ids.has(e.target.node))) return;
      board.value.nodes.push(...draft.nodes);
      if (draft.original) board.value.edges.splice(board.value.edges.findIndex(e => e.id === draft.original.id),1,...draft.edges);
      else board.value.edges.push(...draft.edges);
      const root = draft.nodes[0];
      dropParent(root);
      modified();
      selectNode(root.id);
    }

    function pressNode(event, node) {
      finishField();
      if (event.altKey && !event.ctrlKey && event.button === 0 && node.kind !== "connectionPoint") {
        if (!online.value || reconnect.value) return;
        beginDrag(event,"clone",{nodeID: node.id});
        return;
      }
      const controlClick = event.ctrlKey && !event.altKey && (event.button === 0 || event.button === 2);
      if ((event.button !== 0 && !controlClick) || reconnect.value) return;
      event.preventDefault();
      event.stopPropagation();
      menu.value = null;
      event.currentTarget.focus({preventScroll: true});
      const initial = world(event);
      const cabling = controlClick;
      const locked = ancestors(node, nodeMap.value).some(parent => parent.locked);
      gesture.value = {group: cabling || locked ? [] : moveGroup(node), locked, type: cabling ? "cable" : "move", pointer: event.pointerId, nodeID: node.id,
        position: {...node.position}, initial, screen: [event.clientX, event.clientY], moved: false};
      if (cabling) preview.value = {edge: {source: node.id, target: {point: initial}, style: "arrow"}};
      event.currentTarget.setPointerCapture(event.pointerId);
      if (!cabling && !occupied(node.id)) claimGesture(node);
      else if (!cabling) gesture.value.locked = true;
    }

    function claimGesture(node) {
      const operation = gesture.value;
      operation.waiting = true;
      if (inspector.value?.kind === "node" && inspector.value.id !== node.id) inspectNothing();
      selectNode(node.id).then(granted => {
        if (gesture.value !== operation) return;
        operation.waiting = false;
        operation.locked ||= !granted || groupBlocked(node);
        if (operation.type === "resize" && granted) {
          const current = nodeMap.value.get(node.id);
          operation.original = copy(current);
          operation.width = drawnNode(node.id).width;
          operation.height = drawnNode(node.id).height;
        }
        if (operation.type === "move" && granted) {
          const current = nodeMap.value.get(node.id);
          operation.group = moveGroup(current);
          operation.position = {...current.position};
        }
        if (operation.done) finishPointer(operation.done.event, operation.done.cancel);
        else if (operation.latest) updatePointer(operation.latest);
      });
    }

    function pressEndpoint(event, edge, end) {
      finishField();
      if ((event.button !== 0 && !(event.ctrlKey && event.button === 2)) || reconnect.value) return;
      const original = edgeEndpoint(edge, end);
      const geometry = edgeGeometry(edge, drawnNode);
      const position = end === "source" ? geometry.from : geometry.to;
      event.preventDefault();
      event.stopPropagation();
      menu.value = null;
      selectNode(null, edge.id);
      selected.value = {kind: "endpoint", id: edge.id, end};
      gesture.value = {type: "endpoint", original: {...original}, pointer: event.pointerId, edgeID: edge.id, end,
        position: {...position}, initial: world(event), screen: [event.clientX, event.clientY], moved: false};
      event.currentTarget.setPointerCapture(event.pointerId);
    }

    function endpointAt(point, edge, end, commit = false) {
      const opposite = edgeEndpoint(edge, otherEnd(end)).node;
      const free = nearbyEnd(point, edge);
      if (free) {
        if (opposite && end === free.end && edgeEndpoint(free.edge, otherEnd(free.end)).node === opposite) {
          return {point, blocked: true};
        }
        if (!commit) return {point: free.point, junction: free.point};
        const node = {...makeNode(free.point), title: "", kind: "connectionPoint",
          shape: "ellipse", fill: edgePaint(free.edge).color, width: 14, height: 14};
        board.value.nodes.push(node);
        dropParent(node);
        setEndpoint(free.edge, free.end, {node: node.id});
        return {node: node.id};
      }
      const node = snap(point, opposite);
      if (node && opposite && board.value.edges.some(candidate => candidate.id !== edge.id &&
          edgeEndpoint(candidate, end).node === node.id && edgeEndpoint(candidate, otherEnd(end)).node === opposite)) {
        return {point, blocked: true};
      }
      return node ? {node: node.id} : {point: clampPoint(point)};
    }

    function pressCorner(event, node, sx, sy) {
      finishField();
      if (!event.altKey || event.button !== 0 || occupied(node.id) || ancestors(node, nodeMap.value).some(n => n.locked)) return;
      event.preventDefault();
      event.stopPropagation();
      lastClick = null;
      menu.value = null;
      const drawn = drawnNode(node.id);
      gesture.value = {type: "resize", pointer: event.pointerId, nodeID: node.id, sx, sy,
        original: JSON.parse(JSON.stringify(node)), width: drawn.width, height: drawn.height,
        initial: world(event), screen: [event.clientX, event.clientY], moved: false};
      canvas.value.setPointerCapture(event.pointerId);
      claimGesture(node);
    }

    function resizeCorner(operation, point) {
      const {original, width, height, sx, sy} = operation;
      const node = nodeMap.value.get(operation.nodeID);
      const w = limit(width + sx * (point.x-operation.initial.x), 64, 880);
      const h = limit(height + sy * (point.y-operation.initial.y), 40, 680);
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
      if (operation?.waiting) {
        operation.latest = event;
        operation.moved ||= Math.hypot(event.clientX-operation.screen[0], event.clientY-operation.screen[1]) > 3;
        return;
      }
      const point = world(event);
      if (operation) {
        operation.moved ||= Math.hypot(event.clientX - operation.screen[0], event.clientY - operation.screen[1]) > 3;
        if (operation.type === "clone" || operation.type === "split") {
          if (operation.moved) {
            if (!insertion.value) stageInsertion(cloneBox(nodeMap.value.get(operation.nodeID)));
            moveInsertion(operation,point);
          }
          return;
        }
        if (["rectangle","batch","text"].includes(operation.type)) {
          operation.point = point;
          const delta = {x: point.x-operation.initial.x, y: point.y-operation.initial.y};
          if (operation.type === "batch") {
            if (snapToGrid.value) {
              const spacing = board.value.gridSpacing ?? 20;
              for (const k of ["x","y"]) delta[k] = Math.round(delta[k]/spacing)*spacing;
            }
            const points = [...operation.members].map(id => nodeMap.value.get(id)?.position).filter(Boolean);
            for (const edge of board.value.edges) if (batch.value?.edges.has(edge.id)) {
              if (edge.sourcePoint && !edge.source) points.push(edge.sourcePoint);
              if (edge.target.point) points.push(edge.target.point);
            }
            for (const p of points) for (const k of ["x","y"]) delta[k] = limit(delta[k],-100000-p[k],100000-p[k]);
          }
          if (operation.type === "text") {
            const n = drawnNode(operation.nodeID);
            const bounds = operation.bounds;
            delta.x = bounds ? limit(delta.x, Math.min(0,-n.width/2-bounds.left), Math.max(0,n.width/2-bounds.right)) : limit(delta.x,-n.width,n.width);
            delta.y = bounds ? limit(delta.y, Math.min(0,-n.height/2-bounds.top), Math.max(0,n.height/2-bounds.bottom)) : limit(delta.y,-n.height,n.height);
          }
          operation.delta = delta;
          return;
        }
        if (operation.type === "resize") {
          if (operation.moved && !operation.locked) resizeCorner(operation, point);
          return;
        }
        if (operation.type === "move" || operation.type === "endpoint") {
          if (!operation.moved) return;
          const position = clampPoint({x: operation.position.x + point.x - operation.initial.x,
            y: operation.position.y + point.y - operation.initial.y});
          if (operation.type === "move") {
            if (!operation.locked && !operation.group.some(member => occupied(member.id))) {
              if (snapToGrid.value) {
                const spacing = board.value.gridSpacing ?? 20;
                for (const axis of ["x", "y"]) position[axis] = (Math.round(position[axis] / spacing - .5) + .5) * spacing;
              }
              translateGroup(operation.group, position.x-operation.position.x, position.y-operation.position.y);
              const current = nodeMap.value.get(operation.nodeID).position;
              live.motion({node: operation.nodeID, revision: baseline.revision,
                delta: {x: current.x-operation.position.x, y: current.y-operation.position.y}});
            }
          } else {
            const edge = edgeMap.value.get(operation.edgeID);
            operation.endPosition = position;
            const endpoint = endpointAt(position, edge, operation.end);
            operation.endPosition = endpoint.point ?? position;
            preview.value = {target: endpoint.node, junction: endpoint.junction};
          }
          return;
        }
        const edge = {source: operation.nodeID, sourcePoint: operation.nodeID ? undefined : operation.initial, target: {point}, style: "arrow", endArrow: true};
        edge.target = endpointAt(point, edge, "target");
        preview.value = {edge, target: edge.target.node, junction: edge.target.junction};
      } else {
        const {edgeID, end} = reconnect.value;
        const edge = {...edgeMap.value.get(edgeID)};
        const endpoint = endpointAt(point, edge, end);
        setEndpoint(edge, end, endpoint);
        preview.value = {edge, target: endpoint.node, junction: endpoint.junction};
      }
    }

    function finishPointer(event, cancel = false) {
      const operation = gesture.value;
      if (!operation || operation.pointer !== event.pointerId) return;
      // Handle quick clicks even while the selection request is pending.
      if (operation.waiting && operation.type === "move" && !operation.moved && !cancel &&
          Math.hypot(event.clientX-operation.screen[0], event.clientY-operation.screen[1]) <= 3) operation.waiting = false;
      if (operation.waiting) {
        // Pointer capture can end before the server acknowledges the selection.
        operation.done ??= {event, cancel};
        return;
      }
      if (!cancel) updatePointer(event);
      if (insertion.value) {
        if (cancel) insertion.value = null;
        else commitInsertion();
      } else if (operation.type === "rectangle" && operation.moved && !cancel) selectRectangle(operation);
      else if (operation.type === "batch" && operation.moved && !cancel) finishBatch(operation);
      else if (operation.type === "text" && operation.moved && !cancel && !operation.locked) {
        const node = nodeMap.value.get(operation.nodeID);
        const drawn = drawnNode(node.id);
        const point = operation.point;
        const slot = (v, size) => v < -size/6 ? 0 : v > size/6 ? 2 : 1;
        const alignment = ["left","center","right"][slot(point.x-node.position.x,drawn.width)];
        const verticalAlignment = ["top","middle","bottom"][slot(point.y-node.position.y,drawn.height)];
        const style = {alignment,verticalAlignment};
        if (operation.section === "title") Object.assign(node,style);
        else node[operation.section] = {...node[operation.section], ...style};
        if (alignment === "center" && verticalAlignment === "middle") {
          if (operation.section === "title" && node.titleOutside) node.titleOutside = false;
        }
        modified();
      } else if (operation.type === "resize" && operation.moved && !operation.locked) {
        if (cancel) {
          const index = board.value.nodes.findIndex(n => n.id === operation.nodeID);
          board.value.nodes[index] = operation.original;
        } else modified();
      } else if (operation.type === "move" && operation.moved) {
        lastClick = null;
        const node = nodeMap.value.get(operation.nodeID);
        if (cancel && !operation.locked) live.endMotion(node.id, baseline.revision);
        if (cancel && !operation.locked) translateGroup(operation.group, 0, 0);
        else if (!operation.locked) {
          live.flushMotion();
          dropParent(node);
          modified();
        }
      } else if (!operation.moved && !cancel && (operation.nodeID || operation.edgeID || operation.hitID)) {
        const kind = operation.hitKind ?? (operation.nodeID ? "node" : "edge");
        const id = operation.hitID ?? operation.nodeID ?? operation.edgeID;
        const time = performance.now();
        const [x,y] = operation.screen;
        if (lastClick?.id === id && lastClick.kind === kind && time-lastClick.time < 450 &&
            Math.hypot(x-lastClick.x,y-lastClick.y) < 10) {
          lastClick = null;
          openProperties(kind,id,event.altKey && kind === "node" ? "text" : true);
        } else {
          lastClick = {id,kind,time,x,y};
          if (operation.type === "move" && !editingPanel.value && !manuallyClosed.value && !note.value) showNote(nodeMap.value.get(id), false);
        }
      } else if (operation.type === "cable" && operation.moved && !cancel) {
        const edge = {id: id(), ...preview.value.edge};
        edge.target = endpointAt(world(event), edge, "target", true);
        if (edge.target.blocked) problem.value = "Ezen az útvonalon már van kábel.";
        else {
          board.value.edges.push(edge);
          modified();
          selectNode(null, edge.id);
          selected.value = {kind: "edge", id: edge.id};
        }
      } else if (operation.type === "endpoint" && operation.moved) {
        const edge = edgeMap.value.get(operation.edgeID);
        const endpoint = cancel ? operation.original
          : endpointAt(operation.endPosition, edge, operation.end, true);
        if (endpoint.blocked) problem.value = "Ezen az útvonalon már van kábel.";
        else setEndpoint(edge, operation.end, endpoint);
        if (!cancel && !endpoint.blocked) {
          pruneJunctions();
          if (endpoint.node) selected.value = {kind: "edge", id: edge.id};
          modified();
        }
      }
      gesture.value = null;
      preview.value = null;
      if (dirty.value && !saveTimer) scheduleSave();
    }

    function retarget(edge, end) {
      menu.value = null;
      reconnect.value = {edgeID: edge.id, end};
      preview.value = null;
    }

    function shifted(point, delta) {
      return {x: point.x + delta.x, y: point.y + delta.y};
    }

    function rectangle(a, b) {
      return {x: Math.min(a.x,b.x), y: Math.min(a.y,b.y), width: Math.abs(a.x-b.x), height: Math.abs(a.y-b.y)};
    }

    function selectRectangle(drag) {
      const box = rectangle(drag.initial, drag.point);
      const inside = p => p.x >= box.x && p.x <= box.x + box.width && p.y >= box.y && p.y <= box.y + box.height;
      const nodes = new Set(), edges = new Set();
      for (const {node} of drawings.value.values()) {
        if ([-1,1].every(k => inside({x: node.position.x+k*node.width/2, y: node.position.y+k*node.height/2}))) nodes.add(node.id);
      }
      for (const edge of board.value.edges) {
        const {from,to,control} = edgeGeometry(edge, drawnNode);
        if (!inside(from) || !inside(to)) continue;
        // A quadratic can extend past both endpoints at its interior extrema.
        const fits = !control || ["x","y"].every(axis => {
          const t = (from[axis]-control[axis])/(from[axis]-2*control[axis]+to[axis]);
          if (!(t > 0 && t < 1)) return true;
          const at = key => (1-t)**2*from[key]+2*(1-t)*t*control[key]+t*t*to[key];
          return inside({x: at("x"), y: at("y")});
        });
        if (fits) edges.add(edge.id);
      }
      if (nodes.size || edges.size) {
        batch.value = {nodes, edges};
        manuallyClosed.value = false;
      }
    }

    watch(board, () => {
      const group = batch.value;
      if (!group) return;
      for (const id of group.nodes) if (!nodeMap.value.has(id)) group.nodes.delete(id);
      for (const id of group.edges) if (!edgeMap.value.has(id)) group.edges.delete(id);
      if (!group.nodes.size && !group.edges.size) batch.value = null;
    });

    function batchBlocked(ids) {
      const blocked = !online.value || [...ids].some(id => occupied(id) || !nodeMap.value.has(id) ||
        ancestors(nodeMap.value.get(id), nodeMap.value).some(n => n.locked && !ids.has(n.id)));
      if (blocked) problem.value = "A kijelölés módosításához aktív kapcsolat és szabadon szerkeszthető objektumok szükségesek.";
      return blocked;
    }

    function moveBatchEdge(edge, drag) {
      const result = {...edge};
      for (const end of ["source","target"]) {
        const endpoint = edgeEndpoint(edge,end);
        if (!endpoint.node) setEndpoint(result,end,{point: shifted(endpoint.point,drag.delta)});
      }
      return result;
    }

    function finishBatch(drag) {
      if (!batch.value || batchBlocked(drag.members)) return;
      gesture.value = null;
      for (const id of drag.members) {
        const node = nodeMap.value.get(id);
        node.position = shifted(node.position,drag.delta);
      }
      for (const edge of board.value.edges) {
        if (batch.value.edges.has(edge.id)) Object.assign(edge,moveBatchEdge(edge,drag));
      }
      for (const id of batch.value.nodes) {
        const node = nodeMap.value.get(id);
        if (!drag.members.has(node.parent)) dropParent(node);
      }
      modified();
    }

    function deleteBatch() {
      const group = batch.value;
      if (!group || batchBlocked(group.nodes) || !confirm("Törlöd a kijelölt objektumokat?")) return;
      board.value.edges = board.value.edges.filter(e => !group.edges.has(e.id));
      for (const edge of board.value.edges) {
        const {from,to} = edgeGeometry(edge,drawnNode);
        if (group.nodes.has(edge.source)) setEndpoint(edge,"source",{point: from});
        if (group.nodes.has(edge.target.node)) setEndpoint(edge,"target",{point: to});
      }
      for (const node of board.value.nodes) {
        while (node.parent && group.nodes.has(node.parent)) node.parent = nodeMap.value.get(node.parent)?.parent;
      }
      board.value.nodes = board.value.nodes.filter(n => !group.nodes.has(n.id));
      pruneJunctions();
      modified();
      clearSelection();
    }

    function beginDrag(event, type, extra = {}) {
      event.preventDefault();
      event.stopPropagation();
      menu.value = null;
      const point = world(event);
      gesture.value = {type, initial: point, point, delta: {x:0,y:0}, screen: [event.clientX,event.clientY],
        pointer: event.pointerId, moved: false, ...extra};
      (type === "clone" ? event.currentTarget : canvas.value).setPointerCapture(event.pointerId);
    }

    function pressCanvas(event) {
      finishField();
      if (event.target.closest("[role=link]")?.getAttribute?.("role") === "link") return;
      const hit = event.target.closest("[data-node], [data-edge]");
      if (event.button === 0 && !event.ctrlKey && !reconnect.value) {
        if (event.altKey && !hit) {
          clearSelection();
          beginDrag(event, "rectangle");
          return;
        }
        if (!event.altKey && batch.value && (batch.value.nodes.has(hit?.dataset?.node) || batch.value.edges.has(hit?.dataset?.edge))) {
          const members = new Set([...batch.value.nodes].flatMap(id => moveGroup(nodeMap.value.get(id)).map(n => n.id)));
          beginDrag(event, "batch", {members, hitID: hit.dataset.node ?? hit.dataset.edge, hitKind: hit.dataset.node ? "node" : "edge"});
          return;
        }
      }
      rightPress = event.button === 2 && !event.ctrlKey;
      if (!reconnect.value && !event.target.closest("[data-node], [data-edge]")) {
        if (event.ctrlKey && !event.altKey && [0, 2].includes(event.button) && online.value) {
          event.preventDefault();
          event.stopPropagation();
          menu.value = null;
          const initial = clampPoint(world(event));
          gesture.value = {type: "cable", pointer: event.pointerId, initial, screen: [event.clientX, event.clientY], moved: false};
          preview.value = {edge: {sourcePoint: initial, target: {point: initial}, style: "arrow"}};
          canvas.value.setPointerCapture(event.pointerId);
          return;
        }
        if (event.button === 0) clearSelection();
      }
      if (event.button !== 0 || event.ctrlKey || !reconnect.value) return;
      event.preventDefault();
      event.stopPropagation();
      const {edgeID, end} = reconnect.value;
      const edge = edgeMap.value.get(edgeID);
      const endpoint = endpointAt(world(event), edge, end, true);
      if (endpoint.blocked) { problem.value = "Ezen az útvonalon már van kábel."; return; }
      setEndpoint(edge, end, endpoint);
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

    async function showNote(node, select = true) {
      if (!node || reconnect.value) return;
      if (select) { editingPanel.value = false; manuallyClosed.value = false; }
      if (select && !occupied(node.id) && held.value !== node.id) selectNode(node.id);
      menu.value = null;
      inspector.value = null;
      const request = ++noteRequest;
      note.value = {id: node.id, request, loading: Boolean(node.text)};
      if (!node.text) return;
      try {
        const rendered = await checked(await fetch("/api/text", {method: "POST", headers: {
          "Content-Type": "application/json", "X-CSRF-Token": csrf,
        }, body: JSON.stringify({text: node.text})}));
        const html = await rendered.text();
        if (note.value?.request === request) note.value = {id: node.id, html, loading: false};
      } catch (error) {
        if (note.value?.request === request) note.value = {id: node.id, error: error.message, loading: false};
      }
    }

    async function commit() {
      if (!dirty.value) return;
      saving.value = true;
      try {
        for (let attempt = 0; attempt < 4; attempt++) {
          if (!dirty.value || (gesture.value?.moved && ["move", "resize"].includes(gesture.value.type))) return;
          const version = generation.value;
          pruneJunctions();
          const submitted = copy(board.value);
          const result = await fetch(endpoint, {method: "PUT", headers: {"Content-Type": "application/json",
            "X-CSRF-Token": csrf, "X-Worksheet-Client": live.client, "If-Match": '"' + baseline.revision + '"'},
            body: JSON.stringify(encodeWorksheet({...submitted, schemaVersion: 2}))});
          if (result.status === 412) { await refresh(); continue; }
          if (result.status === 409 || result.status === 423) {
            const state = await live.snapshot();
            peers.value = state.participants;
            held.value = state.participants.find(p => p.mine)?.node ?? null;
            await refresh();
            if (result.status === 409) continue;
            // A lease may have changed owners while this tab was disconnected.
            const foreign = new Set(peers.value.filter(p => !p.mine && !p.viewing && p.node).map(p => p.node));
            const local = new Map(board.value.nodes.map(n => [n.id, n]));
            for (const node of baseline.nodes) if (foreign.has(node.id)) local.set(node.id, copy(node));
            board.value.nodes = [...local.values()];
            historyBase.nodes = historyBase.nodes.map(n => foreign.has(n.id) ? copy(local.get(n.id) || n) : n);
            if (gesture.value?.group?.some(n => foreign.has(n.id))) gesture.value = null;
            scheduleSave();
            throw new Error("A közben lefoglalt doboz visszaállt a közös munkalapon látható állapotára.");
          }
          const saved = decodeWorksheet(await (await checked(result)).json());
          historyBase = rebaseWorksheet(submitted, historyBase, saved);
          board.value = rebaseWorksheet(submitted, copy(board.value), saved);
          baseline = copy(saved);
          savedGeneration.value = version;
          problem.value = "";
          if (dirty.value) scheduleSave();
          return;
        }
        scheduleSave();
        throw new Error("Párhuzamos mentés, újrapróbálkozás…");
      } finally { saving.value = false; }
    }

    async function save() {
      if (!online.value || gesture.value?.type === "endpoint") return;
      try { await enqueue(commit); }
      catch (error) {
        if (held.value) live.endMotion(held.value, baseline.revision);
        problem.value = error.message;
        if (!error.status || error.status >= 500) setTimeout(() => { if (dirty.value) save(); }, 1200);
      }
    }

    async function sessionAction(action) {
      if (!online.value || checkpointBusy.value || gesture.value) return;
      if (action === "resign" && !confirm("Visszaállítod a közös munkalapot a legutóbbi Mentéshez vagy a munkamenet elejéhez? Ez minden résztvevő vásznára érvényes.")) return;
      checkpointBusy.value = true;
      problem.value = "";
      const expectedCheckpoint = checkpointRevision;
      const observedRevision = baseline.revision;
      try {
        await enqueue(async () => {
          if (action === "checkpoint") await commit();
          const revision = action === "resign" ? observedRevision : baseline.revision;
          const state = await live.checkpoint(action, revision, expectedCheckpoint);
          receiveCheckpoint(state);
          if (action === "resign") await refresh();
        });
      } catch (error) {
        problem.value = error.message;
        if (error.status === 412) await enqueue(refresh).catch(() => {});
      } finally { checkpointBusy.value = false; }
    }

    async function followBoxLink(destination) {
      if (destination.kind === "website") { openExternalLink(destination.href); return; }
      const target = new URL(destination.href, location.href);
      if (dirty.value) await save();
      if (!dirty.value) location.assign((target.pathname === "/" ? "/" : "/edit" + target.pathname) + target.search + target.hash);
    }

    async function exportSVG() {
      if (!board.value || !canvas.value) return;
      await loadCanvasText(textSources.value).catch(() => {});
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
      output.append(title, background, scene);
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
        sessionAction("checkpoint");
      }
      if (searchQuery.value !== null) {
        if (event.key === "Escape" || event.key === "Enter") {
          event.preventDefault?.();
          searchQuery.value = null;
        }
        return;
      }
      if ((event.ctrlKey || event.metaKey) && !event.altKey && ["z", "y"].includes(event.key.toLowerCase())) {
        event.preventDefault?.();
        event.target?.closest?.("input, textarea, select")?.blur();
        replay(event.key.toLowerCase() === "y" || event.shiftKey);
        return;
      }
      if (event.key !== "Escape" && event.target?.closest?.("input, textarea, select, [contenteditable=true]")) return;
      if (event.key === "Enter" && !event.shiftKey && !event.target?.closest?.("button, a")) {
        event.preventDefault?.();
        if (!event.repeat) {
          searchQuery.value = "";
          nextTick(() => searchInput.value?.focus());
        }
        return;
      }
      if (["Delete", "Backspace"].includes(event.key) && (selected.value || batch.value) && !gesture.value) {
        event.preventDefault?.();
        if (event.repeat) return;
        if (batch.value) { deleteBatch(); return; }
        const {kind, id} = selected.value;
        if (kind === "node" && nodeMap.value.has(id)) deleteNode(nodeMap.value.get(id), event.ctrlKey);
        else if (edgeMap.value.has(id)) removeEdge(edgeMap.value.get(id));
        return;
      }
      if (event.key === "Escape") {
        const active = gesture.value;
        if (active) {
          finishPointer({pointerId: active.pointer}, true);
          if (canvas.value.hasPointerCapture?.(active.pointer)) canvas.value.releasePointerCapture(active.pointer);
        }
        if (!selected.value && !active && !reconnect.value) manuallyClosed.value = true;
        if (active?.waiting) gesture.value = null;
        document.activeElement?.closest?.("[data-node], [data-edge]")?.blur();
        lastClick = null;
        clearSelection();
        reconnect.value = null;
        preview.value = null;
      }
    }

    // macOS can release pointer capture when Ctrl+click dispatches contextmenu.
    function outsideMove(event) {
      if (gesture.value && !canvas.value?.contains(event.target)) updatePointer(event);
    }
    function outsideUp(event) {
      if (gesture.value && !canvas.value?.contains(event.target)) finishPointer(event);
    }
    function cancelGesture() {
      if (gesture.value) finishPointer({pointerId: gesture.value.pointer}, true);
      clearModifiers();
    }

    const currentCrumb = document.querySelector(".breadcrumbs a[aria-current=page]");
    async function switchToViewer(event) {
      if (!dirty.value || event.button || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      await save();
      if (!dirty.value) location.assign(currentCrumb.href);
    }

    function beforeUnload(event) {
      if (!dirty.value) return;
      event.preventDefault();
      event.returnValue = "";
    }

    onMounted(async () => {
      currentCrumb?.addEventListener?.("click", switchToViewer);
      window.addEventListener("keydown", keyboard);
      window.addEventListener("keyup", modifiers);
      window.addEventListener("blur", cancelGesture);
      window.addEventListener("pointermove", outsideMove);
      window.addEventListener("pointerup", outsideUp);
      window.addEventListener("beforeunload", beforeUnload);
      window.addEventListener("pagehide", live.stop);
      window.addEventListener("pageshow", restore);
      try {
        const response = await checked(await fetch(endpoint));
        baseline = decodeWorksheet(await response.json());
        board.value = copy(baseline);
        historyBase = copy(baseline);
        live.start();
        await nextTick();
        initializeZoom();
        if (canvas.value.querySelector) mouse.bind(canvas.value, canvas.value.querySelector("[data-mouse-layer]"), mount.querySelector(".canvas-controls"));
      } catch (error) {
        problem.value = error.message;
      }
    });

    function restore(event) { if (event.persisted) { held.value = null; clearSelection(); live.start(); } }

    onUnmounted(() => {
      currentCrumb?.removeEventListener?.("click", switchToViewer);
      mouse?.stop();
      live.stop();
      window.removeEventListener("pagehide", live.stop);
      window.removeEventListener("pageshow", restore);
      resizeObserver?.disconnect();
      window.removeEventListener("keydown", keyboard);
      window.removeEventListener("keyup", modifiers);
      window.removeEventListener("blur", cancelGesture);
      window.removeEventListener("pointermove", outsideMove);
      window.removeEventListener("pointerup", outsideUp);
      window.removeEventListener("beforeunload", beforeUnload);
    });

    function renderNode(node) {
      const {node: drawn, layout} = drawings.value.get(node.id);
      const position = displayPosition(node);
      const selectors = peers.value.filter(p => p.node === node.id && (!p.mine || (selected.value?.kind === "node" && selected.value.id === node.id)));
      const owner = selectors.find(p => !p.viewing) ?? selectors[0];
      const destination = node.kind === "connectionPoint" ? null : worksheetLink(node.link, path);

      const textDrag = gesture.value?.type === "text" && gesture.value.nodeID === node.id ? gesture.value : null;
      const inset = node.shape === "diamond" ? .45 : node.shape === "ellipse" ? .7 : .94;
      const [outline, dimensions] = selectionOutline(node.kind === "connectionPoint" ? "ellipse" : drawn.shape, drawn.width, drawn.height);
      const snapTarget = preview.value?.target === node.id;
      return h("g", {key: node.id, "data-node": node.id, "data-width": drawn.width, "data-height": drawn.height, tabindex: 0, role: "button",
        "aria-label": node.title, "data-link": destination ? "" : undefined, class: ["idea", {occupied: occupied(node.id), claimed: !!owner}],
        transform: "translate(" + position.x + " " + position.y + ")",
        onPointerenter: event => {
          if (!gesture.value && node.hideText && node.text) showTooltip(event, async signal => {
            const result = await checked(await fetch("/api/text", {method: "POST", signal,
              headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify({text: node.text})}));
            return result.text();
          });
        },
        onPointerleave: hideTooltip,
        onPointerdown: event => { hideTooltip(); pressNode(event, node); },
        onDblclick: event => { event.stopPropagation(); openProperties("node",node.id,event.altKey ? "text" : true); },
        onContextmenu: event => context(event, "node", node.id),
        onKeydown: event => {
          if (event.key === "Enter" && event.shiftKey) openProperties("node", node.id);
        },
      }, [
        owner || snapTarget || batch.value?.nodes.has(node.id) ? h(outline, {"data-editor-only": "", ...dimensions, fill: "none",
          stroke: owner?.color ?? "#16a085", "stroke-width": 3, "pointer-events": "none"}) : null,
        shape(drawn, !!destination),
        node.kind === "connectionPoint" && node.title ? h("text", {x: drawn.width/2 + 4, y: 4, fill: node.textColor, "font-size": 14}, node.title) : null,
        layout.frame ? h("rect", {...layout.frame, "pointer-events": "none", transform: textDrag?.section === "textStyle" ?
          "translate("+textDrag.delta.x+" "+textDrag.delta.y+")" : undefined}) : null,
        h("text", {"font-family": "system-ui, sans-serif", "pointer-events": "none"},
          layout.lines.map(line => h("tspan", {
            class: destination && !line.runs ? "link-label" : undefined,
            "data-body-row": line.section === "textStyle" ? "" : undefined,
            "pointer-events": "visiblePainted", cursor: alt.value && ctrl.value ? "grab" : undefined,
            onPointerdown: e => {
              if (!e.ctrlKey || !e.altKey || ![0,2].includes(e.button) || occupied(node.id) || ancestors(node,nodeMap.value).some(n => n.locked)) return;
              let bounds;
              if (line.section === "textStyle") {
                const rows = Array.from(e.currentTarget.parentNode.querySelectorAll("[data-body-row]"), row => row.getBBox());
                if (rows.length) bounds = {
                  left: Math.min(...rows.map(r => r.x)), right: Math.max(...rows.map(r => r.x+r.width)),
                  top: Math.min(...rows.map(r => r.y)), bottom: Math.max(...rows.map(r => r.y+r.height)),
                };
              }
              beginDrag(e,"text",{nodeID: node.id, section: line.section, bounds});
              claimGesture(node);
            },
            x: line.x + (textDrag?.section === line.section ? textDrag.delta.x : 0),
            y: line.y + (textDrag?.section === line.section ? textDrag.delta.y : 0), "text-anchor": line.anchor, "font-style": line.italic ? "italic" : undefined,
            "text-decoration": line.underline ? "underline" : undefined, fill: line.color, "font-size": line.size, "font-weight": line.weight,
            textLength: line.fit, lengthAdjust: line.fit ? "spacingAndGlyphs" : undefined,
          }, line.runs ? line.runs.map(run => {
            const format = run.format || {};
            if (!format.bold && !format.italic && !format.code && !format.link) return run.text;
            return h("tspan", {"font-weight": format.bold ? 700 : undefined,
              "font-style": format.italic ? "italic" : undefined, "font-family": format.code ? "monospace" : undefined,
              "xml:space": format.code ? "preserve" : undefined,
              "text-decoration": format.link ? "underline" : undefined}, run.text);
          }) : line.text))),
        destination ? h("svg", {x: drawn.width/2*inset-15, y: drawn.height/2*inset-16, width: 14, height: 14,
          viewBox: "0 0 24 24", fill: "none", stroke: node.textColor, "stroke-width": 1.8,
          "stroke-linecap": "round", "stroke-linejoin": "round", "pointer-events": "all",
          role: "link", tabindex: 0, "aria-label": "Hivatkozás megnyitása", cursor: "pointer",
          onPointerdown: e => { if (!e.altKey) e.stopPropagation(); }, onClick: e => e.stopPropagation(),
          onDblclick: e => { if (e.altKey) return; e.preventDefault(); e.stopPropagation(); followBoxLink(destination); },
          onKeydown: e => { if (e.key === "Enter") { e.preventDefault(); e.stopPropagation(); followBoxLink(destination); } }},
          [h("rect", {width: 24, height: 24, fill: "transparent", stroke: "none"}), h("path", {d: linkIcons[destination.kind]})]) : null,
        ...(alt.value && !ctrl.value && !occupied(node.id) && node.kind !== "connectionPoint" && !ancestors(node, nodeMap.value).some(n => n.locked)
          ? [[-1,-1], [1,-1], [1,1], [-1,1]].map(([sx, sy]) => {
            const r = 5/view.value.k;
            return h("rect", {"data-editor-only": "", x: sx*drawn.width/2-r, y: sy*drawn.height/2-r,
              width: 2*r, height: 2*r, fill: "#ffffff", stroke: "#4168e9", "stroke-width": 1/view.value.k,
              cursor: sx === sy ? "nwse-resize" : "nesw-resize", onPointerdown: e => pressCorner(e, node, sx, sy)});
          }) : []),
      ]);
    }

    function renderEndpoint(edge, end, head, color, interactive = true) {
      const attached = Boolean(edgeEndpoint(edge,end).node);
      const attrs = {key: edge.id + end, transform: head.transform, stroke: "none",
        fill: head.visible ? color : "transparent", "pointer-events": interactive ? "all" : "none"};
      if (interactive) Object.assign(attrs, {"data-edge": edge.id, "data-endpoint": end,
        class: attached ? "detach-endpoint" : "edge-endpoint",
        onPointerdown: event => pressEndpoint(event,edge,end),
        onContextmenu: event => context(event,"edge",edge.id),
        onClick: event => event.stopPropagation()});
      if (head.visible) return h("path", {...attrs, d: "M0 0L-1 -.5V.5Z"});
      return interactive ? h("rect", {...attrs, "data-editor-only": "", x:-1, y:-0.5, width:1, height:1}) : null;
    }

    function renderEdge(edge) {
      const drag = gesture.value;
      if (drag?.type === "batch" && batch.value?.edges.has(edge.id)) edge = moveBatchEdge(edge,drag);
      if (drag?.edgeID === edge.id && drag.endPosition) {
        edge = {...edge};
        setEndpoint(edge, drag.end, {point: drag.endPosition});
      }
      const {d, labelPosition, angle, stroke, ends, paint} = wireDrawing(edge, drawnNode);
      const mine = selected.value?.id === edge.id && ["edge","endpoint"].includes(selected.value.kind);
      const colors = peers.value.filter(p => p.mine ? mine : p.edge === edge.id).map(p => p.color);
      if (batch.value?.edges.has(edge.id)) colors.push("#16a085");
      return h("g", {key: edge.id, "data-edge": edge.id, tabindex: 0, role: "button", "aria-label": edge.label || "Vonal",
        onPointerdown: event => {
          if (!event.ctrlKey || event.button !== 0 || reconnect.value || !online.value) return;
          const pathElement = event.currentTarget.querySelector(".edge-hit");
          const length = pathElement.getTotalLength();
          const point = world(event);
          const distance = t => {
            const p = pathElement.getPointAtLength(t);
            return Math.hypot(p.x-point.x, p.y-point.y);
          };
          let nearest = 0;
          for (let i = 1; i <= 16; i++) if (distance(length*i/16) < distance(nearest)) nearest = length*i/16;
          for (let step = length/32; step > .1/view.value.k; step /= 2) {
            for (const t of [Math.max(0,nearest-step), Math.min(length,nearest+step)]) if (distance(t) < distance(nearest)) nearest = t;
          }
          if (Math.min(nearest, length-nearest) < 8/view.value.k) return;
          event.preventDefault();
          event.stopPropagation();
          const p = pathElement.getPointAtLength(nearest);
          const joint = {...makeNode(clampPoint(p)), title: "", kind: "connectionPoint", shape: "ellipse",
            width: 14, height: 14, fill: paint.color};
          const tail = {...edge, id: id(), source: joint.id, sourcePoint: undefined, startArrow: false, label: ""};
          const head = {...copy(edge), target: {node: joint.id}, endArrow: false};
          beginDrag(event,"split",{edgeID: edge.id});
          stageInsertion({nodes: [joint], edges: [head,tail], original: copy(edge)});
        },
        onClick: event => { if (event?.ctrlKey || batch.value?.edges.has(edge.id)) return; selectNode(null, edge.id); inspectNothing(); selected.value = {kind: "edge", id: edge.id}; },
        onDblclick: event => {
          event.stopPropagation();
          openProperties("edge", edge.id, true);
        },
        onContextmenu: event => context(event, "edge", edge.id),
      }, [
        ...colors.map((color, i) => h("path", {"data-editor-only": "", d: stroke.d, "stroke-linecap": "butt", stroke: color,
          "stroke-width": paint.width + 5 * (colors.length-i) / view.value.k, "pointer-events": "none"})),
        h("path", stroke),
        h("path", {"data-editor-only": "", d, stroke: "transparent", "stroke-width": Math.max(paint.width + 10, 14 / view.value.k),
          "pointer-events": "stroke", class: "edge-hit"}),
        renderEndpoint(edge,"source",ends.source,paint.color),
        renderEndpoint(edge,"target",ends.target,paint.color),
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
      const shown = cable ? wireDrawing({...cable, color: "#4168e9"}, drawnNode) : null;
      return h("div", {class: "canvas-area"}, [
        h("svg", {ref: canvas, class: ctrl.value ? "editor-canvas ctrl-held" : "editor-canvas", "aria-label": "Ötletvászon",
          onContextmenu: event => context(event),
          onPointerdownCapture: pressCanvas,
          onPointermove: updatePointer,
          onPointerup: event => finishPointer(event),
          onPointercancel: event => finishPointer(event, true),


        }, [
          h("defs", [
            h("pattern", {id: "worksheet-grid", patternUnits: "userSpaceOnUse", width: spacing, height: spacing}, [
              h("circle", {cx: spacing/2, cy: spacing/2, r: 1.1, fill: board.value.gridColor ?? "#ccd7eb"}),
            ]),
          ]),
          h("rect", {width: "100%", height: "100%", fill: board.value.background ?? paper, "pointer-events": "none"}),
          h("g", {transform: view.value + " translate(" + centerX + " " + centerY + ")"}, [
            gridVisible.value ? h("rect", {x: left-centerX, y: top-centerY, width: size.value.width/view.value.k,
              height: size.value.height/view.value.k, fill: "url(#worksheet-grid)", "pointer-events": "none"}) : null,
            h("path", {"data-editor-only": "", "pointer-events": "none", stroke: "#aab9cf", "stroke-width": 1,
              d: "M -8 0 H 8 M 0 -8 V 8"}),
            h("g", {"data-scene": ""}, [
              ...layers.value.back.map(renderNode),
              h("g", {fill: "none", "stroke-linecap": "round"}, sceneEdges.value.map(renderEdge)),
              ...layers.value.front.map(renderNode),
            ]),
            preview.value?.junction ? h("circle", {"data-editor-only": "", cx: preview.value.junction.x, cy: preview.value.junction.y,
              r: 9 / view.value.k, stroke: "#078469", fill: "#b9f3e1", "stroke-width": 2 / view.value.k, "pointer-events": "none"}) : null,
            shown ? h("g", {"pointer-events": "none"}, [h("path", shown.stroke),
              ...["source","target"].map(end => renderEndpoint(cable,end,shown.ends[end],shown.paint.color,false))]) : null,
            gesture.value?.type === "rectangle" ? h("rect", {...rectangle(gesture.value.initial,gesture.value.point),
              fill: "#4168e922", stroke: "#4168e9", "vector-effect": "non-scaling-stroke", "pointer-events": "none"}) : null,
            mouse ? h("g", {"data-mouse-layer": ""}) : null,
          ]),
        ]),
        h("div", {class: "participants", "aria-label": "Jelenlévők"},
          !online.value && problem.value ? h("span", {class: "connection-lost guest", role: "status"}, "Kapcsolat megszakadt") : peers.value.map((p, index) =>
            h("span", {key: index, class: p.color ? "" : "guest", style: {"--peer": p.color}}, p.name))),
        h("div", {class: "canvas-controls"}, [
          button("", () => zoomBy(0.8), {"aria-label": "Kicsinyítés", title: "Kicsinyítés", symbol: "minus"}),
          h("span", Math.round(view.value.k * 100) + "%"),
          button("", () => zoomBy(1.25), {"aria-label": "Nagyítás", title: "Nagyítás", symbol: "plus"}),
          button("Közép", centerOrigin, {title: "Középre állítás, (0, 0)", symbol: "center"}),
          button("Mind", fit, {title: "A teljes vászon megjelenítése", symbol: "fit"}),
          button("", () => { gridOverride.value = !gridVisible.value; }, {
            title: "Pontrács ezen a kliensen", "aria-label": "Pontrács", "aria-pressed": gridVisible.value, symbol: "grid"}),
          button("", () => { snapToGrid.value = !snapToGrid.value; }, {title: "Rácsra igazítás", "aria-label": "Rácsra igazítás", "aria-pressed": snapToGrid.value, symbol: "snap"}),

        ]),
        board.value && !board.value.nodes.length ? h("p", {class: "canvas-empty"}, "Új doboz hozzáadásához kattints jobb gombbal a vászonra.") : null,
      ]);
    }

    function ping(target) {
      menu.value = null;
      if (target.point) flashPoint(canvas.value?.querySelector("[data-scene]"), target.point);
      else flashNode(canvas.value, target.node);
      live.ping(target).catch(error => { problem.value = error.message; });
    }

    function renderMenu() {
      const open = menu.value;
      if (!open) return null;
      const node = nodeMap.value.get(open.id);
      const edge = board.value?.edges.find(item => item.id === open.id);
      const type = open.kind;
      const entries = type === "node" && node ? [
        button("Ping", () => ping({node: node.id}), {symbol: "center", disabled: !online.value}),
        node.kind !== "connectionPoint" ? button(node.link ? "Link feloldása" : "Link", async () => {
          menu.value = null;
          if (!await selectNode(node.id)) return;
          const current = nodeMap.value.get(node.id);
          if (!current) return;
          const link = current.link ? "" : window.prompt("Hivatkozás (allap, ../ vagy https://…)")?.trim();
          if (link == null) return;
          if (link && !worksheetLink(link, path)) { problem.value = "Érvénytelen hivatkozás."; return; }
          updateItem(current, "link", link);
        }, {symbol: node.link ? "unlink" : "link", disabled: !!occupied(node.id)}) : null,
        button("Szerkesztés", () => openProperties("node", node.id), {symbol: "edit", disabled: !!occupied(node.id)}),
        button("Text megnyitása", () => showNote(node), {symbol: "eye"}),
        button("Törlés", () => { menu.value = null; deleteNode(node); }, {class: "button danger", symbol: "trash", disabled: !!occupied(node.id)}),
      ] : type === "edge" && edge ? [
        button("Szerkesztés", () => openProperties("edge", edge.id), {symbol: "edit"}),
        ...endpointActions(edge),
        button("Kapcsolat törlése", () => removeEdge(edge), {class: "button danger", symbol: "trash"}),
      ] : [
        button("Ping", () => ping({point: clampPoint(open.position)}), {symbol: "center", disabled: !online.value}),
        button("Objektum létrehozása", () => { menu.value = null; addNode(open.position); }, {disabled: !board.value, symbol: "plus"}),
        button("Új munkalap", () => addSubworksheet(open.position), {symbol: "plus", disabled: !online.value}),
        button("Középre állítás", () => { menu.value = null; centerOrigin(); }, {symbol: "center"}),
      ];
      return h("div", {class: "context-menu panel", "aria-label": "Műveletek",
        style: {left: open.x + "px", top: open.y + "px"}}, entries);
    }

    function sidebar(label, contents, deletion) {
      return h("aside", {class: "inspector", "aria-label": label,
        onFocusin: event => { editingField = event.target.matches("textarea,input,select"); },
        onFocusout: finishField,
        onChange: event => { if (event.target.matches("select,input[type=checkbox],input[type=range],input[type=color]")) finishField(); },
        onInputCapture: () => { editingField = true; }}, [
        h("div", {class: "inspector-content stack"}, contents),
        deletion ? h("footer", {class: "inspector-footer"}, deletion) : null,

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
        checkbox("Rejtett a főoldalon", !!sheet.hidden, value => updateItem(sheet, "hidden", value)),
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

    function deleteButton(node) {
      return button("Törlés", () => deleteNode(node), {class: "button danger", symbol: "trash", disabled: !!occupied(node.id)});
    }

    function renderSearch() {
      if (searchQuery.value === null) return null;
      const term = searchQuery.value.trim().toLocaleLowerCase("hu");
      const matches = term ? [
        ...board.value.nodes.filter(n => [n.title, n.text].some(t => t?.toLocaleLowerCase("hu").includes(term)))
          .map(n => ({id: n.id, kind: "node", title: n.title || "Csomópont", point: n.position})),
        ...board.value.edges.filter(e => e.label?.toLocaleLowerCase("hu").includes(term))
          .map(e => ({id: e.id, kind: "edge", title: e.label, point: edgeGeometry(e, drawnNode).labelPosition})),
      ] : [];
      return h("div", {class: "quick-search panel stack", role: "dialog", "aria-label": "Gyorskereső"}, [
        h("input", {ref: searchInput, type: "search", value: searchQuery.value, placeholder: "Keresés a munkalapon",
          "aria-label": "Keresés a munkalapon", onInput: e => { searchQuery.value = e.target.value; }}),
        ...matches.map(m => button(m.title, () => {
          searchQuery.value = null;
          const [cx, cy] = center();
          const k = view.value.k;
          d3.select(canvas.value).call(zoom.transform, d3.zoomIdentity.translate(cx-(cx+m.point.x)*k, cy-(cy+m.point.y)*k).scale(k));
          if (m.kind === "node") selectNode(m.id);
          else { selectNode(null, m.id); selected.value = {kind: "edge", id: m.id}; }
        })),
        term && !matches.length ? h("p", "Nincs találat.") : null,
      ]);
    }

    function renderInspector() {
      if (manuallyClosed.value) return null;
      if (batch.value) {
        const nodes = board.value.nodes.filter(n => batch.value.nodes.has(n.id));
        const joints = nodes.filter(n => n.kind === "connectionPoint").length;
        const edges = board.value.edges.filter(e => batch.value.edges.has(e.id)).length;
        return sidebar("Objektumok", [h("h2","Objektumok:"), h("p", (nodes.length-joints)+" doboz, "+edges+" vonal, "+joints+" csomópont")],
          button("Törlés",deleteBatch,{class: "button danger",symbol: "trash"}));
      }
      if (note.value) {
        const reading = note.value;
        const node = nodeMap.value.get(reading.id);
        if (!node) return null;
        return sidebar("Text", [
          button("Szerkesztés", () => openProperties("node", node.id), {symbol: "edit", disabled: !!occupied(node.id)}),
          h("h2", node.title),
          reading.loading ? h("p", "Betöltés…") : null,
          reading.error ? h("p", {class: "error"}, reading.error) : null,
          !reading.loading && !reading.error ? h("div", {class: "formatted-text", innerHTML: reading.html || "<p>Még nincs leírás.</p>"}) : null,
        ], deleteButton(node));
      }
      if (!inspector.value || inspector.value.kind === "worksheet") {
        const sheet = board.value;
        if (!editingPanel.value) return sidebar("Munkalap", [
          button("Szerkesztés", () => openProperties("worksheet"), {symbol: "edit"}),
          h("h2", sheet.title), h(FormattedText, {source: sheet.text}),
        ], role === "admin" ? button("Munkalap törlése", deleteBoard, {class: "button danger", symbol: "trash"}) : null);
        return sidebar("Munkalap", [
          button("Előnézet", () => { editingPanel.value = false; }, {symbol: "eye"}),
          field("Cím", input(sheet.title, value => updateItem(sheet, "title", value), {maxlength: 120})),
          field("Text", textarea(sheet.text ?? "", value => updateItem(sheet, "text", value))),
          colorPicker("Munkalap háttérszíne", sheet.background ?? paper, value => updateItem(sheet, "background", value), "worksheet/background"),
          colorPicker("Rácspontok színe", sheet.gridColor ?? "#ccd7eb", value => updateItem(sheet, "gridColor", value), "worksheet/grid"),
          checkbox("Pontrács megjelenítése", sheet.gridVisible !== false, v => {
            gridOverride.value = null;
            updateItem(sheet, "gridVisible", v);
          }),
          field("Rácsköz", numeric(sheet.gridSpacing ?? 20, value => updateItem(sheet, "gridSpacing", value), 6, 160)),
          ...(canManage.value ? worksheetAccess(sheet) : []),
          h("div", {class: "inspector-links"}, [
            button("SVG letöltése", exportSVG, {symbol: "download"}),
            link("Mentett JSON letöltése", "/export/json/" + path, "download"),
            link("Mentett Text letöltése", "/export/text/" + path, "download"),
          ]),
        ], role === "admin" ? button("Munkalap törlése", deleteBoard, {class: "button danger", symbol: "trash"}) : null);
      }
      if (inspector.value.kind === "edge") {
        const edge = board.value.edges.find(item => item.id === inspector.value.id);
        if (!edge) return null;
        const paint = edgePaint(edge);
        const style = edge.style === "dashed" || edge.style === "rope" ? edge.style : "solid";
        if (!editingPanel.value) return sidebar("Vonal", [
          button("Szerkesztés", () => openProperties("edge", edge.id), {symbol: "edit"}),
          h("h2", edge.label || "Vonal"),
          h("p", (nodeMap.value.get(edge.source)?.title || "Szabad kezdőpont") + " → " + (nodeMap.value.get(edge.target.node)?.title || "Szabad végpont")),
        ], button("Kapcsolat törlése", () => removeEdge(edge), {class: "button danger", symbol: "trash"}));
        return sidebar("Vonal szerkesztése", [
          button("Előnézet", () => { editingPanel.value = false; }, {symbol: "eye"}),
          field("Címke", input(edge.label || "", value => updateItem(edge, "label", value), {"data-object-label": "", maxlength: 120})),
          colorPicker("Vonal színe", paint.color, value => updateItem(edge, "color", value), edge.id + "/line"),
          field("Vastagság", numeric(paint.width, value => updateItem(edge, "width", value), 0.5, 24)),
          field("Vonaltípus", select(style, lineStyles, value => changeLineStyle(edge, value))),
          checkbox("Nyíl a vonal elején", paint.startArrow, value => updateItem(edge, "startArrow", value)),
          checkbox("Nyíl a vonal végén", paint.endArrow, value => updateItem(edge, "endArrow", value)),
          ...endpointActions(edge),
        ], button("Kapcsolat törlése", () => removeEdge(edge), {class: "button danger", symbol: "trash"}));
      }
      const node = nodeMap.value.get(inspector.value.id);
      if (!node || held.value !== node.id || occupied(node.id)) return null;
      const change = (key, value) => updateItem(node, key, value);
      const title = input(node.title, value => change("title", value), {"aria-label": "Címke", "data-object-label": "", maxlength: 120});
      const color = (label, key, fallback) => colorPicker(label, node[key] ?? fallback, v => change(key, v), node.id + "/" + key);
      if (node.kind === "connectionPoint") return sidebar("Csomópont", [
        button("Előnézet", () => showNote(node), {symbol: "eye"}),
        field("Átmérő", numeric(node.width, size => { node.height = size; change("width", size); }, 4, 128)),
        field("Címke", title), color("Szín", "fill"),
      ], deleteButton(node));
      const alignments = {left: "Balra", center: "Középre", right: "Jobbra"};
      function typography(section) {
        const isTitle = section === "title";
        const style = isTitle ? node : node[section] ?? {};
        const outside = isTitle && !!node.titleOutside;
        const sizeKey = isTitle ? "fontSize" : "size";
        const colorKey = isTitle ? "textColor" : "color";
        const update = (key, value) => isTitle ? change(key, value) : change(section, {...node[section], [key]: value});
        return [
          isTitle ? checkbox("Dobozon kívül", outside, value => {
            if (value && (style.verticalAlignment ?? "middle") === "middle" && (style.alignment ?? node.alignment) === "center") {
              update("verticalAlignment", "top");
            }
            change("titleOutside", value);
          }) : null,
          colorPicker("Szövegszín", style[colorKey] ?? node.textColor,
            v => update(colorKey, v), node.id + "/" + section + "/text"),
          h("div", {class: "fields-two"}, [
            field("Betűméret", numeric(style[sizeKey] ?? 13, v => update(sizeKey, Math.round(v)), 10, isTitle ? 1000 : 60, {step: 1})),
              field("Igazítás", select((style.verticalAlignment ?? "middle") + "-" + (style.alignment ?? node.alignment), {
                "top-left": "Bal felső", "top-center": "Felső közép", "top-right": "Jobb felső",
                "middle-left": "Bal oldal", ...(outside ? {} : {"middle-center": "Közép"}), "middle-right": "Jobb oldal",
                "bottom-left": "Bal alsó", "bottom-center": "Alsó közép", "bottom-right": "Jobb alsó",
              }, value => {
                const [verticalAlignment, alignment] = value.split("-");
                update("verticalAlignment", verticalAlignment);
                update("alignment", alignment);
              })),
          ]),
          h("div", {class: "font-switches"}, [["bold","Félkövér"],["italic","Dőlt"],["underline","Aláhúzott"]]
            .map(([key, label]) => checkbox(label, !!style[key], v => update(key, v)))),
        ];
      }
      const group = (label, children) => h("fieldset", {class: "property-group stack"}, [h("legend", label), ...children]);
      const locked = groupBlocked(node) || ancestors(node, nodeMap.value).some(n => n.locked);
      return sidebar("Ötlet szerkesztése", [
        button("Előnézet", () => showNote(node), {symbol: "eye"}),
        group("Cím", [title, ...typography("title")]),
        group("Doboz", [
          select(node.shape, shapes, value => change("shape", value), {"aria-label": "Forma"}),
          h("div", {class: "fields-two"}, [color("Háttér", "fill"), color("Keret", "border")]),
          button(node.kind === "container" ? "Konténer feloldása" : "Konténer", () => toggleContainer(node), {symbol: "folder", disabled: locked}),
          node.kind === "container" ? checkbox("Lock · tartalom rögzítése", !!node.locked, v => change("locked", v)) : null,
        ]),
        group("Text", [
          textarea(node.text, value => change("text", value)),
          checkbox("Hide text", Boolean(node.hideText), value => change("hideText", value)),
          ...typography("textStyle"),
          h("div", {class: "fields-two"}, [color("Text háttér", "textFill", node.fill),
            color("Text keret", "textBorder", node.border)]),
        ]),
        group("Link", [
          h("input", {"aria-label": "Link",
            value: node.link ?? "", maxlength: 2048, placeholder: "allap, ../ vagy https://…",
            onChange: event => {
              const link = event.target.value.trim();
              if (link && !worksheetLink(link, path)) {
                problem.value = "Érvénytelen hivatkozás.";
                event.target.value = node.link ?? "";
                return;
              }
              change("link", link);
            },
          }),
        ]),
      ], deleteButton(node));
    }

    const toolbar = document.getElementById?.("editor-tools");
    watch(() => board.value?.title, title => {
      const current = toolbar?.closest("header")?.querySelector("[aria-current=page]");
      if (current && title) current.textContent = title;
    });

    function renderHeader() {
      const changed = online.value && (dirty.value || (board.value.revision > checkpointState.value.revision
        ? board.value.revision !== checkpointRevision : checkpointState.value.changed));
      const historyButton = (label, symbol, forward, available) =>
        button(label, () => replay(forward), {
          symbol, disabled: !available || !online.value || !!gesture.value,
          class: available && online.value && gesture.value ? "button gesture-disabled" : "button",
        });
      const controls = [
          historyButton("Visszavonás", "undo", false, undo.value.length || fieldChanged),
          historyButton("Újra", "redo", true, redo.value.length),
          button(h("span", {class: changed ? "save-label-changed" : undefined}, "Mentés"), () => sessionAction("checkpoint"), {symbol: "save",
            title: "Közös visszaállítási pont rögzítése", disabled: checkpointBusy.value || !online.value}),
          button("Resign", () => sessionAction("resign"), {symbol: "undo", title: "A közös visszaállítási pont betöltése",
            disabled: checkpointBusy.value || !online.value}),
      ];
      return toolbar ? h(window.Vue.Teleport, {to: toolbar}, controls) : h("div", controls);
    }

    return () => {
      if (!board.value) return h("p", {class: problem.value ? "error editor-loading" : "editor-loading"}, problem.value || "Szerkesztő betöltése…");
      const currentStatus = reconnect.value ? "Kattints az új célra vagy a vászonra. Esc a megszakításhoz."
        : "";
      return [
        renderHeader(),
        h("div", {class: "editor-workspace"}, [
          renderCanvas(),
          problem.value || currentStatus ? h("p", {class: ["canvas-status", {error: problem.value}], role: "status"}, problem.value || currentStatus) : null,
          renderInspector(),
          renderSearch(),
          button("", () => {
            if (!manuallyClosed.value) { manuallyClosed.value = true; inspectNothing(); }
            else openSidebar();
          }, {class: ["button", "sidebar-open", {active: selected.value && manuallyClosed.value}],
            "aria-expanded": !manuallyClosed.value,
            "aria-label": !manuallyClosed.value ? "Oldalsáv bezárása" : "Oldalsáv megnyitása",
            symbol: !manuallyClosed.value ? "right" : "left"}),
        ]),
        renderMenu(),
      ];
    };
  },
}).mount(mount);
