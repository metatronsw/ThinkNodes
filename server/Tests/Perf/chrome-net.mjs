// Üresjárati hálózati forgalom a szerkesztőben (valódi Chrome, CDP Network): kérések és WebSocket-üzenetek 15 mp alatt.
import {launch, sleep} from "./chrome.mjs";
const chrome = await launch();
try {
  await chrome.open("http://localhost:8888/edit/" + (process.argv[2] ?? "LiquidGlass"));
  await sleep(4000);
  const counts = new Map(), add = key => counts.set(key, (counts.get(key) ?? 0) + 1);
  chrome.listeners.push(m => {
    if (m.method === "Network.requestWillBeSent") add(m.params.request.method + " " + m.params.request.url.replace(/^https?:\/\/[^/]+/, "").replace(/\?.*/, ""));
    if (m.method === "Network.webSocketFrameSent") add("WS ki: " + m.params.response.payloadData.slice(0, 60));
    if (m.method === "Network.webSocketFrameReceived") add("WS be: " + m.params.response.payloadData.slice(0, 60));
  });
  await chrome.send("Network.enable");
  await sleep(15000);
  for (const [k, n] of [...counts.entries()].sort((a, b) => b[1] - a[1])) console.log(String(n).padStart(4), k);
} finally { await chrome.close(); }
