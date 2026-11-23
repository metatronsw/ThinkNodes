import {openPresentation, setWebPublic, webPresentationURL} from "./web-presentations.js";
import {fetchPage, updateSection, watchPageUpdates} from "./page-updates.js";
import {bindAudioPlayers} from "./audio-player.js";
import {assetURL, attachmentURL, checkText, fileSheet, fileURL, isCommonFile, plainFirstLine, sharedFileBox, fileName, fileNameParts, importFile, nodeName, objectURL, pngForClipboard, validImageStem, writeText} from "./canvas-files.js";
import {hasTrait, rootType, traits, typeLabel} from "./node-types.js";
import {chooseRemoval, openFileBrowser} from "./file-browser.js";
import {decodeWorksheet, encodeWorksheet} from "./worksheet-json.js";
import {sharedMouse} from "./mouse.js";
import {worksheetChanges, replayChanges, sameValue} from "./editor-history.js?v=2";
import {flashNode, flashPoint} from "./ping.js";
import {showTooltip, hideTooltip} from "./tooltip.js";
import {justifyRows} from "./justify.js";
import {canvasMarkdown, canvasMarkdownAvailable} from "./canvas-markdown.js";
import {liveConnection, rebaseWorksheet} from "./collaboration.js";
import {worksheetLink, linkIcons, openExternalLink} from "./links.js";
import {useWorksheetGeometry, commentCollapsed, visibleComment, automaticBorder, automaticGridColor, canvasBounds, defaultGridSpacing, edgeEndpoint, edgeGeometry, edgeInRectangle, edgePaint, labelLayout, limit, linkCaption, fitCaption, textWidth, lineAppearances, lineTypes, maximumLineWidth, polygonVertices, selectionOutline, shapeDistance, shapeGeometry, shapeLabelRatios, shapeOutline, shapes, taperedArc, wireArrow, wireGradientValues, wireLabelLayout} from "./geometry.js?v=22";

import {ancestors, overlapFraction} from "./containers.js?v=3";

const mount = document.querySelector("#editor");
const {path, csrf, user, motionRate} = mount.dataset;
const d3 = window.d3;
const {createApp, computed, getCurrentInstance, h, nextTick, onMounted, onUnmounted, onUpdated, ref, shallowRef, toRaw, watch} = window.Vue;

// Az új munkalapállapotban a tartalmilag változatlan dobozok és vonalak a korábbi objektumot kapják vissza.
// Az elrendezés- és vonalgeometria-gyorsítótárak objektumazonosság szerint működnek; enélkül minden mentés
// és távoli frissítés után a teljes vászon újra tördelődne és újrarajzolódna.
function keepUnchanged(previous, next) {
  if (!previous) return next;
  for (const group of ["nodes", "edges"]) {
    const old = new Map((previous[group] ?? []).map(item => [item.id, item]));
    next[group] = next[group].map(item => {
      const before = old.get(item.id);
      return before && sameValue(toRaw(before), item) ? before : item;
    });
  }
  return next;
}
const endpoint = "/api/worksheet/" + path;

function icon(name) {
  return h("svg", {class: "ui-icon", "aria-hidden": "true", viewBox: "0 0 24 24"}, [
    h("use", {href: "/icons.svg#" + name}),
  ]);
}

function button(label, onClick, props = {}) {
  const {symbol = "file", ...attributes} = props;
  return h("button", {type: "button", class: "button", onClick, ...attributes}, [icon(symbol), label]);
}

const headerButtonClass = "button header-button";
function headerButton(onClick, {class: modifiers, ...props}) {
  return button("", onClick, {...props, class: [headerButtonClass, modifiers]});
}

const themes = JSON.parse(mount.dataset.themes || "[]");
const currentBoard = ref(null);
const appearance = computed(() => currentBoard.value?.appearance ?? {theme: 1, palette: 1});
const activeTheme = computed(() => themes.find(t => t.id === appearance.value.theme) ?? themes[0]);
const activePalette = computed(() => activeTheme.value?.palettes.find(p => p.id === appearance.value.palette) ?? activeTheme.value?.palettes[0]);
const siteDisplay = ref(document.documentElement?.dataset?.display || "light");
window.addEventListener("thinknodes-display", () => { siteDisplay.value = document.documentElement.dataset.display; });
const mode = computed(() => {
  const wanted = siteDisplay.value;
  return activeTheme.value?.modes.includes(wanted) ? wanted : activeTheme.value?.modes[0] ?? "light";
});
const graphics = computed(() => activeTheme.value?.graphics ?? {});
// A téma három betűtípusa (Theme.swift fontFamily): 1 = alap, 2 és 3 jól eltérő.
const defaultFonts = ["system-ui, sans-serif", "Georgia, 'Times New Roman', serif", "'Chalkboard SE', 'Comic Sans MS', cursive"];
function fontFamily(index) {
  const list = graphics.value.fonts ?? defaultFonts;
  return list[Math.min(Math.max((index ?? 1) - 1, 0), list.length - 1)];
}
useWorksheetGeometry(() => graphics.value);
const fallbackColors = ["#f5f8fc","#182335","#dce9ff","#526982","#304ccc","#478666","#f3ae49","#e95c59"];
function paint(value, role) {
  if (typeof value === "string") return value;
  const colors = activePalette.value?.colors ?? [];
  const color = colors.find(c => c.id === value) ?? colors.find(c => c.id === role);
  return color?.[mode.value] ?? color?.light ?? color?.dark ?? fallbackColors[role];
}

const ColorPicker = {
  props: {label: String, color: [String, Number], role: Number, disabled: Boolean, compact: Boolean, transparent: Boolean, clear: Function},
  emits: ["update"],
  setup(props, {emit}) {
    const expanded = ref(false);
    const tile = value => h("span", {class: "palette-tile", style: {backgroundColor: paint(value, props.role)}});
    return () => h("div", {class: ["color-field", {"compact-color": props.compact}]}, [
      props.compact ? null : h("span", props.label),
      h("button", {type: "button", class: "color-sample", "aria-label": props.label + " színválasztó",
        disabled: props.disabled, "aria-expanded": expanded.value,
        onClick: () => { expanded.value = !expanded.value; }}, [
          props.transparent ? h("span", {class: "palette-tile transparent-swatch"}) : tile(props.color),
        ]),
      expanded.value && !props.disabled ? h("div", {class: "color-tools color-presets"}, [
        h("button", {type: "button", ...controlName(props.clear ? "Háttér törlése" : "Alapértelmezett szín"),
          onClick: () => props.clear ? props.clear() : emit("update", props.role)}, [icon("clear-color")]),
        ...(activePalette.value?.colors ?? []).map(c => h("button", {type: "button", key: c.id, title: c.name,
          "aria-label": c.name, "aria-pressed": !props.transparent && c.id === props.color,
          onClick: () => { emit("update", c.id); }}, [tile(c.id)])),
      ]) : null,
    ]);
  },
};

function colorPicker(label, value, change, key, disabled = false, compact = false, role = 2, options = {}) {
  return h(ColorPicker, {key, label, role, color: value, disabled, compact, onUpdate: change, ...options});
}

function controlName(label) {
  return {title: label, "aria-label": label};
}

function iconToggle(title, pressed, onClick, symbol, disabled = false) {
  return h("button", {type: "button", class: "button option-icon", ...controlName(title),
    "aria-pressed": pressed, onClick, disabled}, [symbol]);
}

function optionPicker(label, choices, current, change, preview) {
  return h("div", {class: "property-options", role: "group", "aria-label": label},
    Object.entries(choices).map(([value, title]) =>
      iconToggle(title, current === value, () => change(value), preview(value))));
}

function optionSymbol(tag, attributes, viewBox = "0 0 24 24") {
  return h("svg", {class: "ui-icon", viewBox, "aria-hidden": "true"}, [
    h(tag, {fill: "none", stroke: "currentColor", "stroke-width": 1.65, "stroke-linejoin": "round", ...attributes}),
  ]);
}

function shapeSymbol(value) {
  const [tag, geometry] = shapeGeometry(value, 18, 16);
  if (value === "rounded" && tag === "rect") geometry.rx = 4;
  return optionSymbol(tag, geometry, "-12 -12 24 24");
}

function lineTypeSymbol(type) {
  if (type === "zigzag") return optionSymbol("path", {d: "M3 12H10L14 8L10 16L14 12H21", "stroke-linecap": "round"});
  if (type === "lightning") return optionSymbol("path", {d: "M2 12L5 8L8 16L11 8L14 16L17 8L20 16L23 12"});
  const target = {point: {x: 21, y: type === "sCurve" ? 18 : 12}};
  const sourcePoint = {x: 3, y: type === "sCurve" ? 6 : 12};
  const {d} = edgeGeometry({type, sourcePoint, target}, () => undefined);
  return optionSymbol("path", {d, "stroke-linecap": "round"});
}

function lineAppearanceSymbol(appearance) {
  const paint = edgePaint({appearance, width: 1.5});
  return optionSymbol("path", {d: "M3 12H21", "stroke-width": paint.lineWidth,
    "stroke-linecap": paint.linecap, "stroke-dasharray": appearance === "dotted" ? "0 4.5" : paint.dash});
}

function field(label, control) {
  return h("label", [h("span", label), control]);
}

function input(value, change, props = {}) {
  return h("input", {value, onInput: event => change(event.target.value), ...props});
}

function numeric(value, change, min, max, {clampValue = false, ...props} = {}) {
  return h("input", {
    value,
    onInput: ({target}) => {
      if (target.value === "") return;
      const parsed = Number(target.value);
      const bounded = clampValue ? limit(parsed, min, max) : parsed;
      if (!(bounded >= min && bounded <= max)) return;
      if (bounded !== parsed) target.value = String(bounded);
      change(bounded);
    },
    type: "number", min, max, step: "any",
    onBlur: event => { event.target.value = value; },
    ...props,
  });
}

function propertyTools(...controls) {
  return h("div", {class: "property-options property-tools"}, controls);
}


// Egyszerű CSV/TSV feldolgozás a táblázatnézethez (Rendering.swift parseCSV).
function parseCSV(source, separator = ",") {
  const rows = [];
  let row = [], field = "", quoted = false;
  for (let i = 0; i < source.length && rows.length < 200; i++) {
    const c = source[i];
    if (quoted) {
      if (c === '"') { if (source[i + 1] === '"') { field += '"'; i++; } else quoted = false; }
      else field += c;
    } else if (c === '"' && !field) quoted = true;
    else if (c === separator) { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && source[i + 1] === "\n") i++;
      row.push(field); field = ""; rows.push(row.slice(0, 30)); row = [];
    } else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row.slice(0, 30)); }
  return rows.filter(r => !(r.length === 1 && r[0] === ""));
}

const FormattedText = {
  props: {source: String, justified: Boolean},
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
    return () => error.value ? h("p", {class: "error"}, error.value) : h("div", {class: ["formatted-text", {"justified-text": props.justified}], innerHTML: html.value});
  },
};

const boxAnimations = {
  none: "Nincs animáció", pulse: "Pulzálás", blink: "Villogás", rock: "Ringatózás", hop: "Ugrálás",
};

const boxMotion = {
  pulse: {dur: "2.8s", times: "0;.5;1", scale: "1;1.09;1"},
  blink: {dur: "2.4s", times: "0;.5;1", opacity: "1;.28;1"},
  rock: {dur: "4.8s", times: "0;.08;.19;.3;.4;.49;1", rotate: "0;8;-6;3;-1;0;0"},
  hop: {dur: "5.8s", times: "0;.06;.15;.24;.32;.4;1",
    translate: "0 0;0 1;0 -17;0 0;0 -4;0 0;0 0", scale: "1 1;1.03 .95;1.035 1.06;1.045 .96;.99 1.02;1 1;1 1"},
};

// Egységes vászon-osztálynév: `node is-<típus>` (+ `has-children` konténernél). A Rendering.swift `nodeClasses` ugyanezt adja.
function nodeClasses(node, hasChildren = false) {
  const root = rootType(node.type);
  let classes = "node is-" + node.type;
  if (root !== node.type) classes += " is-" + root;
  if (node.link) classes += " has-link";
  if (hasChildren) classes += " has-children";
  return classes;
}
const isJunction = node => node?.type === "junction";
// Doboz: a sima doboz és az előnézetes link-doboz (`preview`, Model.swift normalizePreview).
const isBox = node => node?.type === "box" || node?.type === "preview";
// Linkes doboz mindig `preview` (téglalap, 5 px lekerekítés, animáció nélkül); link nélkül sima `box`.
function normalizePreview(node) {
  if (node.type === "box" && node.link) node.type = "preview";
  if (node.type === "preview" && !node.link) node.type = "box";
  if (node.type === "preview") { node.shape = "rectangle"; delete node.animation; }
  return node;
}
// A doboz alakja: az előnézetes doboz mindig 5 px-es lekerekítésű téglalap.
function boxShapeGeometry(node, width = node.width, height = node.height) {
  return node.type === "preview" ? ["rect", {x: -width/2, y: -height/2, width, height, rx: 5}] : shapeGeometry(node.shape, width, height);
}
const isImage = node => rootType(node?.type) === "image";
const isTextFile = node => rootType(node?.type) === "text";

function animateBox(mode, contents) {
  const motion = Object.hasOwn(boxMotion, mode) ? boxMotion[mode] : null;
  if (!motion) return contents;
  const {dur, times, ...tracks} = motion;
  const timing = {dur: parseFloat(dur) / (graphics.value.motionSpeed ?? 1) + "s", repeatCount: "indefinite", calcMode: "spline", keyTimes: times,
    keySplines: times.split(";").slice(1).map(() => ".33 0 .67 1").join(";")};
  const animations = Object.entries(tracks).map(([type, values]) => type === "opacity"
    ? h("animate", {...timing, attributeName: "opacity", values})
    : h("animateTransform", {...timing, attributeName: "transform", type, additive: "sum", values}));
  return [h("g", {class: "node-motion", "data-box-animation": mode}, [...animations, ...contents])];
}

function backgroundMode(node) {
  return node.backgroundMode ?? "solid";
}

function elevationShadow(node) {
  // Képnél a láthatósági mód nem számít: a Kiemelés árnyéka mindig a teljes kép alatt van.
  if (!node.elevated || (!isImage(node) && backgroundMode(node) === "free")) return null;
  const [tag, geometry] = shapeGeometry(node.shape, node.width, node.height);
  // Üres dobozon csak a keret vet árnyékot; a kitöltött doboz árnyéka a doboz alatt marad (nincs clipPath: gyorsabb mozgatás).
  if (!isImage(node) && backgroundMode(node) === "empty") {
    return h("g", {class: "node-shadow", "pointer-events": "none", "aria-hidden": "true"},
      [h(tag, {...geometry, transform: "translate(12 28)", fill: "none", stroke: "#11172b", "stroke-opacity": .44, "stroke-width": 1.6})]);
  }
  return h("g", {class: "node-shadow", "pointer-events": "none", "aria-hidden": "true"},
    [h(tag, {...geometry, transform: "translate(12 28)", fill: "#11172b", "fill-opacity": .44})]);
}

function shape(node, linked, dropTarget = false) {
  if (isJunction(node)) {
    const [tag, attrs] = shapeGeometry(graphics.value.junction ?? "ellipse", node.width, node.height);
    return h(tag, {...attrs, class: "junction-surface", fill: paint(node.fill, 2)});
  }
  const [tag, geometry] = boxShapeGeometry(node);
  const image = isImage(node) ? node.file : null;
  const mode = backgroundMode(node);
  const blurred = mode === "blurred", empty = mode === "empty";
  const free = mode === "free" || !!image;  // a kép mindig háttér nélkül, a saját átlátszóságával jelenik meg
  if (dropTarget) return h(tag, {...geometry, class: "drop-target", "data-container-candidate": "",
    fill: empty || free ? "none" : paint(node.fill, 2), "pointer-events": "fill",
    stroke: "#08796c", "stroke-width": 5, "stroke-dasharray": "0 8", "stroke-linecap": "round",
    "vector-effect": "non-scaling-stroke"});
  if (free) return h(tag, {...geometry, "data-editor-only": "", fill: "none", stroke: "none", "pointer-events": "fill"});
  const locked = isBox(node) && node.locked;
  const glass = graphics.value.glass && mode === "solid" && !image;
  const fill = paint(node.fill, 2);
  // Üres doboz: csak a keret látszik, a keret színe a doboz színe. Elmosottnál a háttér elmosódik, a keret nem.
  const frame = empty ? paint(node.fill, 2) : image && !empty ? "none" : glass ? "url(#glass-rim)" : automaticBorder(fill);
  const translucent = mode === "translucent";
  const style = {fill: empty ? "none" : fill, stroke: frame, "fill-opacity": translucent ? .75 : undefined,
    "pointer-events": empty ? "fill" : undefined, class: "node-surface",
    "stroke-width": locked ? 6.4 : glass ? 3 : 1.6,
    "data-locked-outline": locked ? "" : undefined, "stroke-dasharray": linked && isBox(node) ? "7 4" : undefined,
    opacity: blurred ? .98 : undefined, filter: blurred ? "url(#box-background-blur)" : undefined};
  if (blurred) return [
    h(tag, {...geometry, fill, opacity: .98, filter: "url(#box-background-blur)", stroke: "none", class: "node-surface"}),
    h(tag, {...geometry, fill: "none", stroke: frame, "stroke-width": 1.6, class: "node-frame", "pointer-events": "none"}),
  ];
  if (glass) return [
    h(tag, {...style, ...geometry, "fill-opacity": .66}),
    h(tag, {...geometry, fill: "url(#glass-sheen)", "pointer-events": "none", "aria-hidden": "true"}),
  ];
  return h(tag, {...style, ...geometry});
}

// The stored endpoints are the tips. Stop the shaft at each triangle's base.
function resolveWireColor(edge) { return paint(edge.color, 3); }

function wireDrawing(edge, geometry) {
  const {from, to, sourceToward, targetToward, bent, path} = geometry;
  const paint = edgePaint({...edge, color: resolveWireColor(edge)});
  const taper = taperedArc(geometry, paint);
  if (taper) {
    return {ends: taper.ends, stroke: {d: taper.outline(), fill: paint.color, stroke: "none"}, paint, taper};
  }
  const limit = bent || !(paint.startArrow && paint.endArrow) ? Infinity : Math.hypot(to.x - from.x, to.y - from.y) / 2;
  const ends = {source: wireArrow(from, sourceToward, paint.width, paint.startArrow, limit),
    target: wireArrow(to, targetToward, paint.width, paint.endArrow, limit)};
  const stroke = {d: path(ends.source.base, ends.target.base), fill: "none", stroke: paint.color,
    "stroke-width": paint.lineWidth, "stroke-linecap": paint.linecap, "stroke-dasharray": paint.dash};
  return {ends, stroke, paint};
}

function animatedWire(edge, paint, from, to, taper, shaftPath) {
  if (!edge.animated) return {};
  const loop = {repeatCount: "indefinite"};
  if (edge.appearance === "thick") {
    const pulse = Math.min(maximumLineWidth, paint.lineWidth * 1.45);
    const values = taper ? [shaftPath, taper.outline(pulse / paint.lineWidth), shaftPath] : [paint.lineWidth, pulse, paint.lineWidth];
    return {shaft: h("animate", {...loop, attributeName: taper ? "d" : "stroke-width", values: values.join(";"), dur: "3s"})};
  }
  const reverse = paint.startArrow && !paint.endArrow;
  const roundTrip = paint.startArrow && paint.endArrow;
  if (paint.dash) {
    const shift = paint.width * (edge.appearance === "dotted" ? 8 : 6) * (reverse ? 1 : -1);
    return {shaft: h("animate", {...loop, attributeName: "stroke-dashoffset",
      values: roundTrip ? "0;" + shift + ";0" : "0;" + shift, dur: roundTrip ? "3.2s" : "1.6s"})};
  }
  const dx = to.x - from.x, dy = to.y - from.y;
  if (dx === 0 && dy === 0) return {};
  const id = "editor-wire-gradient-" + edge.id;
  const values = wireGradientValues(from, to, paint);
  const gradient = h("linearGradient", {id, gradientUnits: "userSpaceOnUse",
    x1: from.x, y1: from.y, x2: to.x, y2: to.y}, [
    ...[0, .25, .5, .75, 1].map(offset => h("stop", {offset,
      "stop-color": paint.color, "stop-opacity": offset === .5 ? .5 : 1})),
    h("animateTransform", {...loop, attributeName: "gradientTransform", type: "translate",
      values, dur: roundTrip ? "12s" : "6s"}),
  ]);
  return {gradient, color: "url(#" + id + ")"};
}

function setEndpoint(edge, end, endpoint) {
  if (end === "source") {
    edge.source = endpoint.node;
    edge.sourcePoint = endpoint.point;
  } else {
    edge.target = endpoint.node ? {node: endpoint.node} : {point: endpoint.point};
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
    const board = currentBoard;
    const insertion = ref(null);
    const shift = ref(false);
    const insertionEdges = computed(() => {
      const draft = insertion.value;
      if (!draft) return [];
      return draft.cloneLink && shift.value ? [...draft.edges, draft.cloneLink] : draft.edges;
    });
    const sceneNodes = computed(() => {
      const nodes = board.value?.nodes ?? [];
      return insertion.value ? nodes.concat(insertion.value.nodes) : nodes;
    });
    const sceneEdges = computed(() => {
      const edges = board.value?.edges ?? [];
      const draft = insertion.value;
      return draft ? edges.filter(e => e.id !== draft.original?.id).concat(insertionEdges.value) : edges;
    });
    const elevatedNodes = computed(() => {
      const elevated = new Set(sceneNodes.value.filter(node => node.elevated === true).map(node => node.id));
      if (!elevated.size) return elevated;
      const children = new Map();
      for (const {id, parent} of sceneNodes.value) {
        if (!parent) continue;
        if (!children.has(parent)) children.set(parent, []);
        children.get(parent).push(id);
      }
      for (const id of elevated) for (const child of children.get(id) ?? []) elevated.add(child);
      return elevated;
    });
    const containerIDs = computed(() => new Set(sceneNodes.value.filter(node => isBox(node) && node.container).map(node => node.id)));
    const orderedNodes = computed(() => [...sceneNodes.value].sort((a,b) =>
      Number(elevatedNodes.value.has(a.id))-Number(elevatedNodes.value.has(b.id)) ||
      Number(containerIDs.value.has(b.id))-Number(containerIDs.value.has(a.id)) || b.width*b.height-a.width*a.height));
    const wireLayers = computed(() => {
      const nodes = orderedNodes.value;
      const order = new Map(nodes.map((node, index) => [node.id, index]));
      const firstElevated = nodes.findIndex(node => elevatedNodes.value.has(node.id));
      const layers = Array.from({length: nodes.length + 1}, () => []);
      for (const edge of sceneEdges.value) {
        const source = order.get(edge.source) ?? nodes.length;
        const target = order.get(edge.target.node) ?? nodes.length;
        const nested = nestingDirection(nodeMap.value.get(edge.source), nodeMap.value.get(edge.target.node));
        const index = nested ? Math.max(source, target) : Math.min(source, target);
        layers[index === nodes.length && firstElevated >= 0 ? firstElevated : index].push(edge);
      }
      return layers;
    });
    const nodeMap = computed(() => new Map(sceneNodes.value.map(node => [node.id, node])));
    const edgeMap = computed(() => new Map(board.value?.edges.map(edge => [edge.id, edge])));
    const containerReceivers = computed(() => (board.value?.nodes ?? [])
      .filter(isBox)
      .sort((a, b) => a.width * a.height - b.width * b.height));
    const ctrl = ref(false);
    const alt = ref(false);
    const canvasText = shallowRef(new Map());
    const textSources = computed(() => [...new Set(
      board.value?.nodes.filter(node => isBox(node) && node.text).map(node => node.text)
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
    const nodeLayouts = new WeakMap();
    const emptyBlocks = [];
    // Gépelés közben az új szöveg feldolgozásáig az objektum utolsó ismert szövege marad látható
    // (azonosító szerint, így akkor sem villan üresre, ha a csomópont objektuma kicserélődik).
    const lastBlocksById = new Map();
    function nodeLayout(node) {
      let layout = nodeLayouts.get(node);
      if (!layout) {
        const text = computed(() => {
          if (!node.text) { lastBlocksById.delete(node.id); return emptyBlocks; }
          const blocks = canvasText.value.get(node.text) ?? lastBlocksById.get(node.id) ?? emptyBlocks;
          lastBlocksById.set(node.id, blocks);
          return blocks;
        });
        layout = computed(() => labelLayout(node, text.value));
        nodeLayouts.set(node, layout);
      }
      return layout.value;
    }
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
      const node = nodeMap.value.get(id);
      return node && (motions.value.size || gesture.value?.type === "batch") ? {...node, position: displayPosition(node)} : node;
    }
    const edgeGeometries = new WeakMap();
    const wireDrawings = new WeakMap();
    function nestingDirection(source, target) {
      if (!source || !target) return 0;
      if (ancestors(target, nodeMap.value).some(node => node.id === source.id)) return 1;
      return ancestors(source, nodeMap.value).some(node => node.id === target.id) ? -1 : 0;
    }

    function wireGeometry(edge) {
      const source = drawnNode(edge.source), target = drawnNode(edge.target.node);
      const start = source?.position ?? edge.sourcePoint, end = target?.position ?? edge.target.point;
      const nested = nestingDirection(source, target);
      const inputs = [graphics.value, edge.type, nested,
        start.x, start.y, source?.width, source?.height, source?.shape, source?.type,
        end.x, end.y, target?.width, target?.height, target?.shape, target?.type];
      const cached = edgeGeometries.get(edge);
      if (cached && inputs.every((value, i) => value === cached.inputs[i])) return cached.geometry;
      const geometry = edgeGeometry(edge, id => id === edge.source ? source : target, nested);
      edgeGeometries.set(edge, {inputs, geometry});
      return geometry;
    }

    function cachedWireDrawing(edge, geometry) {
      const inputs = [edge.appearance, resolveWireColor(edge), edge.width, edge.startArrow, edge.endArrow];
      const cached = wireDrawings.get(edge);
      if (cached?.geometry === geometry && inputs.every((value, i) => value === cached.inputs[i])) return cached.drawing;
      const drawing = wireDrawing(edge, geometry);
      wireDrawings.set(edge, {geometry, inputs, drawing});
      return drawing;
    }

    const drawnBounds = () => canvasBounds({
      nodes: sceneNodes.value.map(node => {
        const {extentX, extentY} = nodeLayout(node);
        return {...node, extentX, extentY};
      }), edges: board.value.edges,
    });
    const preferences = JSON.parse(mount.dataset.preferences || "{}");
    const gridVisible = ref(preferences.showGrid ?? true);
    const snapToGrid = ref(preferences.snap ?? false);
    const panLocked = ref(preferences.panLocked ?? false);
    const spacePan = ref(false);
    const previewImages = ref([]);
    async function loadPreviewImages() {
      try {
        previewImages.value = await (await checked(await fetch("/api/preview-images/" + path))).json();
      } catch (error) { problem.value = error.message; }
    }
    let preferenceWrite = Promise.resolve();
    function savePreferences() {
      if (!user) return;
      const body = JSON.stringify({theme: preferences.theme, showGrid: gridVisible.value, snap: snapToGrid.value,
        panLocked: panLocked.value});
      preferenceWrite = preferenceWrite.then(async () => checked(await fetch("/api/preferences", {
        method: "POST", keepalive: true, headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body
      }))).catch(error => { problem.value = error.message; });
    }
    function toggleGrid() { gridVisible.value = !gridVisible.value; savePreferences(); }
    const gridSpacing = computed(() => board.value?.gridSpacing ?? defaultGridSpacing);
    const gridColor = computed(() => automaticGridColor(paint(board.value?.background, 0)));

    const selected = ref(null);
    const batch = ref(null);
    const searchQuery = ref(null);
    const searchInput = ref(null);
    const searchHistoryKey = "thinknodes/search-history/" + user;
    const searchHistoryLimit = 10;
    let searchHistory = [];
    const searchHistoryIndex = ref(-1);
    try {
      const saved = JSON.parse(window.localStorage?.getItem(searchHistoryKey) ?? "[]");
      if (Array.isArray(saved)) searchHistory = saved.filter(term => typeof term === "string" && term.trim()).slice(0, searchHistoryLimit);
    } catch { /* History is still available in this tab. */ }
    const toolbarOpen = ref(true);
    const editingObject = ref(null);
    const objectPanelOpen = ref(true);
    const canvasPanelOpen = ref(false);
    const reconnect = ref(null);
    const menu = ref(null);
    const inspector = ref(null);
    const attachmentInput = ref(null);
    let uploadAnchor;
    const uploading = ref(false);
    const canvas = ref(null);
    const canvasPointer = ref(null);
    const view = shallowRef(d3.zoomIdentity);
    const zoomScale = computed(() => view.value.k);
    // A nagyítás 25%-os lépcsőkre kerekítve: a fogantyúk mérete és a vonalak találati szélessége csak lépcsőváltáskor
    // változik, így a legtöbb nagyítási lépés nem rajzol újra vonalat és fogantyút (PLAN.md C2).
    const zoomStep = computed(() => Math.pow(1.25, Math.round(Math.log(view.value.k) / Math.log(1.25))));
    const panning = ref(false);
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
    let canDeselectOnClick = false;
    let rightPress = false;

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
      board.value = keepUnchanged(board.value, rebaseWorksheet(baseline, copy(board.value), latest));
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

    // Mentés ütemezése. Mezőszerkesztés (gépelés) közben a mentés a szünetre vár (0,5 mp), de legfeljebb 2 mp-et,
    // így nem megy ki minden leütés után a teljes munkalap; egyébként (húzás, gomb) 70 ms után ment. PLAN.md C5.
    let saveDue = null;
    function fireSave() { saveTimer = null; saveDue = null; save(); }
    function scheduleSave() {
      if (!editingField) {
        if (saveTimer && saveDue === null) return;
        clearTimeout(saveTimer);
        saveDue = null;
        saveTimer = setTimeout(fireSave, 70);
        return;
      }
      const now = performance.now();
      saveDue ??= now + 2000;
      clearTimeout(saveTimer);
      saveTimer = setTimeout(fireSave, Math.max(0, Math.min(500, saveDue - now)));
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
      if (item) inspector.value = {kind: item.kind === "node" ? "node" : "edge", id: item.id};
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
      // A markdown-feldolgozás helyben, szinkron fut (commonmark.js, Public/canvas-markdown.js): a szöveg még ugyanabban
      // a képkockában megjelenik, kérés nélkül. Ha a commonmark.js nem töltődött be, a szerver dolgozza fel (régi út).
      if (canvasMarkdownAvailable()) {
        const current = new Set(sources);
        const updated = new Map([...canvasText.value].filter(([source]) => current.has(source)));
        for (const source of sources) if (!updated.has(source)) updated.set(source, canvasMarkdown(source));
        canvasText.value = updated;
        return;
      }
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
      // A mező elhagyásakor a gépelés miatt késleltetett mentés azonnal (70 ms) indul.
      if (saveDue !== null && dirty.value) scheduleSave();
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
      const retained = new Set(next.nodes.flatMap(node => node.file ? [node.file.asset] : []));
      const removedFiles = board.value.nodes.filter(node => node.file && !retained.has(node.file.asset));
      if (!confirmFileRemoval(removedFiles)) return;
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

    // A vászonréteg a látható területnél nagyobb (overscan); a jelenet origója a látható terület bal felső sarka.
    // A pontokat ehhez a csoporthoz mérjük, így az eltolás és a mozdulat közbeni CSS-transzform is benne van.
    // Puffer a látható terület körül, a látható méret arányában, oldalanként (CSS: --overscan).
    const overscan = 1;
    const sceneOrigin = ref(null);
    const margin = () => [size.value.width * overscan, size.value.height * overscan];

    function world(event) {
      const [px, py] = d3.pointer(event, sceneOrigin.value ?? canvas.value);
      const [x, y] = view.value.invert([px, py]);
      const [centerX, centerY] = center();
      return {x: x - centerX, y: y - centerY};
    }

    const resizeTarget = computed(() => {
      if (spacePan.value || !alt.value || ctrl.value) return;
      if (gesture.value?.type === "resize") return gesture.value.nodeID;
      if (!canvasPointer.value || !canvas.value) return;
      const point = world(canvasPointer.value);
      const padding = 16 / view.value.k;
      return orderedNodes.value.findLast(node => {
        if (isJunction(node)) return false;
        const drawn = drawnNode(node.id);
        return Math.abs(point.x - drawn.position.x) <= drawn.width / 2 + padding
          && Math.abs(point.y - drawn.position.y) <= drawn.height / 2 + padding;
      })?.id;
    });

    function rememberCanvasPointer({clientX, clientY}) {
      canvasPointer.value = {clientX, clientY};
    }

    function pastePosition() {
      if (canvasPointer.value) {
        const hit = document.elementFromPoint?.(canvasPointer.value.clientX, canvasPointer.value.clientY);
        if (!document.elementFromPoint || hit && canvas.value?.contains(hit)) return world(canvasPointer.value);
      }
      return worldAtCenter();
    }

    function clampPoint(point) {
      return {x: limit(point.x, -100000, 100000), y: limit(point.y, -100000, 100000)};
    }

    function measure() {
      // A látható terület a vászon szülője (a vászonréteg maga nagyobb, lásd overscan).
      const area = canvas.value?.parentElement ?? canvas.value;
      if (area) size.value = {width: area.clientWidth, height: area.clientHeight};
    }

    const pinchTolerance = 6; // CSS pixels between the two touch points
    let touchView;
    function touchPair(event) {
      const points = [...event.touches].sort((a, b) => a.identifier - b.identifier)
        .slice(0, 2).map(touch => d3.pointer(touch, sceneOrigin.value ?? canvas.value));
      const [[ax, ay], [bx, by]] = points;
      return {x: (ax + bx) / 2, y: (ay + by) / 2, distance: Math.max(1, Math.hypot(ax - bx, ay - by))};
    }
    function startTouchView(event) {
      if (event.touches.length < 2) return;
      event.preventDefault();
      const drag = gesture.value;
      if (drag) {
        if (drag.waiting) gesture.value = null;
        else finishPointer({pointerId: drag.pointer}, true);
      }
      const pair = touchPair(event);
      touchView = {...pair, zoomDistance: pair.distance, transform: view.value};
      canDeselectOnClick = false;
    }
    function moveTouchView(event) {
      if (!touchView || event.touches.length < 2) return;
      event.preventDefault();
      const pair = touchPair(event);
      const start = touchView.transform;
      touchView.zoomDistance = limit(touchView.zoomDistance, pair.distance - pinchTolerance, pair.distance + pinchTolerance);
      const k = limit(start.k * touchView.zoomDistance / touchView.distance, 0.0005, 4);
      const [x, y] = start.invert([touchView.x, touchView.y]);
      d3.select(zoomHost()).call(zoom.transform, d3.zoomIdentity.translate(pair.x - x*k, pair.y - y*k).scale(k));
    }
    function endTouchView(event) {
      if (!touchView) return;
      if (event.touches.length >= 2) startTouchView(event);
      else if (!event.touches.length) touchView = null;
    }
    function scrollsSelectedText(event) {
      if (event.ctrlKey || selected.value?.kind !== "node") return false;
      const content = event.target.closest(".node-note, .node-file pre, .inline-edit textarea");
      return content?.closest("[data-node]")?.dataset.node === selected.value.id
        && content.scrollHeight > content.clientHeight;
    }

    function initializeZoom() {
      if (!canvas.value || zoom) return;
      measure();
      zoom = d3.zoom().scaleExtent([0.0005, 4])
        .filter(event => {
          // A vezérlők és jelenlévők (a vászon szülőjének többi gyereke) fölötti események nem nagyítanak/pásztáznak.
          if (canvas.value?.contains && event.target && !canvas.value.contains(event.target)) return false;
          if (event.type === "wheel") return !gesture.value && !scrollsSelectedText(event);
          if (event.type === "touchstart") return false;
          if (spacePan.value) return !event.button && !gesture.value;
          return !panLocked.value && !event.button && !event.altKey && !event.ctrlKey && !reconnect.value && !gesture.value
            && !event.target.closest("[data-node], [data-edge]");
        })
        .on("start", event => { menu.value = null; if (event.sourceEvent) lastClick = null; markMoving("zoom", true); })
        .on("zoom", event => {
          const type = event.sourceEvent?.type;
          if (type === "mousemove" || type === "pointermove" || type === "touchmove") panning.value = true;
          // Felhasználói mozdulat (görgetés, egérrel pásztázás) közben csak a vászon CSS-rétege mozog;
          // a programozott nézetváltás (Mind, keresés, érintés) azonnal érvényes.
          if (event.sourceEvent) previewView(event.transform);
          else commitView(event.transform);
        })
        .on("end", event => { panning.value = false; commitView(event?.transform ?? pendingView); markMoving("zoom", false); });
      // A zoom a nem transzformált szülőn figyel, így a mozdulat közbeni CSS-transzform nem zavarja a koordinátáit.
      d3.select(zoomHost()).call(zoom).on("dblclick.zoom", null);
      resizeObserver = new ResizeObserver(measure);
      resizeObserver.observe(zoomHost() ?? canvas.value);
      fit();
    }

    // Nagyítás és pásztázás a grafikus kártyán (PLAN.md C3/C6): mozdulat közben a teljes vászon-SVG egy CSS-transzformmal
    // skálázódik és tolódik, újrarajzolás és SVG-újraelrendezés nélkül; a valódi nézet a mozdulat végén egyszer frissül.
    // A pontkoordináták (world) közben is helyesek, mert a getScreenCTM a CSS-transzformot is tartalmazza.
    function zoomHost() { return canvas.value?.parentElement; }
    let pendingView = null;
    function previewView(transform) {
      pendingView = transform;
      const svg = canvas.value, current = view.value;
      if (!svg?.style) return;
      const scale = transform.k / current.k;
      const shiftX = transform.x - scale * current.x, shiftY = transform.y - scale * current.y;
      // Az origó a látható terület bal felső sarka a (nagyobb) rétegen belül.
      const [marginX, marginY] = margin();
      const {width, height} = size.value;
      // Hibrid: ha a látható terület kilógna az előre kirajzolt rétegből, azonnal valódi újrarajzolás jön
      // (egy lassabb képkocka), így levágott doboz sosem látszik. Utána az eltolás az új nézethez képest folytatódik.
      const covered = shiftX - scale * marginX <= 0 && shiftY - scale * marginY <= 0 &&
        shiftX + scale * (width + marginX) >= width && shiftY + scale * (height + marginY) >= height;
      if (!covered) { commitView(transform); return; }
      svg.style.transformOrigin = marginX + "px " + marginY + "px";
      svg.style.transform = `matrix(${scale},0,0,${scale},${shiftX},${shiftY})`;
      // A rács nem skálázódik a réteggel: a mintája közvetlenül az élő nézetet követi.
      const [centerX, centerY] = center();
      zoomHost()?.querySelector?.("#worksheet-grid")?.setAttribute("patternTransform", transform + " translate(" + centerX + " " + centerY + ")");
    }
    function commitView(transform) {
      pendingView = null;
      if (canvas.value?.style) canvas.value.style.transform = "";
      if (transform && (transform.k !== view.value.k || transform.x !== view.value.x || transform.y !== view.value.y)) view.value = transform;
    }

    function fit() {
      if (!zoom || !board.value) return;
      const bounds = drawnBounds();
      const [x, y] = center();
      const scale = limit(Math.min((x * 2 - 40) / bounds.width, (y * 2 - 40) / bounds.height, 1), 0.0005, 1);
      d3.select(zoomHost()).call(zoom.transform, d3.zoomIdentity.translate(x * (1 - scale), y * (1 - scale)).scale(scale));
    }

    function centerOrigin() {
      if (!zoom) return;
      d3.select(zoomHost()).call(zoom.transform, d3.zoomIdentity);
    }

    function id() {
      // randomUUID is unavailable on plain HTTP at a LAN address.
      return Array.from(crypto.getRandomValues(new Uint8Array(16)), byte => byte.toString(16).padStart(2, "0")).join("");
    }

    function makeNode(position, type = "box") {
      return {id: id(), type, text: "", position: clampPoint(position), width: 176, height: 80,
        shape: "rounded", fill: 2, textColor: 1, fontSize: 16, alignment: "center"};
    }

    function addNode(position = worldAtCenter(), properties = {}) {
      if (!board.value || !online.value) return;
      finishField();
      const node = normalizePreview({...makeNode(position, properties.type), ...properties});
      board.value.nodes.push(node);
      modified();
      openProperties("node", node.id, isBox(node) ? "text" : true);
    }

    function selectedBox() {
      return selected.value?.kind === "node" ? nodeMap.value.get(selected.value.id) : null;
    }

    function transfer(action) {
      Promise.resolve().then(action).catch(error => { problem.value = error.message; });
    }

    // http(s) cím a vágólapon vagy behúzva: linkes doboz (docs/node-types.md, link képesség).
    function externalURL(text) {
      const value = text.trim();
      if (!/^https?:\/\/\S+$/i.test(value)) return null;
      try { const url = new URL(value); return url.hostname && !url.username && !url.password ? url.href : null; }
      catch { return null; }
    }

    function addLinkBox(href, position) {
      addNode(position, {link: {kind: "url", target: href}, width: 220, height: 90});
    }

    async function pasteText(text, position) {
      if (!text || !online.value) return;
      const source = text.startsWith(location.origin + "/") ? new URL(text) : null;
      if (source && /^#object-[a-z0-9-]+$/.test(source.hash)) {
        const sourcePath = source.pathname.slice(1);
        const sheet = sourcePath === path ? board.value : decodeWorksheet(await (await checked(await fetch("/api/worksheet/" + sourcePath))).json());
        const item = sheet.nodes.find(n => n.id === source.hash.slice(8));
        if (item?.file) {
          const copied = {type: item.type, text: item.text, link: item.link, width: item.width, height: item.height,
            alignment: item.alignment, hideText: item.hideText};
          if (sourcePath !== path) {
            const url = ["image", "audio"].includes(rootType(item.type)) ? fileURL(sourcePath, item.file) : "/api/box-file/" + sourcePath + "?id=" + encodeURIComponent(item.id);
            const blob = await (await checked(await fetch(url))).blob();
            const imported = await importFile(new File([blob], fileName(item.file, isImage(item)), {type: blob.type}), path, csrf);
            if (!imported) return;
            addNode(position, {...imported, ...copied, type: imported.type});
            return;
          }
          addNode(position, {...copied, file: {...item.file}});
          return;
        }
      }
      const href = externalURL(text);
      if (href) { addLinkBox(href, position); return; }
      checkText(text);
      const box = selectedBox();
      if (isBox(box) && held.value === box.id && !occupied(box.id)) updateItem(box, "text", checkText([box.text,text].filter(Boolean).join("\n")));
      else addNode(position, {text, width: 260, height: 140});
    }

    async function importFiles(files, position, belowButton = false) {
      if (!online.value) throw Error("A beillesztéshez aktív szerkesztői kapcsolat szükséges.");
      const failures = [];
      let bottom = position.y;
      for (const blob of files) {
        try {
          const properties = await importFile(blob, path, csrf);
          if (!properties) continue;
          if (!online.value) throw Error("A kapcsolat megszakadt.");
          const y = bottom + (belowButton || bottom !== position.y ? properties.height / 2 : 0);
          addNode({x: position.x, y}, properties);
          bottom = y + properties.height / 2 + 46;
        } catch (error) { failures.push((blob.name || "Vágólap") + " · " + error.message); }
      }
      if (failures.length) throw Error(failures.join("\n"));
    }

    // Tallózó: a projekt bármely lapjának fájlja vagy .web oldala beilleszthető (feltöltés nélkül, közös hivatkozással).
    function insertFromBrowser() {
      transfer(async () => {
        const choice = await openFileBrowser(path, csrf);
        if (!choice || !online.value) return;
        const own = path.split("/").slice(1).map(decodeURIComponent).join("/");
        // Saját mappa: belső azonosítóval a megszokott hivatkozás; azonosító nélküli kép/hang közösként, valódi névvel.
        const source = choice.source === own && (choice.asset || !/\.(png|jpe?g|webp|gif|svg|mp3|wav|ogg|flac|m4a|aac)$/i.test(choice.name))
          ? undefined : choice.source;
        const position = worldAtCenter();
        if (choice.kind === "web") {
          const target = (choice.source ? choice.source + "/" : "") + choice.name;
          addNode(position, {text: choice.name.replace(/\.web$/, ""), link: {kind: "web", target}, width: 320, height: 200});
          return;
        }
        const sheet = choice.common ? "" : [choice.project, ...(choice.source ? choice.source.split("/").map(encodeURIComponent) : [])].join("/");
        addNode(position, await sharedFileBox(choice.name, sheet, source, choice.asset ?? choice.name));
      });
    }

    async function uploadAttachments(event) {
      const files = Array.from(event.target.files);
      event.target.value = "";
      if (!files.length || uploading.value) return;
      uploading.value = true;
      try {
        const position = uploadAnchor ? world(uploadAnchor) : worldAtCenter();
        await importFiles(files, position, !!uploadAnchor);
      } catch (error) {
        problem.value = error.message;
      } finally { uploading.value = false; }
    }

    const editingText = target => target?.closest?.("input, textarea, select, [contenteditable=true]");
    function onPaste(event) {
      if (editingText(event.target) || !online.value) return;
      const files = Array.from(event.clipboardData.files);
      const text = event.clipboardData.getData("text/plain") || event.clipboardData.getData("text/markdown");
      if (!files.length && !text) return;
      event.preventDefault();
      const position = pastePosition();
      transfer(() => files.length ? importFiles(files, position) : pasteText(text, position));
    }
    function copyBox(node) {
      if (!node) return;
      if (isImage(node) && navigator.clipboard?.write && window.ClipboardItem) {
        return navigator.clipboard.write([new ClipboardItem({"image/png": pngForClipboard(fileURL(path, node.file))})]);
      }
      return writeText(node.file ? objectURL(path,node.id) : node.text);
    }
    function onCopy(event) {
      const node = selectedBox();
      if (!node || editingText(event.target) || window.getSelection()?.toString()) return;
      event.preventDefault();
      event.clipboardData.setData("text/plain", node.file ? objectURL(path,node.id) : node.text);
      if (isImage(node)) transfer(() => copyBox(node));
    }

    async function addSubworksheet() {
      menu.value = null;
      const name = window.prompt("Új munkalap útvonalneve")?.trim();
      if (!name) return;
      if (!/^[\p{L}\p{M}\p{Nd}_-]+$/u.test(name)) {
        problem.value = "A név betűt, számot, kötőjelet és aláhúzást tartalmazhat.";
        return;
      }
      try {
        await enqueue(commit);
        const child = path + "/" + encodeURIComponent(name);
        await checked(await fetch("/api/subworksheet/" + child, {
          method: "POST", headers: {"X-CSRF-Token": csrf},
        }));
        location.assign("/edit/" + child);
      } catch (error) { problem.value = error.message; }
    }

    const editKey = ref("text");
    const inlineDraft = ref("");
    async function editObject(kind, id, focus = true) {
      if (objectPanelOpen.value) return openProperties(kind, id, focus);
      await openProperties(kind, id);
      if (selected.value?.id !== id) return;
      editKey.value = kind === "edge" ? "label" : "text";
      const item = kind === "edge" ? edgeMap.value.get(id) : nodeMap.value.get(id);
      inlineDraft.value = item?.[editKey.value] ?? "";
      editingObject.value = id;
      await nextTick();
      const input = mount.querySelector?.(".inline-edit input, .inline-edit textarea");
      input?.focus?.();
      input?.select?.();
    }

    async function openProperties(kind, itemID, focusLabel = false, showCanvasInput = true) {
      if (kind === "node" && !(await selectNode(itemID))) return;
      if (kind !== "node") selectNode(null, kind === "edge" ? itemID : null);
      selected.value = {kind, id: itemID};
      inspector.value = {kind, id: itemID};
      menu.value = null;
      if (focusLabel) {
        objectPanelOpen.value = true;
        await nextTick();
        const field = mount.querySelector?.(".object-inspector [data-object-label]");
        if (selected.value?.id === itemID && field) {
          field.focus();
          editKey.value = kind === "edge" ? "label" : "text";
          editingObject.value = showCanvasInput ? itemID : null;
          field.select();
        }
      }
    }

    function joinAtJunction(id, connected) {
      if (connected.length !== 2) return;
      const [keep, shorter] = connected.sort((a,b) => wireGeometry(b).length - wireGeometry(a).length);
      const end = keep.source === id ? "source" : "target";
      const far = shorter.source === id ? "target" : "source";
      const destination = edgeEndpoint(shorter, far);
      const candidate = {...keep};
      setEndpoint(candidate, end, destination);
      if (candidate.source && candidate.target.node && (candidate.source === candidate.target.node ||
          board.value.edges.some(e => e.id !== keep.id && e.source === candidate.source && e.target.node === candidate.target.node))) return;
      setEndpoint(keep, end, destination);
      keep[end === "source" ? "startArrow" : "endArrow"] = far === "source" ? !!shorter.startArrow : shorter.endArrow !== false;
      board.value.edges = board.value.edges.filter(e => e.id !== shorter.id);
    }

    function confirmFileRemoval(nodes) {
      if (!nodes.length) return true;
      const names = new Set(nodes.map(nodeName));
      return confirm("Lomtárba helyezed a fájlokat és törlöd a dobozaikat?\n" + [...names].join("\n"));
    }

    // Fájl- és .web-doboz törlése (közös elemek): ha más lap is használja, három lehetőség közül választhat
    // (csak a doboz / elem lomtárba + a többi doboz törlése / elem lomtárba + a többi üres doboz); ha nem, rákérdezés után lomtárba.
    function deleteObjects(ids, preserve, edges = new Set()) {
      const shared = [...ids].map(id => nodeMap.value.get(id)).filter(node => (node?.file && !isCommonFile(node.file)) || node?.link?.kind === "web");
      if (!shared.length) { removeObjects(ids, preserve, edges); return; }
      const key = node => node.link?.kind === "web" ? "web:" + node.link.target : JSON.stringify([node.file.source ?? null, node.file.asset]);
      for (const node of board.value.nodes) if (((node.file && !isCommonFile(node.file)) || node.link?.kind === "web")
        && shared.some(item => key(item) === key(node))) ids.add(node.id);
      if (batchBlocked(ids)) return;
      transfer(() => enqueue(async () => {
        await commit();
        const targets = [...new Map(shared.map(node => [key(node), node])).values()];
        const others = [];
        for (const node of targets) {
          const usage = await (await checked(await fetch("/api/usage/" + path + "?id=" + encodeURIComponent(node.id), {cache: "no-store"}))).json();
          for (const entry of usage) if (entry.sheet !== path) others.push({node, title: entry.title || entry.sheet, count: entry.nodes.length});
        }
        const names = targets.map(nodeName);
        const choice = others.length ? await chooseRemoval(names, others)
          : confirm("Lomtárba helyezed, és törlöd a dobozt?\n" + names.join("\n")) ? "delete" : null;
        if (!choice) return;
        if (choice !== "keep") {
          const failed = [];
          for (const node of targets) {
            const result = await (await checked(await fetch("/api/release/" + path, {method: "POST",
              headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify({id: node.id, mode: choice})}))).json();
            failed.push(...result.failed);
          }
          if (failed.length) problem.value = "Ezeken a lapokon nem sikerült módosítani (valaki szerkeszti a dobozt): " + failed.join(", ");
        }
        const before = copy(board.value);
        removeObjects(ids, preserve, edges, false);
        const after = copy(board.value);
        try { await commit(); recordChanges(); }
        catch (error) {
          board.value = keepUnchanged(board.value, rebaseWorksheet(after, copy(board.value), before));
          if (!worksheetChanges(baseline, copy(board.value)).length) savedGeneration.value = generation.value;
          throw error;
        }
      }));
    }

    function removeObjects(ids, preserve, selectedEdges = new Set(), record = true) {
      const boxes = new Set([...ids].filter(id => !isJunction(nodeMap.value.get(id))));
      board.value.edges = board.value.edges.filter(edge => {
        if (preserve && (ids.has(edge.source) || ids.has(edge.target.node))) return true;
        if (selectedEdges.has(edge.id)) return false;
        return preserve || !(boxes.has(edge.source) || boxes.has(edge.target.node));
      });
      if (!preserve) {
        for (const id of ids) {
          if (!boxes.has(id)) joinAtJunction(id, board.value.edges.filter(e => e.source === id || e.target.node === id));
        }
      }
      for (const edge of board.value.edges) {
        if (!ids.has(edge.source) && !ids.has(edge.target.node)) continue;
        const {from, to} = wireGeometry(edge);
        if (ids.has(edge.source)) setEndpoint(edge, "source", {point: clampPoint(from)});
        if (ids.has(edge.target.node)) setEndpoint(edge, "target", {point: clampPoint(to)});
      }
      for (const node of board.value.nodes) {
        while (node.parent && ids.has(node.parent)) node.parent = nodeMap.value.get(node.parent)?.parent;
      }
      board.value.nodes = board.value.nodes.filter(node => !ids.has(node.id));
      pruneJunctions();
      if (record) modified(); else markDirty();
      clearSelection();
    }

    async function deleteNode(node, preserve = false, includeChildren = false) {
      if (!(await selectNode(node.id)) || groupBlocked(node)) return;
      const ids = new Set(includeChildren && containerIDs.value.has(node.id) ? moveGroup(node).map(n => n.id) : [node.id]);
      deleteObjects(ids, preserve);
    }

    function removeEdge(edge) {
      board.value.edges = board.value.edges.filter(item => item.id !== edge.id);
      pruneJunctions();
      clearSelection();
      modified();
    }

    // Leválasztáskor a vonalvég a kötési ponttól egy kicsit eltávolodik, hogy ne maradjon rajta a csomópont szélén.
    function detach(edge, end) {
      const attachedNode = edgeEndpoint(edge, end).node;
      if (!attachedNode) return;
      const {from, to} = wireGeometry(edge);
      const at = end === "source" ? from : to;
      const center = nodeMap.value.get(attachedNode);
      let dx = center ? at.x - center.position.x : 0, dy = center ? at.y - center.position.y : 0;
      const length = Math.hypot(dx, dy);
      if (length < 1) { dx = 0; dy = 1; } else { dx /= length; dy /= length; }
      const away = {x: at.x + dx * 32, y: at.y + dy * 32};
      setEndpoint(edge, end, {point: gridPoint(away)});
      pruneJunctions();
      modified();
    }

    function inspectNothing() {
      editingObject.value = null;
      finishField();
      inspector.value = null;
      menu.value = null;
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

    function fitsInside(child, container) {
      return container.width >= child.width && container.height >= child.height &&
        (container.width > child.width || container.height > child.height) &&
        overlapFraction(child, container) > 0.5;
    }

    function dropReceiver(node, excluded) {
      if (node.elevated === true) return;
      const dragged = drawnNode(node.id);
      return containerReceivers.value.find(candidate => candidate.id !== node.id && !excluded?.has(candidate.id) &&
        (!isJunction(node) || containerIDs.value.has(candidate.id)) &&
        fitsInside(dragged, drawnNode(candidate.id)) &&
        !occupied(candidate.id) && !ancestors(candidate, nodeMap.value).some(parent => parent.id === node.id));
    }

    function dropParent(node, excluded) {
      const target = dropReceiver(node, excluded);
      if (target) target.container = true;
      node.parent = target?.id;
    }

    function capturableChildren(container, excluded) {
      if (!containerIDs.value.has(container.id)) return [];
      const drawn = drawnNode(container.id);
      const parents = new Set(ancestors(container, nodeMap.value).map(parent => parent.id));
      const candidates = new Map();
      for (const child of board.value.nodes) {
        if (child.id === container.id || child.elevated === true || isJunction(child) || excluded?.has(child.id) ||
            parents.has(child.id) || occupied(child.id) || !fitsInside(drawnNode(child.id), drawn)) continue;
        const lineage = ancestors(child, nodeMap.value);
        if (!lineage.some(parent => parent.id === container.id || parent.locked)) candidates.set(child.id, {child, lineage});
      }
      // A captured container brings its descendants with it.
      return [...candidates.values()].filter(({lineage}) => !lineage.some(parent => candidates.has(parent.id)))
        .map(({child}) => child);
    }

    function dropBox(node, excluded) {
      dropParent(node, excluded);
      for (const child of capturableChildren(node, excluded)) child.parent = node.id;
    }

    const containerDropTargets = computed(() => {
      const drag = gesture.value;
      const targets = new Set();
      if (!drag?.moved || drag.waiting || drag.locked) return targets;
      function mark(node, excluded, capture = true) {
        const target = node && !isJunction(node) && dropReceiver(node, excluded);
        if (target && target.id !== node.parent) targets.add(target.id);
        if (capture && node && capturableChildren(node, excluded).length) targets.add(node.id);
      }
      if (drag.type === "move" && !drag.group.some(member => occupied(member.id))) {
        mark(nodeMap.value.get(drag.nodeID));
      } else if (drag.type === "clone") {
        mark(insertion.value?.nodes[0], undefined, false);
      } else if (drag.type === "batch" && batch.value &&
          [...drag.members].every(id => {
            const node = nodeMap.value.get(id);
            return node && !occupied(id) && !ancestors(node, nodeMap.value)
              .some(parent => parent.locked && !drag.members.has(parent.id));
          })) {
        for (const id of batch.value.nodes) {
          const node = nodeMap.value.get(id);
          if (node && !drag.members.has(node.parent)) mark(node, drag.members);
        }
      }
      return targets;
    });

    function junctionDropTarget(node, excluded) {
      if (!isJunction(node)) return;
      const point = drawnNode(node.id).position;
      return orderedNodes.value.findLast(box => !isJunction(box) && !excluded?.has(box.id) &&
        shapeDistance(drawnNode(box.id), point) <= 1);
    }

    const junctionTarget = computed(() => {
      const drag = gesture.value;
      if (!drag?.moved || drag.waiting || drag.locked) return;
      if (drag.type === "split") return junctionDropTarget(insertion.value?.nodes[0])?.id;
      if (drag.type === "move" && !occupied(drag.nodeID)) return junctionDropTarget(nodeMap.value.get(drag.nodeID))?.id;
    });

    function junctionAttachments(boxes, edges) {
      const changes = new Map();
      const routes = new Set();
      for (const edge of edges) {
        const source = boxes.get(edge.source), target = boxes.get(edge.target.node);
        const from = source ?? edge.source, to = target ?? edge.target.node;
        if (from && to) {
          const route = from + "/" + to;
          if (from === to || routes.has(route)) return null;
          routes.add(route);
        }
        if (!source && !target) continue;
        const attached = {...edge};
        if (source) setEndpoint(attached, "source", {node: source});
        if (target) setEndpoint(attached, "target", {node: target});
        changes.set(edge.id, attached);
      }
      return changes;
    }

    function dissolveJunctions(boxes, attachments) {
      board.value.edges = board.value.edges.map(edge => attachments.get(edge.id) ?? edge);
      board.value.nodes = board.value.nodes.filter(node => !boxes.has(node.id));
    }

    const junctionConflict = "A csomópont nem oldható fel ezen a dobozon, mert önmagába vezető vagy ismétlődő vonal keletkezne.";

    function pruneJunctions() {
      const counts = new Map();
      for (const edge of board.value.edges) {
        for (const id of new Set([edge.source, edge.target.node])) {
          if (id) counts.set(id, (counts.get(id) ?? 0) + 1);
        }
      }
      const removed = new Map(board.value.nodes.filter(n => isJunction(n) && (counts.get(n.id) ?? 0) < 2)
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
      if (inspector.value?.kind === "node" && !nodeMap.value.has(inspector.value.id)) inspectNothing();
    }

    function snap(point, exclude, releaseFrom, inside) {
      const padding = 8 / zoomScale.value;
      const node = orderedNodes.value.findLast(node => node.id !== exclude && (!inside || ancestors(node, nodeMap.value).some(parent => parent.id === exclude)) &&
        shapeDistance(drawnNode(node.id), point, node.id === releaseFrom ? 0 : padding) <= 1);
      if (node) return {node: node.id};
    }

    function gridPoint(point) {
      if (!snapToGrid.value) return clampPoint(point);
      const spacing = gridSpacing.value;
      const minIndex = Math.ceil(-100000 / spacing), maxIndex = Math.floor(100000 / spacing);
      const snapAxis = value => limit(Math.round(value / spacing), minIndex, maxIndex) * spacing;
      return {x: snapAxis(point.x), y: snapAxis(point.y)};
    }

    function cablePreview(source, point) {
      const edge = {target: {point}, type: "straight", appearance: "plain", endArrow: true};
      setEndpoint(edge, "source", source);
      return edge;
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
      const cloneLink = {id: id(), source: source.id, target: {node: nodes[0].id}, type: "straight", endArrow: true};
      return {nodes, edges, cloneLink};
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
      const root = draft.nodes[0];
      let edges = insertionEdges.value, nodes = draft.nodes;
      const target = junctionDropTarget(root);
      const attachments = target && junctionAttachments(new Map([[root.id, target.id]]), sceneEdges.value);
      insertion.value = null;
      if (!online.value || draft.original && JSON.stringify(edgeMap.value.get(draft.original.id)) !== JSON.stringify(draft.original)) return;
      if (target && !attachments) { problem.value = junctionConflict; return; }
      if (attachments) {
        nodes = nodes.filter(node => node.id !== root.id);
        edges = edges.map(edge => attachments.get(edge.id) ?? edge);
      }
      if (board.value.nodes.length + nodes.length > 2000 ||
          board.value.edges.length + edges.length - (draft.original ? 1 : 0) > 4000) {
        problem.value = "A művelettel a munkalap túllépné a dobozok vagy vonalak számának korlátját.";
        return;
      }
      const ids = new Set([...nodeMap.value.keys(), ...nodes.map(n => n.id)]);
      if (edges.some(e => e.source && !ids.has(e.source) || e.target.node && !ids.has(e.target.node))) return;
      board.value.nodes.push(...nodes);
      if (draft.original) board.value.edges.splice(board.value.edges.findIndex(e => e.id === draft.original.id),1,...edges);
      else board.value.edges.push(...edges);
      if (!attachments) dropParent(root);
      modified();
      if (!attachments) openProperties("node", root.id, true);
    }

    function pressNode(event, node) {
      finishField();
      if (event.altKey && !event.ctrlKey && event.button === 0 && !isJunction(node)) {
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
      if (cabling) {
        gesture.value.source = {node: node.id};
        preview.value = {edge: cablePreview(gesture.value.source, initial)};
      }
      (cabling ? canvas.value : event.currentTarget).setPointerCapture(event.pointerId);
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

    function pressEndpoint(event, edge, end, fromShaft = false) {
      finishField();
      if ((event.button !== 0 && !(event.ctrlKey && event.button === 2)) || reconnect.value || !online.value) return;
      const original = edgeEndpoint(edge, end);
      const geometry = wireGeometry(edge);
      const initial = world(event);
      const position = fromShaft ? initial : end === "source" ? geometry.from : geometry.to;
      event.preventDefault();
      event.stopPropagation();
      menu.value = null;
      event.currentTarget.focus({preventScroll: true});
      selectNode(null, edge.id);
      selected.value = {kind: "endpoint", id: edge.id, end};
      gesture.value = {type: "endpoint", original: {...original}, pointer: event.pointerId, edgeID: edge.id, end,
        position: {...position}, initial, screen: [event.clientX, event.clientY], moved: false};
      canvas.value.setPointerCapture(event.pointerId);
    }

    function endpointAt(point, edge, end, commit = false, releaseFrom) {
      const opposite = edgeEndpoint(edge, otherEnd(end)).node;
      const origin = opposite && drawnNode(opposite);
      const inside = origin && shapeDistance(origin, point) <= 1;
      const free = !inside && nearbyEnd(point, edge);
      if (free) {
        if (opposite && end === free.end && edgeEndpoint(free.edge, otherEnd(free.end)).node === opposite) {
          return {point, blocked: "Ezen az útvonalon már van kábel."};
        }
        if (!commit) return {point: free.point, junction: free.point};
        const node = {...makeNode(free.point, "junction"),
          shape: "ellipse", fill: free.edge.color ?? 3, width: graphics.value.junctionSize ?? 12, height: graphics.value.junctionSize ?? 12};
        board.value.nodes.push(node);
        dropParent(node);
        setEndpoint(free.edge, free.end, {node: node.id});
        return {node: node.id, createdJunction: true};
      }
      const target = snap(point, opposite, releaseFrom, inside);
      if (inside && !target) return {point, blocked: "A dobozon belül egy belső dobozt válassz."};
      if (target && opposite && board.value.edges.some(candidate => candidate.id !== edge.id &&
          edgeEndpoint(candidate, end).node === target.node && edgeEndpoint(candidate, otherEnd(end)).node === opposite)) {
        return {point, blocked: "Ezen az útvonalon már van kábel."};
      }
      return target ?? {point: gridPoint(point)};
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
      if (operation?.type === "pan") {
        const [x, y] = operation.screen;
        const start = operation.startView;
        const next = start.translate((event.clientX - x) / start.k, (event.clientY - y) / start.k);
        d3.select(zoomHost()).call(zoom.transform, next);
        return;
      }
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
              const anchor = operation.snapAnchor;
              if (anchor) {
                const snapped = gridPoint(shifted(anchor, delta));
                delta.x = snapped.x - anchor.x;
                delta.y = snapped.y - anchor.y;
              }
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
              const snapped = gridPoint(position);
              translateGroup(operation.group, snapped.x-operation.position.x, snapped.y-operation.position.y);
              const current = nodeMap.value.get(operation.nodeID).position;
              live.motion({node: operation.nodeID, revision: baseline.revision,
                delta: {x: current.x-operation.position.x, y: current.y-operation.position.y}});
            }
          } else {
            const edge = edgeMap.value.get(operation.edgeID);
            operation.endPosition = position;
            const endpoint = endpointAt(position, edge, operation.end, false, operation.original.node);
            preview.value = {target: endpoint.node, attachment: endpoint, junction: endpoint.junction};
          }
          return;
        }
        const edge = cablePreview(operation.source, point);
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
        Object.assign(node, {alignment, verticalAlignment, justified: undefined});
        modified();
      } else if (operation.type === "resize" && operation.moved && !operation.locked) {
        if (cancel) {
          const index = board.value.nodes.findIndex(n => n.id === operation.nodeID);
          board.value.nodes[index] = operation.original;
        } else modified();
      } else if (operation.type === "move" && operation.moved) {
        lastClick = null;
        const node = nodeMap.value.get(operation.nodeID);
        if (!operation.locked) {
          const target = !cancel && junctionDropTarget(node);
          const boxes = target && new Map([[node.id, target.id]]);
          const attachments = boxes && junctionAttachments(boxes, board.value.edges);
          if (cancel || target && !attachments) {
            live.endMotion(node.id, baseline.revision);
            translateGroup(operation.group, 0, 0);
            if (target) problem.value = junctionConflict;
          } else if (!operation.group.some(member => occupied(member.id))) {
            live.flushMotion();
            if (attachments) dissolveJunctions(boxes, attachments);
            else dropBox(node);
            modified();
            if (attachments) clearSelection();
          }
        }
      } else if (!operation.moved && !cancel && (operation.nodeID || operation.edgeID || operation.hitID)) {
        const kind = operation.hitKind ?? (operation.nodeID ? "node" : "edge");
        const id = operation.hitID ?? operation.nodeID ?? operation.edgeID;
        const time = performance.now();
        const [x,y] = operation.screen;
        if (lastClick?.id === id && lastClick.kind === kind && time-lastClick.time < 450 &&
            Math.hypot(x-lastClick.x,y-lastClick.y) < 10) {
          lastClick = null;
          editObject(kind,id,event.altKey && kind === "node" ? "text" : true);
        } else {
          lastClick = {id,kind,time,x,y};
        }
      } else if (operation.type === "cable" && operation.moved && !cancel) {
        const edge = {id: id(), ...preview.value.edge};
        const endpoint = endpointAt(world(event), edge, "target", true);
        if (endpoint.blocked) problem.value = endpoint.blocked;
        else {
          setEndpoint(edge, "target", endpoint);
          board.value.edges.push(edge);
          modified();
          openProperties("edge", edge.id, true, false);
        }
      } else if (operation.type === "endpoint" && operation.moved) {
        const edge = edgeMap.value.get(operation.edgeID);
        const endpoint = cancel ? operation.original
          : endpointAt(operation.endPosition, edge, operation.end, true, operation.original.node);
        if (endpoint.blocked) problem.value = endpoint.blocked;
        else setEndpoint(edge, operation.end, endpoint);
        if (!cancel && !endpoint.blocked) {
          pruneJunctions();
          if (endpoint.node && !endpoint.createdJunction) selected.value = {kind: "edge", id: edge.id};
          modified();
          if (endpoint.createdJunction) openProperties("node", endpoint.node);
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

    function selectionMembers() {
      const nodes = new Set(batch.value?.nodes), edges = new Set(batch.value?.edges);
      const item = selected.value;
      if (item) (item.kind === "node" ? nodes : edges).add(item.id);
      return {nodes, edges};
    }

    function selectMembers(group) {
      clearSelection();
      if (group.nodes.size || group.edges.size) {
        batch.value = group;
      }
    }

    // A téglalap által érintett (vagy teljesen tartalmazott) objektumok; a húzás közbeni kiemelés is ezt használja.
    // Balról jobbra / fentről lefelé húzva csak a teljesen bent lévő objektumok, jobbról balra vagy
    // alulról felfelé húzva minden, ami a téglalapot akár csak érinti (Ctrl-lal is kérhető).
    function rectangleTouches(drag) {
      return !!drag.touching || drag.point.x < drag.initial.x || drag.point.y < drag.initial.y;
    }
    function rectangleMembers(drag) {
      drag = {...drag, touching: rectangleTouches(drag)};
      const box = rectangle(drag.initial, drag.point);
      const right = box.x + box.width, bottom = box.y + box.height;
      const inside = p => p.x >= box.x && p.x <= right && p.y >= box.y && p.y <= bottom;
      const hits = {nodes: new Set(), edges: new Set()};
      for (const node of sceneNodes.value) {
        const closest = {x: limit(node.position.x, box.x, right), y: limit(node.position.y, box.y, bottom)};
        let touches = shapeDistance(node, closest) <= 1;
        if (drag.touching && !touches) {
          const vertices = polygonVertices(node.shape, node.width/2, node.height/2);
          if (vertices) {
            const points = vertices.map(([x,y]) => ({x: node.position.x+x, y: node.position.y+y}));
            touches = edgeInRectangle({boundsPoints: [...points, points[0]], command: "L"}, box, true);
          }
        }
        if (touches && node.shape === "rounded" && !graphics.value.boxChamfer) {
          const dx = Math.max(0, Math.abs(closest.x-node.position.x)-node.width/2+12);
          const dy = Math.max(0, Math.abs(closest.y-node.position.y)-node.height/2+12);
          touches = Math.hypot(dx,dy) <= 12;
        }
        if (drag.touching ? touches : [-1,1].every(k => inside({x: node.position.x+k*node.width/2, y: node.position.y+k*node.height/2}))) hits.nodes.add(node.id);
      }
      for (const edge of board.value.edges) {
        if (edgeInRectangle(wireGeometry(edge), box, drag.touching)) hits.edges.add(edge.id);
      }
      return hits;
    }

    // Húzás közben a téglalapba eső objektumok már kiemelve látszanak.
    const marqueeHits = computed(() => gesture.value?.type === "rectangle" ? rectangleMembers(gesture.value) : null);

    // A saját kijelölés színe: a felhasználó színe (ha a munkamenetben van), különben a témabeli kijelölési szín.
    function selectionTint() {
      return peers.value.find(p => p.mine)?.color ?? paint(graphics.value.selection ?? 4, 4);
    }

    function selectRectangle(drag) {
      const group = drag.additive ? selectionMembers() : {nodes: new Set(), edges: new Set()};
      const hits = rectangleMembers(drag);
      for (const id of hits.nodes) group.nodes.add(id);
      for (const id of hits.edges) group.edges.add(id);
      selectMembers(group);
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
      const boxes = new Map();
      for (const id of batch.value.nodes) {
        const target = junctionDropTarget(nodeMap.value.get(id), drag.members);
        if (target) boxes.set(id, target.id);
      }
      const attachments = boxes.size ? junctionAttachments(boxes, board.value.edges) : null;
      if (boxes.size && !attachments) { problem.value = junctionConflict; return; }
      gesture.value = null;
      for (const id of drag.members) {
        const node = nodeMap.value.get(id);
        node.position = shifted(node.position,drag.delta);
      }
      if (attachments) {
        dissolveJunctions(boxes, attachments);
        for (const id of boxes.keys()) batch.value.nodes.delete(id);
      }
      for (const edge of board.value.edges) {
        if (batch.value.edges.has(edge.id)) Object.assign(edge,moveBatchEdge(edge,drag));
      }
      for (const id of batch.value.nodes) {
        const node = nodeMap.value.get(id);
        if (!drag.members.has(node.parent)) dropBox(node, drag.members);
      }
      if (!batch.value.nodes.size && !batch.value.edges.size) batch.value = null;
      modified();
    }

    function deleteBatch(preserve = false) {
      const group = batch.value;
      if (!group || batchBlocked(group.nodes)) return;
      deleteObjects(new Set(group.nodes), preserve, group.edges);
    }

    // Mozgás közben (pásztázás, nagyítás, húzás) a drága szűrők (elmosás, glow, üvegpanelek) ki vannak kapcsolva;
    // a jelzés DOM-attribútum (data-moving), nem Vue-állapot, így nem rajzol újra semmit (PLAN.md C4).
    const movingSources = new Set();
    function markMoving(source, active) {
      if (active) movingSources.add(source); else movingSources.delete(source);
      const workspace = canvas.value?.closest?.(".editor-workspace");
      if (!workspace?.toggleAttribute) return;
      workspace.toggleAttribute("data-moving", movingSources.size > 0);
    }
    watch(() => !!gesture.value?.moved, moving => markMoving("gesture", moving));

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
      if (event.pointerType === "touch" && (!event.isPrimary || touchView)) {
        event.stopPropagation();
        return;
      }
      const touchPan = event.pointerType === "touch" && !panLocked.value && !reconnect.value &&
        !event.target.closest("[data-node], [data-edge]");
      if ((spacePan.value || touchPan) && event.button === 0) {
        beginDrag(event, "pan", {startView: view.value});
        return;
      }
      finishField();
      canDeselectOnClick = false;
      if (event.target.closest?.("[data-audio-player]")) return;
      if (event.target.closest("[role=link]")?.getAttribute?.("role") === "link") return;
      const hit = event.target.closest("[data-node], [data-edge]");
      if (event.button === 0 && !reconnect.value) {
        if (event.altKey && !hit) {
          if (!event.shiftKey) clearSelection();
          beginDrag(event, "rectangle", {additive: event.shiftKey, touching: event.ctrlKey});
          return;
        }
        if (event.shiftKey && !event.altKey && !event.ctrlKey && hit) {
          event.preventDefault();
          event.stopPropagation();
          const group = selectionMembers();
          const set = hit.dataset.node ? group.nodes : group.edges, id = hit.dataset.node ?? hit.dataset.edge;
          if (!set.delete(id)) set.add(id);
          selectMembers(group);
          return;
        }
        if (hit?.dataset?.endpoint) return;
        if (!event.altKey && !event.ctrlKey && batch.value && (batch.value.nodes.has(hit?.dataset?.node) || batch.value.edges.has(hit?.dataset?.edge))) {
          const members = new Set([...batch.value.nodes].flatMap(id => moveGroup(nodeMap.value.get(id)).map(n => n.id)));
          const hitEdge = edgeMap.value.get(hit.dataset.edge);
          const snapAnchor = nodeMap.value.get(hit.dataset.node)?.position ?? hitEdge?.sourcePoint ?? hitEdge?.target.point ??
            nodeMap.value.get(members.values().next().value)?.position;
          beginDrag(event, "batch", {members, snapAnchor, hitID: hit.dataset.node ?? hit.dataset.edge, hitKind: hit.dataset.node ? "node" : "edge"});
          return;
        }
      }
      rightPress = event.button === 2 && !event.ctrlKey;
      if (!reconnect.value && !hit) {
        if (event.ctrlKey && !event.altKey && [0, 2].includes(event.button) && online.value) {
          event.preventDefault();
          event.stopPropagation();
          menu.value = null;
          const initial = gridPoint(world(event));
          const source = {point: initial};
          gesture.value = {type: "cable", source, pointer: event.pointerId, initial, screen: [event.clientX, event.clientY], moved: false};
          preview.value = {edge: cablePreview(source, initial)};
          canvas.value.setPointerCapture(event.pointerId);
          return;
        }
        canDeselectOnClick = event.button === 0 && !event.ctrlKey;
      }
      if (event.button !== 0 || event.ctrlKey || !reconnect.value) return;
      event.preventDefault();
      event.stopPropagation();
      const {edgeID, end} = reconnect.value;
      const edge = edgeMap.value.get(edgeID);
      const endpoint = endpointAt(world(event), edge, end, true);
      if (endpoint.blocked) { problem.value = endpoint.blocked; return; }
      setEndpoint(edge, end, endpoint);
      pruneJunctions();
      reconnect.value = null;
      preview.value = null;
      modified();
      if (endpoint.createdJunction) openProperties("node", endpoint.node);
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
      if (key === "link") normalizePreview(item);
      modified();
    }

    function elevationButton(node, inMenu = false) {
      const blocked = item => !online.value || occupied(item.id) || ancestors(item, nodeMap.value).some(parent => parent.locked);
      return button("", async () => {
        if (inMenu) {
          menu.value = null;
          if (!await selectNode(node.id)) return;
        }
        const current = nodeMap.value.get(node.id);
        if (!current || blocked(current)) return;
        const elevated = current.elevated !== true;
        if (elevated) current.parent = undefined;
        updateItem(current, "elevated", elevated ? true : undefined);
      }, {symbol: "box-elevated", ...controlName("Kiemelés"), "aria-pressed": node.elevated === true, disabled: !!blocked(node),
        class: inMenu ? "button" : "button option-icon"});
    }

    function renameFile(node, stem) {
      const {extension} = fileNameParts(node.file, isImage(node));
      const filename = isImage(node) || !extension ? stem : stem + "." + extension;
      if (!validImageStem(filename)) { problem.value = "Érvénytelen fájlnév."; return false; }
      const previous = node.file;
      node.file = {...previous, filename};
      markDirty();
      transfer(() => enqueue(async () => {
        try {
          await commit();
          recordChanges();
        } catch (error) {
          const current = nodeMap.value.get(node.id);
          if (current?.file?.filename === filename) current.file = {...current.file, filename: previous.filename};
          if (!worksheetChanges(baseline, copy(board.value)).length) savedGeneration.value = generation.value;
          throw error;
        }
      }));
      return true;
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
            body: JSON.stringify(encodeWorksheet(submitted))});
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
          board.value = keepUnchanged(board.value, rebaseWorksheet(submitted, copy(board.value), saved));
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
      if (action === "resign" && !confirm("Visszaállítod a közös munkalapot a legutóbbi Mentéshez vagy a munkamenet elejéhez? Ez minden résztvevő vásznára érvényes. A visszaállítás során eltűnő fájlok a lomtárba kerülnek.")) return;
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
      if (destination.kind === "web") { openPresentation(destination.href); return; }
      if (destination.kind === "website") { openExternalLink(destination.href); return; }
      const target = new URL(destination.href, location.href);
      if (dirty.value) await save();
      if (!dirty.value) location.assign((target.pathname === "/" ? "/" : "/edit" + target.pathname) + target.search + target.hash);
    }

    function modifiers(event) {
      if (event.type === "keyup" && event.code === "Space") {
        spacePan.value = false;
        if (gesture.value?.type === "pan") gesture.value = null;
      }
      ctrl.value = event.ctrlKey;
      alt.value = event.altKey;
      shift.value = event.shiftKey;
    }
    function clearModifiers() { spacePan.value = false; ctrl.value = false; alt.value = false; shift.value = false; panning.value = false; }

    function keyboard(event) {
      modifiers(event);
      if (event.code === "Space" && !editingText(event.target) && (canvasPointer.value || !event.target?.closest?.("button, a"))) {
        event.preventDefault();
        spacePan.value = true;
        const drag = gesture.value;
        if (drag && drag.type !== "pan") {
          const screen = canvasPointer.value ? [canvasPointer.value.clientX, canvasPointer.value.clientY] : drag.screen;
          finishPointer({pointerId: drag.pointer}, true);
          gesture.value = {type: "pan", pointer: drag.pointer, screen, startView: view.value};
          canvas.value.setPointerCapture(drag.pointer);
        }
        return;
      }
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        sessionAction("checkpoint");
      }
      if (searchQuery.value !== null) {
        if (event.key === "Escape" || event.key === "Enter") {
          event.preventDefault?.();
          if (event.key === "Escape") closeSearch();
          else if (!event.repeat && !event.isComposing) {
            if (searchHistoryIndex.value >= 0) useSearchHistory(searchHistory[searchHistoryIndex.value]);
            else if (event.shiftKey) addSearchResult();
            else acceptSearch();
          }
        } else if (["ArrowUp", "ArrowDown"].includes(event.key)) {
          const up = event.key === "ArrowUp";
          if (!searchQuery.value.trim()) {
            event.preventDefault?.();
            if (!searchHistory.length) return;
            const index = searchHistoryIndex.value;
            const count = searchHistory.length;
            searchHistoryIndex.value = index < 0 ? (up ? count - 1 : 0) :
              (index + (up ? -1 : 1) + count) % count;
            scrollToSearchRow();
            return;
          }
          if (!searchHits.value.length) return;
          event.preventDefault?.();
          const hits = searchHits.value;
          const index = hits.indexOf(activeHit.value);
          const next = hits[(index + (up ? -1 : 1) + hits.length) % hits.length];
          if (event.shiftKey && candidates.value.has(hits[index].key)) {
            pinnedHits.value.set(hits[index].key, hits[index]);
          }
          activateHit(next);
          if (event.shiftKey) {
            pinnedHits.value.set(next.key, next);
            omittedKey.value = null;
          }
          scrollToSearchRow();
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
      if (event.key === "Enter" && !event.shiftKey && (canvasPointer.value || !event.target?.closest?.("button, a"))) {
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
        if (batch.value) { deleteBatch(event.ctrlKey); return; }
        const {kind, id} = selected.value;
        if (kind === "node" && nodeMap.value.has(id)) deleteNode(nodeMap.value.get(id), event.ctrlKey, event.ctrlKey);
        else if (edgeMap.value.has(id)) removeEdge(edgeMap.value.get(id));
        return;
      }
      if (event.key === "Escape") {
        const active = gesture.value;
        if (active) {
          finishPointer({pointerId: active.pointer}, true);
          if (canvas.value.hasPointerCapture?.(active.pointer)) canvas.value.releasePointerCapture(active.pointer);
        }
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
      touchView = null;
      if (gesture.value) finishPointer({pointerId: gesture.value.pointer}, true);
      canvasPointer.value = null;
      clearModifiers();
    }

    // A szerkesztő bezárása: mentetlen változásnál előbb ment, utána nyitja a megtekintőt.
    async function switchToViewer(event) {
      if (!dirty.value || event.button || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      const target = event.currentTarget.href;
      await save();
      if (!dirty.value) location.assign(target);
    }

    function beforeUnload(event) {
      if (!dirty.value) return;
      event.preventDefault();
      event.returnValue = "";
    }

    let audioControls;
    onMounted(async () => {
      window.addEventListener("copy", onCopy);
      window.addEventListener("paste", onPaste);
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
        watchPageUpdates(async (signal, incoming) => {
          const {response, page} = incoming ?? await fetchPage(signal);
          if (signal.aborted) return;
          if (response.status >= 500) throw Error("A munkalap nem érhető el.");
          const editor = page.querySelector("#editor");
          if (editor && editor.dataset.csrf === csrf) {
            updateSection(document, page, ".worksheet-nav .header-actions");
            live.start();
            if (canvasPanelOpen.value) await loadPreviewImages();
          } else if (!dirty.value) {
            location.reload();
          } else {
            live.start();
          }
        });
        await nextTick();
        initializeZoom();
        if (canvas.value.addEventListener) audioControls = bindAudioPlayers(canvas.value);
        if (canvas.value.querySelector) {
          const controls = mount.querySelector(".canvas-controls");
          mouse.bind(canvas.value, canvas.value.querySelector("[data-mouse-layer]"), controls, controls?.querySelector("[data-canvas-fullscreen]"));
        }
      } catch (error) {
        problem.value = error.message;
      }
    });

    function restore(event) { if (event.persisted) { held.value = null; clearSelection(); live.start(); } }

    onUnmounted(() => {
      audioControls?.abort();
      mouse?.stop();
      live.stop();
      window.removeEventListener("pagehide", live.stop);
      window.removeEventListener("pageshow", restore);
      resizeObserver?.disconnect();
      window.removeEventListener("copy", onCopy);
      window.removeEventListener("paste", onPaste);
      window.removeEventListener("keydown", keyboard);
      window.removeEventListener("keyup", modifiers);
      window.removeEventListener("blur", cancelGesture);
      window.removeEventListener("pointermove", outsideMove);
      window.removeEventListener("pointerup", outsideUp);
      window.removeEventListener("beforeunload", beforeUnload);
    });

    // Szövegfájl-objektumok tartalma (docs/node-types.md, text típus): a szöveg csak a fájlban van.
    // Kulcs: asset + változásszámláló; mentés után a `file.rev` nő, a többi kliens ebből tölti újra.
    const fileTexts = shallowRef(new Map());
    const fileSaveState = ref(new Map());
    const fileTextKey = (node, rev = node.file.rev ?? 0) => JSON.stringify([node.file.source ?? null, node.file.asset]) + "#" + rev;
    const pendingFileSaves = new Map();
    watch(() => (board.value?.nodes ?? []).filter(isTextFile).map(fileTextKey), async keys => {
      for (const key of new Set(keys)) {
        if (fileTexts.value.has(key)) continue;
        const [source, asset] = JSON.parse(key.slice(0, key.lastIndexOf("#")));
        fileTexts.value = new Map(fileTexts.value).set(key, null);
        try {
          const text = await (await checked(await fetch(fileURL(path, {source: source ?? undefined, asset})))).text();
          fileTexts.value = new Map(fileTexts.value).set(key, text);
        } catch (error) {
          const next = new Map(fileTexts.value);
          next.delete(key);
          fileTexts.value = next;
          problem.value = error.message;
        }
      }
    }, {immediate: true});

    function editFileText(node, text) {
      const key = fileTextKey(node);
      fileTexts.value = new Map(fileTexts.value).set(key, text);
      fileSaveState.value = new Map(fileSaveState.value).set(node.id, "Mentés…");
      clearTimeout(pendingFileSaves.get(node.id));
      pendingFileSaves.set(node.id, setTimeout(() => transfer(async () => {
        pendingFileSaves.delete(node.id);
        const current = nodeMap.value.get(node.id);
        if (!current?.file) return;
        const latest = fileTexts.value.get(fileTextKey(current)) ?? text;
        await checked(await fetch(attachmentURL(fileSheet(path, current.file), current.file.asset), {method: "PUT",
          headers: {"X-CSRF-Token": csrf, "Content-Type": "text/plain; charset=utf-8"}, body: latest}));
        const rev = (current.file.rev ?? 0) + 1;
        fileTexts.value = new Map(fileTexts.value).set(fileTextKey(current, rev), latest);
        if (held.value === current.id) updateItem(current, "file", {...current.file, rev});
        fileSaveState.value = new Map(fileSaveState.value).set(node.id, "Mentve");
      }), 1500));
    }


    function editOverlay(item, x, y, width, height) {
      if (editingObject.value !== item.id) return null;
      const key = editKey.value, inline = !objectPanelOpen.value;
      if (!inline && key === "text") return null;
      const background = automaticGridColor(paint(item.fill, 2));
      const light = parseInt(background.slice(1,3),16)*.299 + parseInt(background.slice(3,5),16)*.587 + parseInt(background.slice(5),16)*.114 > 150;
      return h("foreignObject", {class: "inline-edit", x, y, width, height, "pointer-events": inline ? "all" : "none",
        onPointerdown: e => e.stopPropagation(), onClick: e => e.stopPropagation(), onDblclick: e => e.stopPropagation()}, [
        h(key === "text" && !isJunction(item) ? "textarea" : "input", {value: inline ? inlineDraft.value : item[key] || "", onInput: e => { if (inline) inlineDraft.value = e.target.value; }, readonly: !inline, tabindex: inline ? 0 : -1,
          maxlength: key === "text" && !isJunction(item) ? 100000 : 120, style: {background, color: light ? "#101010" : "white"},
          onChange: e => {
            if (!inline) return;
            const target = key === "label" ? edgeMap.value.get(item.id) : nodeMap.value.get(item.id);
            if (!target || (key !== "label" && held.value !== item.id)) return;
            const value = e.target.value;
            updateItem(target, key, value);
          },
          onBlur: () => { if (inline) editingObject.value = null; },
          onKeydown: e => { e.stopPropagation(); if (e.key === "Enter" && !e.isComposing && !e.shiftKey) { e.preventDefault(); e.target.blur(); } }})
      ]);
    }
    // A link célja a szerkesztőben: külső / belső cím a worksheetLink szerint, .web mappa prezentációként.
    function linkDestination(link) {
      if (!link) return null;
      if (link.kind === "web") {
        const href = webPresentationURL(path, link.target);
        return href ? {kind: "web", href, preview: href + "_tn-preview"} : null;
      }
      const destination = worksheetLink(link.target, path);
      if (!destination) return null;
      if (link.kind === "sheet") return {...destination, preview: "/api/preview" + (destination.href === "/" ? "" : destination.href) + "?fill=1"};
      return {...destination, preview: "/api/link-preview?url=" + encodeURIComponent(link.target)};
    }

    function renderFileDownload(node, label = null, classes = "node-download") {
      const filename = nodeName(node);
      const href = isCommonFile(node.file) ? fileURL(path, node.file) : "/api/box-file/" + path + "?id=" + encodeURIComponent(node.id);
      const download = () => transfer(async () => { await enqueue(commit); location.assign(href); });
      return h("button", {type: "button", class: classes, title: filename,
        "aria-label": "Letöltés · " + filename,
        onPointerdown: event => event.stopPropagation(),
        onClick: event => { event.stopPropagation(); if (event.detail === 0 || classes !== "node-download") download(); },
        onDblclick: event => { event.stopPropagation(); download(); },
      }, [icon("package"), label ?? h("span", filename)]);
    }

    const stopScroll = e => {
      const el = e.currentTarget;
      if (el.scrollHeight > el.clientHeight || el.scrollWidth > el.clientWidth) e.stopPropagation();
    };
    // A görgethető tartalom (pl. CSV) bárhol megfogva mozgatható; csak a görgetősávokon (a jobb és alsó
    // ~14px-es sávban, ha van mit görgetni) marad a görgetés.
    const scrollbarPress = e => {
      const el = e.currentTarget, bounds = el.getBoundingClientRect();
      const scale = bounds.width / (el.offsetWidth || 1), band = 14;
      const point = e.touches?.[0] ?? e;
      const x = (point.clientX - bounds.left) / scale, y = (point.clientY - bounds.top) / scale;
      const vertical = el.scrollHeight > el.clientHeight && x >= el.offsetWidth - band;
      const horizontal = el.scrollWidth > el.clientWidth && y >= el.offsetHeight - band;
      if (vertical || horizontal) e.stopPropagation();
    };

    function renderFileText(node) {
      const text = fileTexts.value.get(fileTextKey(node));
      if (text == null) return h("p", {class: "muted"}, "…");
      const preview = text.slice(0, 200000);
      const ext = (node.file.filename ?? "").split(".").pop().toLowerCase();
      if (node.type === "csv") {
        const [head = [], ...rows] = parseCSV(preview, ext === "tsv" ? "\t" : ",");
        return h("table", {class: "node-csv"}, [
          h("thead", [h("tr", head.map(cell => h("th", cell)))]),
          h("tbody", rows.map(row => h("tr", row.map(cell => h("td", cell))))),
        ]);
      }
      if (node.type === "code") return h("pre", {class: "node-code"}, [h("code", preview)]);
      if (ext === "md" || ext === "markdown") return h(FormattedText, {source: preview, justified: node.justified});
      return h("pre", {class: ["node-plain", {"justified-text": node.justified}]}, preview);
    }

    // Fájlt tároló objektum (Rendering.swift fileBox): felül fájlnév, középen tartalom, alul megjegyzés.
    const fileNameSpace = 30, belowSpace = 400;
    function renderFileBox(node, destination) {
      const file = node.file, root = rootType(node.type);
      let content;
      if (root === "image") {
        content = h("img", {src: fileURL(path, file), alt: nodeName(node), draggable: false,
          class: file.asset.toLowerCase().endsWith(".svg") ? "is-svg" : undefined});
      } else if (root === "audio") {
        content = h("div", {"data-audio-player": "", class: "node-audio",
          onPointerdown: e => e.stopPropagation(), onDblclick: e => e.stopPropagation()}, [
          h("audio", {src: fileURL(path, file), preload: "metadata", hidden: true}),
          button("", null, {symbol: "play", "data-audio-toggle": "", "aria-label": "Lejátszás", title: "Lejátszás"}),
          h("input", {type: "range", min: 0, max: 0, step: "any", disabled: true, "data-audio-seek": "", "aria-label": "Lejátszási pozíció"}),
          h("small", {"data-audio-time": ""}, "0:00"),
          h("small", {"data-audio-status": "", role: "status"}),
        ]);
      } else if (root === "text") {
        content = h("div", {class: ["node-note", {"with-fold": backgroundMode(node) === "solid"}], style: {fontSize: (node.fontSize ?? 13) + "px"},
          onPointerdown: scrollbarPress, onMousedown: scrollbarPress, onTouchstart: scrollbarPress, onWheel: stopScroll},
          [renderFileText(node)]);
      } else {
        const ext = (file.filename ?? file.asset).split(".").pop().toUpperCase();
        content = h("div", {class: "node-document"}, [
          h("span", {class: "node-document-icon"}, [icon("package"), h("b", ext)]),
          renderFileDownload(node, "Letöltés", "node-download button small"),
        ]);
      }
      // A megjegyzés a legegyszerűbb formában: egy sor, formázás nélkül; a CSS rövidíti „…”-tal (Rendering.swift plainComment).
      // Text a doboz alatt: markdown formázott (összecsukva első sor + „…”).
      const comment = node.text?.trim()
        ? h("footer", {class: "node-comment align-" + (node.alignment ?? "center")}, [h(FormattedText, {source: visibleComment(node)})]) : null;
      const marker = node.link ? h("p", {class: "node-link-caption", "data-link-kind": node.link.kind,
        onPointerdown: e => { if (!e.altKey && !e.ctrlKey) e.stopPropagation(); },
        onClick: e => { e.stopPropagation(); if (destination) followBoxLink(destination); }},
        [icon(node.link.kind === "url" ? "website" : "link"), h("span", linkCaption(node.link))]) : null;
      // A doboz belsejében csak a tartalom van; a fájlnév a doboz felett, a link és a megjegyzés alatta áll.
      // Egyetlen foreignObject, normál (nem abszolút) elrendezéssel: a Safari így is jó helyre rajzolja,
      // és dobozonként csak egy HTML-réteget kell újraelrendezni nagyításkor.
      const below = marker || comment;
      return h("foreignObject", {class: "node-file-frame", x: -node.width / 2, y: -node.height / 2 - fileNameSpace, width: node.width,
        height: fileNameSpace + node.height + (below ? belowSpace : 0)}, [
        h("div", {class: "node-file-stack", style: {color: paint(node.textColor, 1)}}, [
          h("div", {class: "node-above", style: {height: fileNameSpace + "px"}},
            file.showFilename !== false ? [h("header", {class: "node-file-name"}, [renderFileDownload(node)])] : []),
          h("div", {class: ["node-file", "node-" + root], style: {height: node.height + "px"}}, [h("div", {class: "node-body"}, [content])]),
          below ? h("div", {class: "node-below"}, [marker, comment]) : null,
        ]),
      ]);
    }

    function renderLinkMarker(node, destination, above = false) {
      const [, , inset] = shapeLabelRatios(node.shape);
      const caption = linkCaption(node.link);
      // A link felirata a doboz alatt, a dobozon kívül áll.
      const available = Math.max(12, node.width - 22);
      // Egysoros felirat: ha nem fér el, „…”-tal rövidül (nincs tördelés, nincs összenyomás).
      const shownCaption = fitCaption(caption, 13, available);
      const shown = textWidth(shownCaption, 13);
      // Előnézetes doboznál a felirat a doboz felett áll (mint a fájlnév), egyébként alatta.
      const left = -(shown + 18) / 2, bottom = above ? -node.height / 2 - 6 : node.height / 2 + 20;
      const color = paint(node.textColor, 1);
      const iconPath = node.link.kind === "web" ? linkIcons.web : linkIcons[destination?.kind ?? "worksheet"];
      const open = e => { e.preventDefault(); e.stopPropagation(); if (destination) followBoxLink(destination); };
      return h("g", {class: "node-link", "data-link-kind": node.link.kind, role: "link", tabindex: 0, cursor: "pointer",
        "aria-label": "Hivatkozás megnyitása · " + caption,
        onPointerdown: e => { if (!e.altKey && !e.ctrlKey) e.stopPropagation(); },
        onClick: open, onKeydown: e => { if (e.key === "Enter") open(e); }}, [
        h("rect", {x: left - 4, y: bottom - 17, width: shown + 26, height: 20, fill: "transparent", stroke: "none"}),
        h("svg", {x: left, y: bottom - 14, width: 14, height: 14, viewBox: "0 0 24 24", fill: "none", stroke: color,
          "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round"}, [h("path", {d: iconPath})]),
        h("text", {x: left + 18, y: bottom - 2, "font-size": 13, fill: color, stroke: "none"}, shownCaption),
      ]);
    }

    // Publikus jog a .web mappán (szerver), a doboz `webPublic` mezője a pillangó ikonhoz tükrözi.
    function toggleWebPublic(node) {
      const reference = node.link.target, next = !node.webPublic;
      transfer(async () => {
        await setWebPublic(path, csrf, reference, next);
        for (const item of board.value.nodes) if (item.link?.kind === "web" && item.link.target === reference && !occupied(item.id)) {
          item.webPublic = next || undefined;
        }
        modified();
      });
    }

    // Publikus jog a fájlon (a tulajdonos lap mappájában); a `webPublic` mező a pillangó ikonhoz tükrözi.
    function toggleFilePublic(node) {
      const {asset, source} = node.file, next = !node.webPublic;
      transfer(async () => {
        await checked(await fetch("/api/file-public/" + fileSheet(path, node.file), {method: "PATCH",
          headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify({name: asset, publicAccess: next})}));
        for (const item of board.value.nodes) if (item.file?.asset === asset && item.file?.source === source && !occupied(item.id)) {
          item.webPublic = next || undefined;
        }
        modified();
      });
    }

    const previewRatios = new Map();
    function renderNode(node) {
      const drawn = node;
      const layout = nodeLayout(node);
      const position = displayPosition(node);
      const selectors = peers.value.filter(p => p.node === node.id && (!p.mine || (selected.value?.kind === "node" && selected.value.id === node.id)));
      const owner = selectors.find(p => !p.viewing) ?? selectors[0];
      // Két eset: a saját kijelölés (világosabb doboz, vastagabb keret, glow nélkül) és a többi
      // felhasználó kijelölése (az ő színükkel pulzáló glow, ahogy eddig).
      const peerOwner = selectors.find(p => !p.mine && !p.viewing) ?? selectors.find(p => !p.mine);
      const ownSelected = selectors.some(p => p.mine) || !!batch.value?.nodes.has(node.id) || !!marqueeHits.value?.nodes.has(node.id);
      const destination = linkDestination(node.link);
      const junction = isJunction(node);

      const textDrag = gesture.value?.type === "text" && gesture.value.nodeID === node.id ? gesture.value : null;
      const [, , inset] = shapeLabelRatios(node.shape);
      const [outline, dimensions] = selectionOutline(junction ? graphics.value.junction ?? "ellipse" : drawn.shape, drawn.width, drawn.height);
      const snapTarget = (preview.value?.target ?? junctionTarget.value) === node.id;
      const strong = false;  // a Félkövér/Dőlt/Aláhúzott gombok megszűntek; a markdown formázás marad
      const labels = layout.lines.length ? h("text", {class: "node-text", "font-family": fontFamily(node.font), "pointer-events": "none"},
          layout.lines.map(line => h("tspan", {
            "data-body-row": "",
            "pointer-events": "visiblePainted", cursor: alt.value && ctrl.value ? "text" : undefined,
            onPointerdown: e => {
              if (!e.ctrlKey || !e.altKey || ![0,2].includes(e.button) || occupied(node.id) || ancestors(node,nodeMap.value).some(n => n.locked)) return;
              const rows = Array.from(e.currentTarget.parentNode?.querySelectorAll?.("[data-body-row]") ?? [], row => row.getBBox());
              const bounds = rows.length ? {
                left: Math.min(...rows.map(r => r.x)), right: Math.max(...rows.map(r => r.x+r.width)),
                top: Math.min(...rows.map(r => r.y)), bottom: Math.max(...rows.map(r => r.y+r.height)),
              } : undefined;
              beginDrag(e,"text",{nodeID: node.id, bounds});
              claimGesture(node);
            },
            x: line.x + (textDrag ? textDrag.delta.x : 0),
            y: line.y + (textDrag ? textDrag.delta.y : 0), "text-anchor": line.anchor,
            "data-justify": line.justifyWidth, fill: paint(line.color, 1), "font-size": line.size, "font-weight": line.weight,
          }, line.runs.map(run => {
            const format = run.format || {};
            if (!format.bold && !format.italic && !format.code && !format.link) return run.text;
            return h("tspan", {"font-weight": format.bold ? (strong ? 900 : 700) : undefined,
              "font-size": format.bold && strong ? line.size * 1.1 : undefined,
              "font-style": format.italic ? "italic" : undefined, "font-family": format.code ? "monospace" : undefined,
              "xml:space": format.code ? "preserve" : undefined,
              "text-decoration": format.link ? "underline" : undefined}, run.text);
          })))) : null;
      const webClip = "web-clip-" + node.id;
      // Előnézet a doboz arányában (0,05-ös lépés, Rendering.swift); húzás közben a korábbi kép marad, elengedéskor új renderelés.
      const ratio = (Math.round(Math.min(Math.max(drawn.width / Math.max(1, drawn.height), .25), 6) * 20) / 20).toFixed(2);
      if (!gesture.value || !previewRatios.has(node.id)) previewRatios.set(node.id, ratio);
      const linkPreview = isBox(node) && destination?.preview && layout.webPreview ? h("g", {"pointer-events": "none"}, [
        h("clipPath", {id: webClip}, [h(...boxShapeGeometry(drawn))]),
        h("image", {class: "node-link-preview node-site-preview", href: node.link.kind !== "web" ? destination.preview : destination.preview + "?ratio=" + previewRatios.get(node.id) + (node.staticPreview ? "&live=0" : ""),
          x: -drawn.width/2, y: -drawn.height/2, width: Math.max(1, drawn.width), height: Math.max(1, drawn.height),
          preserveAspectRatio: "xMidYMid slice", "clip-path": "url(#" + webClip + ")"})])
      : isBox(node) && destination?.preview && layout.previewSpace ? h("image", {class: "node-link-preview",
        href: destination.preview, x: -drawn.width/2*inset + 6, y: -drawn.height/2*inset + 6,
        width: Math.max(1, drawn.width*inset - 12), height: Math.max(1, layout.previewSpace - 6),
        preserveAspectRatio: "xMidYMid meet", "pointer-events": "none"}) : null;
      // Publikus .web: pillangó ikon a doboz felett középen.
      const publicMark = (node.link?.kind === "web" || node.file) && node.webPublic ? h("svg", {class: "ui-icon web-public-mark", "pointer-events": "none",
        x: -10, y: -drawn.height/2 - (node.file ? 54 : node.type === "preview" ? 44 : 26), width: 20, height: 20, viewBox: "0 0 24 24", color: paint(node.textColor, 1)},
        [h("use", {href: "/icons.svg#butterfly"})]) : null;
      const junctionLabel = junction && node.text ? h("g", {class: "node-label-turn", transform: "rotate(" + (node.angle ?? 0) + ")"}, [
        h("text", {class: "node-label", x: drawn.width/2 + 4, y: 4, fill: paint(node.textColor, 1), "font-size": 14}, node.text)]) : null;
      return h("g", {key: node.id, "data-node": node.id, "data-type": node.type, "data-width": drawn.width, "data-height": drawn.height, tabindex: 0,
        role: rootType(node.type) === "audio" ? "group" : "button",
        "aria-label": nodeName(node), "data-link": destination ? "" : undefined,
        class: [nodeClasses(node, containerIDs.value.has(node.id)), {"editing-object": editingObject.value === node.id, occupied: occupied(node.id), claimed: !!owner, "own-selected": ownSelected}],
        // A saját kijelölés glow-ja (CSS drop-shadow currentColor) a kijelölés színét veszi fel.
        color: ownSelected ? selectionTint() : undefined,
        transform: "translate(" + position.x + " " + position.y + ")",
        onPointerenter: event => {
          // Buboréksúgó: túl hosszú doboz-szöveg, illetve összecsukott többsoros megjegyzés (fájl- és előnézetes doboz).
          const tooltip = node.file || node.type === "preview" ? commentCollapsed(node) : isBox(node) && layout.overflow;
          if (!gesture.value && tooltip && node.text) showTooltip(event, async signal => {
            const result = await checked(await fetch("/api/text", {method: "POST", signal,
              headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify({text: node.text})}));
            return result.text();
          }, node.justified, {background: paint(node.fill, 2), color: paint(node.textColor, 1)});
        },
        onPointerleave: hideTooltip,
        onPointerdown: event => { hideTooltip(); pressNode(event, node); },
        onDblclick: event => {
          event.stopPropagation();
          // Előnézetes (linkes) doboz: dupla kattintás megnyitja a linket; Alt-tal a szerkesztés marad.
          if (node.type === "preview" && destination && !event.altKey) { followBoxLink(destination); return; }
          editObject("node", node.id, event.altKey ? "text" : true);
        },
        onContextmenu: event => context(event, "node", node.id),
        onKeydown: event => {
          if (event.key === "Enter" && event.shiftKey) openProperties("node", node.id);
        },
      }, [
        peerOwner || snapTarget ? h(outline, {"data-editor-only": "", ...dimensions, class: "selection-glow", color: peerOwner ? peerOwner.color : selectionTint(), fill: "none",
          stroke: peerOwner ? peerOwner.color : selectionTint(), "stroke-width": 3, "pointer-events": "none"}) : null,
        // Saját kijelölés látható felület nélküli objektumon (Free doboz, átlátszó kép, csomópont): vékony, nyugodt körvonal.
        ownSelected && !peerOwner && (junction || backgroundMode(node) === "free" || isImage(node))
          ? h(outline, {"data-editor-only": "", ...dimensions, class: "selection-own", color: selectionTint(), fill: "none", stroke: selectionTint(), "stroke-width": 2.5, "pointer-events": "none"}) : null,
        candidates.value.has("node/" + node.id) ? h(outline, {"data-editor-only": "", ...dimensions, class: "search-candidate", "stroke-width": 3}) : null,
        ...animateBox(isBox(node) ? node.animation : undefined, [
          elevationShadow(drawn),
          shape(drawn, !!destination, containerDropTargets.value.has(node.id)),
          node.file ? renderFileBox(node, destination) : null,
          junctionLabel,
          linkPreview,
          publicMark,
          // A szöveg közvetlenül a doboz csoportjában van (nincs dobozonkénti vágás): az elrendezés eleve a dobozon belül tartja.
          labels,
          editingObject.value === node.id ? editOverlay(node, -drawn.width/2,
            junction ? -14 : (layout.lines[0]?.y ?? (node.file ? drawn.height/2 - 20 : 0)) - 18,
            drawn.width, editKey.value === "text" && !junction ? Math.max(34, drawn.height/2) : 28) : null,
          isBox(node) && node.link ? renderLinkMarker(drawn, destination, node.type === "preview") : null,
          node.type === "preview" && node.text?.trim() ? h("foreignObject", {x: -drawn.width/2, y: drawn.height/2, width: drawn.width, height: 4000,
            "pointer-events": "none"}, [h("div", {class: "node-below", style: {color: paint(node.textColor, 1)}}, [
              h("footer", {class: "node-comment align-" + (node.alignment ?? "center")}, [h(FormattedText, {source: visibleComment(node)})])])]) : null,
        ]),
        ...(resizeTarget.value === node.id && gesture.value?.type !== "rectangle" && !occupied(node.id) && !ancestors(node, nodeMap.value).some(n => n.locked)
          ? [[-1,-1], [1,-1], [1,1], [-1,1]].map(([sx, sy]) => {
            const r = 5 / zoomScale.value;
            return h("rect", {"data-editor-only": "", class: "node-handle", x: sx*drawn.width/2-r, y: sy*drawn.height/2-r,
              width: 2*r, height: 2*r, fill: "#ffffff", stroke: "#4168e9", "stroke-width": 1 / zoomScale.value,
              cursor: sx === sy ? "nwse-resize" : "nesw-resize", onPointerdown: e => pressCorner(e, node, sx, sy)});
          }) : []),
      ]);
    }

    function renderJunctionHandles() {
      // Transparent centers keep junctions reachable under the wires' wider hit areas.
      const handles = orderedNodes.value.filter(isJunction).map(node => {
        const drawn = drawnNode(node.id);
        return h("circle", {key: node.id, "data-node": node.id,
          cx: drawn.position.x, cy: drawn.position.y, r: drawn.width/2, fill: "transparent",
          class: "junction-handle", onPointerdown: event => pressNode(event,node),
          onContextmenu: event => context(event,"node",node.id),
          onDblclick: event => { event.stopPropagation(); editObject("node",node.id,true); }});
      });
      return h("g", {"data-editor-only": ""}, handles);
    }

    function renderArrow(head, color, animated = false) {
      if (!head.visible) return null;
      return h("path", {class: "wire-arrow", transform: head.transform, stroke: "none", fill: color, "pointer-events": "none", d: "M0 0L-1 -.5V.5Z"},
        animated ? [h("animateTransform", {attributeName: "transform", type: "scale", additive: "sum",
          values: "1;1.12;1", dur: "3s", repeatCount: "indefinite"})] : undefined);
    }

    function endpointHandle(edge, end, point) {
      return h("circle", {key: end + "/" + edge.id, transform: "translate(" + point.x + " " + point.y + ")",
        r: 10 / zoomStep.value, fill: "transparent", tabindex: -1, "pointer-events": alt.value ? "none" : "all",
        "data-edge": edge.id, "data-endpoint": end, class: edgeEndpoint(edge, end).node ? "wire-handle is-attached" : "wire-handle",
        onPointerdown: event => pressEndpoint(event, edge, end),
        onContextmenu: event => context(event, "edge", edge.id),
        onClick: event => event.stopPropagation(),
        onDblclick: event => { event.stopPropagation(); editObject("edge", edge.id, true); },
      });
    }

    // A vonal húzás közbeni (csoportos mozgatás, végpont húzása) megjelenített változata.
    function displayedEdge(original) {
      let edge = original;
      const drag = gesture.value;
      if (drag?.type === "batch" && batch.value?.edges.has(edge.id)) edge = moveBatchEdge(edge,drag);
      if (drag?.edgeID === edge.id && drag.endPosition) {
        edge = {...edge};
        setEndpoint(edge, drag.end, preview.value?.attachment ?? {point: drag.endPosition});
      }
      return edge;
    }

    function selectedEdge(edge) {
      return selected.value?.id === edge.id && ["edge","endpoint"].includes(selected.value.kind);
    }

    function renderEdge(original) {
      const edge = displayedEdge(original);
      const geometry = wireGeometry(edge);
      const {d, from, to} = geometry;
      const {stroke, ends, paint, taper} = cachedWireDrawing(edge, geometry);
      const label = edge.label?.trim() ? wireLabelLayout(geometry, edge.label, paint, edge.labelInLine) : null;
      const clipId = "editor-wire-gap-" + edge.id;
      const clipPath = label?.clip ? "url(#" + clipId + ")" : undefined;
      const mine = selectedEdge(edge);
      const animatedArrows = edge.animated && edge.appearance === "thick";
      // Saját kijelölés: világosabb és vastagabb vonal; más felhasználó kijelölése: az ő színű glow.
      const local = mine || batch.value?.edges.has(edge.id) || marqueeHits.value?.edges.has(edge.id);
      const selectionColor = peers.value.find(peer => !peer.mine && peer.edge === edge.id)?.color;
      // Kijelöléskor a vonal és a nyilak megőrzik az eredeti színüket; a felhasználó színű glow az eredeti alakot követi.
      const color = paint.color;
      const animation = animatedWire(edge, {...paint, color}, from, to, taper, stroke.d);
      const shaftColor = animation.color ?? color;
      return h("g", {key: "edge/" + edge.id, class: "wire", "data-edge": edge.id, fill: "none", "stroke-linecap": "round",
        tabindex: 0, role: "button", "aria-label": edge.label || "Vonal",
        onPointerdown: event => {
          if (event.button !== 0) return;
          event.preventDefault();
          if (event.shiftKey || reconnect.value || !online.value) return;
          event.currentTarget.focus({preventScroll: true});
          const pathElement = event.currentTarget.querySelector(".wire-hit");
          const length = pathElement.getTotalLength();
          const point = world(event);
          const distance = t => {
            const p = pathElement.getPointAtLength(t);
            return Math.hypot(p.x-point.x, p.y-point.y);
          };
          let nearest = 0, best = distance(0);
          function probe(t) {
            const candidate = distance(t);
            if (candidate < best) {
              nearest = t;
              best = candidate;
            }
          }
          for (let i = 1; i <= 16; i++) probe(length * i / 16);
          for (let step = length/32; step > .1/zoomScale.value; step /= 2) {
            const left = Math.max(0, nearest-step), right = Math.min(length, nearest+step);
            probe(left);
            probe(right);
          }
          if (!event.ctrlKey) {
            if (nearest <= length/3 || nearest >= 2*length/3) pressEndpoint(event,edge,nearest <= length/3 ? "source" : "target", true);
            return;
          }
          if (Math.min(nearest, length-nearest) < 8/view.value.k) return;
          const p = pathElement.getPointAtLength(nearest);
          const joint = {...makeNode(clampPoint(p), "junction"), shape: "ellipse",
            width: graphics.value.junctionSize ?? 12, height: graphics.value.junctionSize ?? 12, fill: edge.color ?? 3};
          const tail = {...edge, id: id(), source: joint.id, sourcePoint: undefined, startArrow: false, label: ""};
          const head = {...copy(edge), target: {node: joint.id}, endArrow: false};
          beginDrag(event,"split",{edgeID: edge.id});
          stageInsertion({nodes: [joint], edges: [head,tail], original: copy(edge)});
        },
        onClick: event => { if (event?.ctrlKey || event?.shiftKey || batch.value?.edges.has(edge.id)) return; selectNode(null, edge.id); inspectNothing(); selected.value = {kind: "edge", id: edge.id}; },
        onDblclick: event => {
          event.stopPropagation();
          editObject("edge", edge.id, true);
        },
        onContextmenu: event => context(event, "edge", edge.id),
      }, [
        label?.clip ? h("defs", [h("clipPath", {id: clipId}, [
          h("path", {d: label.clip, transform: label.transform}),
        ])]) : null,
        candidates.value.has("edge/" + edge.id) ? h("path", {"data-editor-only": "", d: taper ? d : stroke.d, class: "search-candidate", "clip-path": clipPath,
          "stroke-width": paint.lineWidth + 9 / zoomScale.value}) : null,
        animation.gradient ? h("defs", [animation.gradient]) : null,
        h("path", {"data-editor-only": "", d, stroke: "transparent", "stroke-width": Math.max(paint.lineWidth + 10, 14 / zoomStep.value),
          "pointer-events": "stroke", class: "wire-hit"}),
        // Kijelölés: a meglévő vonal, nyilak és animáció kap árnyék alapú glow-t, így a jelzés pontosan az eredeti geometriát követi.
        h("g", {class: {"wire-own": local, "wire-glow": !!selectionColor}, style: selectionColor || local ? {color: selectionColor ?? paint.color} : undefined}, [
          h("path", {class: "wire-line", ...stroke, ...(taper ? {fill: shaftColor} : {stroke: shaftColor}), "pointer-events": "none", "clip-path": clipPath}, animation.shaft ? [animation.shaft] : undefined),
          renderArrow(ends.source, color, animatedArrows),
          renderArrow(ends.target, color, animatedArrows),
        ]),
        label ? h("text", {transform: label.transform, y: label.y, textLength: label.textLength,
          "dominant-baseline": label.clip ? "central" : undefined,
          "font-family": "system-ui, sans-serif", "font-size": label.fontSize, "font-weight": label.fontWeight, "text-anchor": "middle",
          stroke: "none", fill: paint.color, class: "wire-label"}, edge.label) : null,
        editingObject.value === edge.id ? editOverlay(original, geometry.labelPosition.x-80, geometry.labelPosition.y-30,160,28) : null,
      ]);
    }

    // Dobozonként külön komponens: a doboz csak akkor rajzolódik újra, ha a saját adatai vagy az általa olvasott
    // állapot változik (gépelés, húzás egy dobozon nem építi újra a többi doboz virtuális DOM-ját). PLAN.md C1.
    const NodeView = {
      props: {node: Object},
      setup(props) {
        const instance = getCurrentInstance();
        // Sorkizárás: a szóközöket a böngészőben mért sorszélesség alapján tágítjuk (Public/justify.js).
        const justify = () => justifyRows(instance.proxy.$el);
        onMounted(justify);
        onUpdated(justify);
        return () => renderNode(props.node);
      },
    };

    // Vonalanként külön komponens: húzáskor csak a mozgatott dobozhoz kötött vonalak rajzolódnak újra. PLAN.md C1.
    const EdgeView = {
      props: {edge: Object},
      setup: props => () => renderEdge(props.edge),
    };

    // A végpontok és csomópontok fogantyúi a vonalak és dobozok fölött, külön komponensben:
    // a nagyításfüggő méretük miatt nagyításkor csak ez a réteg rajzolódik újra.
    // Egy vonal két végpont-fogantyúja; csak a saját vonala geometriájától és a nagyítástól függ.
    const EdgeHandles = {
      props: {edge: Object},
      setup: props => () => {
        const {from, to} = wireGeometry(displayedEdge(props.edge));
        return [endpointHandle(props.edge, "source", from), endpointHandle(props.edge, "target", to)];
      },
    };
    const JunctionHandles = {setup: () => () => renderJunctionHandles()};
    const HandleLayer = {
      setup: () => () => {
        const edges = wireLayers.value.flat();
        // A kijelölt vonal fogantyúi kerülnek legfelülre.
        const ordered = [...edges.filter(edge => !selectedEdge(edge)), ...edges.filter(selectedEdge)];
        // Keep the clickable endpoints above the boxes without changing the wire's paint order.
        return [h("g", {"data-editor-only": "", "data-endpoint-handles": ""},
          ordered.map(edge => h(EdgeHandles, {key: edge.id, edge}))), h(JunctionHandles)];
      },
    };

    const CanvasScene = {
      setup: () => () => {
        const layers = wireLayers.value;
        const children = [];
        const addEdge = edge => children.push(h(EdgeView, {key: "edge/" + edge.id, edge}));
        orderedNodes.value.forEach((node, index) => {
          layers[index].forEach(addEdge);
          children.push(h(NodeView, {key: node.id, node}));
        });
        layers.at(-1).forEach(addEdge);
        children.push(h(HandleLayer, {key: "handles"}));
        return h("g", {"data-scene": ""}, children);
      },
    };

    function dragCursor() {
      if (spacePan.value) return gesture.value?.type === "pan" ? "grabbing" : "grab";
      const active = gesture.value;
      if (active?.type === "resize") return active.sx === active.sy ? "nwse-resize" : "nesw-resize";
      if (active?.type === "rectangle") return "crosshair";
      if (active?.type === "move") return active.locked ? undefined : "move";
      if (active?.moved && !active.locked && !active.waiting) {
        return ["move", "batch", "clone", "text", "split"].includes(active.type) ? "move" : "grabbing";
      }
      return panning.value ? "grabbing" : undefined;
    }

    // A nézet (pásztázás, nagyítás) és a húzás közbeni előnézetek külön komponensben: így a nagyítás és a
    // pásztázás nem rajzolja újra a teljes felületet (fejléc, panelek, ellenőrző). PLAN.md C2/C3.
    const ViewLayer = {
      setup: () => () => {
        const [centerX, centerY] = center();
        const cable = preview.value?.edge;
        const shown = cable ? wireDrawing({...cable, color: "#4168e9"}, wireGeometry(cable)) : null;
        return h("g", {transform: view.value + " translate(" + centerX + " " + centerY + ")"}, [
            h("path", {"data-editor-only": "", "pointer-events": "none", stroke: "#aab9cf", "stroke-width": 1,
              d: "M -8 0 H 8 M 0 -8 V 8"}),
            h(CanvasScene),
            preview.value?.junction ? h("circle", {"data-editor-only": "", cx: preview.value.junction.x, cy: preview.value.junction.y,
              r: 9 / view.value.k, stroke: "#078469", fill: "#b9f3e1", "stroke-width": 2 / view.value.k, "pointer-events": "none"}) : null,
            shown ? h("g", {"pointer-events": "none"}, [h("path", shown.stroke),
              renderArrow(shown.ends.source, shown.paint.color), renderArrow(shown.ends.target, shown.paint.color)]) : null,
            gesture.value?.type === "rectangle" ? h("rect", {class: "marquee", ...rectangle(gesture.value.initial,gesture.value.point),
              "stroke-dasharray": rectangleTouches(gesture.value) ? "6 4" : undefined,
              fill: "#4168e922", stroke: "#4168e9", "vector-effect": "non-scaling-stroke", "pointer-events": "none"}) : null,
            mouse ? h("g", {class: "peer-cursors", "data-mouse-layer": ""}) : null,
          ]);
      },
    };

    // A háttérrács külön SVG-réteg a vászon alatt: nagyítás/pásztázás közben a mintája közvetlenül követi a mozdulatot
    // (previewView), így a vászonréteg szélén is mindig látszik.
    const GridLayer = {
      setup: () => () => {
        const [centerX, centerY] = center();
        const spacing = gridSpacing.value;
        const {grid, glass} = graphics.value;
        const drafting = grid === "drafting";
        const lined = drafting || grid === "lines";
        const gridSize = drafting ? spacing * 5 : spacing;
        const gridLine = at => `M0 ${at} H${gridSize} M${at} 0 V${gridSize}`;
        const gridStroke = {stroke: "#789bb0", fill: "none"};
        return h("svg", {class: "canvas-grid-layer", "aria-hidden": "true", "data-editor-only": ""}, [
          h("defs", [
            h("pattern", {id: "worksheet-grid", patternUnits: "userSpaceOnUse", x: -spacing/2, y: -spacing/2, width: gridSize, height: gridSize,
              patternTransform: view.value + " translate(" + centerX + " " + centerY + ")"}, [
              ...(drafting ? [h("path", {...gridStroke, "stroke-opacity": .08, d: [1, 2, 3, 4].map(i => gridLine((i + .5) * spacing)).join(" ")})] : []),
              lined
                ? h("path", {...gridStroke, "stroke-opacity": .22, d: gridLine(spacing/2)})
                : h("circle", {cx: spacing/2, cy: spacing/2, r: glass ? 1 : 1.1, fill: glass ? "#a397bf" : gridColor.value,
                  "fill-opacity": glass ? .24 : .28}),
            ]),
          ]),
          gridVisible.value ? h("rect", {class: "canvas-grid", width: "100%", height: "100%", fill: "url(#worksheet-grid)"}) : null,
        ]);
      },
    };

    function renderCanvas() {
      const {grid, glass} = graphics.value;
      const lined = grid === "drafting" || grid === "lines";
      // A háttér a munkalap színe (a rács alatt); a vászonréteg átlátszó.
      return h("div", {class: "canvas-area", style: {background: paint(board.value.background, 0), "--overscan": overscan}}, [
        h(GridLayer),
        h("svg", {ref: canvas, class: ["canvas", "editor-canvas", {"ctrl-held": ctrl.value, "alt-held": alt.value}],
          "data-drag-cursor": dragCursor(), "aria-label": "Ötletvászon",
          onContextmenu: event => context(event),
          onClickCapture: event => { if (spacePan.value) { event.preventDefault(); event.stopPropagation(); } },
          onClick: event => {
            // D3 suppresses the click after a pan.
            if (canDeselectOnClick && !event.target.closest("[data-node], [data-edge]")) clearSelection();
            canDeselectOnClick = false;
          },
          onDblclickCapture: event => { if (spacePan.value) { event.preventDefault(); event.stopPropagation(); } },
          onDblclick: event => {
            if (spacePan.value || event.button !== 0 || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey ||
                gesture.value || reconnect.value || event.target.closest("[data-node], [data-edge]")) return;
            addNode(world(event));
          },
          onDragover: event => {
            const types = event.dataTransfer.types;
            if (types.includes("Files") || types.includes("text/uri-list") || types.includes("text/plain")) event.preventDefault();
          },
          onDrop: event => {
            event.preventDefault();
            const files = Array.from(event.dataTransfer.files), point = world(event);
            if (files.length) { transfer(() => importFiles(files, point)); return; }
            const dropped = (event.dataTransfer.getData("text/uri-list") || event.dataTransfer.getData("text/plain"))
              .split(/\r?\n/).find(line => line && !line.startsWith("#")) ?? "";
            const href = externalURL(dropped);
            if (href && online.value) addLinkBox(href, point);
          },
          onTouchstartCapture: startTouchView,
          onTouchmoveCapture: moveTouchView,
          onTouchendCapture: endTouchView,
          onTouchcancelCapture: endTouchView,
          onPointerdownCapture: pressCanvas,
          onPointerenter: rememberCanvasPointer,
          onPointermove: event => { rememberCanvasPointer(event); updatePointer(event); },
          onPointerleave: () => { canvasPointer.value = null; },
          onPointerup: event => finishPointer(event),
          onPointercancel: event => finishPointer(event, true),


        }, [
          h("defs", [
            sceneNodes.value.some(node => backgroundMode(node) === "blurred")
              ? h("filter", {id: "box-background-blur", x: "-30%", y: "-30%", width: "160%", height: "160%"}, [h("feGaussianBlur", {stdDeviation: 2})]) : null,
            ...(glass ? [
              h("linearGradient", {id: "glass-rim", x2: "25%", y2: "100%"}, [
                h("stop", {offset: "0%", "stop-color": "#f4eeff", "stop-opacity": .93}),
                h("stop", {offset: "40%", "stop-color": "#b39bd8", "stop-opacity": .72}),
                h("stop", {offset: "76%", "stop-color": "#6e5a98", "stop-opacity": .62}),
                h("stop", {offset: "100%", "stop-color": "#ab91df", "stop-opacity": .78}),
              ]),
              h("linearGradient", {id: "glass-sheen", x2: "0%", y2: "100%"}, [
                h("stop", {offset: "0%", "stop-color": "#fff", "stop-opacity": .30}),
                h("stop", {offset: "34%", "stop-color": "#fff", "stop-opacity": .08}),
                h("stop", {offset: "58%", "stop-color": "#fff", "stop-opacity": 0}),
                h("stop", {offset: "100%", "stop-color": "#a58ade", "stop-opacity": .17}),
              ]),
            ] : []),
          ]),
          h("g", {ref: sceneOrigin, transform: "translate(" + margin().join(" ") + ")"}, [h(ViewLayer)]),
          spacePan.value ? h("rect", {width: "100%", height: "100%", fill: "none",
            "pointer-events": "all", "aria-hidden": "true", "data-editor-only": ""}) : null,
        ]),
        // A létrehozó neve nem jelenik meg a vásznon (a megtekintő cím sorában látszik); itt csak a jelenlévők.
        h("div", {class: "canvas-people"}, [
          h("div", {class: "participants", "aria-label": "Jelenlévők"},
            !online.value && problem.value ? h("span", {class: "connection-lost", role: "status"}, "Kapcsolat megszakadt") : peers.value.map((p, index) =>
              // A jelenlévők gombok; egyelőre nem csinálnak semmit (később: chatüzenet küldése).
              h("button", {key: index, type: "button", class: "button tool-button participant", title: p.name,
                onPointerdown: event => event.stopPropagation()},
                [p.avatar ? h("img", {class: "peer-avatar", src: "/icons/avatar-" + p.avatar + ".svg", alt: ""}) : null, p.name]))),
        ]),
        h("div", {class: "canvas-controls", "data-open": toolbarOpen.value}, [
          button("", () => { toolbarOpen.value = !toolbarOpen.value; }, {symbol: toolbarOpen.value ? "left" : "right",
            "aria-label": "Eszköztár", "aria-expanded": toolbarOpen.value}),
          button("", toggleGrid, {
            title: lined ? "Saját rács megjelenítése" : "Saját pontrács megjelenítése",
            "aria-label": lined ? "Rács" : "Pontrács", "aria-pressed": gridVisible.value, symbol: "grid"}),
          button("", () => { snapToGrid.value = !snapToGrid.value; savePreferences(); }, {title: "Rácsra igazítás", "aria-label": "Rácsra igazítás", "aria-pressed": snapToGrid.value, symbol: "snap"}),
          button("", () => { panLocked.value = !panLocked.value; savePreferences(); },
            {symbol: "hand", title: "Vászonmozgatás zárolása", "aria-label": "Vászonmozgatás zárolása", "aria-pressed": panLocked.value}),
          button("", fit, {"aria-label": "Mind", title: "A teljes vászon megjelenítése", symbol: "fit-objects"}),
          button("", () => transfer(async () => {
            if (document.fullscreenElement) await document.exitFullscreen();
            else await document.documentElement.requestFullscreen();
          }), {symbol: "fit", title: "Teljes képernyő", "aria-label": "Teljes képernyő", "data-canvas-fullscreen": ""}),
        ]),
        board.value && !board.value.nodes.length ? h("p", {class: "canvas-empty"}, "Új dobozhoz kattints duplán az üres vászonra.") : null,
      ]);
    }

    function ping(target) {
      menu.value = null;
      if (target.point) flashPoint(canvas.value?.querySelector("[data-scene]"), target.point);
      else flashNode(canvas.value, target.node);
      live.ping(target).catch(error => { problem.value = error.message; });
    }

    // .web link ZIP-feltöltéssel jön létre (canvas-files.js importFile).
    const linkKinds = [["sheet", "Másik munkalap", "file"], ["url", "Külső cím", "link"]];

    // Link hozzáadása (docs/node-types.md, link képesség): a fajtát rögtön meg kell adni.
    // Link hozzáadása a közös tallózó ablakkal: munkalap, .web oldal vagy külső webcím.
    async function addLink(node) {
      const choice = await openFileBrowser(path, csrf, {link: true});
      if (!choice || !await selectNode(node.id)) return;
      const current = nodeMap.value.get(node.id);
      if (!current || held.value !== node.id || !online.value) return;
      if (choice.kind === "url") {
        const target = externalURL(choice.target);
        if (!target) { problem.value = "Érvénytelen webcím."; return; }
        updateItem(current, "link", {kind: "url", target});
      } else if (choice.kind === "sheet") {
        if (worksheetLink(choice.target, path)?.kind !== "worksheet") { problem.value = "Érvénytelen hivatkozás."; return; }
        updateItem(current, "link", {kind: "sheet", target: choice.target});
      } else updateItem(current, "link", {kind: "web", target: choice.target});
    }

    async function removeLink(node) {
      if (!confirm("Törlöd a linket?\n" + linkCaption(node.link))) return;
      if (!await selectNode(node.id)) return;
      const current = nodeMap.value.get(node.id);
      if (current) updateItem(current, "link", undefined);
    }

    function chooseLink(node) {
      menu.value = null;
      transfer(() => addLink(node));
    }

    function renderMenu() {
      const open = menu.value;
      if (!open) return null;
      const node = nodeMap.value.get(open.id);
      const edge = board.value?.edges.find(item => item.id === open.id);
      const type = open.kind;
      const entries = type === "node" && node ? [
        node.file ? button("Link másolása", () => { menu.value = null; transfer(() => writeText(objectURL(path,node.id))); }, {symbol: "link"}) : null,
        button("Ping", () => ping({node: node.id}), {symbol: "center", disabled: !online.value}),
        !isJunction(node) ? elevationButton(node, true) : null,
        // Link csak hozzáadható innen; eltávolítása a tulajdonságpanel ✕ gombjával.
        hasTrait(node, "link") && !node.link ? button("Link hozzáadása", () => {
          chooseLink(node);
        }, {symbol: "link", disabled: !!occupied(node.id)}) : null,
        button("Szerkesztés", () => openProperties("node", node.id), {symbol: "edit", disabled: !!occupied(node.id)}),
        // Egyetlen törlés: fájl- és linkes doboznál a közös kérdőablak jön fel (deleteObjects).
        button("Törlés", () => { menu.value = null; deleteNode(node); }, {class: "button danger", symbol: "trash", disabled: !!occupied(node.id)}),
      ] : type === "edge" && edge ? [
        button("Szerkesztés", () => openProperties("edge", edge.id), {symbol: "edit"}),
        ...endpointActions(edge),
        button("Kapcsolat törlése", () => removeEdge(edge), {class: "button danger", symbol: "trash"}),
      ] : [
        button("Ping", () => ping({point: clampPoint(open.position)}), {symbol: "center", disabled: !online.value}),
        button("Objektum létrehozása", () => {
          menu.value = null;
          addNode(open.position);
        }, {disabled: !board.value, symbol: "plus"}),
        button("Új munkalap", addSubworksheet, {symbol: "plus", disabled: !online.value}),
        button("Középre állítás", () => { menu.value = null; centerOrigin(); }, {symbol: "center"}),
      ];
      // A menü mindig a böngészőablakon belül marad (jobbra/lent kilógás helyett eltolódik).
      const fit = ({el}) => {
        if (!el?.getBoundingClientRect || typeof innerWidth !== "number") return;
        const box = el.getBoundingClientRect(), margin = 8;
        el.style.left = Math.max(margin, Math.min(open.x, innerWidth - box.width - margin)) + "px";
        el.style.top = Math.max(margin, Math.min(open.y, innerHeight - box.height - margin)) + "px";
      };
      return h("div", {class: "context-menu panel", "aria-label": "Műveletek",
        style: {left: open.x + "px", top: open.y + "px"}, onVnodeMounted: fit, onVnodeUpdated: fit}, entries);
    }

    function sidebar(label, contents, canvasSettings = false) {
      return h("aside", {class: ["inspector", canvasSettings ? "canvas-inspector" : "object-inspector"], "aria-label": label,
        onFocusin: event => { editingField = event.target.matches("textarea,input,select"); },
        onFocusout: () => { editingObject.value = null; finishField(); },
        onKeydown: e => {
          if (editingObject.value && e.key === "Enter" && !e.isComposing && !e.shiftKey) {
            e.preventDefault(); e.stopPropagation(); e.target.blur();
          }
        },
        onChange: event => { if (event.target.matches("select,input[type=checkbox],input[type=range],input[type=color]")) finishField(); },
        onInputCapture: () => { editingField = true; }}, [
        h("div", {class: "inspector-content stack"}, contents),
      ]);
    }

    function endpointActions(edge, compact = false) {
      return [["source", "Kezdőpont"], ["target", "Végpont"]].map(([end, label]) => {
        const attached = !!edgeEndpoint(edge, end).node;
        const name = label + (attached ? " leválasztása" : " lekötése");
        const action = attached ? () => { detach(edge, end); menu.value = null; } : () => retarget(edge, end);
        const symbol = compact ? "endpoint-" + end : attached ? "unlink" : "right";
        return compact ? iconToggle(name, attached, action, icon(symbol)) : button(name, action, {symbol});
      });
    }

    function group(label, children) {
      return h("fieldset", {class: "property-group stack"}, [h("legend", label), ...children]);
    }

    const searchHits = computed(() => {
      const term = searchQuery.value?.trim().toLocaleLowerCase("hu");
      if (!term || !board.value) return [];
      const titles = [], bodies = [];
      const matches = text => text?.toLocaleLowerCase("hu").includes(term);
      for (const n of board.value.nodes) {
        const name = nodeName(n);
        const nameMatch = matches(name);
        if (nameMatch || matches(n.text)) {
          (nameMatch ? titles : bodies).push({key: "node/" + n.id, kind: "node", id: n.id, title: name || typeLabel(n.type),
            source: nameMatch ? "Cím" : "Text"});
        }
      }
      for (const e of board.value.edges) {
        if (matches(e.label)) titles.push({key: "edge/" + e.id, kind: "edge", id: e.id, title: e.label, source: "Cím"});
      }
      return titles.concat(bodies);
    });
    const cursorKey = ref(null);
    const pinnedHits = ref(new Map());
    const omittedKey = ref(null);
    const activeHit = computed(() => searchHits.value.find(hit => hit.key === cursorKey.value) ?? searchHits.value[0]);
    const candidates = computed(() => {
      if (searchHistoryIndex.value >= 0) return new Map();
      const items = new Map(pinnedHits.value);
      const active = activeHit.value;
      if (active && active.key !== omittedKey.value) items.set(active.key, active);
      return items;
    });

    function activateHit(hit) {
      if (hit.key !== activeHit.value?.key) omittedKey.value = null;
      cursorKey.value = hit.key;
    }

    function toggleCandidate(hit) {
      activateHit(hit);
      if (pinnedHits.value.delete(hit.key)) omittedKey.value = hit.key;
      else {
        pinnedHits.value.set(hit.key, hit);
        omittedKey.value = null;
      }
    }

    function closeSearch() {
      searchHistoryIndex.value = -1;
      searchQuery.value = null;
      cursorKey.value = omittedKey.value = null;
      pinnedHits.value.clear();
    }

    function setSearchQuery(query) {
      searchHistoryIndex.value = -1;
      searchQuery.value = query;
      cursorKey.value = omittedKey.value = null;
    }

    function scrollToSearchRow() {
      nextTick(() => searchInput.value?.parentElement?.querySelector('[data-active="true"]')?.scrollIntoView({block: "nearest"}));
    }

    function useSearchHistory(term) {
      setSearchQuery(term);
      nextTick(() => searchInput.value?.focus());
    }

    function rememberSearch() {
      const term = searchQuery.value.trim();
      if (term) {
        const normalized = term.toLocaleLowerCase("hu");
        searchHistory = [term, ...searchHistory.filter(query => query.toLocaleLowerCase("hu") !== normalized)]
          .slice(0, searchHistoryLimit);
        try { window.localStorage?.setItem(searchHistoryKey, JSON.stringify(searchHistory)); }
        catch { /* Keep the history in this tab. */ }
      }
    }

    function centerSearchSelection(group) {
      const points = [
        ...[...group.nodes].map(id => nodeMap.value.get(id)?.position),
        ...[...group.edges].map(id => {
          const edge = edgeMap.value.get(id);
          return edge && wireGeometry(edge).labelPosition;
        }),
      ].filter(Boolean);
      if (!points.length) return;
      let x = 0, y = 0;
      for (const point of points) {
        x += point.x;
        y += point.y;
      }
      const [cx, cy] = center(), k = view.value.k;
      d3.select(zoomHost()).call(zoom.transform,
        d3.zoomIdentity.translate(cx-(cx+x/points.length)*k, cy-(cy+y/points.length)*k).scale(k));
    }

    function addSearchResult() {
      const hit = activeHit.value;
      if (!hit) return;
      const group = selectionMembers();
      const members = hit.kind === "node" ? group.nodes : group.edges;
      rememberSearch();
      if (members.has(hit.id)) return;
      members.add(hit.id);
      selectMembers(group);
      centerSearchSelection(group);
    }

    async function acceptSearch() {
      rememberSearch();
      const hits = [...candidates.value.values()].filter(hit =>
        (hit.kind === "node" ? nodeMap.value : edgeMap.value).has(hit.id));
      const focus = hits.find(hit => hit.key === activeHit.value?.key) ?? hits[0];
      closeSearch();
      if (!focus) return;
      const group = {nodes: new Set(), edges: new Set()};
      for (const hit of hits) {
        (hit.kind === "node" ? group.nodes : group.edges).add(hit.id);
      }
      centerSearchSelection(group);
      if (hits.length > 1) {
        selectMembers(group);
      } else if (focus.kind === "node") await selectNode(focus.id);
      else if (await selectNode(null, focus.id)) selected.value = {kind: "edge", id: focus.id};
    }

    function renderSearch() {
      if (searchQuery.value === null) return null;
      return h("div", {class: "quick-search panel stack", role: "dialog", "aria-label": "Gyorskereső"}, [
        h("input", {ref: searchInput, type: "search", value: searchQuery.value, placeholder: "Keresés a munkalapon",
          "aria-label": "Keresés a munkalapon", onInput: e => setSearchQuery(e.target.value)}),
        searchHistoryIndex.value >= 0 ? h("ul", {class: "search-history", "aria-label": "Keresési előzmények"},
          searchHistory.map((term, index) => h("li", {key: term, "data-active": index === searchHistoryIndex.value}, [
            button(h("span", {class: "search-title"}, term), () => useSearchHistory(term), {
              symbol: "search", title: term, onFocus: () => { searchHistoryIndex.value = index; },
            }),
          ]))) : searchHits.value.map(hit => h("div", {key: hit.key, class: "search-row",
          "data-candidate": candidates.value.has(hit.key),
          "data-active": hit.key === activeHit.value?.key, onMouseenter: () => activateHit(hit)}, [
          button(h("span", {class: "search-title"}, hit.title), () => activateHit(hit), {
            symbol: hit.source === "Cím" ? "file" : "comment", title: hit.source + " · " + hit.title,
            "aria-label": hit.title + " (" + hit.source + ")", onFocus: () => activateHit(hit),
          }),
          h("button", {type: "button", class: "button", title: "Candidate rögzítése",
            "aria-label": "Candidate rögzítése · " + hit.title, "aria-pressed": pinnedHits.value.has(hit.key),
            onClick: () => toggleCandidate(hit)}, "☞"),
        ])),
        searchQuery.value.trim() && !searchHits.value.length ? h("p", "Nincs találat.") : null,
      ]);
    }

    function themeSettings(sheet, extra = []) {
      const current = appearance.value;
      const theme = activeTheme.value;
      if (!theme) return null;
      function select(label, value, entries, change) {
        return field(label, h("select", {value, "aria-label": label, disabled: !online.value,
          onChange: event => updateItem(sheet, "appearance", change(event.target.value))},
          entries.map(([id, name]) => h("option", {value: id}, name))));
      }
      return group("Megjelenés", [
        select("Téma", theme.id, themes.map(t => [t.id,t.name]), value => {
          const next = themes.find(t => t.id === Number(value));
          return {theme: next.id, palette: next.palettes[0].id};
        }),
        select("Paletta", activePalette.value.id, theme.palettes.map(p => [p.id,p.name]),
          value => ({...current, palette: Number(value)})),
        ...extra,
      ]);
    }

    function renderCanvasInspector() {
      if (!canvasPanelOpen.value) return null;
      const sheet = board.value;
      return sidebar("Munkalap", [
        h("input", {ref: attachmentInput, type: "file", multiple: true, hidden: true,
          onChange: uploadAttachments}),
        group("Cím", [input(sheet.title, value => updateItem(sheet, "title", value), {"aria-label": "Cím", maxlength: 120})]),
        group("Leírás", [markdownEditor(sheet.text ?? "", value => updateItem(sheet, "text", value), 7, "Leírás")]),
        themeSettings(sheet, [
          colorPicker("Munkalap háttérszíne", sheet.background ?? 0,
            value => updateItem(sheet, "background", value), "worksheet/background", false, false, 0),
          field("Rácsköz", numeric(sheet.gridSpacing ?? 32, value => updateItem(sheet, "gridSpacing", Math.round(value)), 6, 160,
            {...controlName("Rácsköz"), step: 1, clampValue: true})),
        ]),
        group("Előnézeti kép", [h("select", {"aria-label": "Előnézeti kép", value: previewImages.value.includes(sheet.previewImage) ? sheet.previewImage : "",
          onFocus: loadPreviewImages, onChange: e => updateItem(sheet, "previewImage", e.target.value || undefined)}, [
          h("option", {value: ""}, "Default · Munkalap SVG"), ...previewImages.value.map(name => h("option", {value: name}, name))
        ]), h("img", {class: "canvas-preview-thumbnail", alt: "Előnézet", loading: "lazy",
          src: "/api/preview/" + path + "?v=" + sheet.revision + "&image=" + encodeURIComponent(sheet.previewImage ?? "")})]),
        h("div", {class: "property-inline file-actions"}, [button("Beillesztés – Tallózás", insertFromBrowser,
          {symbol: "folder", disabled: !online.value, title: "Már feltöltött fájl vagy weboldal beillesztése a projektből"})]),
        h("div", {class: "property-inline file-actions"}, [button(uploading.value ? "Feltöltés…" : "Fájl feltöltése", event => {
          const bounds = event.currentTarget.getBoundingClientRect();
          uploadAnchor = {clientX: bounds.left + bounds.width / 2, clientY: bounds.bottom + 12};
          attachmentInput.value?.click();
        }, {symbol: "plus", disabled: uploading.value || !online.value, title: "Fájl feltöltése"})]),
      ], true);
    }

    // Markdown szerkesztő: formázógombok nélkül, a szöveg közvetlenül szerkeszthető.
    function markdownEditor(value, change, rows = 6, label = "Text", primary = false) {
      return h("div", {class: "markdown-editor stack"}, [
        h("textarea", {"aria-label": label, value, maxlength: 100000, rows, "data-object-label": primary ? "" : undefined,
          onInput: event => change(event.target.value)}),
      ]);
    }

    const alignmentPositions = [
      ["top","left","Bal felső","↖"], ["top","center","Felső közép","↑"], ["top","right","Jobb felső","↗"],
      ["middle","left","Bal oldal","←"], ["middle","center","Közép","•"], ["middle","right","Jobb oldal","→"],
      ["bottom","left","Bal alsó","↙"], ["bottom","center","Alsó közép","↓"], ["bottom","right","Jobb alsó","↘"],
    ];

    // A tulajdonságpanel a típusok képességeiből áll össze (docs/node-types.md); több kijelölt objektumnál
    // a közös képességek látszanak, és a módosítás mindegyikre érvényes.
    function nodePanels(nodes) {
      const single = nodes.length === 1 ? nodes[0] : null;
      const first = nodes[0];
      const common = nodes.map(node => traits(node.type)).reduce((a, b) => new Set([...a].filter(trait => b.has(trait))));
      const same = key => nodes.every(node => node[key] === first[key]);
      const value = (key, fallback) => same(key) ? first[key] ?? fallback : fallback;
      const change = (key, next) => {
        for (const node of nodes) {
          const current = nodeMap.value.get(node.id);
          if (current && !occupied(current.id)) current[key] = typeof next === "function" ? next(current) : next;
        }
        modified();
      };
      const color = (label, key, role, compact = true) => colorPicker(label, value(key, role), v => change(key, v),
        nodes.map(n => n.id).join(",") + "/" + key, false, compact, role);
      const mode = value("backgroundMode", "solid");
      const setBackground = (next, fill) => {
        for (const node of nodes) {
          const current = nodeMap.value.get(node.id);
          if (!current || occupied(current.id)) continue;
          current.backgroundMode = next === "solid" ? undefined : next;
          if (fill !== undefined) current.fill = fill;
        }
        modified();
      };
      const backgroundTools = () => [
        nodes.some(isImage) ? null : colorPicker("Háttér", value("fill", 2),
          v => setBackground(mode === "free" ? "solid" : mode, v), nodes.map(n => n.id).join(",") + "/fill", false, true, 2,
          {transparent: mode === "free"}),
        // Képnél a Free és az Üres értelmetlen; az Elmosott és az Áttetsző magára a képre hat.
        nodes.some(isImage) ? null : iconToggle("Free", mode === "free", () => setBackground(mode === "free" ? "solid" : "free"), icon("box-free")),
        nodes.some(isImage) ? null : iconToggle("Üres", mode === "empty", () => setBackground(mode === "empty" ? "solid" : "empty"), icon("box-empty")),
        iconToggle("Elmosott", mode === "blurred", () => setBackground(mode === "blurred" ? "solid" : "blurred"), icon("box-blur")),
        iconToggle("Áttetsző", mode === "translucent", () => setBackground(mode === "translucent" ? "solid" : "translucent"), icon("box-background")),
      ];
      const elevation = () => single ? elevationButton(single) : iconToggle("Kiemelés", nodes.every(n => n.elevated === true), () => {
        const raise = !nodes.every(n => n.elevated === true);
        change("elevated", node => { if (raise) node.parent = undefined; return raise ? true : undefined; });
      }, icon("box-elevated"));
      const linkButton = () => single && common.has("link") && !single.link
        ? h("button", {type: "button", class: "button option-icon link-add", ...controlName("Link hozzáadása"),
            disabled: !online.value, onClick: () => chooseLink(single)}, [icon("link")]) : null;
      const panels = [];

      if (common.has("label")) panels.push(group("Címke", [
        single ? input(single.text ?? "", v => change("text", v), {"aria-label": "Címke", "data-object-label": "", maxlength: 120}) : null,
        propertyTools(h("span", {class: "muted"}, [icon("rotate")]),
          numeric(value("angle", 0), v => change("angle", v ? Math.round(v) : undefined), -360, 360, {...controlName("Elforgatás (fok)"), step: 1})),
      ]));

      if (common.has("file") && single) {
        const {stem, extension} = fileNameParts(single.file, isImage(single));
        const visible = single.file.showFilename !== false;
        panels.push(group("Fájlnév", [h("div", {class: "property-inline file-name-field"}, [
          h("input", {type: "text", "aria-label": "Fájlnév", value: stem, maxlength: 200, "data-object-label": "",
            onChange: event => {
              const name = event.target.value.trim();
              if (name === stem || !renameFile(single, name)) event.target.value = stem;
            },
            onKeydown: event => {
              if (event.key !== "Enter" || event.isComposing) return;
              event.preventDefault(); event.stopPropagation(); event.target.blur();
            }}),
          extension ? h("span", {class: "muted"}, "." + extension) : null,
          iconToggle(visible ? "Fájlnév elrejtése" : "Fájlnév megjelenítése", visible,
            () => change("file", node => ({...node.file, showFilename: !visible})), icon(visible ? "eye" : "eye-off")),
        ])]));
      }

      if (common.has("text")) {
        const fontSize = numeric(value("fontSize", 16), v => change("fontSize", Math.round(v)), 1, 10000,
          {...controlName("Betűméret"), step: 1, clampValue: true, disabled: nodes.every(n => n.fitText)});
        const fontButton = (index, label) => iconToggle(label, nodes.every(n => (n.font ?? 1) === index),
          () => change("font", index === 1 ? undefined : index),
          h("span", {class: "font-sample", style: {fontFamily: fontFamily(index)}}, "Aa"));
        const justified = nodes.every(n => n.justified === true);
        panels.push(group("Text", [
          single ? markdownEditor(single.text ?? "", v => change("text", v), 6, "Text", true) : null,
          h("div", {class: "typography-tools"}, [
            h("div", {class: "typography-rows"}, [propertyTools(
              iconToggle("AutoSize", nodes.every(n => n.fitText), () => change("fitText", !nodes.every(n => n.fitText) || undefined),
                optionSymbol("path", {d: "M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5M8 16l4-8 4 8m-6.5-3h5"})),
              fontSize,
              fontButton(1, "Alap betűtípus"), fontButton(2, "Második betűtípus"), fontButton(3, "Harmadik betűtípus"),
            ), propertyTools(
              color("Szövegszín", "textColor", 1),
              iconToggle("Sorkizárás", justified, () => change("justified", justified ? undefined : true), icon(justified ? "justify" : "text-" + value("alignment", "center"))),
              iconToggle("Összecsukás (csak az első sor)", nodes.every(n => n.hideText), () => change("hideText", nodes.every(n => n.hideText) ? undefined : true), icon("more")),
            )]),
            h("div", {class: "alignment-picker", role: "group", "aria-label": "Igazítás"},
              alignmentPositions.map(([vertical, horizontal, label, symbol]) => h("button", {
                type: "button", ...controlName(label),
                "aria-pressed": vertical === value("verticalAlignment", "middle") && horizontal === value("alignment", "center"),
                onClick: () => { change("verticalAlignment", vertical); change("alignment", horizontal); },
              }, symbol))),
          ]),
        ]));
      }

      if (common.has("fileText") && single) {
        const key = fileTextKey(single);
        const loaded = fileTexts.value.get(key);
        const justified = single.justified === true;
        panels.push(group("Text", [
          loaded == null ? h("p", {class: "muted"}, "Betöltés…") :
            h("textarea", {"aria-label": "Fájl tartalma", class: ["file-text-editor", {"justified-text": justified}], value: loaded, rows: 10,
              spellcheck: single.type !== "code", onInput: event => editFileText(single, event.target.value)}),
          propertyTools(
            numeric(single.fontSize ?? 14, v => change("fontSize", Math.round(v)), 6, 72, {...controlName("Betűméret"), step: 1, clampValue: true}),
            color("Szövegszín", "textColor", 1),
            single.type === "text" ? iconToggle("Sorkizárás", justified, () => change("justified", justified ? undefined : true), icon("justify")) : null,
            h("small", {class: "muted", role: "status"}, fileSaveState.value.get(single.id) ?? ""),
          ),
        ]));
      }

      if (common.has("comment")) {
        const hidden = nodes.every(n => n.hideText);
        panels.push(group("Text", [
          single ? markdownEditor(single.text ?? "", v => change("text", v), 3, "Text") : null,
          propertyTools(
            ...[["left", "Balra", "text-left"], ["center", "Középre", "text-center"], ["right", "Jobbra", "text-right"]].map(([align, label, symbol]) =>
              iconToggle(label, value("alignment", "center") === align, () => change("alignment", align), icon(symbol))),
            iconToggle(hidden ? "Text megjelenítése" : "Text elrejtése", !hidden, () => change("hideText", hidden ? undefined : true),
              icon(hidden ? "eye-off" : "eye")),
          ),
        ]));
      }


      if (common.has("shape")) panels.push(group("Doboz", [
        optionPicker("Forma", shapes, value("shape", null), v => change("shape", v), shapeSymbol),
        optionPicker("Animáció", boxAnimations, value("animation", "none") ?? "none", v => change("animation", v === "none" ? undefined : v), v => icon("box-" + v)),
        h("div", {class: "property-options property-tools box-effect-options"}, [
          ...backgroundTools(), elevation(),
          single && containerIDs.value.has(single.id) ? iconToggle("Tartalom rögzítése", !!single.locked,
            () => change("locked", single.locked ? undefined : true), icon(single.locked ? "lock" : "unlock")) : null,
          linkButton(),
        ]),
      ]));
      else if (common.has("surface")) panels.push(group("Megjelenés", [
        // Képnél a megjelenés-módosítók közül csak a Kiemelés maradt.
        h("div", {class: "property-options property-tools box-effect-options"}, [...(nodes.some(isImage) ? [] : backgroundTools()), elevation(), linkButton()]),
      ]));

      if (common.has("diameter")) panels.push(group("Megjelenés", [propertyTools(
        numeric(value("width", 12), size => change("width", node => { node.height = size; return size; }), 4, 128, controlName("Átmérő")),
        color("Szín", "fill", 2),
      )]));

      if (single?.file && !isCommonFile(single.file)) panels.push(h("fieldset", {class: "property-group stack link-group"}, [
        h("legend", [h("span", "Hozzáférés")]),
        h("div", {class: "link-row link-actions"}, [
          iconToggle(single.webPublic ? "Publikus: bárki letöltheti" : "Publikus: ki", !!single.webPublic,
            () => toggleFilePublic(single), icon("butterfly"), !online.value),
        ]),
      ]));

      if (single?.link) {
        const destination = linkDestination(single.link);
        const kindLabel = single.link.kind === "web" ? "Weboldal" : linkKinds.find(([kind]) => kind === single.link.kind)?.[1] ?? "Link";
        // A Link csoport mindig legfelül áll.
        panels.unshift(h("fieldset", {class: "property-group stack link-group"}, [
          h("legend", [h("span", "Link · " + kindLabel)]),
          h("div", {class: "link-row"}, [
            single.link.kind === "web" ? h("input", {"aria-label": "Weboldal neve (a mappa is átnevezve)", value: linkCaption(single.link), maxlength: 80,
                onChange: event => {
                  const field = event.target, name = field.value.trim(), previous = linkCaption(single.link);
                  if (name === previous) return;
                  transfer(async () => {
                    try {
                      const response = await fetch("/api/web-rename/" + path, {method: "POST",
                        headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf},
                        body: JSON.stringify({reference: single.link.target, name})});
                      const result = await response.json().catch(() => ({}));
                      if (!response.ok) throw Error(result.reason || "Az átnevezés sikertelen.");
                      // Minden doboz ezen a lapon, amely erre a mappára mutat, az új nevet kapja.
                      const old = single.link.target;
                      for (const item of board.value.nodes) if (item.link?.kind === "web" && item.link.target === old && !occupied(item.id)) {
                        item.link = {kind: "web", target: result.reference};
                      }
                      modified();
                    } catch (error) { field.value = previous; throw error; }
                  });
                }}) : h("input", {"aria-label": "Link célja", value: single.link.target, maxlength: 2048,
                onChange: event => {
                  const raw = event.target.value.trim();
                  const target = single.link.kind === "url" ? externalURL(raw) : worksheetLink(raw, path)?.kind === "worksheet" ? raw : null;
                  if (!target) { problem.value = "Érvénytelen hivatkozás."; event.target.value = single.link.target; return; }
                  change("link", {kind: single.link.kind, target});
                }}),
            destination ? button("", () => followBoxLink(destination), {symbol: single.link.kind === "url" ? "website" : "right", class: "button option-icon", ...controlName("Megnyitás")}) : null,
          ]),
          // Második sor: a többi gomb.
          h("div", {class: "link-row link-actions"}, [
            // .web: előnézet generálása be/ki; munkalap- és külső link: előnézet megjelenítése be/ki (kikapcsolva a szöveg látszik).
            iconToggle(single.link.kind === "web" ? (single.staticPreview ? "Előnézet generálása: ki" : "Előnézet generálása: be")
              : (single.staticPreview ? "Előnézet: ki (a szöveg látszik)" : "Előnézet: be"),
              !single.staticPreview, () => change("staticPreview", single.staticPreview ? undefined : true), icon("camera")),
            single.link.kind === "web" ? iconToggle(single.webPublic ? "Publikus: bárki megnézheti" : "Publikus: ki",
              !!single.webPublic, () => toggleWebPublic(single), icon("butterfly"), !online.value) : null,
            h("button", {type: "button", class: "button option-icon link-remove", ...controlName("Link törlése"),
              onClick: () => removeLink(single)}, [icon("close")]),
          ]),
        ]));
      }
      return panels;
    }

    function edgePanels(edges) {
      const single = edges.length === 1 ? edges[0] : null;
      const first = edges[0];
      const same = key => edges.every(edge => edge[key] === first[key]);
      const value = (key, fallback) => same(key) ? first[key] ?? fallback : fallback;
      const change = (key, next) => { for (const edge of edges) edge[key] = typeof next === "function" ? next(edge) : next; modified(); };
      const paint = edgePaint(first);
      const all = (key, fallback) => edges.every(edge => (edge[key] ?? fallback) === true);
      return [
        group("Vonal", [
          single ? input(single.label || "", v => change("label", v), {...controlName("Címke"), "data-object-label": "", maxlength: 120}) : null,
          propertyTools(
            colorPicker("Vonal színe", value("color", 3), v => change("color", v), edges.map(e => e.id).join(",") + "/line", false, true, 3),
            numeric(value("width", 2), v => change("width", v), 0.5, maximumLineWidth, controlName("Alapvastagság")),
          ),
        ]),
        group("Vonaltípus", [optionPicker("Vonaltípus", lineTypes, value("type", "straight"), v => change("type", v), lineTypeSymbol)]),
        group("Megjelenés", [h("div", {class: "property-options line-appearance-options"}, [
          optionPicker("Megjelenés", lineAppearances, value("appearance", "plain"), v => change("appearance", v), lineAppearanceSymbol),
          iconToggle("Felirat a vonalban", all("labelInLine", false), () => change("labelInLine", all("labelInLine", false) ? undefined : true), icon("wire-label")),
          iconToggle("Animáció bekapcsolása", all("animated", false), () => change("animated", !all("animated", false)), icon("play")),
        ])]),
        group("Végpontok", [h("div", {class: "property-options property-tools endpoint-tools"}, [
          iconToggle("Nyíl a vonal elején", all("startArrow", false), () => change("startArrow", !all("startArrow", false)), icon("left")),
          iconToggle("Nyíl a vonal végén", all("endArrow", true), () => change("endArrow", !all("endArrow", true)), icon("right")),
          single ? h("span", {class: "endpoint-actions"}, endpointActions(single, true)) : null,
        ])]),
      ];
    }

    function renderInspector() {
      if (!objectPanelOpen.value || !selected.value && !batch.value) return null;
      if (batch.value) {
        const nodes = board.value.nodes.filter(n => batch.value.nodes.has(n.id) && !occupied(n.id));
        const edges = board.value.edges.filter(e => batch.value.edges.has(e.id));
        const joints = nodes.filter(isJunction).length;
        const summary = (nodes.length-joints)+" doboz, "+edges.length+" vonal, "+joints+" csomópont";
        return sidebar("Objektumok", [
          h("p", {class: "muted"}, summary),
          ...(nodes.length ? nodePanels(nodes) : []),
          ...(edges.length ? edgePanels(edges) : []),
        ]);
      }
      if (!inspector.value) return null;
      if (inspector.value.kind === "edge") {
        const edge = board.value.edges.find(item => item.id === inspector.value.id);
        return edge ? sidebar("Vonal szerkesztése", edgePanels([edge])) : null;
      }
      const node = nodeMap.value.get(inspector.value.id);
      if (!node || held.value !== node.id || occupied(node.id)) return null;
      return sidebar(isJunction(node) ? typeLabel(node.type) : typeLabel(node.type) + " szerkesztése", nodePanels([node]));
    }

    const topRow = mount.closest?.(".editor-root")?.querySelector(".worksheet-nav");
    function renderHeader() {
      const changed = online.value && (dirty.value || (board.value.revision > checkpointState.value.revision
        ? board.value.revision !== checkpointRevision : checkpointState.value.changed));
      const historyButton = (label, symbol, forward, available) =>
        headerButton(() => replay(forward), {title: label, "aria-label": label,
          symbol, disabled: !available || !online.value || !!gesture.value,
          class: {"gesture-disabled": available && online.value && !!gesture.value},
        });
      const controls = [
          historyButton("Visszavonás", "undo", false, undo.value.length || fieldChanged),
          historyButton("Újra", "redo", true, redo.value.length),
          headerButton(() => sessionAction("resign"), {"aria-label": "Resign", symbol: "restore", title: "A közös visszaállítási pont betöltése",
            disabled: checkpointBusy.value || !online.value}),
          headerButton(() => sessionAction("checkpoint"), {symbol: "save", "aria-label": "Mentés", class: {"save-label-changed": changed},
            title: "Közös visszaállítási pont rögzítése", disabled: checkpointBusy.value || !online.value}),
      ];
      return h("div", {class: "worksheet-history"}, controls);
    }

    return () => {
      if (!board.value) return h("p", {class: problem.value ? "error editor-loading" : "editor-loading"}, problem.value || "Szerkesztő betöltése…");
      const currentStatus = reconnect.value ? "Kattints az új célra vagy a vászonra. Esc a megszakításhoz."
        : "";
      return [
        h("div", {class: "editor-workspace", "data-glass": graphics.value.glass ? mode.value : undefined, style: {
          "--sheet-glow": (graphics.value.glow ?? 3) + "px"
        }}, [
          renderCanvas(),
          problem.value || currentStatus ? h("p", {class: ["canvas-status", {error: problem.value}], role: "status"}, problem.value || currentStatus) : null,
          h("div", {class: "inspector-column"}, [renderInspector()]),
          canvasPanelOpen.value ? h("div", {class: "inspector-column canvas-inspector-column"}, [renderCanvasInspector()]) : null,
          renderSearch(),
          h(topRow ? window.Vue.Teleport : "div", topRow ? {to: topRow} : {}, [
          renderHeader(),
          h("a", {class: [headerButtonClass, "worksheet-close"], href: "/" + path, title: "Szerkesztő bezárása", "aria-label": "Bezárás", onClick: switchToViewer}, [icon("close")]),
          headerButton(() => { finishField(); editingObject.value = null; objectPanelOpen.value = !objectPanelOpen.value; }, {
            class: ["sidebar-open", {active: (selected.value || batch.value) && !objectPanelOpen.value}],
            "aria-expanded": objectPanelOpen.value,
            "aria-label": objectPanelOpen.value ? "Oldalsáv bezárása" : "Oldalsáv megnyitása",
            symbol: "property-panel",
          }),
          headerButton(() => { finishField(); canvasPanelOpen.value = !canvasPanelOpen.value; if (canvasPanelOpen.value) loadPreviewImages(); }, {
            class: "sidebar-open sidebar-open-canvas",
            "aria-expanded": canvasPanelOpen.value,
            "aria-label": canvasPanelOpen.value ? "Vászonbeállítások bezárása" : "Vászonbeállítások megnyitása",
            symbol: "canvas-menu",
          }),
          ]),
        ]),
        renderMenu(),
      ];
    };
  },
}).mount(mount);
