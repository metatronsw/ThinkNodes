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
  return {id, title: id, position: {x, y}, width, height, shape: "rectangle", autoSize: false, markdown: "",
    fill: "#bbbbbb", border: "#555555", textColor: "#111111", alignment: "center", fontSize: 16, bold: true};
}
let sheet = {title: "Próba", revision: 1, nodes: [
  node("outer", 0, 0, 300, 240), node("inner", 10, 10, 160, 120), node("child", 10, 10, 64, 40),
  node("outside", 340, 0, 100, 80), {...node("auto", -420, 0, 120, 60), autoSize: true},
], edges: [{id: "one", source: "outside", target: {point: {x: 400, y: 230}}, style: "arrow"}]};
let selectedNode;
let writes = 0;
let checkpoint = structuredClone(sheet);
globalThis.fetch = async (url, options) => {
  if (url.includes("/presence/")) {
    const {action, node, since} = JSON.parse(options.body);
    if (since) return new Promise(() => {});
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
  if (url.includes("markdown/canvas")) return Response.json({
    blocks: JSON.parse(options.body).sources.map(source => [{kind: "body", runs: [{text: source}]}]),
  });
  if (options?.method === "PUT") {
    writes++;
    sheet = JSON.parse(options.body);
    sheet.revision++;
  }
  return Response.json(sheet);
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
  await drag(handle, handle.props.cx, handle.props.cy, x, y, {ctrlKey: true}, cancel);
  toggle("Control", false); await tick();
}

const oneWire = () => find(n => n.tag === "g" && n.props["data-edge"] === "one");
const panel = () => find(n => n.tag === "aside");
const sidebarToggle = () => find(n => n.tag === "button" && n.props["aria-label"]?.startsWith("Oldalsáv "));
oneWire().props.onClick();
await tick();
assert.ok(panel(), "selecting a wire opens the panel");
toggle("Escape", true); await tick();
assert.equal(panel()?.props["aria-label"], "Munkalap");
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
assert.ok(!button("Mentés").props.class.includes("primary"));
for (let x = 1; x <= 24; x++) {
  canvas().props.onPointermove(event(canvas(), x, 20));
  assert.equal(button("Mentés").props.disabled, false);
  await new Promise(resolve => setTimeout(resolve, 8));
}
assert.equal(writes, beforeDrag, "holding and moving must not write the worksheet");
canvas().props.onPointerup(event(canvas(), 24, 20));
await new Promise(resolve => setTimeout(resolve, 150));
assert.equal(writes, beforeDrag + 1);
assert.ok(button("Mentés").props.class.includes("primary"));
await save();
assert.ok(!button("Mentés").props.class.includes("primary"));
await drag(graphic("outer"), 24, 20, 80, 70);
await new Promise(resolve => setTimeout(resolve, 150));
await button("Resign").props.onClick();
await tick();
assert.deepEqual(model("outer").position, {x: 24, y: 20});
await drag(graphic("outer"), 24, 20, 0, 0);
await save();

await properties("outer");
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

const free = endpoint("one", "target");
assert.equal(free.props.fill, "transparent");
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
assert.equal(endpoint("one", "target"), undefined, "cancel restores the attachment");
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
await properties(joint.id);
listeners.keydown({key: "Backspace", ctrlKey: true}); await tick(); await save();
assert.ok(!model(joint.id) && incident.every(id => !edge(id)));
const freeStart = event(canvas(), -600, -320, {ctrlKey: true, target: {closest: () => null}});
canvas().props.onPointerdownCapture(freeStart);
canvas().props.onPointermove(event(canvas(), -510, -315));
canvas().props.onPointerup(event(canvas(), -510, -315));
await save();
assert.deepEqual(sheet.edges.at(-1).sourcePoint, {x: -600, y: -320});
assert.deepEqual(sheet.edges.at(-1).target.point, {x: -510, y: -315});
assert.equal(sheet.edges.at(-1).endArrow, true);
const markerID = "arrow-" + sheet.edges.at(-1).id;
assert.ok(prop("marker-end", "url(#" + markerID + ")"));
assert.equal(prop("id", markerID).props.markerWidth, 6.75);

for (const [id, x, y, automatic] of [["outside",180,30,false], ["auto",-420,0,true]]) {
  toggle("Alt", true); await tick();
  const corner = find(n => n.props.cursor === "nwse-resize" && n.props.x > 0, graphic(id));
  const cx = x + corner.props.x + 5, cy = y + corner.props.y + 5;
  await drag(corner, cx, cy, cx+40, cy+30, {altKey: true});
  await save();
  assert.ok(model(id).width > (automatic ? 64 : 100));
  assert.equal(model(id).fontSize > 16, automatic);
}
await properties("outside");
const hex = prop("aria-label", "Háttér HEX");
for (const value of ["#", "#a", "#ab", "#abc", "#abcd", "#abcde", "#abcdef"]) {
  hex.props.onInput({target: {value}}); await tick();
  assert.equal(hex.props.value, value);
}
assert.ok(prop("fill", "#abcdef", graphic("outside")));
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
const comment = section("Megjegyzés"), markdown = section("Markdown");
edit(control(comment, "Megjegyzés"), "Rövid");
edit(control(comment, "Betűméret"), "19");
control(comment, "Igazítás").props.onChange({target: {value: "right"}});
enable(check(comment, "Dőlt"));
edit(control(markdown, "Markdown"), "Törzs");
enable(check(markdown, "Show Markdown"));
enable(check(markdown, "Aláhúzott"));
edit(prop("aria-label", "Markdown háttér HEX"), "#ffeecc");
await tick();
const details = find(n => n.tag === "tspan" && text(n) === "Rövid", graphic("outside"));
assert.equal(details.props["font-size"], 19);
assert.equal(details.props["font-style"], "italic");
assert.equal(details.props["text-anchor"], "end");
assert.equal(find(n => n.tag === "tspan" && text(n) === "Törzs", graphic("outside")).props["text-decoration"], "underline");
assert.ok(prop("fill", "#ffeecc", graphic("outside")));
edit(prop("aria-label", "Markdown háttér HEX"), "#ffb77a");
await tick();
assert.equal(find(n => n.tag === "rect" && n.props["pointer-events"] === "none" && n.props.fill === "#ffb77a", graphic("outside")), undefined);
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
prop("aria-label", "Pontrács").props.onClick(); await tick(); await save();
assert.equal(sheet.gridVisible, false);
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
await press("Előnézet");
assert.equal(text(panel().children.at(-1)), "Törlés");
globalThis.confirm = () => { throw Error("Connected nodes must delete without a prompt"); };
listeners.keydown({key: "Backspace"}); await tick(); await save();
assert.ok(!model("outside") && edge("one").sourcePoint);
console.log("Passed editor gestures, junction cleanup, container nesting and lock, text scaling, palette, HEX and world grid.");

const {worksheetLink} = await import("../../Public/links.js");
assert.deepEqual(worksheetLink("../közös", "main/lab"), {kind: "worksheet", href: "/main/k%C3%B6z%C3%B6s"});
assert.equal(worksheetLink("/..", "main/lab").href, "/main");
assert.equal(worksheetLink("sub/one", "main").href, "/main/sub/one");
assert.equal(worksheetLink("https://example.org", "main").kind, "website");
assert.equal(worksheetLink("javascript:alert(1)", "main"), null);

const {labelLayout} = await import("../../Public/geometry.js");
const sample = {...node("label", 0, 0, 240, 200), showMarkdown: true};
const hiddenNote = labelLayout({...sample, markdown: "**Szöveg**", showMarkdown: false, markdownStyle: {alignment: "right", verticalAlignment: "bottom"}});
const dot = hiddenNote.lines.find(l => l.runs);
assert.equal(dot.text, "•");
assert.equal(dot.anchor, "end");
assert.ok(dot.y > 0);
const blocks = [{kind: "body", runs: [{text: "Markdown"}]}];
for (const vertical of ["top", "middle", "bottom"]) {
  for (const align of ["left", "center", "right"]) {
    const layout = labelLayout({...sample, alignment: align, verticalAlignment: vertical}, []);
    assert.equal(layout.lines[0].anchor, {left: "start", center: "middle", right: "end"}[align]);
    assert.equal(Math.sign(Math.round(layout.lines[0].y - 5.28)) || 0, {top: -1, middle: 0, bottom: 1}[vertical]);
  }
}
const layout = labelLayout({...sample, verticalAlignment: "bottom", markdownStyle: {verticalAlignment: "top"}}, blocks);
assert.ok(layout.lines.find(l => l.text === "Markdown").y < layout.lines.find(l => l.text === "label").y);

const outside = labelLayout({...sample, titleOutside: true, alignment: "left", verticalAlignment: "top",
  comment: "Megjegyzés", markdownOutside: true, markdownStyle: {alignment: "center", verticalAlignment: "bottom"}}, blocks);
assert.ok(outside.lines.filter(l => !l.runs).every(l => l.x < -outside.width/2 && l.y < -outside.height/2));
assert.ok(outside.lines.find(l => l.runs).y > outside.height/2);
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
