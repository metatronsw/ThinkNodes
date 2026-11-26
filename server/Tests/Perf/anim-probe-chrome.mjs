import {launch, sleep} from "./chrome.mjs";
import {readFileSync} from "node:fs";
const chrome = await launch();
try {
  await chrome.open("http://localhost:8888/bench-anim.svg", "document.readyState === 'complete'");
  await sleep(1500);
  console.log("Chrome:", await chrome.js(readFileSync(new URL("./anim-probe.js", import.meta.url), "utf8")));
} finally { await chrome.close(); }
