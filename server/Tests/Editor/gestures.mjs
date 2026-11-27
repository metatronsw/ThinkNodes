// Run from the repository root with Node 22 or later. The Vue runtime is the same one served to browsers.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {runInThisContext} from "node:vm";

// Gyorsított idő: a szerkesztő és a teszt minden időzítése (mentés 70 ms, gépelési szünet, dupla kattintás ablaka …)
// nyolcadannyi valós ideig tart, az óra (performance.now) pedig ugyanennyivel gyorsabban jár – az arányok így
// megmaradnak, a teszt viszont töredék idő alatt lefut. TEST_SPEED=1 a valós idejű futás (hibakereséshez).
const speed = Number(process.env.TEST_SPEED) || 8;
const realSetTimeout = globalThis.setTimeout, realNow = performance.now.bind(performance);
globalThis.setTimeout = (callback, delay = 0, ...rest) => realSetTimeout(callback, delay / speed, ...rest);
performance.now = () => realNow() * speed;
const read = name => readFileSync("Public/vendor/" + name + ".js", "utf8");
globalThis.ThinkNodesNodeTypes = JSON.parse(readFileSync("Public/node-types.json", "utf8"));
globalThis.ThinkNodesQuickTools = JSON.parse(readFileSync("Public/quick-tools.json", "utf8"));
runInThisContext(read("vue"));
// A d3 szűkített csomagja (zoom, zoomIdentity, select, pointer): Public/lib/d3-zoom.js, deploy/d3-slim.sh.
runInThisContext(readFileSync("Public/lib/d3-zoom.js", "utf8"));
const {Vue, d3} = globalThis;
function element(tag, text) {
  return Vue.markRaw({tag, text, children: [], props: {}, style: {}, clientWidth: 1200, clientHeight: 800,
    querySelector() { return null; }, focus() {}, setPointerCapture() {}});
}
function remove(node) {
  if (node.parent) node.parent.children.splice(node.parent.children.indexOf(node), 1);
  node.parent = null;
}
const renderer = Vue.createRenderer({
  createElement: tag => element(tag), createText: text => element("#text", text), createComment: text => element("#comment", text),
  patchProp(node, key, old, value) { node.props[key] = value; },
  setText(node, text) { node.text = text; },
  setElementText(node, text) { node.text = text; node.children = []; },
  insert(node, parent, before) {
    if (node === before) return;
    remove(node);
    const index = before ? parent.children.indexOf(before) : -1;
    parent.children.splice(index < 0 ? parent.children.length : index, 0, node);
    node.parent = parent;
  },
  remove, parentNode: n => n.parent, nextSibling: n => n.parent?.children[n.parent.children.indexOf(n)+1],
});
const root = element("root");
root.dataset = {themes: JSON.stringify(["ThinkDefault","LiquidGlass","Blueprint"].map(name =>
  JSON.parse(readFileSync("Public/themes/" + name + ".json", "utf8")))), path: "test", role: "admin", user: "admin"};
const listeners = {};
const zoomEvents = {};
let requestedZoom;
function zoom() {
  const behavior = () => {};
  behavior.scaleExtent = () => behavior;
  behavior.constrain = () => behavior;
  behavior.filter = filter => { zoomEvents.filter = filter; return behavior; };
  behavior.on = (key, fn) => { zoomEvents[key] = fn; return behavior; };
  behavior.transform = (_, transform) => { requestedZoom = transform; };
  return behavior;
}
globalThis.document = {documentElement: {dataset: {display: "light"}}, querySelector: () => root,
  // A jelenlét-figyelés (collaboration.js: nézi-e a lapot) a fókuszt és a láthatóságot kérdezi.
  hidden: false, hasFocus: () => true, addEventListener() {},
  // A dobozon szerkesztés (editor.js codeEdit) a kurzort a szövegcsomópontok szerint állítja be; itt nincs valódi DOM.
  createTreeWalker: () => ({nextNode: () => null})};
const storage = new Map();
globalThis.window = {getSelection: () => ({rangeCount: 0, setBaseAndExtent() {}}), localStorage: {getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value)},
  Vue: {...Vue, createApp: renderer.createApp}, addEventListener(key, fn) { listeners[key] = fn; }, removeEventListener() {},
  d3: {...d3, zoom, pointer: e => [e.clientX, e.clientY],
    select: () => ({call(fn, ...args) { fn(this, ...args); return this; }, on() { return this; }})}};
globalThis.NodeFilter = {SHOW_TEXT: 4};
globalThis.ResizeObserver = class { observe() {} };
globalThis.confirm = () => true;
globalThis.getComputedStyle = () => ({lineHeight: "20px", fontSize: "14px", paddingTop: "0px", paddingBottom: "0px"});

function node(id, x, y, width, height) {
  return {id, type: "box", position: {x, y}, width, height, shape: "rectangle", text: id,
    fill: "#bbbbbb", textColor: "#111111", alignment: "center", fontSize: 16};
}
const {decodeWorksheet, encodeWorksheet} = await import("../../Public/worksheet-json.js");
let sheet = {schemaVersion: 3, appearance: {theme:1,palette:1}, creator: "admin", title: "Próba", revision: 1, nodes: [
  {...node("outer", 0, 0, 300, 240), text: "outer\n\nchild"}, node("inner", 10, 10, 160, 120), node("child", 10, 10, 64, 40),
  node("outside", 340, 0, 100, 80), {...node("auto", -420, 0, 120, 60), fitText: true},
], edges: [{id: "one", source: "outside", target: {point: {x: 400, y: 230}}, type: "straight", appearance: "plain"}]};
let socket, finishPoll, fetchWorksheet;
globalThis.location = new URL("http://localhost/test");
globalThis.WebSocket = window.WebSocket = class {
  constructor() { socket = this; }
};
let selectedNode;
let writes = 0;
const attachmentUploads = [];
let svgUpload;
let checkpoint = structuredClone(sheet);
let savedPreferences;
globalThis.fetch = async (url, options) => {
  if (url.startsWith("/api/preview-images/")) return Response.json([]);
  if (url === "/api/preferences") {
    savedPreferences = JSON.parse(options.body);
    return new Response(null, {status: 204});
  }
  if (url === "/api/worksheet-file/test?name=lap.thnode" && options?.method === "POST") {
    return Response.json({path: "test/lap"});
  }
  if (url === "/api/subworksheet/test/jegyzet" && options?.method === "POST") {
    return Response.json({title: "Jegyzet"});
  }
  if (url === "/api/media/test?filename=pelda.png" && options?.method === "POST") {
    return Response.json({asset: "pelda.png"});
  }
  if (url === "/api/media/test?filename=mozgas.SVG" && options?.method === "POST") {
    svgUpload = options;
    return Response.json({asset: "mozgas.svg"});
  }
  if (url.startsWith("/api/attachment/") && options?.method === "POST") {
    attachmentUploads.push({url, file: options.body});
    return new Response(null, {status: 201});
  }
  if (url.startsWith("/api/usage/")) return Response.json([]);
  if (url.startsWith("/api/release/")) return Response.json({failed: []});
  if (url.includes("/presence/")) {
    const {action, node, since} = JSON.parse(options.body);
    if (since) return new Promise(resolve => { finishPoll = resolve; });
    if (action === "select") selectedNode = node;
    if (action === "checkpoint") checkpoint = structuredClone(sheet);
    if (action === "resign") {
      const revision = sheet.revision + 1;
      sheet = {...structuredClone(checkpoint), revision, resetRevision: revision};
      checkpoint = structuredClone(sheet);
    }
    return Response.json({version: "1", revision: sheet.revision, checkpointRevision: checkpoint.revision,
      checkpointChanged: sheet.revision !== checkpoint.revision,
      participants: [{mine: true, name: "admin", color: "#365bd6", node: selectedNode}]});
  }
  if (url.includes("text/canvas")) return Response.json({
    blocks: JSON.parse(options.body).sources.map(source => [{kind: "body", runs: [{text: source}]}]),
  });
  if (options?.method === "PUT") {
    writes++;
    const submitted = JSON.parse(options.body);
    assert.equal(submitted.schemaVersion, 3);
    assert.ok(submitted.nodes.every(node => node.pos && !node.position));
    sheet = decodeWorksheet(submitted);
    sheet.revision++;
  }
  if (fetchWorksheet) await fetchWorksheet;
  return Response.json(encodeWorksheet(sheet));
};
await import("../../Public/editor.js");
const tick = async () => { await new Promise(resolve => setTimeout(resolve, 0)); await Vue.nextTick(); };
await tick();
function find(test, rootNode = root) {
  if (test(rootNode)) return rootNode;
  for (const child of rootNode.children) {
    const result = find(test, child);
    if (result) return result;
  }
}
const prop = (key, value, scope) => find(n => n.props[key] === value, scope);
const graphic = id => prop("data-node", id);
// A saját kijelölés a doboz "own-selected" osztálya (világosabb, vastagabb keret); a glow a többi felhasználóé.
const classList = c => typeof c === "string" ? c.split(/\s+/) : Array.isArray(c) ? c.flatMap(classList) : c && typeof c === "object" ? Object.keys(c).filter(k => c[k]) : [];
const ownSelected = id => classList(graphic(id).props.class).includes("own-selected") && !prop("class", "selection-glow", graphic(id));
const canvas = () => prop("aria-label", "Ötletvászon");
const text = n => n.text ?? n.children.map(text).join("");
const button = label => find(n => n.tag === "button" && (text(n) === label || n.props["aria-label"] === label));
const endpoint = (id, end) => find(n => n.props["data-edge"] === id && n.props["data-endpoint"] === end);
const event = (target, x, y, extra = {}) => ({currentTarget: target, target, button: 0, pointerId: 1,
  clientX: x+600, clientY: y+400, preventDefault() {}, stopPropagation() {}, ctrlKey: false, altKey: false, ...extra});
async function drag(target, x, y, toX, toY, keys = {}, cancel = false) {
  const down = event(target, x, y, keys);
  target.props.onPointerdown(down);
  const move = event(canvas(), toX, toY);
  canvas().props.onPointermove(move);
  // A húzás közbeni jelzők (nodeUi.shifted) a Vue ütemezőjével frissülnek; böngészőben a mozdulat és a felengedés külön feladat.
  await tick();
  if (cancel) canvas().props.onPointercancel(move);
  else canvas().props.onPointerup(move);
  await tick();
}
async function properties(id) {
  graphic(id).props.onKeydown({key: "Enter", shiftKey: true});
  await tick();
}
async function press(label) { button(label).props.onClick(); await tick(); }
// Azonos nevű gomb több választócsoportban is lehet (pl. „Vastag” a Megjelenés és a Vonalméret csoportban):
// a gomb a csoport (role="group", aria-label) alatt keresve.
const groupButton = (group, label) => find(n => n.tag === "button" && (text(n) === label || n.props["aria-label"] === label),
  find(n => n.props.role === "group" && n.props["aria-label"] === group, panel()));
async function pressIn(group, label) { groupButton(group, label).props.onClick(); await tick(); }
// A munkalap magától ment (editor.js scheduleSave: 70 ms, gépelés közben 0,5 mp); a „Mentés” gomb verziót ment.
async function save() { await new Promise(resolve => setTimeout(resolve, 110)); await tick(); }
const model = id => sheet.nodes.find(n => n.id === id);
const edge = id => sheet.edges.find(e => e.id === id);
assert.equal(prop("class", "canvas-creator"), undefined, "the editor omits its own creator name");
const toggle = (key, down) => listeners[down ? "keydown" : "keyup"]({key, ctrlKey: down && key === "Control", altKey: down && key === "Alt"});
async function detachDrag(id, end, x, y, cancel = false) {
  toggle("Control", true); await tick();
  const handle = endpoint(id, end);
  assert.equal(handle.props.class, "wire-handle is-attached");
  const [,cx,cy] = /translate\(([^ ]+) ([^)]+)\)/.exec(handle.props.transform);
  await drag(handle, +cx, +cy, x, y, {ctrlKey: true}, cancel);
  toggle("Control", false); await tick();
}

// The revision notice can arrive well before the worksheet GET finishes.
socket.onmessage({data: JSON.stringify({node: "outside", revision: sheet.revision, delta: {x: 25, y: 0}})});
await tick();
const peerState = {participants: [{node: "outside", mine: false, name: "peer"}]};
let deliverWorksheet;
fetchWorksheet = new Promise(resolve => { deliverWorksheet = resolve; });
sheet.revision++;
model("outside").position.x = 365;
finishPoll(Response.json({...peerState, version: "2", revision: sheet.revision}));
await tick();
assert.equal(graphic("outside").props.transform, "translate(365 0)", "keep the drag preview until the GET completes");
deliverWorksheet();
await tick();
assert.equal(graphic("outside").props.transform, "translate(365 0)");
model("outside").position.x = 340;
sheet.revision++;
finishPoll(Response.json({participants: [], version: "3", revision: sheet.revision}));
await tick();
checkpoint = structuredClone(sheet);

const oneWire = () => find(n => n.tag === "g" && n.props["data-edge"] === "one");
// Minden vonal minden (nem kiemelt) doboz fölött van.
assert.ok(oneWire().parent.children.indexOf(oneWire()) > oneWire().parent.children.indexOf(graphic("outside")));
const panel = () => find(n => n.tag === "aside" && n.props["aria-label"] !== "Munkalap");
const titleActions = [];
const labelInput = () => prop("data-object-label", "", panel());
root.querySelector = selector => {
  if (selector !== ".object-inspector [data-object-label]") return null;
  const title = labelInput();
  if (!title) return null;
  title.focus = () => titleActions.push("focus");
  title.select = () => titleActions.push(title.props.value);
  return title;
};
const canvasPanel = () => find(n => n.tag === "aside" && n.props["aria-label"] === "Munkalap");
// A munkalap megjelenése a vászonpanel „Megjelenés” gombjára középen felugró panelben (editor.js renderAppearancePopup).
const appearancePanel = () => find(n => n.tag === "aside" && n.props["aria-label"] === "Megjelenés");
const openAppearance = async () => {
  if (appearancePanel()) return;
  find(n => n.tag === "button" && text(n) === "Megjelenés", canvasPanel()).props.onClick(); await tick();
};
const sidebarToggle = () => find(n => n.tag === "button" && n.props["aria-label"]?.startsWith("Oldalsáv "));
const canvasToggle = () => find(n => n.tag === "button" && n.props["aria-label"]?.startsWith("Vászonbeállítások "));
const headerHistory = prop("class", "worksheet-history");
const closeEditor = find(n => n.tag === "a" && n.props["aria-label"] === "Bezárás");
for (const control of [...headerHistory.children, closeEditor, sidebarToggle(), canvasToggle()]) {
  assert.ok(control.props.class.split(" ").includes("header-button"));
}
assert.ok(!panel() && !canvasPanel(), "no selection shows neither inspector initially");
oneWire().props.onClick();
await tick();
assert.equal(panel()?.props["aria-label"], "Vonal szerkesztése");
assert.ok(button("Egyenes"), "selecting a wire opens its editable properties directly");
canvasToggle().props.onClick(); await tick();
assert.ok(panel() && canvasPanel());
assert.ok(find(n => n.tag === "input" && n.props.value === sheet.title, canvasPanel()));
assert.equal(find(n => n.tag === "button" && text(n) === "Sorkizárás", canvasPanel()), undefined);
assert.ok(button("Fájl feltöltése"));
const emptyCanvasEvent = (x, y) => event(canvas(), x, y, {target: {closest: () => null}});
// Egérrel csak a jobb gomb pásztáz (objektum fölött is); a bal gomb, a szóköz és a vászonmozgatás-zár megszűnt.
assert.equal(prop("aria-label", "Vászonmozgatás zárolása"), undefined, "no pan-lock toolbar button");
const plainPress = {button: 0, type: "mousedown", target: {closest: () => null}};
const rightPan = {...plainPress, button: 2};
assert.equal(zoomEvents.filter(plainPress), false, "the left button does not pan");
assert.equal(zoomEvents.filter({...plainPress, target: {closest: () => graphic("outer")}}), false);
assert.equal(zoomEvents.filter(rightPan), true, "the right button pans the empty canvas");
assert.equal(zoomEvents.filter({...rightPan, target: {closest: () => graphic("outer")}}), true, "the right button pans over objects too");
assert.equal(zoomEvents.filter({...rightPan, ctrlKey: true}), false, "Ctrl + right button is left for cables");
const touches = (coordinates) => ({preventDefault() {}, touches: coordinates.map(([clientX, clientY], identifier) =>
  ({identifier, clientX, clientY}))});
canvas().props.onTouchstartCapture(touches([[10, 10], [30, 10]]));
canvas().props.onTouchmoveCapture(touches([[18, 16], [38, 16]]));
assert.deepEqual([requestedZoom.x, requestedZoom.y, requestedZoom.k], [8, 6, 1]);
canvas().props.onTouchmoveCapture(touches([[17, 16], [43, 16]]));
assert.deepEqual([requestedZoom.x, requestedZoom.y, requestedZoom.k], [10, 6, 1]);
canvas().props.onTouchmoveCapture(touches([[0, 10], [40, 10]]));
assert.equal(requestedZoom.k, 1.7);
canvas().props.onTouchmoveCapture(touches([[2, 10], [40, 10]]));
assert.equal(requestedZoom.k, 1.7);
canvas().props.onTouchendCapture(touches([]));
assert.equal(zoomEvents.filter({...plainPress, type: "wheel"}), true);
listeners.keydown({key: " ", code: "Space", preventDefault() {}});
await tick();
assert.equal(canvas().props["data-drag-cursor"], undefined, "Space no longer switches to panning");
listeners.keyup({type: "keyup", key: " ", code: "Space"});
// Jobb kattintás: a helyi menü a felengedéskor nyílik, ha közben nem volt (küszöb fölötti) mozgás.
globalThis.innerWidth = 1200;
globalThis.innerHeight = 800;
const contextMenuOpen = () => !!button("Objektum létrehozása");
const rightAt = (x, y, extra = {}) => event(canvas(), x, y, {button: 2, target: {closest: () => null}, ...extra});
const rightRelease = (x, y, type = "pointerup") => listeners[type]({...rightAt(x, y), type});
// macOS: a contextmenu már a lenyomáskor jön; a menü csak felengedéskor nyílik.
canvas().props.onPointerdownCapture(rightAt(300, -100));
canvas().props.onContextmenu(rightAt(300, -100));
await tick();
assert.ok(!contextMenuOpen(), "the menu waits for the release");
rightRelease(302, -98);
await tick();
assert.ok(contextMenuOpen(), "a still right click opens the menu on release");
toggle("Escape", true); await tick();
// Mozgással (pásztázás) nincs menü, akármikor jön a contextmenu.
canvas().props.onPointerdownCapture(rightAt(300, -100));
canvas().props.onContextmenu(rightAt(300, -100));
listeners.pointermove({...rightAt(340, -60), type: "pointermove"});
rightRelease(300, -100);
await tick();
assert.ok(!contextMenuOpen(), "a right drag pans without opening the menu");
// Windows: a contextmenu a felengedés után jön.
canvas().props.onPointerdownCapture(rightAt(300, -100));
rightRelease(301, -100);
canvas().props.onContextmenu(rightAt(301, -100));
await tick();
assert.ok(contextMenuOpen(), "contextmenu after a still release opens the menu");
toggle("Escape", true); await tick();
canvas().props.onPointerdownCapture(rightAt(300, -100));
listeners.pointermove({...rightAt(300, -140), type: "pointermove"});
rightRelease(300, -100);
canvas().props.onContextmenu(rightAt(300, -100));
await tick();
assert.ok(!contextMenuOpen(), "contextmenu after a right drag is ignored");
oneWire().props.onClick(); await tick();
assert.ok(panel() && canvasPanel());
const wirePointerHandler = oneWire().props.onPointerdown;
canvas().props.onPointerdownCapture(emptyCanvasEvent(280, 180));
zoomEvents.zoom({transform: d3.zoomIdentity.translate(25, 15), sourceEvent: {type: "mousemove"}});
await tick();
const shieldCursor = () => prop("class", "drag-shield").props.style.cursor;
assert.equal(shieldCursor(), "grabbing");
zoomEvents.end();
canvas().props.onPointerup(emptyCanvasEvent(305, 195));
await tick();
assert.equal(shieldCursor(), "auto");
assert.equal(canvas().props["data-drag-cursor"], undefined);
assert.ok(panel() && canvasPanel(), "panning keeps the selection and both inspectors");
assert.equal(oneWire().props.onPointerdown, wirePointerHandler, "panning keeps the scene render intact");
zoomEvents.zoom({transform: d3.zoomIdentity});
const backgroundClick = emptyCanvasEvent(280, 180);
canvas().props.onPointerdownCapture(backgroundClick);
canvas().props.onClick(backgroundClick);
await tick();
assert.ok(!panel() && canvasPanel(), "clicking empty canvas hides only the object inspector");
assert.equal(sidebarToggle().props["aria-expanded"], true);
oneWire().props.onClick(); await tick();
assert.ok(panel() && canvasPanel(), "reselecting shows the object panel again");
sidebarToggle().props.onClick(); await tick();
oneWire().props.onClick(); await tick();
assert.ok(!panel() && canvasPanel(), "single-click respects a manual close");
oneWire().props.onDblclick({stopPropagation() {}}); await tick();
assert.ok(!panel() && canvasPanel(), "double-click respects a manual close");
toggle("Escape", true); await tick();
oneWire().props.onClick(); await tick();
assert.ok(!panel() && canvasPanel(), "manual close survives deselection and reselecting");
sidebarToggle().props.onClick(); await tick();
assert.ok(panel() && canvasPanel(), "the object toggle reopens the panel for the current selection");
canvasToggle().props.onClick(); await tick();
assert.ok(panel() && !canvasPanel(), "the canvas toggle closes only the canvas panel");
toggle("Escape", true); await tick();

for (const ctrlKey of [false, true]) {
  await properties("outer");
  sidebarToggle().props.onClick(); await tick();
  for (let click = 0; click < 2; click++) {
    const target = graphic("outer");
    target.props.onPointerdown(event(target, 0, 0, {ctrlKey}));
    canvas().props.onPointerup(event(canvas(), 0, 0, {ctrlKey}));
    await tick();
  }
  assert.ok(!panel());
  // A doboz szövege a dobozon, a szöveg helyén szerkeszthető (nincs fölé tett szövegmező).
  assert.equal(prop("class", "inline-edit", graphic("outer")), undefined);
  graphic("outer").props.onDblclick({stopPropagation() {}, ctrlKey}); await tick(); await tick();
  assert.ok(prop("class", "box-edit", graphic("outer")), "double-click edits the box text in place");
  assert.equal(prop("class", "node-text", graphic("outer")), undefined, "the editor replaces the drawn text");
  toggle("Escape", true); await tick();
  sidebarToggle().props.onClick(); await tick();
  toggle("Escape", true); await tick();
}

const down = event(graphic("outer"), 0, 0);
graphic("outer").props.onPointerdown(down);
await tick();
const beforeDrag = writes;
for (let x = 1; x <= 24; x++) {
  canvas().props.onPointermove(event(canvas(), x, 20));
  await new Promise(resolve => setTimeout(resolve, 8));
}
assert.equal(writes, beforeDrag, "holding and moving must not write the worksheet");
canvas().props.onPointerup(event(canvas(), 24, 20));
await new Promise(resolve => setTimeout(resolve, 150));
assert.equal(writes, beforeDrag + 1);
await press("Visszavonás"); await save();
assert.deepEqual(model("outer").position, {x: 0, y: 0});
assert.ok(button("Visszavonás").props.disabled);
await press("Újra");
await new Promise(resolve => setTimeout(resolve, 100));
await save();
await drag(graphic("outer"), 24, 20, 0, 0);
await save();

// Duplicate connections and the box as one operation, and discard a cancelled drag.
const sourceBeforeClone = structuredClone(model("outside"));
await drag(graphic("outside"),340,0,390,45,{altKey:true},true);
await save();
assert.equal(sheet.nodes.length,5);
const cloneSource = graphic("outside");
cloneSource.props.onPointerdown(event(cloneSource, 340, 0, {altKey: true}));
canvas().props.onPointermove(event(canvas(), 390, 45, {altKey: true}));
const wireCount = () => {
  const wires = find(n => n.tag === "g" && n.props["data-edge"] === "one").parent;
  return wires.children.filter(n => n.props["data-edge"]).length;
};
await tick();
assert.equal(wireCount(), 2);
listeners.keydown({key: "Shift", altKey: true, shiftKey: true});
await tick();
assert.equal(wireCount(), 3, "pressing Shift without moving shows the proposed link");
listeners.keyup({key: "Shift", altKey: true, shiftKey: false});
await tick();
assert.equal(wireCount(), 2, "releasing Shift without moving hides the proposed link");
titleActions.length = 0;
canvas().props.onPointerup(event(canvas(), 390, 45, {altKey: true, shiftKey: true}));
await save();
assert.deepEqual(titleActions, ["focus", "outside"]);
const duplicate = sheet.nodes.find(n => n.text === "outside" && n.id !== "outside");
assert.deepEqual(duplicate.position,{x:390,y:45});
assert.equal(duplicate.fill,sourceBeforeClone.fill);
assert.ok(sheet.edges.some(e => e.source === "outside" && e.target.node === duplicate.id && e.endArrow));
assert.ok(sheet.edges.some(e => e.source === duplicate.id));
assert.deepEqual(model("outside"),sourceBeforeClone);
await press("Visszavonás"); await save();
assert.equal(sheet.nodes.length,5);
assert.equal(sheet.edges.length,1);

const unlinkedSource = graphic("outside");
unlinkedSource.props.onPointerdown(event(unlinkedSource, 340, 0, {altKey: true, shiftKey: true}));
canvas().props.onPointermove(event(canvas(), 390, 45, {altKey: true, shiftKey: true}));
canvas().props.onPointerup(event(canvas(), 390, 45, {altKey: true, shiftKey: false}));
await save();
assert.equal(sheet.nodes.length, 6);
assert.equal(sheet.edges.length, 2, "dropping after releasing Shift keeps only the duplicated connection");
await press("Visszavonás"); await save();

// Rectangle selection, one-step group moves/deletes and alignment on release.
function selectArea(x, y, endX, endY, keys = {}) {
  const area = canvas();
  area.props.onPointerdownCapture(event(area,x,y,{altKey:true,...keys,target:{closest:()=>null}}));
  area.props.onPointermove(event(area,endX,endY,{altKey:true}));
  area.props.onPointerup(event(area,endX,endY,{altKey:true}));
}
selectArea(-160,-130,160,130);
await tick();
assert.equal(panel().props["aria-label"], "Objektumok");
assert.ok(text(panel()).includes("3 doboz, 0 vonal, 0 csomópont"));
function shiftClick(id) {
  const target = {closest: selector => selector.includes("[data-node]") ? {dataset: {node:id}} : null};
  canvas().props.onPointerdownCapture(event(canvas(),0,0,{shiftKey:true,target}));
}
selectArea(389,-2,392,2,{shiftKey:true,ctrlKey:true}); await tick();
assert.ok(text(panel()).includes("4 doboz, 0 vonal"));
shiftClick("outside"); await tick();
assert.ok(text(panel()).includes("3 doboz, 0 vonal"));
selectArea(370,125,380,132,{ctrlKey:true,shiftKey:true}); await tick();
assert.ok(text(panel()).includes("3 doboz, 1 vonal"));
selectArea(-160,-130,160,130); await tick();
canvas().props.onPointerdownCapture(event(canvas(),0,0,{target:{closest: selector => selector.includes("[data-node]") ? {dataset:{node:"outer"}} : null}}));
canvas().props.onPointermove(event(canvas(),25,35));
canvas().props.onPointerup(event(canvas(),25,35));
await save();
assert.deepEqual(model("child").position,{x:35,y:45});
assert.deepEqual(model("outer").position,{x:25,y:35});
await press("Visszavonás"); await save();
assert.deepEqual(model("child").position,{x:10,y:10});
listeners.keydown({key:"Delete"}); await save();
assert.ok(!model("child") && !model("outer") && !model("inner"));
await press("Visszavonás"); await save();
assert.ok(model("outer") && model("inner") && model("child"));
const titleSpan = find(n => n.tag === "tspan" && text(n) === "outer",graphic("outer"));
titleSpan.props.onPointerdown(event(titleSpan,0,0,{altKey:true,ctrlKey:true}));
await tick();
canvas().props.onPointermove(event(canvas(),125,-90,{altKey:true}));
canvas().props.onPointerup(event(canvas(),125,-90,{altKey:true}));
await save();
assert.equal(model("outer").alignment,"right");
assert.equal(model("outer").verticalAlignment,"top");
await press("Visszavonás"); await save();
assert.equal(model("outer").alignment,"center");
await properties("outer");
const titleInput = () => labelInput();
panel().props.onInputCapture();
titleInput().props.onInput({target: {value: "first"}});
await save();
titleInput().props.onInput({target: {value: "finished"}});
panel().props.onFocusout();
await press("Visszavonás"); await save();
assert.equal(model("outer").text, "outer\n\nchild");
panel().props.onInputCapture();
titleInput().props.onInput({target: {value: "temporary"}});
titleInput().props.onInput({target: {value: "outer\n\nchild"}});
panel().props.onFocusout();
await tick();
assert.equal(button("Újra").props.disabled, false, "an unchanged field preserves redo");
await press("Újra"); await save();
assert.equal(model("outer").text, "finished");
titleInput().props.onInput({target: {value: "outer\n\nchild"}});
panel().props.onFocusout();
await save();
assert.equal(button("Konténer"), undefined);
await drag(graphic("outer"), 0, 0, 9, 10); await save();
assert.equal(model("outer").parent, undefined);
assert.equal(model("inner").parent, undefined);
assert.equal(model("child").parent, undefined);
await drag(graphic("outer"), 9, 10, 0, 0); await save();
const candidateBorder = id => prop("data-container-candidate", "", graphic(id));
const isContainer = id => sheet.nodes.find(n => n.id === id)?.container === true;
const placeChild = event(graphic("child"), 10, 10);
graphic("child").props.onPointerdown(placeChild);
const childOverInner = event(canvas(), 20, 10);
canvas().props.onPointermove(childOverInner); await tick();
assert.equal(candidateBorder("inner").props["stroke-dasharray"], "10 7");
assert.equal(candidateBorder("outer"), undefined);
assert.equal(isContainer("inner"), false);
canvas().props.onPointercancel(childOverInner); await tick();
assert.equal(candidateBorder("inner"), undefined);
await drag(graphic("child"), 10, 10, 20, 10); await save();
assert.equal(isContainer("inner"), true);
assert.equal(candidateBorder("inner"), undefined);
await drag(graphic("child"), 20, 10, 10, 10); await save();
await drag(graphic("inner"), 10, 10, 20, 10); await save();
await drag(graphic("inner"), 20, 10, 10, 10);
await save();
assert.equal(model("child").parent, "inner");
assert.equal(model("inner").parent, "outer");
assert.equal(isContainer("outer"), true);
const beforeInnerWire = sheet.edges.length;
await drag(graphic("outer"), 140, 70, 105, 70, {ctrlKey: true});
await save();
assert.equal(sheet.edges.length, beforeInnerWire, "an inward drag over empty space cannot connect to the source");
await drag(graphic("outer"), 140, 70, 10, 10, {ctrlKey: true});
await save();
const innerWire = sheet.edges.find(e => e.source === "outer" && e.target.node === "child");
assert.ok(innerWire, "an inward drag connects to the innermost box");
const orderedScene = graphic("outer").parent.children;
const wireGraphic = prop("data-edge", innerWire.id);
assert.ok(orderedScene.indexOf(wireGraphic) > orderedScene.indexOf(graphic("inner")), "the wire paints over both containers");
assert.ok(orderedScene.indexOf(wireGraphic) > orderedScene.indexOf(graphic("child")), "the wire paints over the inner box too");
await press("Visszavonás"); await save();
await properties("outer");
const outerText = prop("aria-label", "Text", panel());
const originalText = model("outer").text;
const renderedBody = () => prop("data-body-row", "", graphic("outer"));
await new Promise(resolve => setTimeout(resolve, 100));
assert.equal(text(renderedBody()), originalText.split("\n")[0]);
outerText.props.onInput({target: {value: "Új dobozszöveg"}});
await tick();
assert.equal(text(renderedBody()), originalText.split("\n")[0], "the last rendered text stays visible while Markdown is pending");
outerText.props.onInput({target: {value: originalText}});
await tick();
await drag(graphic("outer"), -100, -100, -60, -70);
await save();
assert.deepEqual(model("child").position, {x: 50, y: 40});
assert.deepEqual(model("inner").position, {x: 50, y: 40});
await properties("outer");
await press("Tartalom rögzítése");
assert.equal(prop("data-locked-outline", "", graphic("outer")).props["stroke-width"], 6.4);
await drag(graphic("child"), 50, 40, 95, 62);
await save();
assert.deepEqual(model("child").position, {x: 50, y: 40});
await drag(graphic("outside"), 340, 0, 190, 30); await save();
assert.equal(model("outside").parent, undefined, "exactly 50 percent is insufficient");
await drag(graphic("outside"), 190, 30, 180, 30); await save();
assert.equal(model("outside").parent, "outer");
await properties("outer");
assert.equal(button("Konténer feloldása"), undefined);
await press("Tartalom rögzítése");
await drag(graphic("outer"), 40, 30, 440, -270); await save();
await drag(graphic("inner"), 450, -260, 50, 40); await save();
await drag(graphic("outside"), 580, -270, 180, 30); await save();
assert.equal(model("inner").parent, undefined);
assert.equal(model("child").parent, "inner");
assert.equal(model("outside").parent, undefined);
// A kiürült konténer újra sima doboz: mozgatva nem fog be más dobozt, akárhogy fedi.
assert.equal(isContainer("outer"), false, "an emptied container is a plain box again");
await drag(graphic("outer"), 440, -270, 330, 30); await save();
assert.equal(model("outside").parent, undefined);
await drag(graphic("outer"), 330, 30, 320, 30); await save();
assert.equal(model("outside").parent, undefined, "a plain box captures nothing when it is moved over another box");
// A ráejtett doboztól újra konténer lesz.
await drag(graphic("outside"), 180, 30, 195, 30); await save();
assert.equal(model("outside").parent, "outer");
assert.equal(isContainer("outer"), true);
await drag(graphic("outside"), 195, 30, 180, 30); await save();
assert.equal(model("outside").parent, "outer");
assert.deepEqual(model("outside").position, {x: 180, y: 30});
await properties("outside");
assert.equal(button("Kiemelés").props["aria-pressed"], false);
await press("Kiemelés"); await save();
assert.equal(model("outside").elevated, true);
assert.equal(model("outside").parent, undefined);
assert.deepEqual(model("outside").position, {x: 180, y: 30});
assert.equal(button("Kiemelés").props["aria-pressed"], true);
const shadow = prop("class", "node-shadow", graphic("outside"));
assert.ok(shadow);
assert.equal(find(n => n.props.stroke !== undefined, shadow), undefined);
assert.equal(text(button("Kiemelés")), "");
assert.equal(prop("id", "elevated-box-shadow"), undefined);
assert.ok(graphic("outside").parent.children.indexOf(graphic("outside")) > graphic("outer").parent.children.indexOf(graphic("outer")));
await drag(graphic("outside"), 180, 30, 300, 40); await save();
assert.equal(model("outside").parent, undefined, "an elevated box cannot be dropped into a container");
await press("Visszavonás"); await save();
await drag(graphic("outer"), 320, 30, 310, 30); await save();
assert.equal(model("outside").parent, undefined, "a moving container cannot capture an elevated box");
await press("Visszavonás"); await save();
await properties("outside");
await press("Kiemelés"); await save();
assert.equal(prop("class", "node-shadow", graphic("outside")), undefined);
await drag(graphic("outside"), 180, 30, 195, 30); await save();
assert.equal(model("outside").parent, "outer", "turning elevation off allows containment again");
await press("Visszavonás"); await save();
await press("Visszavonás"); await save();
await press("Visszavonás"); await save();
assert.equal(model("outside").elevated, undefined);
assert.equal(model("outside").parent, "outer");
// A dobozt két húzás tette a konténerbe (oda és vissza a helyére): mindkettőt vissza kell vonni.
await press("Visszavonás"); await save();
await press("Visszavonás"); await save();
assert.equal(model("outside").parent, undefined);
await press("Visszavonás"); await save();

// A drag from the middle attaches to the box even when it starts away from its border.
canvas().props.onPointermove(event(canvas(), 180, 30, {ctrlKey: true}));
await tick();
assert.equal(find(n => n.props["data-anchor"]), undefined);
sidebarToggle().props.onClick();
titleActions.length = 0;
await drag(graphic("outside"), 180, 30, -420, 0, {ctrlKey: true});
assert.deepEqual(titleActions, ["focus", ""], "creating an arrow reopens the inspector and focuses its label");
labelInput().props.onInput({target: {value: "Új kapcsolat"}});
await save();
assert.equal(sheet.edges.at(-1).source, "outside");
assert.deepEqual(sheet.edges.at(-1).target, {node: "auto"});
assert.equal(sheet.edges.at(-1).label, "Új kapcsolat");
await press("Visszavonás"); await save();
await press("Visszavonás"); await save();

// A további lépések a (közben kiürült, így sima dobozzá vált) „outer" dobozt a régi, távoli helyén várják.
const outerPlace = model("outer").position;
if (outerPlace.x !== 440 || outerPlace.y !== -270) { await drag(graphic("outer"), outerPlace.x, outerPlace.y, 440, -270); await save(); }
assert.deepEqual(model("outer").position, {x: 440, y: -270});
const free = endpoint("one", "target");
assert.ok(["circle", "path"].includes(free.tag));
assert.ok(["all", "stroke"].includes(free.props["pointer-events"]));
const attached = endpoint("one", "source");
const endpointLayer = attached.parent;
assert.ok(endpointLayer.parent.children.indexOf(endpointLayer) > endpointLayer.parent.children.indexOf(graphic("outside")));
const [, attachedX, attachedY] = /translate\(([^ ]+) ([^)]+)\)/.exec(attached.props.transform);
const anchor = model("outside");
const dx = +attachedX - anchor.position.x, dy = +attachedY - anchor.position.y;
const outward = Math.abs(dx) / anchor.width >= Math.abs(dy) / anchor.height
  ? {x: 6 * Math.sign(dx), y: 0} : {x: 0, y: 6 * Math.sign(dy)};
const originalCapture = canvas().setPointerCapture;
let capturePointer;
canvas().setPointerCapture = pointerId => { capturePointer = pointerId; };
attached.props.onPointerdown(event(attached, +attachedX, +attachedY));
assert.equal(capturePointer, 1);
const shortPull = event(canvas(), +attachedX + outward.x, +attachedY + outward.y);
canvas().props.onPointermove(shortPull); await tick();
assert.equal(shieldCursor(), "grabbing");
canvas().props.onPointerup(shortPull); await save();
canvas().setPointerCapture = originalCapture;
assert.equal(edge("one").source, undefined);
assert.deepEqual(edge("one").sourcePoint, {x: +attachedX + outward.x, y: +attachedY + outward.y});
await press("Visszavonás"); await save();
assert.equal(edge("one").source, "outside");
await drag(graphic("outside"), 180, 30, 400, 230, {ctrlKey: true});
await save();
assert.equal(sheet.nodes.some(n => n.type === "junction"), false, "duplicate route cannot create a junction");
await drag(graphic("auto"), -420, 0, 400, 230, {ctrlKey: true});
await save();
const junction = sheet.nodes.find(n => n.type === "junction");
assert.equal(edge("one").target.node, junction.id);
const secondID = sheet.edges.at(-1).id;
assert.equal(edge(secondID).target.node, junction.id);
await drag(graphic("child"), 50, 40, 400, 230, {ctrlKey: true});
await save();
assert.equal(sheet.edges.at(-1).target.node, junction.id);
const junctionWires = sheet.edges.filter(e => e.target.node === junction.id).map(e => e.id);
await drag(graphic(junction.id), 400, 230, 180, 30); await save();
assert.deepEqual(model(junction.id).position, junction.position, "an invalid loop leaves the junction in place");
assert.ok(junctionWires.every(id => edge(id).target.node === junction.id));
await drag(graphic(junction.id), 400, 230, 440, -270, {}, true); await save();
assert.ok(junctionWires.every(id => edge(id).target.node === junction.id));
await drag(graphic(junction.id), 400, 230, 440, -270); await save();
// Az „outer" itt már üres, tehát sima doboz: a ráejtett csomópont feloldódik benne.
assert.equal(model(junction.id), undefined);
assert.ok(junctionWires.every(id => edge(id).target.node === "outer"));
await press("Visszavonás"); await save();
assert.ok(model(junction.id));
assert.ok(junctionWires.every(id => edge(id).target.node === junction.id));
shiftClick(junction.id); await tick();
const batchJunctionHit = {closest: selector => selector.includes("[data-node]") ? {dataset: {node: junction.id}} : null};
canvas().props.onPointerdownCapture(event(canvas(), 400, 230, {target: batchJunctionHit}));
canvas().props.onPointermove(event(canvas(), 440, -270));
await tick();
canvas().props.onPointerup(event(canvas(), 440, -270));
await save();
assert.equal(model(junction.id), undefined);
assert.ok(junctionWires.every(id => edge(id).target.node === "outer"));
await press("Visszavonás"); await save();
await detachDrag("one", "target", 450, 245, true);
assert.equal(endpoint("one", "target").props.class, "wire-handle is-attached", "cancel restores the attachment");
await detachDrag("one", "target", 450, 245);
await save();
assert.ok(edge("one").target.point);
assert.ok(model(junction.id));
await detachDrag(secondID, "target", 430, 290);

await save();
assert.equal(model(junction.id), undefined);
assert.deepEqual(sheet.edges.at(-1).target.point, junction.position);
const originBox = graphic("outside");
originBox.props.onPointerdown(event(originBox, 180, 30, {ctrlKey: true}));
canvas().props.onPointermove(event(canvas(), 434, 292));
await tick();
const marker = find(n => n.tag === "circle" && n.props.stroke === "#078469");
assert.deepEqual([marker.props.cx, marker.props.cy], [430, 290]);
canvas().props.onPointerup(event(canvas(), 434, 292));
await save();
const joint = sheet.nodes.find(n => n.type === "junction");
const incident = sheet.edges.filter(e => e.source === joint.id || e.target.node === joint.id).map(e => e.id);
assert.equal(incident.length, 2);
const {edgeGeometry: geometry} = await import("../../Public/geometry.js");
const [longer, shorter] = incident.map(edge).sort((a,b) => geometry(b,model).length-geometry(a,model).length);
await properties(joint.id);
listeners.keydown({key:"Delete"}); await tick(); await save();
assert.ok(!model(joint.id) && !edge(shorter.id) && edge(longer.id));
assert.ok(![edge(longer.id).source, edge(longer.id).target.node].includes(joint.id));
await press("Visszavonás"); await save();
assert.ok(model(joint.id) && incident.every(edge));
await properties(joint.id);
listeners.keydown({key: "Backspace", ctrlKey: true}); await tick(); await save();
assert.ok(!model(joint.id) && incident.every(id => edge(id) && ![edge(id).source,edge(id).target.node].includes(joint.id)));
const freeStart = event(canvas(), -600, -320, {ctrlKey: true, target: {closest: () => null}});
canvas().props.onPointerdownCapture(freeStart);
canvas().props.onPointermove(event(canvas(), -510, -315));
canvas().props.onPointerup(event(canvas(), -510, -315));
await save();
assert.deepEqual(sheet.edges.at(-1).sourcePoint, {x: -600, y: -320});
assert.deepEqual(sheet.edges.at(-1).target.point, {x: -510, y: -315});
assert.equal(sheet.edges.at(-1).endArrow, true);
const freeWire = find(n => n.tag === "g" && n.props["data-edge"] === sheet.edges.at(-1).id);
assert.ok(find(n => n.props.d === "M0 0L-1 -.5V.5Z" && n.props.transform.startsWith("translate(-510 -315)"),freeWire));
const freeShaft = find(n => n.props.class === "wire-line", freeWire);
assert.equal(freeShaft.props["stroke-linecap"], "butt");
const shaftEnd = freeShaft.props.d.split(" ").slice(-2).map(Number);
assert.ok(Math.abs(Math.hypot(shaftEnd[0]+510,shaftEnd[1]+315)-6.75*freeShaft.props["stroke-width"]) < 1e-8);
const freeHandle = endpoint(sheet.edges.at(-1).id, "source");
assert.ok(freeHandle);

const freeLength = Math.hypot(90, 5);
freeWire.querySelector = () => ({
  getTotalLength: () => freeLength,
  getPointAtLength: distance => ({x: -600 + 90 * distance / freeLength, y: -320 + 5 * distance / freeLength}),
});
let selectionPrevented = false;
freeWire.props.onPointerdown(event(freeWire, -555, -317.5, {
  preventDefault() { selectionPrevented = true; },
}));
assert.ok(selectionPrevented, "pressing the middle of a wire suppresses native text selection");
titleActions.length = 0;
await drag(freeWire, -555, -317.5, -550, -300, {ctrlKey: true});
assert.equal(panel().props["aria-label"], "Csomópont");
assert.deepEqual(titleActions, ["focus", ""]);
await press("Visszavonás"); await save();

const freeWireID = freeWire.props["data-edge"];
const wireBeforeSplit = structuredClone(edge(freeWireID));
await drag(freeWire, -555, -317.5, -420, 0, {ctrlKey: true}); await save();
assert.equal(sheet.nodes.some(node => node.type === "junction"), false);
assert.deepEqual(edge(freeWireID).target, {node: "auto"});
assert.ok(sheet.edges.some(e => e.source === "auto" && e.target.point?.x === -510 && e.target.point?.y === -315));
await press("Visszavonás"); await save();
assert.deepEqual(edge(freeWireID), wireBeforeSplit);

for (const [id, x, y, automatic] of [["outside",180,30,false], ["auto",-420,0,true]]) {
  canvas().props.onPointermove(event(canvas(), x, y));
  toggle("Alt", true); await tick();
  assert.equal(find(n => n.props.cursor === "nwse-resize", graphic(id === "auto" ? "outside" : "auto")), undefined);
  const corner = find(n => n.props.cursor === "nwse-resize" && n.props.x > 0, graphic(id));
  const cx = x + corner.props.x + 5, cy = y + corner.props.y + 5;
  await drag(corner, cx, cy, cx+40, cy+30, {altKey: true});
  await save();
  assert.ok(model(id).width > (automatic ? 64 : 100));
  assert.equal(model(id).fontSize, 16);
}
await properties("outside");
assert.equal(prop("aria-label", "Háttér HEX"), undefined);
prop("aria-label","Háttér színválasztó").props.onClick(); await tick();
prop("aria-label","Moha").props.onClick(); await tick();
assert.ok(prop("fill","#29a383", graphic("outside")));
assert.equal(find(n => n.props.type === "range", panel()), undefined);
assert.ok(prop("aria-label", "Korall"), "the palette stays open after choosing a color");
prop("aria-label", "Korall").props.onClick(); await tick();
prop("aria-label", "Moha").props.onClick(); await tick();
assert.ok(prop("fill","#29a383", graphic("outside")));
const section = label => find(n => n.tag === "fieldset" && n.children[0]?.text === label);
const control = (scope, label) => prop("aria-label", label, scope);
const edit = (control, value) => control.props.onInput({target: {value}});
const animationPicker = prop("aria-label", "Animáció", section("Doboz"));
assert.equal(animationPicker.children.length, 5);
assert.ok(animationPicker.children.every(option => text(option) === ""));
assert.equal(button("Nincs animáció").props["aria-pressed"], true);
// A szerkesztőben CSS-animáció (app.css „Tartalom-animációk”): a csoport jelzi a módot, SMIL-elem nincs benne.
for (const [option, mode] of [["Pulzálás", "pulse"], ["Villogás", "blink"], ["Ringatózás", "rock"], ["Ugrálás", "hop"]]) {
  await press(option);
  const animated = prop("data-box-animation", mode, graphic("outside"));
  assert.equal(animated.props.class, "node-motion");
  assert.deepEqual(animated.children.filter(n => n.tag.startsWith("animate")), []);
}
await save();
assert.equal(model("outside").animation, "hop");
await press("Nincs animáció");
assert.equal(prop("data-box-animation", "hop", graphic("outside")), undefined);
assert.equal(button("Free").props["aria-pressed"], false);
await press("Free"); await save();
assert.equal(model("outside").backgroundMode, "free");
assert.equal(prop("aria-label", "Háttér színválasztó").props.disabled, false);
assert.ok(prop("class", "palette-tile transparent-swatch", prop("aria-label", "Háttér színválasztó")));
assert.equal(prop("pointer-events", "fill", graphic("outside")).props.stroke, "none");
assert.equal(prop("pointer-events", "fill", graphic("outside")).props.fill, "none");
assert.equal(find(n => n.tag === "clipPath", graphic("outside")), undefined);
await press("Üres"); await save();
assert.equal(model("outside").backgroundMode, "empty");
assert.equal(button("Free").props["aria-pressed"], false);
const emptySurface = prop("class", "node-surface", graphic("outside"));
assert.equal(emptySurface.props.fill, "none");
assert.notEqual(emptySurface.props.stroke, "none");
// Az elmosott háttér megszűnt; a vászonszín (a munkalap háttérszíne, rács nélkül) a paletta 0. színe, minden dobozon
// választható (a külön „Vászonszín” gomb megszűnt).
assert.equal(button("Elmosott"), undefined);
assert.equal(prop("id", "box-background-blur"), undefined);
assert.equal(button("Vászonszín (a rács nem látszik át)"), undefined);
await press("Üres"); await save();
assert.equal(model("outside").backgroundMode, undefined);
const backgroundPicker = () => prop("aria-label", "Háttér színválasztó");
const ownFill = model("outside").fill;
if (!backgroundPicker().props["aria-expanded"]) backgroundPicker().props.onClick();
await tick();
const swatches = () => find(n => n.props?.class?.includes?.("color-tools"), backgroundPicker().parent);
assert.equal(prop("class", "canvas-swatch", swatches()), swatches().children.filter(n => n.tag === "button")[1]);
prop("class", "canvas-swatch", swatches()).props.onClick(); await save();
assert.equal(model("outside").fill, 0);
assert.equal(model("outside").backgroundMode, undefined);
const canvasSurface = prop("class", "node-surface", graphic("outside"));
assert.notEqual(canvasSurface.props.fill, "none");
assert.equal(canvasSurface.props["fill-opacity"], undefined);
assert.equal(canvasSurface.props.filter, undefined);
// Közvetlen szín a #hex mezőből (a rövid alak is); témaváltáskor is ez marad.
const hexField = () => prop("class", "color-hex", swatches());
hexField().props.onChange({target: {value: "#1A2"}}); await save();
assert.equal(model("outside").fill, "#11aa22");
assert.equal(prop("class", "node-surface", graphic("outside")).props.fill, "#11aa22");
assert.equal(hexField().props.value, "#11aa22");
hexField().props.onChange({target: {value: "zöld"}}); await save();
assert.equal(model("outside").fill, "#11aa22");
if (typeof ownFill === "number") {
  const name = JSON.parse(readFileSync("Public/themes/ThinkDefault.json", "utf8")).palettes[0].colors.find(c => c.id === ownFill).name;
  find(n => n.tag === "button" && n.props["aria-label"] === name, swatches()).props.onClick();
} else hexField().props.onChange({target: {value: ownFill}});
await save();
assert.equal(model("outside").fill, ownFill);
await press("Free"); await save();
assert.equal(model("outside").backgroundMode, "free");
assert.equal(prop("class", "node-surface", graphic("outside")), undefined);
await press("Free");
assert.ok(prop("fill", "#29a383", graphic("outside")));
assert.equal(find(n => n.tag === "clipPath", graphic("outside")), undefined);
const body = section("Text");
const titleSize = control(body, "Betűméret");
assert.equal(titleSize.props.min, 1);
assert.equal(titleSize.props.max, 10000);
const oversizedTitle = {value: "10001"};
titleSize.props.onInput({target: oversizedTitle}); await tick(); await save();
assert.equal(oversizedTitle.value, "10000");
assert.equal(model("outside").fontSize, 10000);
const undersizedTitle = {value: "0"};
titleSize.props.onInput({target: undersizedTitle}); await tick(); await save();
assert.equal(undersizedTitle.value, "1");
assert.equal(model("outside").fontSize, 1);
edit(titleSize, "16"); await tick();
assert.equal(section("Cím"), undefined, "a box has a single Text section");
const justifyButton = control(body, "Sorkizárás");
assert.equal(text(justifyButton), "");
assert.ok(prop("href", "/icons.svg#text-center", justifyButton));
assert.equal(justifyButton.props["aria-pressed"], false);
justifyButton.props.onClick(); await tick(); await save();
assert.equal(model("outside").justified, true);
assert.equal(justifyButton.props["aria-pressed"], true);
assert.ok(prop("href", "/icons.svg#justify", justifyButton));
justifyButton.props.onClick(); await tick();
assert.equal(control(body, "Összecsukás (csak az első sor)").props["aria-pressed"], false);
assert.ok(prop("href", "/icons.svg#more", control(body, "Összecsukás (csak az első sor)")));
for (const tool of ["Címsor", "Félkövér (markdown)", "Dőlt (markdown)", "Lista", "Kód", "Link (markdown)"]) assert.equal(control(body, tool), undefined, tool);
edit(control(body, "Betűméret"), "18.7");
prop("aria-label","Jobb oldal",body).props.onClick();
for (const removed of ["Félkövér", "Dőlt", "Aláhúzott"]) assert.equal(control(body, removed), undefined, removed + " is gone");
control(body, "Második betűtípus").props.onClick();
edit(labelInput(), "Törzs");
assert.equal(prop("aria-label", "Text háttér színválasztó"), undefined);
const bodyLabel = () => find(n => n.tag === "tspan" && text(n) === "Törzs", graphic("outside"));
for (let attempt = 0; !bodyLabel() && attempt < 25; attempt++) {
  await new Promise(resolve => setTimeout(resolve, 40));
  await tick();
}
const details = bodyLabel();
assert.ok(details, "the Markdown response renders the body label");
assert.equal(details.props["font-size"], 19);
assert.equal(details.props["font-style"], undefined);
assert.equal(details.props["text-anchor"], "end");
assert.equal(model("outside").font, 2);
assert.equal(details.parent.props["font-family"], "Georgia, 'Times New Roman', serif");
assert.equal(control(body, "Második betűtípus").props["aria-pressed"], true);
const autoSize = prop("aria-label", "AutoSize", body);
assert.equal(autoSize.parent.children[autoSize.parent.children.indexOf(autoSize) + 1], titleSize);
autoSize.props.onClick(); await tick(); await save();
assert.equal(autoSize.props["aria-pressed"], true);
assert.equal(model("outside").fitText, true);
assert.equal(titleSize.props.disabled, true);
autoSize.props.onClick(); await tick(); await save();
assert.equal(titleSize.props.disabled, false);
assert.equal(model("outside").fontSize, 19);
control(body, "Alap betűtípus").props.onClick();
edit(labelInput(), "outside\n\nTörzs");
panel().props.onFocusout();
await save();
toggle("Escape", true); await tick();
canvasToggle().props.onClick(); await tick();
assert.ok(!text(canvasPanel()).includes("Rácsköz"), "the appearance opens in its own popup");
assert.ok(find(n => n.tag === "a" && n.props.href === "/_naplo/test?from=%2Fedit%2Ftest", canvasPanel()), "the project log is linked from the canvas panel");
await openAppearance();
assert.ok(text(appearancePanel()).includes("Rácsköz"), "the grid spacing is part of the canvas appearance");
for (const label of ["Rácspontok színe", "Pontrács megjelenítése", "Tulajdonos", "Rejtett a főoldalon", "Nyilvános munkalap", "Szerkesztők"]) {
  assert.ok(!text(canvasPanel()).includes(label) && !text(appearancePanel()).includes(label));
}
listeners.keydown({key: "Escape"}); await tick();
assert.equal(appearancePanel(), undefined, "Escape closes the appearance popup");
canvasToggle().props.onClick(); await tick();
// A háttérrács vászonelemre (canvas) rajzolódik (editor.js drawGrid), a hamis DOM-ban nem vizsgálható.
const {automaticGridColor} = await import("../../Public/geometry.js");
assert.equal(automaticGridColor("#ffffff"), "#808080");
assert.equal(automaticGridColor("#000000"), "#808080");
assert.equal(automaticGridColor("#112233"), "#889199");
assert.equal(automaticGridColor("#ddeeff"), "#6f7780");
// A rácsra igazítás, a rács és a LowPerformance mód a „Rács és megjelenítés” csoportban van (S, G, L billentyűvel is).
// A tesztkörnyezet típusonként egy figyelőt tárol: a csoport megnyitásakor a lenyíló Esc-figyelője felülírná.
const editorKeys = listeners.keydown;
const viewGroup = () => prop("aria-label", "Rács és megjelenítés");
const openView = async () => { if (viewGroup().props["aria-expanded"] !== true) { viewGroup().props.onClick(); await tick(); } };
const labelled = prefix => find(n => n.tag === "button" && String(n.props["aria-label"] ?? "").startsWith(prefix));
const snapSwitch = () => labelled("Rácsra igazítás");
assert.equal(labelled("Rácsra igazítás"), undefined, "the view settings are inside the closed group");
viewGroup().props.onContextmenu({preventDefault() {}, stopPropagation() {}}); await tick();
assert.equal(viewGroup().props["aria-expanded"], true, "right click opens a group");
await openView();
assert.equal(snapSwitch().props["aria-pressed"], false);
editorKeys({key: "s"}); await tick();
assert.equal(snapSwitch().props["aria-pressed"], true, "S toggles snapping");
editorKeys({key: "s"}); await tick();
assert.equal(snapSwitch().props["aria-pressed"], false);
editorKeys({key: "s", target: {closest: selector => selector.includes("input") ? {} : null}}); await tick();
assert.equal(snapSwitch().props["aria-pressed"], false, "S does nothing while typing");
const lowSwitch = () => labelled("LowPerformance mód");
assert.equal(lowSwitch().props["aria-pressed"], false);
editorKeys({key: "l"}); await tick();
assert.equal(lowSwitch().props["aria-pressed"], true, "L toggles the low performance mode");
editorKeys({key: "l"}); await tick();
assert.equal(lowSwitch().props["aria-pressed"], false);
snapSwitch().props.onClick(); await tick();
const start = model("auto").position;
await drag(graphic("auto"), start.x, start.y, 121, -83);
await save();
// Rácsra illesztésnél a doboz bal felső sarka kerül rácspontra (32-es rácsköz).
const snappedBox = model("auto");
assert.deepEqual([snappedBox.width, snappedBox.height], [160, 90]);
assert.deepEqual(snappedBox.position, {x:112, y:-83});
assert.deepEqual({x: snappedBox.position.x - snappedBox.width / 2, y: snappedBox.position.y - snappedBox.height / 2}, {x:32, y:-128});
const freeCableStart = event(canvas(), -593, -352, {ctrlKey: true, target: {closest: () => null}});
canvas().props.onPointerdownCapture(freeCableStart);
canvas().props.onPointermove(event(canvas(), -492, -357));
canvas().props.onPointerup(event(canvas(), -492, -357));
await save();
const snappedWire = sheet.edges.at(-1).id;
assert.deepEqual(edge(snappedWire).sourcePoint, {x:-608, y:-352});
assert.deepEqual(edge(snappedWire).target.point, {x:-480, y:-352});
await drag(endpoint(snappedWire, "target"), -480, -352, -452, -380);
await save();
assert.deepEqual(edge(snappedWire).target.point, {x:-448, y:-384});
await press("Visszavonás"); await save();
await press("Visszavonás"); await save();
assert.equal(edge(snappedWire), undefined);

await openView();
snapSwitch().props.onClick(); await tick();
const transform = d3.zoomIdentity.translate(35, 75).scale(2);
zoomEvents.zoom({transform}); await tick();
const gridWrites = writes;
await openView();
assert.equal(labelled("Saját pontrács").props["aria-pressed"], true);
editorKeys({key: "g"}); await tick();
await new Promise(resolve => setTimeout(resolve, 100));
assert.equal(writes, gridWrites);
assert.equal(sheet.gridVisible, undefined);
assert.equal(savedPreferences.showGrid, false);
viewGroup().props.onClick(); await tick();
listeners.keydown = editorKeys;
toggle("Enter", true); await tick();
const search = prop("aria-label", "Keresés a munkalapon");
assert.ok(search);
const beforeSearch = selectedNode;
const candidate = id => prop("class", "search-candidate", graphic(id));
search.props.onInput({target: {value: "t"}}); await tick();
const rows = () => search.parent.children.filter(n => n.props.class === "search-row");
const first = text(rows()[0].children[0]), second = text(rows()[1].children[0]);
assert.ok(candidate(first));
rows()[0].children[1].props.onClick(); await tick();
toggle("ArrowDown", true); await tick();
assert.ok(candidate(first) && candidate(second));
assert.ok(rows()[0].props["data-candidate"] && rows()[1].props["data-candidate"]);
toggle("ArrowUp", true); await tick();
assert.ok(candidate(first) && !candidate(second));
rows()[0].children[1].props.onClick(); await tick();
assert.ok(!candidate(first));
assert.equal(rows()[0].props["data-candidate"], false);
rows()[1].props.onMouseenter(); await tick();
assert.ok(candidate(second));
rows()[1].children[1].props.onClick(); await tick();
rows()[0].props.onMouseenter(); await tick();
assert.equal(selectedNode, beforeSearch);
toggle("Enter", true); await tick();
assert.ok(!candidate(first) && !candidate(second));
assert.ok(ownSelected(first) && ownSelected(second));
toggle("Enter", true); await tick();
prop("aria-label", "Keresés a munkalapon").props.onInput({target: {value: "törzs"}}); await tick();
assert.ok(candidate("outside"));
toggle("Escape", true); await tick();
assert.ok(!candidate("outside"));
toggle("Escape", true); await tick();
toggle("Enter", true); await tick();
prop("aria-label", "Keresés a munkalapon").props.onInput({target: {value: "child"}}); await tick();
listeners.keydown({key: "ArrowDown", shiftKey: true}); await tick();
assert.ok(candidate("child") && candidate("outer"));
listeners.keydown({key: "ArrowUp", shiftKey: true}); await tick();
assert.ok(candidate("child") && candidate("outer"));
listeners.keydown({key: "Enter", shiftKey: true}); await tick();
assert.ok(prop("aria-label", "Keresés a munkalapon"));
assert.ok(ownSelected("child"));
assert.ok(!ownSelected("outer"));
toggle("ArrowDown", true); await tick();
listeners.keydown({key: "Enter", shiftKey: true}); await tick();
assert.ok(prop("aria-label", "Keresés a munkalapon"));
toggle("Escape", true); await tick();
assert.ok(!candidate("child") && !candidate("outer"));
assert.ok(ownSelected("child") && ownSelected("outer"));
const mean = axis => (model("child").position[axis] + model("outer").position[axis]) / 2;
assert.equal(requestedZoom.k, 2);
assert.equal(requestedZoom.x, 600 - (600 + mean("x")) * 2);
assert.equal(requestedZoom.y, 400 - (400 + mean("y")) * 2);
toggle("Enter", true); await tick();
prop("aria-label", "Keresés a munkalapon").props.onInput({target: {value: "child"}}); await tick();
assert.ok(candidate("child") && button("outer") && !candidate("outer"));
assert.ok(prop("href", "/icons.svg#file", button("child")));
assert.ok(prop("href", "/icons.svg#comment", button("outer")));
toggle("Enter", true); await tick();
assert.ok(!prop("aria-label", "Keresés a munkalapon"));
assert.equal(selectedNode, "child");
toggle("Enter", true); await tick();
const historyInput = prop("aria-label", "Keresés a munkalapon");
const historyList = () => prop("aria-label", "Keresési előzmények");
const activeHistory = () => prop("data-active", true, historyList());
const beforeHistoryZoom = requestedZoom;
toggle("ArrowDown", true); await tick();
assert.equal(text(activeHistory()), "child");
assert.equal(historyInput.props.value, "");
assert.ok(prop("href", "/icons.svg#search", activeHistory()));
assert.equal(historyList().children.every(row => row.children.length === 1), true);
assert.ok(!candidate("child"));
toggle("ArrowUp", true); await tick();
assert.equal(text(activeHistory()), "t");
toggle("ArrowDown", true); await tick();
assert.equal(text(activeHistory()), "child");
toggle("ArrowDown", true); await tick();
assert.equal(text(activeHistory()), "t");
toggle("ArrowUp", true); await tick();
assert.equal(text(activeHistory()), "child");
toggle("Enter", true); await tick();
assert.equal(historyInput.props.value, "child");
assert.ok(!historyList() && candidate("child"));
assert.equal(requestedZoom, beforeHistoryZoom);
toggle("ArrowDown", true); await tick();
assert.ok(candidate("outer"));
toggle("Escape", true); await tick();
for (let index = 0; index < 11; index++) {
  toggle("Enter", true); await tick();
  prop("aria-label", "Keresés a munkalapon").props.onInput({target: {value: "history " + index}});
  toggle("Enter", true); await tick();
}
assert.deepEqual(JSON.parse(storage.get("thinknodes/search-history/admin")),
  Array.from({length: 10}, (_, index) => "history " + (10 - index)));
await properties("outside");
await drag(graphic("inner"), 50, 40, 50, 40);
assert.equal(panel()?.props["aria-label"], "Doboz szerkesztése");
await drag(graphic("child"), 50, 40, 50, 40, {ctrlKey: true});
await properties("inner");
listeners.keydown({key: "Delete", ctrlKey: true}); await tick(); await save();
assert.ok(!model("inner") && !model("child"));
assert.ok(!sheet.edges.some(e => [e.source,e.target.node].includes("child")));
await properties("outside");
assert.equal(button("Előnézet"), undefined);
assert.equal(find(n => n.tag === "footer", panel()), undefined);
globalThis.confirm = () => { throw Error("Connected nodes must delete without a prompt"); };
listeners.keydown({key: "Backspace"}); await tick(); await save();
assert.ok(!model("outside") && !edge("one"));
await press("Visszavonás"); await save();
assert.ok(model("outside"));
assert.equal(edge("one").source, "outside");
await press("Újra"); await save();
assert.ok(!model("outside") && !edge("one"));
await press("Visszavonás"); await save();
toggle("Escape", true); await tick();
canvasToggle().props.onClick(); await tick();
const picker = find(n => n.tag === "input" && n.props.type === "file", canvasPanel());
assert.ok(picker.props.multiple && !picker.props.accept);
const documentFile = new File(["# Leírás"], "Tervezési vázlat.md");
const archive = new File([new Uint8Array([0x50,0x4b,0x05,0x06])], "anyag.zip");
titleActions.length = 0;
await picker.props.onChange({target: {files: [documentFile, archive], value: archive.name}});
await save();
assert.deepEqual(titleActions.slice(-2), ["focus", "anyag"]);
assert.deepEqual(attachmentUploads, [
  {url: "/api/attachment/test?name=" + encodeURIComponent(documentFile.name), file: documentFile},
  {url: "/api/attachment/test?name=anyag.zip", file: archive},
]);
assert.ok(sheet.nodes.some(n => n.type === "text" && n.file.filename === documentFile.name && n.text === ""));
const archiveNode = sheet.nodes.find(n => n.file?.asset === archive.name);
assert.equal(archiveNode.type, "document");
assert.equal(archiveNode.file.showFilename, true);
const archiveDownload = () => prop("aria-label", "Letöltés · anyag.zip", graphic(archiveNode.id));
assert.equal(text(archiveDownload()), "anyag.zip");
await properties(archiveNode.id);
assert.ok(section("Text") && section("Megjelenés"));
await press("Fájlnév elrejtése"); await save();
assert.equal(text(archiveDownload()), "Letöltés", "the document keeps its download button");
await press("Fájlnév megjelenítése"); await save();
assert.equal(text(archiveDownload()), "anyag.zip");
assert.equal(button("Free").props["aria-pressed"], false);
await press("Free"); await save();
assert.equal(prop("class", "node-surface", graphic(archiveNode.id)), undefined);
assert.ok(prop("aria-label", "Letöltés · anyag.zip", graphic(archiveNode.id)));
await press("Free");
const archiveName = prop("aria-label", "Fájlnév");
assert.equal(archiveName.props.value, "anyag");
archiveName.props.onChange({target: {value: "új csomag"}});
await tick();
await save();
assert.equal(model(archiveNode.id).file.filename, "új csomag.zip");
globalThis.Image = class {
  naturalWidth = 160;
  naturalHeight = 80;
  async decode() {}
};
const image = new File(["image"], "pelda.png", {type: "image/png"});
titleActions.length = 0;
await picker.props.onChange({target: {files: [image], value: image.name}});
await tick();
assert.equal(panel().props["aria-label"], "Kép szerkesztése");
assert.ok(section("Text") && !section("Átlátszóság") && prop("aria-label", "Link hozzáadása", panel()));
assert.deepEqual(titleActions, ["focus", "pelda"]);
prop("aria-label", "Text", panel()).props.onInput({target: {value: "Képcím"}});
await save();
assert.equal(sheet.nodes.at(-1).text, "Képcím");
assert.equal(sheet.nodes.at(-1).file.filename, "pelda");
const animation = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10"><rect width="10" height="10"><animate attributeName="x" from="0" to="10" dur="1s" repeatCount="indefinite"/></rect></svg>';
const animatedImage = new File([animation], "mozgas.SVG");
assert.ok(!picker.props.accept);
await picker.props.onChange({target: {files: [animatedImage], value: animatedImage.name}});
await save();
const animatedNode = sheet.nodes.at(-1);
assert.equal(animatedNode.type, "image");
assert.equal(svgUpload.headers["Content-Type"], "image/svg+xml");
assert.equal(await svgUpload.body.text(), animation, "the original animation is uploaded intact");
assert.ok(prop("src", "/api/attachment/test?inline=1&name=mozgas.svg", graphic(animatedNode.id)));
// Képnél a megjelenés-módosítók közül csak a Kiemelés maradt; a kép háttér (felület) nélkül jelenik meg.
const imageSurface = () => prop("class", "node-surface", graphic(animatedNode.id));
for (const removed of ["Alpha csatorna", "Free", "Üres", "Elmosott", "Áttetsző", "Eredeti képarány"]) assert.equal(button(removed), undefined, removed);
assert.equal(prop("aria-label", "Kép háttérszíne színválasztó", panel()), undefined);
assert.ok(button("Kiemelés"));
assert.equal(imageSurface(), undefined);
delete globalThis.Image;
toggle("Escape", true); await tick();
assert.ok(!text(canvasPanel()).includes("fájl feltöltve"));
canvasToggle().props.onClick(); await tick();

zoomEvents.zoom({transform: d3.zoomIdentity}); await tick();
const paste = text => listeners.paste({preventDefault() {}, clipboardData: {files: [], getData: () => text}});
canvas().props.onPointermove(event(canvas(), 200, 72));
paste("A kurzorhoz");
await tick(); await save();
assert.deepEqual(sheet.nodes.at(-1).position, {x: 200, y: 72});
toggle("Escape", true); await tick();
canvas().props.onPointerleave();
paste("A középre");
await tick(); await save();
assert.deepEqual(sheet.nodes.at(-1).position, {x: 0, y: 0});
const pasted = sheet.nodes.at(-1).id;
await properties(pasted);
listeners.keydown({key: "Delete"}); await tick(); await save();
assert.ok(!model(pasted), "an unconnected box is deleted without confirmation");
toggle("Escape", true); await tick();
paste("https://example.org/oldal");
await tick(); await save();
const linkedBox = sheet.nodes.at(-1);
assert.equal(linkedBox.type, "preview", "a linked box becomes a preview box");
assert.equal(linkedBox.shape, "rectangle");
assert.deepEqual(linkedBox.link, {kind: "url", target: "https://example.org/oldal"});
assert.ok(prop("data-link-kind", "url", graphic(linkedBox.id)), "the link marker sits on the box");
{
  // Átméretezés közben a képet tartalmazó dobozon középen a méret, a kép 50%-kal sötétebb; elengedés után eltűnik.
  const {x, y} = linkedBox.position;
  canvas().props.onPointermove(event(canvas(), x, y));
  toggle("Alt", true); await tick();
  const corner = find(n => n.props.cursor === "nwse-resize" && n.props.x > 0, graphic(linkedBox.id));
  const cx = x + corner.props.x + 5, cy = y + corner.props.y + 5;
  corner.props.onPointerdown(event(corner, cx, cy, {altKey: true}));
  canvas().props.onPointermove(event(canvas(), cx + 40, cy + 30));
  await tick();
  const badge = find(n => n.props.class === "resize-size", graphic(linkedBox.id));
  assert.ok(badge, "resizing shows the size badge");
  assert.match(text(badge), /^\d+ × \d+$/);
  assert.ok(find(n => n.props["fill-opacity"] === .5, badge), "the image is darkened by 50%");
  canvas().props.onPointerup(event(canvas(), cx + 40, cy + 30));
  toggle("Alt", false); await tick();
  assert.equal(find(n => n.props.class === "resize-size", graphic(linkedBox.id)), undefined);
}
await properties(linkedBox.id);
assert.ok(find(n => n.tag === "legend" && text(n).startsWith("Link · Külső cím"), panel()));
assert.equal(prop("aria-label", "Link hozzáadása", panel()), undefined, "an existing link hides the add button");
const confirmBeforeLink = globalThis.confirm;
let linkQuestion;
globalThis.confirm = question => { linkQuestion = question; return true; };
await press("Link törlése"); await tick(); await save();
globalThis.confirm = confirmBeforeLink;
assert.ok(linkQuestion.includes("example.org"), "removing a link asks first");
assert.equal(model(linkedBox.id).link, undefined);
assert.ok(prop("aria-label", "Link hozzáadása", panel()));
listeners.keydown({key: "Delete"}); await tick(); await save();
assert.ok(!model(linkedBox.id));
const doubleClick = (x, y, hit) => canvas().props.onDblclick(event(canvas(), x, y, {target: {closest: () => hit}}));
titleActions.length = 0;
sidebarToggle().props.onClick(); await tick();
const beforeDoubleClick = sheet.nodes.length;
doubleClick(340, 0, graphic("outside"));
doubleClick(400, 230, oneWire());
doubleClick(240, -180, null);
await tick(); await save();
assert.equal(sheet.nodes.length, beforeDoubleClick + 1);
assert.deepEqual(sheet.nodes.at(-1).position, {x: 240, y: -180});
assert.deepEqual(titleActions, ["focus", ""]);

sidebarToggle().props.onClick(); await tick();
globalThis.innerWidth = 1200;
globalThis.innerHeight = 800;
const contextClick = event(canvas(), 310, -130, {button: 2, target: {closest: () => null}});
canvas().props.onPointerdownCapture(contextClick);
canvas().props.onContextmenu(contextClick);
listeners.pointerup({...contextClick, type: "pointerup"});
await tick();
await press("Objektum létrehozása"); await save();
assert.deepEqual(sheet.nodes.at(-1).position, {x: 310, y: -130});
assert.deepEqual(titleActions, ["focus", "", "focus", ""]);
window.prompt = () => "jegyzet";
canvas().props.onPointerdownCapture(contextClick);
canvas().props.onContextmenu(contextClick);
listeners.pointerup({...contextClick, type: "pointerup"});
await tick();
titleActions.length = 0;
const beforeCreatingWorksheet = sheet.nodes.length;
let openedWorksheet;
location.assign = target => { openedWorksheet = target; };
await press("Új munkalap");
assert.equal(openedWorksheet, "/edit/test/jegyzet");
assert.equal(sheet.nodes.length, beforeCreatingWorksheet);
assert.deepEqual(titleActions, []);
delete location.assign;
delete window.prompt;
delete root.querySelector;
console.log("Passed editor gestures, junction cleanup, container nesting and lock, text scaling, palette and local world grid.");

const {worksheetLink} = await import("../../Public/links.js");
assert.equal(worksheetLink("https://example.com/" + "é".repeat(1024), "main"), null);
assert.deepEqual(worksheetLink("../közös", "main/lab"), {kind: "worksheet", href: "/main/k%C3%B6z%C3%B6s"});
assert.equal(worksheetLink("/..", "main/lab").href, "/main");
assert.equal(worksheetLink("sub/one", "main").href, "/main/sub/one");
assert.equal(worksheetLink("https://example.org", "main").kind, "website");
assert.equal(worksheetLink("javascript:alert(1)", "main"), null);

const {labelLayout} = await import("../../Public/geometry.js");
const sample = {...node("label", 0, 0, 240, 200), hideText: false};
const codeBlock = {kind: "code", runs: [{text: "  a  b\n\n c\n", format: {code: true}}]};
assert.deepEqual(labelLayout(sample, [codeBlock]).lines.filter(line => line.runs).map(line => line.text),
  ["  a  b", "", " c"]);
const twoBlocks = [{kind: "body", runs: [{text: "Első sor"}]}, {kind: "body", runs: [{text: "Második sor"}]}];
const collapsed = labelLayout({...sample, hideText: true, alignment: "right", verticalAlignment: "bottom"}, twoBlocks);
assert.equal(collapsed.lines.length, 2, "collapsed text shows the first line and an ellipsis line");
assert.equal(collapsed.lines[0].text, "Első sor");
assert.equal(collapsed.lines[1].text, "…");
assert.equal(collapsed.lines[1].anchor, "end");
assert.ok(collapsed.lines[1].y > collapsed.lines[0].y);
assert.equal(collapsed.overflow, true);
assert.equal(labelLayout({...sample,fontSize:28},[{kind:"body",runs:[{text:"body"}]}]).lines[0].size, 28);
const headings = labelLayout(sample, [1, 2, 3].map(level => ({kind: "heading", level, runs: [{text: "H" + level}]})));
assert.deepEqual(headings.lines.map(line => line.size), [26, 21, 18]);
assert.deepEqual(headings.lines.map(line => line.weight), [700, 700, 700]);
// A Félkövér gomb megszűnt: a régi bold mező már nem változtat a megjelenésen.
const strongHeading = labelLayout({...sample, bold: true}, [{kind: "heading", level: 1, runs: [{text: "H"}]}, {kind: "body", runs: [{text: "b"}]}]);
assert.deepEqual(strongHeading.lines.map(line => line.weight), [700, 400]);
const listed = labelLayout({...sample, alignment: "center"}, [{kind: "body", indent: 2, runs: [{text: "• mély"}]}]);
assert.equal(listed.lines[0].anchor, "start");
assert.ok(listed.lines[0].x > -sample.width / 2 * 0.94 + 8);
const blocks = [{kind: "body", runs: [{text: "Text"}]}];
const justifiedRows = labelLayout({...sample, width: 130, justified: true},
  [{kind: "body", runs: [{text: "Ez egy rövid példa több szövegsorral."}]}]).lines;
// Sorkizárás: a tördelt sorok kifeszülnek, a bekezdés utolsó (rövid) sora nem.
assert.ok(justifiedRows[0].justifyWidth > 0);
assert.equal(justifiedRows.at(-1).justifyWidth, undefined);
assert.equal(justifiedRows.at(-1).anchor, "start");
const largeLabel = {...sample, width: 64, height: 40, fontSize: 80};
const bounded = labelLayout(largeLabel, [{kind: "body", runs: [{text: "Hosszú szöveg"}]}]);
assert.equal(bounded.overflow, true);
assert.equal(bounded.lines.length, 0);
const freeLayout = labelLayout({...largeLabel, backgroundMode: "free"}, [{kind: "body", runs: [{text: "Hosszú szöveg"}]}]);
assert.deepEqual(freeLayout.lines, bounded.lines);
assert.equal(freeLayout.overflow, true);
const fitted = labelLayout({...sample, fitText: true}, blocks);
const smaller = labelLayout({...sample, fitText: true, width: 120, height: 100}, blocks);
assert.equal(fitted.overflow, false);
assert.equal(smaller.overflow, false);
assert.ok(fitted.lines[0].size > smaller.lines[0].size);
const compact = labelLayout({...sample, fitText: true, width: 64, height: 40, shape: "triangle"}, twoBlocks);
assert.equal(compact.overflow, false);
assert.equal(compact.lines.length, 2);
for (const vertical of ["top", "middle", "bottom"]) {
  for (const align of ["left", "center", "right"]) {
    const layout = labelLayout({...sample, alignment: align, verticalAlignment: vertical}, blocks);
    assert.equal(layout.lines[0].anchor, {left: "start", center: "middle", right: "end"}[align]);
    assert.equal(Math.sign(Math.round(layout.lines[0].y - 5.28)) || 0, {top: -1, middle: 0, bottom: 1}[vertical]);
  }
}
const linked = labelLayout({...sample, link: {kind: "web", target: "a.web"}}, blocks);
assert.ok(linked.webPreview && linked.previewSpace === sample.height && linked.lines.length === 0 && linked.overflow,
  "a presentation box is filled by its preview; the text appears only as a tooltip");
const sheetLinked = labelLayout({...sample, link: {kind: "sheet", target: "masik"}}, blocks);
assert.ok(sheetLinked.webPreview && sheetLinked.lines.length === 0, "a worksheet link is filled by its preview too");
const sheetText = labelLayout({...sample, staticPreview: true, link: {kind: "sheet", target: "masik"}}, blocks);
assert.ok(!sheetText.webPreview && sheetText.previewSpace === 0 && sheetText.lines.length > 0, "with the preview off the text is shown");
assert.equal(labelLayout({...sample, type: "image"}, blocks).lines.length, 0);

const {rebaseWorksheet} = await import("../../Public/collaboration.js");
const base = {revision: 1, nodes: [node("a", 0, 0), node("b", 40, 10)], edges: []};
const local = structuredClone(base), remote = structuredClone(base);
local.nodes[0].text = "Anna";
remote.nodes[1].text = "Béla";
remote.revision++;
const merged = rebaseWorksheet(base, local, remote);
assert.deepEqual(merged.nodes.map(n => n.text), ["Anna", "Béla"]);
local.edges.push({id: "added", source: "a", target: {node: "b"}});
remote.nodes.pop();
assert.deepEqual(rebaseWorksheet(base, local, remote).edges[0].target, {point: {x: 40, y: 10}});
console.log("Passed link resolution, nine alignments and concurrent worksheet edits.");

const {replayChanges, worksheetChanges} = await import("../../Public/editor-history.js");
const parent = {id: "parent", type: "box", container: true};
const member = {id: "member", type: "box", container: true};
const separated = {nodes: [parent, member], edges: []};
const nested = {nodes: [parent, {...member, parent: "parent"}], edges: []};
const outsiderMove = {nodes: [{...parent, parent: "member"}, member], edges: []};
assert.equal(replayChanges(outsiderMove, worksheetChanges(nested, separated), false, () => false), null);
const originalWire = {id: "old", source: "parent", target: {node: "member"}};
const deletedWire = worksheetChanges({...separated, edges: [originalWire]}, separated);
const replacementWire = {...separated, edges: [{...originalWire, id: "replacement"}]};
assert.equal(replayChanges(replacementWire, deletedWire, false, () => false), null);
const historyJunction = {id: "j", type: "junction"};
const cables = ["one", "two", "three"].map((id, x) => ({id, source: "j", target: {point: {x, y: 0}}}));
const junctionSheet = edges => ({nodes: [historyJunction], edges});
const thirdCable = worksheetChanges(junctionSheet(cables.slice(0, 2)), junctionSheet(cables));
assert.equal(replayChanges(junctionSheet(cables.slice(1)), thirdCable, false, () => false), null);

oneWire().props.onDblclick({stopPropagation() {}});
await tick();
assert.equal(button("Egyenes").props["aria-pressed"], true);
assert.equal(button("Sima").props["aria-pressed"], true);
for (const label of ["Egyenes", "Sima", "Nyíl a vonal elején", "Nyíl a vonal végén", "Animáció bekapcsolása"]) {
  assert.equal(text(button(label)), "", label + " uses an icon and an accessible name");
}
assert.equal(button("Nyíl a vonal elején").props["aria-pressed"], false);
assert.equal(button("Nyíl a vonal végén").props["aria-pressed"], true);
await press("Animáció bekapcsolása");
assert.equal(button("Animáció bekapcsolása").props["aria-pressed"], true);
// Sima animált vonal: egy kis pötty fut végig a vonalon a nyíl irányában (a korábbi gradiens animáció megszűnt);
// két nyílnál oda-vissza (editor.js animatedWire: CSS offset-path, 20 lépés/mp; Rendering.swift wireAnimation: SMIL).
const wireDot = () => find(n => n.tag === "circle" && n.props.class === "wire-dot", oneWire());
const wireMotion = () => wireDot().props.style.animation;
assert.ok(wireDot(), "az animált sima vonalon pötty fut");
assert.ok(!find(n => n.tag === "linearGradient", oneWire()), "nincs gradiens animáció");
assert.ok(!find(n => n.tag?.startsWith("animate"), oneWire()), "a szerkesztőben nincs SMIL");
assert.match(wireDot().props.style.offsetPath, /^path\('M /);
assert.match(wireMotion(), /^tn-dot [\d.]+s steps\(\d+\) infinite$/);
assert.ok(wireDot().props.fill !== "#0090ff", "a kijelölt vonal pöttye a vonal saját színét tartja; csak a glow kapja a felhasználó színét");
const oneWay = parseFloat(wireMotion().split(" ")[1]);
await press("Nyíl a vonal elején");
assert.match(wireMotion(), / alternate$/);
assert.equal(parseFloat(wireMotion().split(" ")[1]), oneWay);
await press("Nyíl a vonal végén");
await press("S-forma");
await press("Pontozott");
assert.equal(button("S-forma").props["aria-pressed"], true);
assert.equal(button("Pontozott").props["aria-pressed"], true);
assert.ok(find(n => n.props.d?.includes(" C ") && n.props["stroke-dasharray"] === "0 16", oneWire()));
assert.equal(find(n => n.props?.style?.["--tn-shift"], oneWire()).props.style["--tn-shift"], "16px");
await save();
assert.equal(edge("one").animated, true);
assert.equal(edge("one").type, "sCurve");
assert.equal(edge("one").appearance, "dotted");
assert.equal(edge("one").startArrow, true);
assert.equal(edge("one").endArrow, false);
await press("Nyíl a vonal elején");
await press("Nyíl a vonal végén");
assert.equal(find(n => n.props?.style?.["--tn-shift"], oneWire()).props.style["--tn-shift"], "-16px");
await press("Szaggatott");
assert.equal(find(n => n.props?.style?.["--tn-shift"], oneWire()).props.style["--tn-shift"], "-12px");
await pressIn("Megjelenés", "Vastag");
const wireLabelInput = prop("data-object-label", "", panel());
wireLabelInput.props.onInput({target: {value: "Középen"}});
await tick();
const wireLabel = () => prop("class", "wire-label", oneWire());
assert.equal(button("Felirat a vonalban").props["aria-pressed"], false);
assert.equal(prop("id", "editor-wire-gap-one", oneWire()), undefined);
assert.equal(wireLabel().props["font-weight"], 700);
assert.equal(wireLabel().props["font-size"], 26);
assert.ok(wireLabel().props.y < 0);
await press("Felirat a vonalban");
const wireGap = prop("id", "editor-wire-gap-one", oneWire());
const inlineLabel = wireLabel();
assert.equal(inlineLabel.props.y, 0);
assert.equal(inlineLabel.props["dominant-baseline"], "central");
assert.equal(inlineLabel.props.textLength, undefined, "inline labels keep their natural glyph proportions");
assert.equal(wireGap.children[0].props.transform, inlineLabel.props.transform);
assert.ok(prop("clip-path", "url(#editor-wire-gap-one)", oneWire()));
await save();
assert.equal(edge("one").labelInLine, true);
await press("Szaggatott");
assert.ok(prop("id", "editor-wire-gap-one", oneWire()));
assert.equal(wireLabel().props["font-size"], 14);
assert.equal(wireLabel().props["font-weight"], 400);
// Vonalméret: a „Közepes” (5) szaggatott vonal felirata 12 + 5; az egyedi vastagság mezője megszűnt.
assert.equal(prop("aria-label", "Alapvastagság", panel()), undefined);
await pressIn("Vonalméret", "Közepes");
assert.equal(wireLabel().props["font-size"], 17);
await pressIn("Vonalméret", "Vékony");
await pressIn("Megjelenés", "Vastag");
await press("Felirat a vonalban");
wireLabelInput.props.onInput({target: {value: ""}});
await tick();
assert.equal(prop("id", "editor-wire-gap-one", oneWire()), undefined);
// Vastag animált vonal: a szár lüktet (CSS, --tn-pulse = 1,45 × vastagság), a nyílhegy a csúcsa körül pulzál.
const thickShaft = () => find(n => classList(n.props.class).includes("wire-motion-thick"), oneWire());
assert.equal(thickShaft().props.style["--tn-pulse"], "5.8px");
const arrow = find(n => n.props.d === "M0 0L-1 -.5V.5Z" && classList(n.props.class).includes("wire-arrow"), oneWire());
// Kijelölve a nyílhegy is kap kijelölés-sávot (a szár sávjával közös, áttetsző csoportban).
assert.ok(find(n => n.props.class === "wire-arrow-halo", oneWire()));
assert.ok(classList(arrow.props.class).includes("wire-arrow-pulse"), "a lüktető nyílhegy");
// Saját kijelölés: glow nélkül, világosabb és vastagabb vonal (alátét); a nyíl megtartja az eredeti színét.
assert.equal(prop("class", "wire-glow", oneWire()), undefined);
// A saját kijelölést a vonal csoportjának "wire-own" osztálya jelzi (app.css), külön alátét-elem nincs.
assert.ok(find(n => classList(n.props.class).includes("wire-own"), oneWire()));
assert.notEqual(arrow.props.fill, "#0090ff");
assert.equal(prop("class", "wire-selected", oneWire()), undefined);
assert.equal(prop("class", "selection-glow", oneWire()), undefined);
await press("Íves");
// Kúpos vastag vonal: a kitöltés köré rajzolt, azonos színű körvonal vastagodik (Safari a CSS `d`-t nem tudja).
const arcPulse = find(n => classList(n.props.class).includes("wire-motion-taper"), oneWire());
assert.notEqual(arcPulse.props.fill, "#0090ff");
assert.equal(arcPulse.props.stroke, arcPulse.props.fill);
assert.ok(parseFloat(arcPulse.props.style["--tn-pulse"]) > 0);
assert.ok(find(n => classList(n.props.class).includes("wire-arrow-pulse"), oneWire()));
await press("Animáció bekapcsolása");
assert.equal(find(n => classList(n.props.class).includes("wire-motion-taper"), oneWire()), undefined);
await press("Egyenes");
await press("Sima");
await save();

await properties("outside");
assert.equal(prop("class", "wire-selected", oneWire()), undefined);
assert.ok(prop("stroke", "#60646c", oneWire()));
for (const [label, shape, vertices] of [["Háromszög", "triangle", 3], ["Ötszög", "pentagon", 5],
  ["Hatszög", "hexagon", 6], ["Paralelogramma", "parallelogram", 4]]) {
  const option = button(label);
  assert.equal(text(option), "");
  await press(label);
  assert.equal(button(label).props["aria-pressed"], true);
  await save();
  assert.equal(model("outside").shape, shape);
  const polygon = find(n => n.tag === "polygon" && n.props.fill === "#29a383", graphic("outside"));
  assert.equal(polygon.props.points.split(" ").length, vertices);
}
await press("Téglalap"); await save();

const {edgeGeometry, edgePaint, edgeInRectangle, borderPoint, polygonVertices, selectionOutline} = await import("../../Public/geometry.js");
for (const [shape, x] of [["triangle", 30], ["pentagon", 55.587096774], ["hexagon", 60], ["parallelogram", 46.5]]) {
  const box = {...node("polygon", 0, 0, 120, 80), shape};
  assert.ok(Math.abs(borderPoint(box, {x: 200, y: 0}).x - x) < 1e-8);
}
for (const shape of ["triangle", "pentagon"]) {
  for (const [width, height] of [[880, 40], [64, 680]]) {
    const vertices = polygonVertices(shape, width / 2, height / 2);
    const [, outline] = selectionOutline(shape, width, height);
    const outer = outline.points.split(" ").map(point => point.split(",").map(Number));
    vertices.forEach(([x, y], index) => {
      const [ax, ay] = outer[index];
      const [bx, by] = outer[(index + 1) % outer.length];
      const gap = Math.abs((bx - ax) * (y - ay) - (by - ay) * (x - ax)) / Math.hypot(bx - ax, by - ay);
      assert.ok(gap >= 10 - 1e-8, shape + " has clearance along every edge");
      assert.ok(Math.abs(x * ay - y * ax) < 1e-8, shape + " preserves its proportions");
    });
  }
}
const route = (type, y = 0) => edgeGeometry({
  type, sourcePoint: {x: -100, y: 0}, target: {point: {x: 100, y}},
}, () => undefined);
assert.equal(route("sCurve").d, "M -100 0 L 100 0");
assert.equal(route("sCurve", 60).d, "M -100 0 C 0 0 0 60 100 60");
assert.ok(Math.abs(route("lightning").labelPosition.x) < 1e-10);
assert.equal(route("lightning").boundsPoints.length, 8);
assert.equal(route("lightning").corners.length, 0);
assert.ok(route("arc").labelPosition.y < 0 && route("rope").labelPosition.y > 0);
const arc = route("arc");
assert.ok(edgeInRectangle(arc, {x:-1,y:-30,width:2,height:2}, true), "the rectangle touches the arc at its apex");
assert.ok(!edgeInRectangle(arc, {x:-1,y:-32,width:2,height:2}, true), "a control hull alone is insufficient");
assert.ok(edgeInRectangle(arc, {x:-100,y:-28,width:200,height:28}, false));
assert.equal(edgePaint({appearance: "thick"}).width, 4);
assert.equal(edgePaint({appearance: "dotted"}).linecap, "round");

const {importFile} = await import("../../Public/canvas-files.js");
const doc = await importFile(new File(['{"large":90071992547409931,"nested":[{},{"literal":"a,b"}]}'], "adat.json"), "test", "token");
assert.equal(doc.type, "code");
assert.equal(doc.text, undefined, "a text file keeps its content only in the file");
const uploadedJSON = await attachmentUploads.at(-1).file.text();
assert.ok(uploadedJSON.includes('"large": 90071992547409931'));
assert.deepEqual(JSON.parse(uploadedJSON).nested, [{},{literal:"a,b"}]);
await assert.rejects(importFile(new File(["szöveg"], "hibás.json"), "test", "token"), /JSON/);
assert.equal((await importFile(new File(["a,b\n1,2"], "tabla.csv"), "test", "token")).type, "csv");
assert.equal((await importFile(new File(["let a = 1"], "app.swift"), "test", "token")).type, "code");
assert.equal((await importFile(new File(["sima szöveg"], "jegyzet.log"), "test", "token")).type, "text");
assert.equal((await importFile(new File([new Uint8Array([1, 2, 3])], "adat.bin"), "test", "token")).type, "document");
const {classify, traits} = await import("../../Public/node-types.js");
assert.equal(classify("hang.wav", new Uint8Array()), "audio");
assert.equal(classify("kep.webp", new Uint8Array()), "image");
assert.ok(traits("code").has("fileText") && traits("image").has("link") && !traits("document").has("link"));
const importedWorksheet = await importFile(new File(['{"title":"Lap"}'], "lap.thnode"), "test", "token");
// A behúzott .thnode új allap lesz, a vászonra pedig rá mutató laplinkes doboz kerül.
assert.deepEqual(importedWorksheet, {text: "lap", link: {kind: "sheet", target: "lap"}, width: 220, height: 90});
// Csomag-ZIP felismerése a tartalomjegyzékből: nyitott (Név/Név.thnode) és titkosított csomag; a sima ZIP nem az.
const {isPackageZip} = await import("../../Public/package.js");
function zipOf(...names) {
  const encoder = new TextEncoder(), chunks = [], entries = [];
  let offset = 0;
  const bytes = (...parts) => { const view = new DataView(new ArrayBuffer(parts.reduce((sum, [size]) => sum + size, 0)));
    let at = 0; for (const [size, value] of parts) { if (size === 2) view.setUint16(at, value, true); else view.setUint32(at, value, true); at += size; }
    return new Uint8Array(view.buffer); };
  for (const name of names) {
    const raw = encoder.encode(name);
    const local = bytes([4, 0x04034b50], [2, 20], [2, 0x800], [2, 0], [2, 0], [2, 0], [4, 0], [4, 0], [4, 0], [2, raw.length], [2, 0]);
    entries.push({raw, offset});
    chunks.push(local, raw);
    offset += local.length + raw.length;
  }
  const start = offset;
  for (const {raw, offset: at} of entries) {
    const header = bytes([4, 0x02014b50], [2, 20], [2, 20], [2, 0x800], [2, 0], [2, 0], [2, 0], [4, 0], [4, 0], [4, 0],
      [2, raw.length], [2, 0], [2, 0], [2, 0], [2, 0], [4, 0], [4, at]);
    chunks.push(header, raw);
    offset += header.length + raw.length;
  }
  chunks.push(bytes([4, 0x06054b50], [2, 0], [2, 0], [2, entries.length], [2, entries.length], [4, offset - start], [4, start], [2, 0]));
  return new Blob(chunks);
}
assert.equal(await isPackageZip(zipOf("Terv/.settings.json", "Terv/Terv.thnode", "Terv/kep.png")), true);
assert.equal(await isPackageZip(zipOf("thinknodes-encrypted.json", "content.bin")), true);
assert.equal(await isPackageZip(zipOf("index.html", "Terv/masik.thnode", "a/b/b.thnode")), false);
assert.equal(await isPackageZip(new Blob(["nem zip, csak szöveg, de elég hosszú hozzá"])), false);
console.log("Passed document import, JSON precision and unsupported format checks.");

if (!canvasPanel()) { canvasToggle().props.onClick(); await tick(); }
await openAppearance();
const chooseAppearance = async (label, value) => {
  const control = prop("aria-label", label, appearancePanel());
  assert.equal(control.props.disabled, false);
  control.props.onChange({target: {value}});
  await tick();
};
// Ugyanazt a modulpéldányt kell betölteni, amelyet a szerkesztő használ (más ?v= más példány, téma nélkül): a verzió
// az editor.js importjából.
const geometryModule = readFileSync("Public/editor.js", "utf8").match(/from "\.\/(geometry\.js\?v=\d+)"/)[1];
const {edgeGeometry: themedGeometry, shapeGeometry: themedShape, taperedArc, arrowLength} = await import("../../Public/" + geometryModule);
await chooseAppearance("Téma", "3");
assert.deepEqual(themedShape("rounded", 100, 80),
  ["polygon", {points: "-45,-40 45,-40 50,-35 50,35 45,40 -45,40 -50,35 -50,-35"}]);
assert.equal(prop("aria-label", "Mód", appearancePanel()), undefined);
document.documentElement.dataset.display = "dark";
listeners["thinknodes-display"](); await tick();
// A munkalap háttérszíne a vászonterület (canvas-area) háttere, a rács és az átlátszó vászonréteg alatt.
assert.equal(prop("class", "canvas-area").props.style.background, "#14273a");
assert.ok(prop("fill", "#bbbbbb", canvas()));
// Üveges látványcsomag (LiquidGlass, id 4): csillogás és fénylő perem a doboz felületén, lekerekített ívű vonalak.
await chooseAppearance("Téma", "4");
assert.ok(prop("data-glass", "dark"));
assert.ok(prop("fill", "url(#fx-sheen)", canvas()));
assert.ok(prop("stroke", "url(#fx-rim)", canvas()).props["stroke-width"] > 0);
const from = {x: 0, y: 0}, to = {x: 200, y: 0};
assert.equal(prop("id", "glass-ambient", canvas()), undefined);
const zigzagWire = themedGeometry({type: "lightning", sourcePoint: from, target: {point: to}}, () => undefined);
const boltWire = themedGeometry({type: "zigzag", sourcePoint: from, target: {point: to}}, () => undefined);
assert.equal(zigzagWire.corners.length, 6);
assert.equal(boltWire.corners.length, 2);
assert.equal((zigzagWire.d.match(/ Q /g) ?? []).length, 6);
const [entry, sharpTip] = zigzagWire.corners[0];
assert.ok(Math.hypot(entry.x - sharpTip.x, entry.y - sharpTip.y) > 10);
assert.ok(!edgeInRectangle(zigzagWire, {x: sharpTip.x - .1, y: sharpTip.y - .1, width: .2, height: .2}, true));
const shallowArc = themedGeometry({type: "straight", sourcePoint: from, target: {point: to}}, () => undefined);
assert.equal(shallowArc.path(from, to), "M 0 0 Q 100 -24 200 0");
assert.ok(Math.abs(shallowArc.labelPosition.x - 100) < 1e-8);
assert.ok(Math.abs(shallowArc.labelPosition.y + 12) < 1e-8);
const widths = (startArrow, endArrow) => {
  // 3-as méret (10,5): a vékony vég a vastagság negyede (Rendering.swift taperedWireArc párja).
  const outline = taperedArc(shallowArc, edgePaint({size: 3, startArrow, endArrow})).outline();
  const points = outline.slice(2, -2).split(" L ").map(pair => pair.split(" ").map(Number));
  return [0, 16, 32].map(i => Math.hypot(points[i][0] - points[65 - i][0], points[i][1] - points[65 - i][1]))
    .map(Math.round);
};
// A laposabb íven (lineArc 0,06) a vastag vég a teljes 10,5-ös vastagság, kerekítve 11.
assert.deepEqual(widths(false, true), [3, 7, 11]);
assert.deepEqual(widths(true, false), [11, 7, 3]);
assert.deepEqual(widths(true, true), [11, 3, 11]);
assert.equal(taperedArc(shallowArc, edgePaint({startArrow: false, endArrow: false})), null);
assert.equal(taperedArc(shallowArc, edgePaint({appearance: "dashed"})), null);
assert.equal(arrowLength(2), 13.5);
assert.equal(arrowLength(4), 17.5);
const curveEnd = {x: 200, y: 80};
assert.equal(themedGeometry({type: "sCurve", sourcePoint: from, target: {point: curveEnd}}, () => undefined).path(from, curveEnd),
  "M 0 0 C 100 0 100 80 200 80");
await chooseAppearance("Téma", "1");
await chooseAppearance("Paletta", "2");
assert.equal(prop("class", "canvas-area").props.style.background, "#171918");
await chooseAppearance("Paletta", "1");
document.documentElement.dataset.display = "light";
listeners["thinknodes-display"](); await tick();
assert.equal(prop("class", "canvas-area").props.style.background, "#f9f9fb");
prop("aria-label", "Munkalap háttérszíne színválasztó", appearancePanel()).props.onClick();
await tick();
prop("aria-label", "Felület", appearancePanel()).props.onClick();
await tick();
assert.equal(prop("class", "canvas-area").props.style.background, "#e6f4fe");
prop("aria-label", "Alapértelmezett szín", appearancePanel()).props.onClick();
await tick();
assert.equal(prop("class", "canvas-area").props.style.background, "#f9f9fb");
prop("aria-label", "Felület", appearancePanel()).props.onClick();
await save();
assert.deepEqual(sheet.appearance, {theme:1, palette:1});
assert.equal(sheet.background, 2);
assert.ok(sheet.nodes.some(node => node.fill === "#bbbbbb"));
console.log("Passed theme, palette and display mode changes.");

// Fájldoboz törlése: a lomtár-párbeszéd (file-browser.js chooseRemoval) valódi DOM-elemeket épít; itt egy apró utánzat.
function fakeElement(tag) {
  return {tag, items: [], handlers: {}, textContent: "", append(...nodes) { this.items.push(...nodes); }, setAttribute() {},
    addEventListener(key, fn) { this.handlers[key] = fn; }, showModal() {}, remove() {},
    close() { this.handlers.close?.(); }};
}
let removalDialog;
document.createElement = fakeElement;
document.body = {append(dialog) { removalDialog = dialog; }};
const dialogText = item => item.textContent + item.items.map(dialogText).join(" ");
const dialogButton = (item, label) => item.tag === "button" && item.textContent === label ? item
  : item.items.map(child => dialogButton(child, label)).find(Boolean);
const removalShown = async () => { for (let i = 0; i < 20 && !removalDialog; i++) await tick(); return removalDialog; };
await properties(archiveNode.id);
listeners.keydown({key: "Delete"});
assert.match(dialogText(await removalShown()), /új csomag\.zip/);
dialogButton(removalDialog, "Mégse").handlers.click();
await tick(); await save();
assert.ok(model(archiveNode.id));
removalDialog = null;
listeners.keydown({key: "Delete"});
dialogButton(await removalShown(), "Lomtárba").handlers.click();
await tick(); await tick(); await save();
assert.equal(model(archiveNode.id), undefined);
console.log("Passed file box removal through the trash dialog.");
