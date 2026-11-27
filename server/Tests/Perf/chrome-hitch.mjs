// Akadások valódi Chrome-ban (CDP, valódi egéresemények): első kijelölés, első / második dobozmozgatás, első / második
// pásztázás, sorozatos kijelölés. A képkockaidőket a lapba töltött Tests/Perf/recorder.js rögzíti.
// Használat: node Tests/Perf/chrome-hitch.mjs [LAP] [ismétlés] [?query]
import {launch, sleep} from "./chrome.mjs";
import {readFileSync} from "node:fs";

const [sheet = "LiquidGlass", rounds = "2", query = ""] = process.argv.slice(2);
const chrome = await launch();
const {send, js} = chrome;
const recorder = readFileSync(new URL("./recorder.js", import.meta.url), "utf8");
const mouse = (type, x, y, buttons = 0, button = "left") => send("Input.dispatchMouseEvent", {type, x: Math.round(x), y: Math.round(y), button: type === "mouseMoved" && !buttons ? "none" : button, buttons, clickCount: type === "mouseMoved" ? 0 : 1});
// A vásznat a jobb gomb pásztázza (button = "right"), a dobozt a bal gomb mozgatja.
async function drag(points, steps, hold = 120, button = "left") {
  const held = button === "right" ? 2 : 1;
  await mouse("mouseMoved", ...points[0]); await mouse("mousePressed", ...points[0], held, button); await sleep(hold);
  for (let k = 1; k < points.length; k++) {
    const [x0, y0] = points[k - 1], [x1, y1] = points[k];
    for (let i = 1; i <= steps; i++) { await mouse("mouseMoved", x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps, held, button); await sleep(16); }
  }
  await sleep(60); await mouse("mouseReleased", ...points.at(-1), 0, button);
}
async function click(x, y) { await mouse("mouseMoved", x, y); await mouse("mousePressed", x, y, 1); await sleep(40); await mouse("mouseReleased", x, y, 0); }
async function recorded(run) {
  await js("__perf.start(), window.__lat = __perf.latencies(['pointerdown', 'pointerup']), 1");
  await run();
  await sleep(500);
  const frames = await js("__perf.stop()"), lat = await js("window.__lat.stop()");
  return {...frames, latency: lat};
}
const show = (name, r) => console.log(name.padEnd(16), "fps", String(r.fps).padStart(5), "| max", String(r.max).padStart(6), "ms | >50ms:", String(r.over50).padStart(2),
  "| >100ms:", String(r.over100).padStart(2), "| késés (lenyomás→képkocka):", (r.latency ?? []).slice(0, 8).join(", "), "ms");
try {
  for (let round = 1; round <= Number(rounds); round++) {
    await chrome.open("http://localhost:8888/edit/" + encodeURIComponent(sheet) + query);
    await js(recorder + "; 1");
    await sleep(5000);
    console.log("— kör", round, "(friss betöltés, 5 mp nyugalom után)");
    const boxes = await js("__perf.nodes('box', 8)");
    const box = boxes[0], empty = await js("__perf.emptyPoint()");
    show("első kijelölés", await recorded(() => click(box.x, box.y)));
    await sleep(1500);
    show("első mozgatás", await recorded(() => drag([[box.x, box.y], [box.x + 220, box.y + 140], [box.x, box.y]], 30)));
    await sleep(1500);
    show("második mozg.", await recorded(() => drag([[box.x, box.y], [box.x + 220, box.y + 140], [box.x, box.y]], 30)));
    await sleep(1500);
    show("első pásztázás", await recorded(() => drag([[empty.x, empty.y], [empty.x + 500, empty.y + 250], [empty.x, empty.y]], 40, 120, "right")));
    await sleep(1500);
    show("második pászt.", await recorded(() => drag([[empty.x, empty.y], [empty.x + 500, empty.y + 250], [empty.x, empty.y]], 40, 120, "right")));
    await sleep(1500);
    show("kijelölések", await recorded(async () => { for (const b of boxes.slice(1)) { await click(b.x, b.y); await sleep(260); } }));
  }
} catch (error) { console.log("HIBA:", error.message); }
finally { await chrome.close(); }
