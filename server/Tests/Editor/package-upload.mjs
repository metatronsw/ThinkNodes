// Darabolt, folytatható csomagfeltöltés (Public/package.js uploadInChunks) utánzott szerverrel és hálózati hibákkal.
// Futtatás a server/ mappából: node Tests/Editor/package-upload.mjs
import assert from "node:assert/strict";

const storage = new Map();
globalThis.localStorage = {getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, String(value)),
  removeItem: key => storage.delete(key)};
globalThis.document = {createElement: () => ({})};
const {uploadInChunks, maximumPackage} = await import("../../Public/package.js");

// Utánzott szerver: munkamenetek a kapott bájtokkal; `faults` a soron következő kérések hibái.
const chunk = 1000;
const sessions = new Map();
let faults = [], requests = [], next = 1;
const reply = (status, body, headers = {}) => new Response(body == null ? null : JSON.stringify(body), {status, headers});
globalThis.fetch = async (url, options = {}) => {
  const method = options.method ?? "GET";
  requests.push(method + " " + url);
  const fault = faults.shift();
  if (fault === "offline") throw new TypeError("Failed to fetch");
  if (fault === "busy") return reply(503, {reason: "Túlterhelt"});
  if (url === "/api/package/uploads" && method === "POST") {
    const {size, target} = JSON.parse(options.body);
    const id = "upload-" + next++;
    sessions.set(id, {size, target, data: new Uint8Array(0)});
    return reply(200, {id, size, received: 0, chunk});
  }
  const [, id, action] = /^\/api\/package\/uploads\/([^/?]+)(\/finish)?/.exec(url) ?? [];
  const session = sessions.get(id);
  if (!session) return reply(410, {reason: "A feltöltés lejárt; kezdd újra."});
  if (action) return session.data.length === session.size ? reply(200, {token: "import-1", needsPassword: false, target: "project", bytes: session.size})
    : reply(409, {reason: "A feltöltés még nem teljes."});
  if (method === "GET") return reply(200, {id, size: session.size, received: session.data.length, chunk});
  const offset = Number(new URL(url, "http://x").searchParams.get("offset"));
  if (offset !== session.data.length) return reply(409, {reason: "A feltöltés máshol tart."}, {"X-ThinkNodes-Received": String(session.data.length)});
  const part = new Uint8Array(await options.body.arrayBuffer());
  session.data = Uint8Array.from([...session.data, ...part]);
  // "lost": a darab megérkezett, de a válasz elveszett.
  if (fault === "lost") throw new TypeError("Failed to fetch");
  return reply(200, {id, size: session.size, received: session.data.length, chunk});
};

const bytes = Uint8Array.from({length: 4500}, (_, index) => index % 251);
const file = (name = "csomag.zip") => Object.assign(new Blob([bytes]), {name, lastModified: 42});
const wait = async () => {};      // az újrapróbálás várakozása nélkül
const same = id => assert.deepEqual([...sessions.get(id).data], [...bytes]);

// 1. Zavartalan feltöltés: 5 darab, a végén a jelentés; a megjegyzett munkamenet törlődik.
let steps = [];
let report = await uploadInChunks(file(), {csrf: "t", wait, progress: (received, size) => steps.push(received)});
assert.equal(report.token, "import-1");
same("upload-1");
assert.deepEqual(steps.slice(0, 6), [0, 1000, 2000, 3000, 4000, 4500]);
assert.equal(requests.filter(r => r.startsWith("PUT")).length, 5);
assert.equal(storage.size, 0);

// 2. Átmeneti hibák: megszakadt kérés, 503, és elveszett válasz (a szerver már tovább tart: 409 → onnan folytat).
requests = []; faults = [undefined, "offline", "busy", undefined, "lost"];
report = await uploadInChunks(file("masik.zip"), {csrf: "t", wait});
same("upload-2");
assert.ok(requests.filter(r => r.startsWith("PUT")).length > 5, "a hibás darabok újra mentek");
assert.equal(sessions.get("upload-2").data.length, 4500, "egy darab sem került be kétszer");

// 3. Tartós kapcsolathiba: a hiba folytatható, a munkamenet megjegyezve; újrahívva onnan folytat, nem elölről.
requests = []; faults = [undefined, undefined, undefined, ...Array(20).fill("offline")];
await assert.rejects(uploadInChunks(file("harmadik.zip"), {csrf: "t", wait, retries: 2}), error => error.resumable === true);
const partial = sessions.get("upload-3").data.length;
assert.equal(partial, 2000);
assert.equal(storage.size, 1);
requests = []; faults = [];
let resumedFrom;
report = await uploadInChunks(file("harmadik.zip"), {csrf: "t", wait, progress: received => { resumedFrom ??= received; }});
assert.equal(resumedFrom, 2000, "a folytatás a szerver állásától indul");
assert.equal(requests[0], "GET /api/package/uploads/upload-3");
assert.equal(requests.filter(r => r === "POST /api/package/uploads").length, 0, "nem nyílt új munkamenet");
same("upload-3");
assert.equal(storage.size, 0);

// 4. A megjegyzett munkamenet közben lejárt a szerveren: új munkamenet, elölről.
storage.set("tnPackageUpload:negyedik.zip|4500|42|", "upload-99");
requests = [];
report = await uploadInChunks(file("negyedik.zip"), {csrf: "t", wait});
assert.equal(requests.filter(r => r === "POST /api/package/uploads").length, 1);
same("upload-4");

// 5. Megszakítás (a párbeszédablak bezárása): a feltöltés leáll, nem próbálkozik újra.
const controller = new AbortController();
requests = [];
const aborted = uploadInChunks(file("otodik.zip"), {csrf: "t", wait, signal: controller.signal,
  progress: received => { if (received >= 2000) controller.abort(); }});
globalThis.fetch = (inner => async (url, options = {}) => { if (options.signal?.aborted) throw new DOMException("Megszakítva", "AbortError"); return inner(url, options); })(globalThis.fetch);
await assert.rejects(aborted, error => error.name === "AbortError");

// 6. Túl nagy fájl: kérés nélkül elutasítva.
requests = [];
await assert.rejects(uploadInChunks({size: maximumPackage + 1, name: "óriás.zip"}, {csrf: "t"}), /4 GiB/);
assert.equal(requests.length, 0);

console.log("Passed chunked package upload: retries, lost responses, resume and expiry.");
