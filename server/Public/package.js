// Projektcsomag (docs/migration.md): letöltés ZIP-ben és importálás (új projektként vagy allapként).

function el(tag, attributes = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attributes)) {
    if (value == null || value === false) continue;
    if (key === "text") node.textContent = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? "" : value);
  }
  node.append(...[children].flat().filter(child => child != null));
  return node;
}

function modal(title) {
  const dialog = el("dialog", {class: "panel password-dialog package-dialog", "aria-label": title});
  const status = el("p", {class: "package-status", role: "status"});
  dialog.append(el("h3", {text: title}));
  document.body.append(dialog);
  dialog.addEventListener("close", () => dialog.remove(), {once: true});
  return {dialog, status};
}

async function failure(response, fallback) {
  const detail = await response.json().catch(() => ({}));
  return Error(detail.reason || fallback + " (" + response.status + ")");
}

const choice = (name, value, label, checked) =>
  el("label", {class: "package-choice"}, [el("input", {type: "radio", name, value, checked}), label]);

const megabytes = bytes => (bytes / 1024 / 1024).toLocaleString("hu-HU", {maximumFractionDigits: 1}) + " MB";

/// Letöltés: `path` a lap URL-útvonala (kódolt részekkel); `protected`: jelszavas projekt (titkosítás kötelező).
export function exportPackage({path, csrf, protected: locked = false}) {
  const {dialog, status} = modal("Letöltés ZIP-csomagként");
  const encrypt = el("input", {type: "checkbox", checked: locked, disabled: locked});
  const password = el("input", {type: "password", autocomplete: "new-password", minlength: 12, "aria-label": "Csomagjelszó"});
  const again = el("input", {type: "password", autocomplete: "new-password", minlength: 12, "aria-label": "Csomagjelszó újra"});
  const secret = el("div", {class: "stack", hidden: !locked}, [
    el("label", {}, ["Csomagjelszó", password]),
    el("label", {}, ["Csomagjelszó újra", again]),
    el("p", {class: "muted", text: "Legalább 12 karakter. Nem egyezhet a projekt jelszavával; importáláskor ezzel nyitható ki a csomag."}),
  ]);
  encrypt.addEventListener("change", () => { secret.hidden = !encrypt.checked; });
  const versions = el("input", {type: "checkbox"});
  const submit = el("button", {class: "button primary", text: "Letöltés"});
  const form = el("form", {class: "stack"}, [
    el("fieldset", {class: "stack"}, [el("legend", {text: "Tartalom"}),
      choice("scope", "tree", "A lap az allapjaival", true), choice("scope", "sheet", "Csak ez a lap", false)]),
    el("label", {class: "package-choice"}, [versions, "Mentett állapotok (.version) is"]),
    el("fieldset", {class: "stack"}, [el("legend", {text: "Más lapok fájljai"}),
      choice("external", "keep", "Hivatkozás marad (figyelmeztetéssel)", true), choice("external", "copy", "Bemásolás a csomagba", false)]),
    el("label", {class: "package-choice"}, [encrypt, locked ? "Titkosítás jelszóval (jelszavas projektnél kötelező)" : "Titkosítás jelszóval"]),
    secret, status,
    el("div", {class: "property-inline"}, [submit, el("button", {class: "button", type: "button", text: "Mégse", onclick: () => dialog.close()})]),
  ]);
  form.addEventListener("submit", async event => {
    event.preventDefault();
    status.textContent = "";
    if (encrypt.checked) {
      if (password.value.length < 12) { status.textContent = "A csomagjelszó legalább 12 karakter legyen."; return; }
      if (password.value !== again.value) { status.textContent = "A két jelszó nem egyezik."; return; }
    }
    submit.disabled = true;
    status.textContent = "Csomag készítése…";
    try {
      const response = await fetch("/api/package/export/" + path + "?prepare=1", {method: "POST",
        headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf},
        body: JSON.stringify({scope: form.elements.scope.value, external: form.elements.external.value,
          versions: versions.checked, password: encrypt.checked ? password.value : undefined})});
      if (!response.ok) throw await failure(response, "A csomag nem készült el");
      // A csomag a szerveren várja a letöltést (egy óráig): a böngésző közvetlenül lemezre tölti, nem a lap memóriájába,
      // és megszakadás után a saját letöltéskezelőjével folytatni tudja.
      const prepared = await response.json();
      el("a", {href: prepared.url, download: prepared.name}).click();
      dialog.close();
    } catch (error) {
      status.textContent = error.message;
      submit.disabled = false;
    }
  });
  dialog.append(form);
  dialog.showModal();
}

/// Importálás: `target` null → új projekt; egyébként a lap URL-útvonala, ami alá allapként kerül.
/// Az új lap útvonalát (kódolt) adja vissza, vagy null-t, ha megszakították.
export function importPackage(file, {target = null, csrf}) {
  return new Promise(resolve => {
    const {dialog, status} = modal(target ? "Importálás allapként" : "Projekt importálása");
    let token = null, done = false;
    const body = el("div", {class: "stack"});
    const finish = value => { done = true; resolve(value); dialog.close(); };
    const upload = new AbortController();
    let uploadID = null;
    dialog.addEventListener("close", () => {
      upload.abort();
      if (done) return;
      resolve(null);
      // Megszakítás feltöltés közben: a félbemaradt rész törlődik a szerverről.
      if (uploadID) {
        forgetUpload(file, target);
        fetch("/api/package/uploads/" + uploadID, {method: "DELETE", headers: {"X-CSRF-Token": csrf}}).catch(() => {});
      }
      if (token) fetch("/api/package/cancel", {method: "POST", headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf},
        body: JSON.stringify({token})}).catch(() => {});
    });
    const cancel = () => el("button", {class: "button", type: "button", text: "Mégse", onclick: () => dialog.close()});
    dialog.append(body, status);
    dialog.showModal();

    const post = async (url, payload) => {
      const response = await fetch(url, {method: "POST", headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf},
        body: JSON.stringify(payload)});
      if (!response.ok) throw await failure(response, "Az importálás sikertelen");
      return response.json();
    };

    function askPassword() {
      const password = el("input", {type: "password", autocomplete: "off", required: true, "aria-label": "Csomagjelszó"});
      const open = el("button", {class: "button primary", text: "Megnyitás"});
      const form = el("form", {class: "stack"}, [
        el("p", {text: "A csomag titkosított. Add meg a csomagjelszót."}),
        el("label", {}, ["Csomagjelszó", password]),
        el("div", {class: "property-inline"}, [open, cancel()]),
      ]);
      form.addEventListener("submit", async event => {
        event.preventDefault();
        open.disabled = true;
        status.textContent = "Kicsomagolás…";
        try { review(await post("/api/package/unlock", {token, password: password.value})); }
        catch (error) { status.textContent = error.message; open.disabled = false; password.select(); }
      });
      body.replaceChildren(form);
      password.focus();
    }

    function review(report) {
      status.textContent = "";
      const name = el("input", {value: report.name ?? "", required: true, "aria-label": "Útvonalnév"});
      const summary = el("p", {class: "muted", text: report.sheets + " munkalap · " + report.files + " fájl · " + megabytes(report.bytes ?? 0)});
      const warnings = report.warnings?.length ? el("details", {class: "package-warnings"}, [
        el("summary", {text: "Figyelmeztetések (" + report.warnings.length + ")"}),
        el("ul", {}, report.warnings.map(text => el("li", {text}))),
      ]) : null;
      const selects = new Map();
      const editors = report.editors?.length ? el("fieldset", {class: "stack"}, [el("legend", {text: "Szerkesztők párosítása"}),
        ...report.editors.map(editor => {
          const select = el("select", {"aria-label": "Párosítás · " + editor.name}, [
            el("option", {value: "", text: "— kimarad —"}),
            ...report.users.map(user => el("option", {value: user, text: user, selected: user === editor.match})),
          ]);
          selects.set(editor.name, select);
          return el("label", {class: "editor-membership"}, [el("span", {text: editor.name}), select]);
        })]) : null;
      const projectPassword = el("input", {type: "password", autocomplete: "new-password", "aria-label": "Projektjelszó"});
      const passwordField = report.target === "project" ? el("label", {}, ["Projektjelszó (nem kötelező)", projectPassword]) : null;
      const submit = el("button", {class: "button primary", text: "Importálás"});
      const form = el("form", {class: "stack"}, [
        el("label", {}, [report.target === "project" ? "Projekt útvonalneve" : "Allap útvonalneve", name]),
        summary, warnings, editors, passwordField,
        report.target === "project" ? el("p", {class: "muted", text: "A tulajdonos te leszel. A csomag nem hoz jelszót; ha a projektet védeni akarod, itt adj meg egyet."}) : null,
        el("div", {class: "property-inline"}, [submit, cancel()]),
      ]);
      form.addEventListener("submit", async event => {
        event.preventDefault();
        submit.disabled = true;
        status.textContent = "Importálás…";
        try {
          const mapping = Object.fromEntries([...selects].map(([from, select]) => [from, select.value]).filter(([, to]) => to));
          const result = await post("/api/package/commit", {token, name: name.value.trim(), editors: mapping,
            projectPassword: projectPassword.value || undefined});
          finish(result.path);
        } catch (error) { status.textContent = error.message; submit.disabled = false; }
      });
      body.replaceChildren(form);
      name.focus();
    }

    (async () => {
      const bar = el("progress", {max: 1, value: 0, class: "package-progress", "aria-label": "Feltöltés"});
      const retry = el("button", {class: "button primary", type: "button", text: "Folytatás", hidden: true});
      body.replaceChildren(el("p", {text: file.name + " · " + megabytes(file.size)}), bar, el("div", {class: "property-inline"}, [retry, cancel()]));
      const run = async () => {
        retry.hidden = true;
        try {
          const report = await uploadInChunks(file, {target, csrf, signal: upload.signal, session: id => { uploadID = id; },
            progress: (received, size, note) => {
              bar.value = size ? received / size : 0;
              status.textContent = note ?? "Feltöltés: " + megabytes(received) + " / " + megabytes(size) + " (" + Math.floor(100 * received / size) + "%)";
            }});
          uploadID = null;
          token = report.token;
          if (report.needsPassword) { status.textContent = ""; askPassword(); } else review(report);
        } catch (error) {
          if (upload.signal.aborted) return;
          status.textContent = error.message;
          // Megszakadt kapcsolat: a már feltöltött rész megmarad a szerveren, innen folytatható.
          retry.hidden = !error.resumable;
        }
      };
      retry.addEventListener("click", run);
      window.addEventListener("online", () => { if (!retry.hidden && !done) run(); }, {signal: upload.signal});
      run();
    })();
  });
}

// --- Darabolt, folytatható feltöltés (ProjectPackage.swift) -----------------------------------------------------
// A fájl 8 MiB-os darabokban megy fel; a szerver minden darab után megmondja, meddig jutott. Megszakadt kapcsolatnál
// a feltöltés néhányszor magától újrapróbál, és mindig onnan folytat, ahol a szerver tart. A munkamenet azonosítója
// a böngészőben megmarad (localStorage), így ugyanazt a fájlt újra kiválasztva az oldal újratöltése után is folytatódik.
export const maximumPackage = 4 * 1024 ** 3 - 1;
const uploadKey = (file, target) => "tnPackageUpload:" + [file.name, file.size, file.lastModified, target ?? ""].join("|");
const remembered = (file, target) => { try { return localStorage.getItem(uploadKey(file, target)); } catch { return null; } };
const remember = (file, target, id) => { try { localStorage.setItem(uploadKey(file, target), id); } catch { /* privát mód */ } };
const forgetUpload = (file, target) => { try { localStorage.removeItem(uploadKey(file, target)); } catch { /* privát mód */ } };
const pause = (ms, signal) => new Promise((resolve, reject) => {
  const timer = setTimeout(resolve, ms);
  signal?.addEventListener("abort", () => { clearTimeout(timer); reject(new DOMException("Megszakítva", "AbortError")); }, {once: true});
});

/// A fájl feltöltése darabokban; az import jelentésével tér vissza. `progress(received, size, note?)`, `session(id)`.
/// Megszakadt kapcsolat miatti végleges hibánál a hiba `resumable` – ugyanez a hívás onnan folytatja.
export async function uploadInChunks(file, {target = null, csrf, signal, progress = () => {}, session = () => {}, retries = 6, wait = pause} = {}) {
  if (file.size > maximumPackage) throw Error("A csomag legfeljebb 4 GiB lehet.");
  const json = {"Content-Type": "application/json", "X-CSRF-Token": csrf};
  const lost = cause => Object.assign(Error("A kapcsolat megszakadt; a feltöltött rész megmaradt, folytatható."), {resumable: true, cause});
  // Hálózati hiba és átmeneti szerverhiba (5xx) újrapróbálható; minden más válasz végleges.
  const attempt = async request => {
    for (let failures = 0; ; failures++) {
      try {
        const response = await request();
        if (response.status < 500) return response;
        if (failures >= retries) throw await failure(response, "A feltöltés sikertelen");
      } catch (error) {
        if (signal?.aborted || error.name === "AbortError") throw error;
        if (!(error instanceof TypeError) && !error.resumable && failures >= retries) throw error;
        if (failures >= retries) throw lost(error);
      }
      progress(received, file.size, "A kapcsolat megszakadt, újrapróbálás…");
      await wait(Math.min(15000, 1000 * 2 ** failures), signal);
    }
  };
  let received = 0, state = null;
  const begin = async () => {
    const response = await attempt(() => fetch("/api/package/uploads", {method: "POST", headers: json, signal,
      body: JSON.stringify({size: file.size, target})}));
    if (!response.ok) throw await failure(response, "A feltöltés nem indítható");
    state = await response.json();
    remember(file, target, state.id);
  };
  // Korábban félbemaradt feltöltés ugyanerről a fájlról: onnan folytatjuk.
  const known = remembered(file, target);
  if (known) {
    const response = await attempt(() => fetch("/api/package/uploads/" + known, {signal}));
    if (response.ok) { const found = await response.json(); if (found.size === file.size) state = found; }
  }
  if (!state) await begin();
  session(state.id);
  received = state.received;
  let restarted = false;
  while (received < file.size) {
    progress(received, file.size);
    const part = file.slice(received, Math.min(file.size, received + state.chunk));
    const response = await attempt(() => fetch("/api/package/uploads/" + state.id + "?offset=" + received, {method: "PUT", signal,
      headers: {"Content-Type": "application/octet-stream", "X-CSRF-Token": csrf}, body: part}));
    if (response.ok) received = (await response.json()).received;
    else if (response.status === 409 && response.headers.has("X-ThinkNodes-Received")) {
      // A szerver máshol tart (pl. az előző darab megérkezett, csak a válasz veszett el): onnan folytatjuk.
      received = Number(response.headers.get("X-ThinkNodes-Received"));
    } else if ((response.status === 410 || response.status === 404) && !restarted) {
      // A félbemaradt feltöltés lejárt a szerveren: elölről.
      restarted = true;
      await begin();
      session(state.id);
      received = 0;
    } else throw await failure(response, "A feltöltés sikertelen");
  }
  progress(file.size, file.size, "Kicsomagolás és ellenőrzés…");
  const finished = await attempt(() => fetch("/api/package/uploads/" + state.id + "/finish", {method: "POST", headers: json, signal}));
  forgetUpload(file, target);
  if (!finished.ok) throw await failure(finished, "Az importálás sikertelen");
  return finished.json();
}

/// ThinkNodes-csomag-e a ZIP (docs/migration.md): titkosított csomag (`thinknodes-encrypted.json`), vagy nyitott csomag,
/// amelynek gyökerében `Név/Név.thnode` van. Csak a ZIP tartalomjegyzékét olvassa (a fájl végéről), a tartalmat nem.
export async function isPackageZip(blob) {
  try {
    if (blob.size < 22 || blob.size > maximumPackage) return false;
    const tailStart = Math.max(0, blob.size - 65557);
    const tail = new DataView(await blob.slice(tailStart).arrayBuffer());
    let end = -1;
    for (let offset = tail.byteLength - 22; offset >= 0; offset--) {
      if (tail.getUint32(offset, true) === 0x06054b50) { end = offset; break; }
    }
    if (end < 0) return false;
    const size = tail.getUint32(end + 12, true), start = tail.getUint32(end + 16, true);
    if (size > 8 * 1024 * 1024 || start + size > blob.size) return false;
    const directory = new DataView(await blob.slice(start, start + size).arrayBuffer());
    const decoder = new TextDecoder();
    for (let offset = 0; offset + 46 <= directory.byteLength && directory.getUint32(offset, true) === 0x02014b50;) {
      const nameLength = directory.getUint16(offset + 28, true);
      const name = decoder.decode(new Uint8Array(directory.buffer, offset + 46, nameLength)).normalize("NFC");
      if (name === "thinknodes-encrypted.json") return true;
      const parts = name.split("/");
      if (parts.length === 2 && parts[1] === parts[0] + ".thnode") return true;
      offset += 46 + nameLength + directory.getUint16(offset + 30, true) + directory.getUint16(offset + 32, true);
    }
  } catch { /* nem olvasható ZIP: nem csomag */ }
  return false;
}

/// Fájlválasztó: egy .zip kiválasztása.
export function chooseZip() {
  return new Promise(resolve => {
    const input = el("input", {type: "file", accept: ".zip,application/zip", hidden: true});
    input.addEventListener("change", () => { resolve(input.files[0] ?? null); input.remove(); });
    input.addEventListener("cancel", () => { resolve(null); input.remove(); });
    document.body.append(input);
    input.click();
  });
}
