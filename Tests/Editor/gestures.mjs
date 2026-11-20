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
function zoom() {
  const behavior = () => {};
  behavior.filter = behavior.scaleExtent = () => behavior;
  behavior.on = (key, fn) => { zoomEvents[key] = fn; return behavior; };
  behavior.transform = () => {};
  return behavior;
}
globalThis.document = {querySelector: () => root};
globalThis.window = {Vue: {...Vue, createApp: renderer.createApp}, addEventListener(key, fn) { listeners[key] = fn; },
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
  node("outer", 0, 0, 300, 240), node("inner", 10, 10, 160, 120), node("child", 10, 10, 64, 40),
  node("outside", 340, 0, 100, 80), {...node("auto", -420, 0, 120, 60), autoSize: true},
], edges: [{id: "one", source: "outside", target: {point: {x: 400, y: 230}}, type: "straight", appearance: "plain"}]};
let socket, finishPoll, fetchWorksheet;
globalThis.location = new URL("http://localhost/test");
globalThis.WebSocket = window.WebSocket = class {
  constructor() { socket = this; }
};
let selectedNode;
let writes = 0;
let checkpoint = structuredClone(sheet);
globalThis.fetch = async (url, options) => {
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
  if (url.includes("worksheet-users")) return Response.json(["admin"]);
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
const button = label => find(n => n.tag === "button" && text(n) === label);
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
const panel = () => find(n => n.tag === "aside");
const sidebarToggle = () => find(n => n.tag === "button" && n.props["aria-label"]?.startsWith("Oldalsáv "));
oneWire().props.onClick();
await tick();
assert.equal(panel()?.props["aria-label"], "Vonal szerkesztése");
assert.ok(button("Egyenes"), "selecting a wire opens its editable properties directly");
toggle("Escape", true); await tick();
assert.equal(panel()?.props["aria-label"], "Munkalap");
assert.ok(find(n => n.tag === "input" && n.props.value === sheet.title, panel()));
toggle("Escape", true); await tick();
assert.ok(!panel(), "Escape without a selection collapses the panel");
sidebarToggle().props.onClick(); await tick();
oneWire().props.onClick(); await tick();
assert.ok(panel(), "reselecting a wire reopens the panel");
sidebarToggle().props.onClick(); await tick();
oneWire().props.onClick(); await tick();
assert.ok(!panel(), "an explicit collapse survives selection");
oneWire().props.onDblclick({stopPropagation() {}}); await tick();
assert.ok(panel(), "double-click reopens a manually collapsed panel");
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
canvas().props.onPointerup(event(canvas(), 390, 45, {altKey: true, shiftKey: true}));
await save();
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
await drag(graphic("outside"), 180, 30, -420, 0, {ctrlKey: true});
await save();
assert.equal(sheet.edges.at(-1).source, "outside");
assert.deepEqual(sheet.edges.at(-1).target, {node: "auto"});
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


for (const [id, x, y, automatic] of [["outside",180,30,false], ["auto",-420,0,true]]) {
  toggle("Alt", true); await tick();
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
const titleSize = control(section("Cím"), "Betűméret");
assert.equal(titleSize.props.max, 1000);
edit(titleSize, "1000"); await tick(); await save();
assert.equal(model("outside").fontSize, 1000);
edit(titleSize, "16"); await tick();
const body = section("Text");
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
toggle("Escape", true); await tick();
const spacing = find(n => n.tag === "label" && n.children[0]?.text === "Rácsköz").children[1];
spacing.props.onInput({target: {value: "36"}}); await tick();
assert.equal(prop("id", "worksheet-grid").props.width, 36);
const snapSwitch = () => prop("aria-label", "Rácsra igazítás");
assert.equal(snapSwitch().props["aria-pressed"], false);
snapSwitch().props.onClick(); await tick();
const start = model("auto").position;
await drag(graphic("auto"), start.x, start.y, 121, -83);
await save();
assert.deepEqual(model("auto").position, {x:126, y:-90});
snapSwitch().props.onClick(); await tick();
const transform = d3.zoomIdentity.translate(35, 75).scale(2);
zoomEvents.zoom({transform}); await tick();
const grid = prop("fill", "url(#worksheet-grid)");
assert.equal(grid.parent.props.transform, transform + " translate(600 400)");
const gridWrites = writes;
prop("aria-label", "Pontrács").props.onClick(); await tick();
await new Promise(resolve => setTimeout(resolve, 100));
assert.equal(writes, gridWrites);
assert.notEqual(sheet.gridVisible, false);
assert.equal(prop("fill", "url(#worksheet-grid)"), undefined);
toggle("Enter", true); await tick();
const search = prop("aria-label", "Keresés a munkalapon");
assert.ok(search);
search.props.onInput({target: {value: "child"}}); await tick();
assert.ok(button("child"));
toggle("Enter", true); await tick();
assert.ok(!prop("aria-label", "Keresés a munkalapon"));
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
assert.equal(text(panel().children.at(-1)), "Törlés");
globalThis.confirm = () => { throw Error("Connected nodes must delete without a prompt"); };
listeners.keydown({key: "Backspace"}); await tick(); await save();
assert.ok(!model("outside") && !edge("one"));
await press("Visszavonás"); await save();
assert.ok(model("outside"));
assert.equal(edge("one").source, "outside");
await press("Újra"); await save();
assert.ok(!model("outside") && !edge("one"));
await press("Visszavonás"); await save();
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
await press("S-forma");
await press("Pontozott");
assert.equal(button("S-forma").props["aria-pressed"], true);
assert.equal(button("Pontozott").props["aria-pressed"], true);
assert.ok(find(n => n.props.d?.includes(" C ") && n.props["stroke-dasharray"] === "0 16", oneWire()));
await save();
assert.equal(edge("one").type, "sCurve");
assert.equal(edge("one").appearance, "dotted");
await press("Egyenes");
await press("Sima");
await save();

const {edgeGeometry, edgePaint, edgeInRectangle} = await import("../../Public/geometry.js");
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
await assert.rejects(importFile(new File(["data"], "idegen.bin")), /Támogatott/);
console.log("Passed document import, JSON precision and unsupported format checks.");
