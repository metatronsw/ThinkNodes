// Run from the repository root with Node 22 or later. The Vue runtime is the same one served to browsers.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {runInThisContext} from "node:vm";

const read = name => readFileSync("Public/vendor/" + name + ".js", "utf8");
runInThisContext(read("vue"));
runInThisContext(read("d3"));
const {Vue, d3} = globalThis;
function element(tag, text) {
  return Vue.markRaw({tag, text, children: [], props: {}, clientWidth: 1200, clientHeight: 800,
    focus() {}, setPointerCapture() {}});
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
root.dataset = {path: "test", role: "admin", user: "admin"};
const listeners = {};
const zoomEvents = {};
let requestedZoom;
function zoom() {
  const behavior = () => {};
  behavior.filter = behavior.scaleExtent = () => behavior;
  behavior.on = (key, fn) => { zoomEvents[key] = fn; return behavior; };
  behavior.transform = (_, transform) => { requestedZoom = transform; };
  return behavior;
}
globalThis.document = {querySelector: () => root};
const storage = new Map();
globalThis.window = {localStorage: {getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value)},
  Vue: {...Vue, createApp: renderer.createApp}, addEventListener(key, fn) { listeners[key] = fn; },
  d3: {...d3, zoom, pointer: e => [e.clientX, e.clientY],
    select: () => ({call(fn, ...args) { fn(this, ...args); return this; }, on() { return this; }})}};
globalThis.ResizeObserver = class { observe() {} };
globalThis.confirm = () => true;

function node(id, x, y, width, height) {
  return {id, title: id, position: {x, y}, width, height, shape: "rectangle", autoSize: false, text: "",
    fill: "#bbbbbb", border: "#555555", textColor: "#111111", alignment: "center", fontSize: 16, bold: true};
}
const {decodeWorksheet, encodeWorksheet} = await import("../../Public/worksheet-json.js");
let sheet = {title: "Próba", revision: 1, nodes: [
  {...node("outer", 0, 0, 300, 240), text: "child"}, node("inner", 10, 10, 160, 120), node("child", 10, 10, 64, 40),
  node("outside", 340, 0, 100, 80), {...node("auto", -420, 0, 120, 60), autoSize: true},
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
globalThis.fetch = async (url, options) => {
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
  if (cancel) canvas().props.onPointercancel(move);
  else canvas().props.onPointerup(move);
  await tick();
}
async function properties(id) {
  graphic(id).props.onKeydown({key: "Enter", shiftKey: true});
  await tick();
}
async function press(label) { button(label).props.onClick(); await tick(); }
async function save() { await button("Mentés").props.onClick(); await tick(); }
const model = id => sheet.nodes.find(n => n.id === id);
const edge = id => sheet.edges.find(e => e.id === id);
const toggle = (key, down) => listeners[down ? "keydown" : "keyup"]({key, ctrlKey: down && key === "Control", altKey: down && key === "Alt"});
async function detachDrag(id, end, x, y, cancel = false) {
  toggle("Control", true); await tick();
  const handle = endpoint(id, end);
  assert.equal(handle.props.class, "detach-endpoint");
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
assert.ok(oneWire().parent.children.indexOf(oneWire()) < oneWire().parent.children.indexOf(graphic("outside")));
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
const sidebarToggle = () => find(n => n.tag === "button" && n.props["aria-label"]?.startsWith("Oldalsáv "));
const canvasToggle = () => find(n => n.tag === "button" && n.props["aria-label"]?.startsWith("Vászonbeállítások "));
assert.ok(!panel() && !canvasPanel(), "no selection shows neither inspector initially");
oneWire().props.onClick();
await tick();
assert.equal(panel()?.props["aria-label"], "Vonal szerkesztése");
assert.ok(button("Egyenes"), "selecting a wire opens its editable properties directly");
canvasToggle().props.onClick(); await tick();
assert.ok(panel() && canvasPanel());
assert.ok(find(n => n.tag === "input" && n.props.value === sheet.title, canvasPanel()));
assert.ok(find(n => n.tag === "button" && text(n) === "Sorkizárás", canvasPanel()));
assert.equal(text(canvasPanel().children[0].children.find(n => n.tag === "button")), "Fájl feltöltése");
const emptyCanvasEvent = (x, y) => event(canvas(), x, y, {target: {closest: () => null}});
canvas().props.onPointerdownCapture(emptyCanvasEvent(280, 180));
zoomEvents.zoom({transform: d3.zoomIdentity.translate(25, 15)});
canvas().props.onPointerup(emptyCanvasEvent(305, 195));
await tick();
assert.ok(panel() && canvasPanel(), "panning keeps the selection and both inspectors");
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
assert.ok(panel() && canvasPanel(), "double-click reopens the object panel");
sidebarToggle().props.onClick(); await tick();
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
  assert.equal(panel()?.props["aria-label"], "Ötlet szerkesztése");
  toggle("Escape", true); await tick();
}

const down = event(graphic("outer"), 0, 0);
graphic("outer").props.onPointerdown(down);
await tick();
const beforeDrag = writes;
assert.ok(!Boolean(find(n => n.props.class === "save-label-changed", button("Mentés"))));
for (let x = 1; x <= 24; x++) {
  canvas().props.onPointermove(event(canvas(), x, 20));
  assert.equal(button("Mentés").props.disabled, false);
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
assert.ok(Boolean(find(n => n.props.class === "save-label-changed", button("Mentés"))));
await save();
assert.ok(!Boolean(find(n => n.props.class === "save-label-changed", button("Mentés"))));
await drag(graphic("outer"), 24, 20, 80, 70);
await new Promise(resolve => setTimeout(resolve, 150));
await button("Resign").props.onClick();
await tick();
assert.deepEqual(model("outer").position, {x: 24, y: 20});
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
const duplicate = sheet.nodes.find(n => n.title === "outside" && n.id !== "outside");
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
const titleInput = () => find(n => n.tag === "input" && n.props.maxlength === 120, panel());
panel().props.onInputCapture();
titleInput().props.onInput({target: {value: "first"}});
await save();
titleInput().props.onInput({target: {value: "finished"}});
panel().props.onFocusout();
await press("Visszavonás"); await save();
assert.equal(model("outer").title, "outer");
panel().props.onInputCapture();
titleInput().props.onInput({target: {value: "temporary"}});
titleInput().props.onInput({target: {value: "outer"}});
panel().props.onFocusout();
await tick();
assert.equal(button("Újra").props.disabled, false, "an unchanged field preserves redo");
await press("Újra"); await save();
assert.equal(model("outer").title, "finished");
await press("Konténer");
await properties("inner");
await press("Konténer");
await save();
assert.equal(model("child").parent, "inner");
assert.equal(model("inner").parent, "outer");
await drag(graphic("outer"), -100, -100, -60, -70);
await save();
assert.deepEqual(model("child").position, {x: 50, y: 40});
assert.deepEqual(model("inner").position, {x: 50, y: 40});
await properties("outer");
const lock = find(n => n.tag === "label" && text(n).includes("Lock"));
lock.children[0].props.onChange({target: {checked: true}});
await drag(graphic("child"), 50, 40, 95, 62);
await save();
assert.deepEqual(model("child").position, {x: 50, y: 40});
await drag(graphic("outside"), 340, 0, 190, 30); await save();
assert.equal(model("outside").parent, undefined, "exactly 50 percent is insufficient");
await drag(graphic("outside"), 190, 30, 180, 30); await save();
assert.equal(model("outside").parent, "outer");
await properties("outer"); await press("Konténer feloldása"); await save();
assert.equal(model("inner").parent, undefined);
assert.equal(model("child").parent, "inner");

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

const free = endpoint("one", "target");
assert.equal(free.tag, "path");
assert.equal(free.props["pointer-events"], "all");
await drag(graphic("outside"), 180, 30, 400, 230, {ctrlKey: true});
await save();
assert.equal(sheet.nodes.some(n => n.kind === "connectionPoint"), false, "duplicate route cannot create a junction");
await drag(graphic("auto"), -420, 0, 400, 230, {ctrlKey: true});
await save();
const junction = sheet.nodes.find(n => n.kind === "connectionPoint");
assert.equal(edge("one").target.node, junction.id);
const secondID = sheet.edges.at(-1).id;
assert.equal(edge(secondID).target.node, junction.id);
await drag(graphic("child"), 50, 40, 400, 230, {ctrlKey: true});
await save();
assert.equal(sheet.edges.at(-1).target.node, junction.id);
await detachDrag("one", "target", 450, 245, true);
assert.equal(endpoint("one", "target").props.class, "detach-endpoint", "cancel restores the attachment");
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
const joint = sheet.nodes.find(n => n.kind === "connectionPoint");
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
const freeShaft = find(n => n.props["stroke-linecap"] === "butt" && !("data-editor-only" in n.props), freeWire);
const shaftEnd = freeShaft.props.d.split(" ").slice(-2).map(Number);
assert.ok(Math.abs(Math.hypot(shaftEnd[0]+510,shaftEnd[1]+315)-6.75*freeShaft.props["stroke-width"]) < 1e-8);
const freeHandle = endpoint(sheet.edges.at(-1).id, "source");
assert.equal(freeHandle.tag, "rect");
assert.equal(freeHandle.props.fill, "transparent");

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
prop("aria-label","Háttér #60b77a").props.onClick(); await tick();
assert.ok(prop("fill","#60b77a", graphic("outside")));
find(n => n.props.type === "range").props.onInput({target: {value: "255"}}); await tick();
assert.ok(prop("fill","#ffb77a", graphic("outside")));
const section = label => find(n => n.tag === "fieldset" && n.children[0]?.text === label);
const control = (scope, label) => find(n => n.tag === "label" && n.children[0]?.text === label, scope).children[1];
const check = (scope, label) => find(n => n.tag === "label" && text(n) === label, scope).children[0];
const edit = (control, value) => control.props.onInput({target: {value}});
const enable = control => control.props.onChange({target: {checked: true}});
const animationPicker = prop("aria-label", "Animáció", section("Doboz"));
assert.equal(animationPicker.children.length, 5);
assert.ok(animationPicker.children.every(option => text(option) === ""));
assert.equal(button("Nincs animáció").props["aria-pressed"], true);
for (const [option, mode, tracks] of [
  ["Pulzálás", "pulse", ["scale"]], ["Villogás", "blink", ["opacity"]],
  ["Ringatózás", "rock", ["rotate"]], ["Ugrálás", "hop", ["translate", "scale"]],
]) {
  await press(option);
  const animated = prop("data-box-animation", mode, graphic("outside"));
  assert.deepEqual(animated.children.filter(n => n.tag.startsWith("animate")).map(n => n.props.type ?? n.props.attributeName), tracks);
}
await save();
assert.equal(model("outside").animation, "hop");
await press("Nincs animáció");
assert.equal(prop("data-box-animation", "hop", graphic("outside")), undefined);
const backgroundSwitch = check(section("Doboz"), "Háttér megjelenítése");
assert.equal(backgroundSwitch.props.checked, true);
backgroundSwitch.props.onChange({target: {checked: false}}); await tick(); await save();
assert.equal(model("outside").backgroundEnabled, false);
assert.equal(prop("aria-label", "Háttér színválasztó").props.disabled, true);
assert.equal(prop("aria-label", "Háttér #60b77a"), undefined);
assert.equal(prop("pointer-events", "fill", graphic("outside")).props.stroke, "none");
assert.equal(prop("pointer-events", "fill", graphic("outside")).props.fill, "none");
assert.equal(find(n => n.tag === "clipPath", graphic("outside")), undefined);
enable(backgroundSwitch); await tick();
assert.equal(prop("aria-label", "Háttér színválasztó").props.disabled, false);
assert.ok(prop("fill", "#ffb77a", graphic("outside")));
assert.equal(find(n => n.tag === "clipPath", graphic("outside")), undefined);
const titleSize = control(section("Cím"), "Betűméret");
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
const body = section("Text");
const justifyButton = find(n => n.tag === "button" && text(n) === "Sorkizárás", body);
assert.equal(justifyButton.props["aria-pressed"], false);
assert.equal(find(n => n.tag === "button" && text(n) === "Sorkizárás", section("Cím")), undefined);
justifyButton.props.onClick(); await tick(); await save();
assert.equal(model("outside").textStyle.justified, true);
assert.equal(justifyButton.props["aria-pressed"], true);
justifyButton.props.onClick(); await tick();
const oversizedBody = {value: "10001"};
control(body, "Betűméret").props.onInput({target: oversizedBody}); await tick(); await save();
assert.equal(oversizedBody.value, "10000");
assert.equal(model("outside").textStyle.size, 10000);
assert.equal(check(body, "Hide text").props.checked, false);
edit(control(body, "Betűméret"), "18.7");
prop("aria-label","Jobb oldal",body).props.onClick();
enable(check(body, "Dőlt"));
edit(find(n => n.tag === "textarea", body), "Törzs");
enable(check(body, "Aláhúzott"));
assert.equal(prop("aria-label", "Text háttér színválasztó"), undefined);
await new Promise(resolve => setTimeout(resolve,150));
await tick();
const details = find(n => n.tag === "tspan" && text(n) === "Törzs", graphic("outside"));
assert.equal(details.props["font-size"], 19);
assert.equal(details.props["font-style"], "italic");
assert.equal(details.props["text-anchor"], "end");
assert.equal(find(n => n.tag === "tspan" && text(n) === "Törzs", graphic("outside")).props["text-decoration"], "underline");
const autoSize = prop("aria-label", "AutoSize", section("Cím"));
assert.equal(autoSize.parent.children[1].children[1], titleSize);
autoSize.props.onClick(); await tick(); await save();
assert.equal(autoSize.props["aria-pressed"], true);
assert.equal(model("outside").fitText, true);
assert.equal(titleSize.props.disabled, true);
assert.equal(control(body, "Betűméret").props.disabled, true);
autoSize.props.onClick(); await tick(); await save();
assert.equal(titleSize.props.disabled, false);
assert.equal(control(body, "Betűméret").props.disabled, false);
assert.equal(model("outside").textStyle.size, 19);
toggle("Escape", true); await tick();
canvasToggle().props.onClick(); await tick();
for (const label of ["Rácsköz", "Rácspontok színe", "Pontrács megjelenítése", "Tulajdonos", "Rejtett a főoldalon", "Nyilvános munkalap", "Szerkesztők"]) {
  assert.ok(!text(canvasPanel()).includes(label));
}
canvasToggle().props.onClick(); await tick();
assert.equal(prop("id", "worksheet-grid").props.width, 32);
const {automaticGridColor} = await import("../../Public/geometry.js");
assert.equal(automaticGridColor("#ffffff"), "#808080");
assert.equal(automaticGridColor("#000000"), "#808080");
assert.equal(automaticGridColor("#112233"), "#889199");
assert.equal(automaticGridColor("#ddeeff"), "#6f7780");
assert.equal(prop("id", "worksheet-grid").children[0].props.fill, automaticGridColor("#f5f8fc"));
const snapSwitch = () => prop("aria-label", "Rácsra igazítás");
assert.equal(snapSwitch().props["aria-pressed"], false);
snapSwitch().props.onClick(); await tick();
const start = model("auto").position;
await drag(graphic("auto"), start.x, start.y, 121, -83);
await save();
assert.deepEqual(model("auto").position, {x:112, y:-80});
snapSwitch().props.onClick(); await tick();
const transform = d3.zoomIdentity.translate(35, 75).scale(2);
zoomEvents.zoom({transform}); await tick();
const grid = prop("fill", "url(#worksheet-grid)");
assert.equal(grid.parent.props.transform, transform + " translate(600 400)");
const gridWrites = writes;
prop("aria-label", "Pontrács").props.onClick(); await tick();
await new Promise(resolve => setTimeout(resolve, 100));
assert.equal(writes, gridWrites);
assert.equal(sheet.gridVisible, undefined);
assert.equal(storage.get("thinknodes/user-grid/admin"), "false");
assert.equal(prop("fill", "url(#worksheet-grid)"), undefined);
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
assert.ok(prop("class", "selection-glow", graphic(first)) && prop("class", "selection-glow", graphic(second)));
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
assert.ok(prop("class", "selection-glow", graphic("child")));
assert.ok(!prop("class", "selection-glow", graphic("outer")));
toggle("ArrowDown", true); await tick();
listeners.keydown({key: "Enter", shiftKey: true}); await tick();
assert.ok(prop("aria-label", "Keresés a munkalapon"));
toggle("Escape", true); await tick();
assert.ok(!candidate("child") && !candidate("outer"));
assert.ok(prop("class", "selection-glow", graphic("child")) && prop("class", "selection-glow", graphic("outer")));
const mean = axis => (model("child").position[axis] + model("outer").position[axis]) / 2;
assert.equal(requestedZoom.k, 2);
assert.equal(requestedZoom.x, 600 - (600 + mean("x")) * 2);
assert.equal(requestedZoom.y, 400 - (400 + mean("y")) * 2);
toggle("Enter", true); await tick();
prop("aria-label", "Keresés a munkalapon").props.onInput({target: {value: "child"}}); await tick();
assert.ok(candidate("child") && button(model("outer").title) && !candidate("outer"));
assert.ok(prop("href", "/icons.svg#file", button("child")));
assert.ok(prop("href", "/icons.svg#comment", button(model("outer").title)));
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
assert.equal(panel()?.props["aria-label"], "Ötlet szerkesztése");
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
assert.deepEqual(titleActions.slice(-2), ["focus", "anyag.zip"]);
assert.deepEqual(attachmentUploads, [
  {url: "/api/attachment/test?name=" + encodeURIComponent(documentFile.name), file: documentFile},
  {url: "/api/attachment/test?name=anyag.zip", file: archive},
]);
assert.ok(sheet.nodes.some(n => n.file?.type === "md" && n.text === "# Leírás"));
const archiveNode = sheet.nodes.find(n => n.file?.asset === archive.name);
assert.equal(archiveNode.file.type, "attachment");
assert.ok(prop("href", "/api/attachment/test?name=anyag.zip", graphic(archiveNode.id)));
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
assert.ok(find(n => n.tag === "button" && text(n) === "Sorkizárás", panel()));
assert.deepEqual(titleActions, ["focus", ""]);
labelInput().props.onInput({target: {value: "Képcím"}});
await save();
assert.equal(sheet.nodes.at(-1).title, "Képcím");
assert.equal(sheet.nodes.at(-1).file.filename, "pelda");
const animation = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10"><rect width="10" height="10"><animate attributeName="x" from="0" to="10" dur="1s" repeatCount="indefinite"/></rect></svg>';
const animatedImage = new File([animation], "mozgas.SVG");
assert.ok(!picker.props.accept);
await picker.props.onChange({target: {files: [animatedImage], value: animatedImage.name}});
await save();
const animatedNode = sheet.nodes.at(-1);
assert.equal(animatedNode.file.type, "image");
assert.equal(svgUpload.headers["Content-Type"], "image/svg+xml");
assert.equal(await svgUpload.body.text(), animation, "the original animation is uploaded intact");
assert.ok(prop("src", "/api/attachment/test?inline=1&name=mozgas.svg", graphic(animatedNode.id)));
const alphaColor = () => prop("aria-label", "Kép háttérszíne", panel());
assert.equal(alphaColor().props.disabled, true, "color is inactive until transparency is detected");
document.createElement = () => ({getContext: () => ({
  drawImage() {},
  getImageData: () => ({data: Uint8ClampedArray.of(0, 0, 0, 80)}),
})});
const graphicImage = () => find(n => n.tag === "img", graphic(animatedNode.id));
graphicImage().props.onLoad({target: {naturalWidth: 1, naturalHeight: 1}});
delete document.createElement;
await tick();
assert.equal(alphaColor().props.disabled, false);
alphaColor().props.onChange({target: {value: "#123456"}});
await tick();
assert.equal(graphicImage().props.style.backgroundColor, "#123456");
await press("Alpha csatorna");
assert.equal(alphaColor().props.disabled, true);
assert.equal(graphicImage().props.style.backgroundColor, "#ffffff");
await save();
assert.equal(model(animatedNode.id).file.alphaEnabled, false);
await press("Alpha csatorna");
await save();
assert.equal(graphicImage().props.style.backgroundColor, "#123456");
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
assert.deepEqual(titleActions, ["focus", "Új ötlet"]);

sidebarToggle().props.onClick(); await tick();
globalThis.innerWidth = 1200;
globalThis.innerHeight = 800;
const contextClick = event(canvas(), 310, -130, {button: 2, target: {closest: () => null}});
canvas().props.onPointerdownCapture(contextClick);
canvas().props.onContextmenu(contextClick);
await tick();
await press("Objektum létrehozása"); await save();
assert.deepEqual(sheet.nodes.at(-1).position, {x: 310, y: -130});
assert.deepEqual(titleActions, ["focus", "Új ötlet", "focus", "Új ötlet"]);
window.prompt = () => "jegyzet";
canvas().props.onPointerdownCapture(contextClick);
canvas().props.onContextmenu(contextClick);
await tick();
titleActions.length = 0;
await press("Új munkalap"); await save();
assert.equal(sheet.nodes.at(-1).link, "jegyzet");
assert.deepEqual(titleActions, ["focus", "Jegyzet"]);
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
const hiddenNote = labelLayout({...sample, text: "**Szöveg**", hideText: true, textStyle: {alignment: "right", verticalAlignment: "bottom"}});
const dot = hiddenNote.lines.find(l => l.runs);
assert.equal(dot.text, "•••");
assert.equal(dot.anchor, "end");
assert.ok(dot.y > 0);
assert.equal(labelLayout({...sample,fontSize:28},[{kind:"body",runs:[{text:"body"}]}]).lines.find(l=>l.runs).size,13);
const blocks = [{kind: "body", runs: [{text: "Text"}]}];
const justifiedRows = labelLayout({...sample, width: 130, textStyle: {justified: true}},
  [{kind: "body", runs: [{text: "Ez egy rövid példa több szövegsorral."}]}]).lines.filter(line => line.runs);
assert.ok(justifiedRows[0].wordSpacing > 0);
assert.equal(justifiedRows.at(-1).wordSpacing, undefined);
assert.equal(justifiedRows.at(-1).anchor, "start");
const largeLabel = {...sample, title: "Hosszú cím", width: 64, height: 40, fontSize: 80, textStyle: {size: 120}};
const bounded = labelLayout(largeLabel, blocks);
assert.equal(bounded.overflow, true);
assert.ok(bounded.lines[0].text.endsWith("…"));
const unbounded = labelLayout({...largeLabel, backgroundEnabled: false}, blocks);
assert.equal(unbounded.overflow, false);
assert.deepEqual(unbounded.lines.map(line => [line.text, line.size]), [["Hosszú cím", 80], ["Text", 120]]);
assert.ok(unbounded.extentX > unbounded.width / 2 && unbounded.extentY > unbounded.height / 2);
const fitted = labelLayout({...sample, fitText: true}, blocks);
const smaller = labelLayout({...sample, fitText: true, width: 120, height: 100}, blocks);
assert.equal(fitted.overflow, false);
assert.equal(smaller.overflow, false);
assert.ok(fitted.lines.find(line => line.section === "title").size > fitted.lines.find(line => line.runs).size);
assert.ok(fitted.lines.find(line => line.runs).size > smaller.lines.find(line => line.runs).size);
const compact = labelLayout({...sample, fitText: true, width: 64, height: 40, shape: "triangle"}, blocks);
assert.equal(compact.overflow, false);
assert.equal(compact.lines.length, 2);
for (const vertical of ["top", "middle", "bottom"]) {
  for (const align of ["left", "center", "right"]) {
    const layout = labelLayout({...sample, alignment: align, verticalAlignment: vertical}, []);
    assert.equal(layout.lines[0].anchor, {left: "start", center: "middle", right: "end"}[align]);
    assert.equal(Math.sign(Math.round(layout.lines[0].y - 5.28)) || 0, {top: -1, middle: 0, bottom: 1}[vertical]);
  }
}
const layout = labelLayout({...sample, verticalAlignment: "bottom", textStyle: {verticalAlignment: "top"}}, blocks);
assert.ok(layout.lines.find(l => l.text === "Text").y < layout.lines.find(l => l.text === "label").y);

const outside = labelLayout({...sample, titleOutside: true, alignment: "left", verticalAlignment: "top",
  textOutside: true, textStyle: {alignment: "center", verticalAlignment: "bottom"}}, blocks);
assert.ok(outside.lines.filter(l => !l.runs).every(l => l.x < -outside.width/2 && l.y < -outside.height/2));
assert.ok(Math.abs(outside.lines.find(l => l.runs).y) <= outside.height/2);
assert.ok(outside.extentX > outside.width/2 && outside.extentY > outside.height/2);

const {rebaseWorksheet} = await import("../../Public/collaboration.js");
const base = {revision: 1, nodes: [node("a", 0, 0), node("b", 40, 10)], edges: []};
const local = structuredClone(base), remote = structuredClone(base);
local.nodes[0].title = "Anna";
remote.nodes[1].title = "Béla";
remote.revision++;
const merged = rebaseWorksheet(base, local, remote);
assert.deepEqual(merged.nodes.map(n => n.title), ["Anna", "Béla"]);
local.edges.push({id: "added", source: "a", target: {node: "b"}});
remote.nodes.pop();
assert.deepEqual(rebaseWorksheet(base, local, remote).edges[0].target, {point: {x: 40, y: 10}});
console.log("Passed link resolution, nine alignments and concurrent worksheet edits.");

const {replayChanges, worksheetChanges} = await import("../../Public/editor-history.js");
const parent = {id: "parent", kind: "container"};
const member = {id: "member", kind: "container"};
const separated = {nodes: [parent, member], edges: []};
const nested = {nodes: [parent, {...member, parent: "parent"}], edges: []};
const outsiderMove = {nodes: [{...parent, parent: "member"}, member], edges: []};
assert.equal(replayChanges(outsiderMove, worksheetChanges(nested, separated), false, () => false), null);
const originalWire = {id: "old", source: "parent", target: {node: "member"}};
const deletedWire = worksheetChanges({...separated, edges: [originalWire]}, separated);
const replacementWire = {...separated, edges: [{...originalWire, id: "replacement"}]};
assert.equal(replayChanges(replacementWire, deletedWire, false, () => false), null);
const historyJunction = {id: "j", kind: "connectionPoint"};
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
assert.equal(prop("attributeName", "gradientTransform", oneWire()).props.dur, "6s");
const gradient = find(n => n.tag === "linearGradient", oneWire());
const stops = gradient.children.filter(n => n.tag === "stop");
assert.deepEqual(stops.map(n => n.props.offset), [0, .25, .5, .75, 1]);
assert.deepEqual(stops.map(n => n.props["stop-opacity"]), [1, 1, .5, 1, 1]);
assert.ok(stops.every(n => n.props["stop-color"] === "#365bd6"));
await press("Nyíl a vonal elején");
assert.equal(prop("attributeName", "gradientTransform", oneWire()).props.dur, "12s");
await press("Nyíl a vonal végén");
await press("S-forma");
await press("Pontozott");
assert.equal(button("S-forma").props["aria-pressed"], true);
assert.equal(button("Pontozott").props["aria-pressed"], true);
assert.ok(find(n => n.props.d?.includes(" C ") && n.props["stroke-dasharray"] === "0 16", oneWire()));
assert.equal(prop("attributeName", "stroke-dashoffset", oneWire()).props.values, "0;16");
await save();
assert.equal(edge("one").animated, true);
assert.equal(edge("one").type, "sCurve");
assert.equal(edge("one").appearance, "dotted");
assert.equal(edge("one").startArrow, true);
assert.equal(edge("one").endArrow, false);
await press("Nyíl a vonal elején");
await press("Nyíl a vonal végén");
assert.equal(prop("attributeName", "stroke-dashoffset", oneWire()).props.values, "0;-16");
await press("Szaggatott");
assert.equal(prop("attributeName", "stroke-dashoffset", oneWire()).props.values, "0;-12");
await press("Vastag");
assert.equal(prop("attributeName", "stroke-width", oneWire()).props.values, "4;5.8;4");
assert.equal(prop("attributeName", "transform", endpoint("one", "target")).props.type, "scale");
const selectionGlow = prop("class", "wire-selected", oneWire());
assert.ok(selectionGlow);
assert.equal(selectionGlow.children.filter(n => n.props["stroke-width"] !== undefined).length, 1);
assert.equal(prop("attributeName", "stroke-width", selectionGlow).parent.props.stroke, "#365bd6");
assert.equal(endpoint("one", "target").props.fill, "#365bd6");
assert.equal(prop("class", "selection-glow", oneWire()), undefined);
await press("Animáció bekapcsolása");
assert.equal(prop("attributeName", "stroke-width", oneWire()), undefined);
await press("Egyenes");
await press("Sima");
await save();

await properties("outside");
assert.equal(prop("class", "wire-selected", oneWire()), undefined);
assert.ok(prop("stroke", "#526982", oneWire()));
for (const [label, shape, vertices] of [["Háromszög", "triangle", 3], ["Ötszög", "pentagon", 5],
  ["Hatszög", "hexagon", 6], ["Paralelogramma", "parallelogram", 4]]) {
  const option = button(label);
  assert.equal(text(option), "");
  await press(label);
  assert.equal(button(label).props["aria-pressed"], true);
  await save();
  assert.equal(model("outside").shape, shape);
  const polygon = find(n => n.tag === "polygon" && n.props.fill === model("outside").fill, graphic("outside"));
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
assert.ok(route("arc").labelPosition.y < 0 && route("rope").labelPosition.y > 0);
const arc = route("arc");
assert.ok(edgeInRectangle(arc, {x:-1,y:-30,width:2,height:2}, true), "the rectangle touches the arc at its apex");
assert.ok(!edgeInRectangle(arc, {x:-1,y:-32,width:2,height:2}, true), "a control hull alone is insufficient");
assert.ok(edgeInRectangle(arc, {x:-100,y:-28,width:200,height:28}, false));
assert.equal(edgePaint({appearance: "thick"}).width, 4);
assert.equal(edgePaint({appearance: "dotted"}).linecap, "round");

const {importFile} = await import("../../Public/canvas-files.js");
const doc = await importFile(new File(['{"large":90071992547409931,"nested":[{},{"literal":"a,b"}]}'], "adat.json"));
assert.equal(doc.file.type, "json");
assert.ok(doc.text.includes('"large": 90071992547409931'));
assert.deepEqual(JSON.parse(doc.text).nested, [{},{literal:"a,b"}]);
await assert.rejects(importFile(new File(["szöveg"], "hibás.json")), /JSON/);
await assert.rejects(importFile(new File(["data"], "lap.thnode")), /munkalapok/);
console.log("Passed document import, JSON precision and unsupported format checks.");
