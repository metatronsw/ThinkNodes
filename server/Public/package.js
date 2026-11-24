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
      const response = await fetch("/api/package/export/" + path, {method: "POST",
        headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf},
        body: JSON.stringify({scope: form.elements.scope.value, external: form.elements.external.value,
          versions: versions.checked, password: encrypt.checked ? password.value : undefined})});
      if (!response.ok) throw await failure(response, "A csomag nem készült el");
      const blob = await response.blob();
      const name = decodeURIComponent(path.split("/").pop()) + ".zip";
      const url = URL.createObjectURL(blob);
      el("a", {href: url, download: name}).click();
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
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
    dialog.addEventListener("close", () => {
      if (done) return;
      resolve(null);
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
      body.replaceChildren(el("p", {text: file.name + " · " + megabytes(file.size)}), el("div", {class: "property-inline"}, [cancel()]));
      status.textContent = "Feltöltés és ellenőrzés…";
      try {
        if (file.size > 200 * 1024 * 1024) throw Error("A csomag legfeljebb 200 MiB lehet.");
        const response = await fetch("/api/package/upload" + (target ? "/" + target : ""), {method: "POST",
          headers: {"Content-Type": "application/zip", "X-CSRF-Token": csrf}, body: file});
        if (!response.ok) throw await failure(response, "A feltöltés sikertelen");
        const report = await response.json();
        token = report.token;
        if (report.needsPassword) { status.textContent = ""; askPassword(); } else review(report);
      } catch (error) { status.textContent = error.message; }
    })();
  });
}

/// ThinkNodes-csomag-e a ZIP (docs/migration.md): titkosított csomag (`thinknodes-encrypted.json`), vagy nyitott csomag,
/// amelynek gyökerében `Név/Név.thnode` van. Csak a ZIP tartalomjegyzékét olvassa (a fájl végéről), a tartalmat nem.
export async function isPackageZip(blob) {
  try {
    if (blob.size < 22 || blob.size > 200 * 1024 * 1024) return false;
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
