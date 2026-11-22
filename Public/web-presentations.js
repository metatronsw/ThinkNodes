export function openPresentation(url) {
  window.open(url, "_blank", "noopener,noreferrer");
}

export function webPresentationURL(path, reference) {
  const segments = reference?.split("/") ?? [];
  const name = segments.pop();
  if (!name?.endsWith(".web")) return null;
  const names = [...segments, name.slice(0, -4)];
  if (names.length > 11 || !names.every(value => /^[\p{L}\p{M}\p{Nd}_-]+$/u.test(value))) return null;
  const project = path.split("/")[0];
  return "/" + [project, ...segments.map(value => encodeURIComponent(value.normalize("NFC"))), "web", encodeURIComponent(names.at(-1).normalize("NFC"))].join("/") + "/";
}

function element(tag, text, attrs = {}) {
  const item = document.createElement(tag);
  Object.assign(item, attrs);
  if (text) item.textContent = text;
  return item;
}

function action(text, handler) {
  const button = element("button", text, {type: "button", className: "button small"});
  button.addEventListener("click", handler);
  return button;
}

function field(title, input) {
  const label = element("label", title);
  label.append(input);
  return label;
}

async function check(response) {
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw Error(error.reason ?? "A prezentáció művelete sikertelen.");
  }
  return response;
}

export async function openPresentationPicker(path, csrf, insert) {
  const endpoint = "/api/web-presentations/" + path;
  const dialog = element("dialog", "", {className: "panel web-presentations-dialog"});
  dialog.setAttribute("aria-label", "Prezentációk");
  const content = element("div", "", {className: "stack"});
  const status = element("p", "", {hidden: true});
  status.setAttribute("role", "alert");
  const report = message => { status.textContent = message; status.hidden = !message; };
  dialog.append(element("h3", "Prezentációk"), status, content, action("Bezárás", () => dialog.close()));
  dialog.addEventListener("close", () => dialog.remove(), {once: true});
  document.body.append(dialog);
  dialog.showModal();

  async function list() {
    report("");
    content.replaceChildren(element("p", "Betöltés…"));
    try {
      const presentations = await (await check(await fetch(endpoint, {cache: "no-store"}))).json();
      if (!presentations.length) {
        content.replaceChildren(element("p", "Ebben a projektben nincs elérhető .web prezentáció."));
        return;
      }
      content.replaceChildren(...presentations.map(item => {
        const row = element("div", "", {className: "web-presentation-row"});
        const title = element("strong", item.reference);
        row.append(title, action("Megnyitás", () => openPresentation(item.url)));
        if (insert) row.append(action("Beszúrás", () => { insert(item); dialog.close(); }));
        if (item.manageable) row.append(action("Hozzáférés", () => settings(item)));
        return row;
      }));
    } catch (error) { content.replaceChildren(); report(error.message); }
  }

  function settings(item) {
    report("");
    const form = element("form", "", {className: "stack"});
    const members = element("input", "", {type: "checkbox", checked: item.membersOnly === true});
    const restrict = element("input", "", {type: "checkbox", checked: Array.isArray(item.editors)});
    const editors = element("input", "", {value: item.editors?.join(", ") ?? "", disabled: !restrict.checked});
    restrict.addEventListener("change", () => { editors.disabled = !restrict.checked; });
    const password = element("input", "", {type: "password", autocomplete: "new-password", maxlength: 72});
    const clear = element("input", "", {type: "checkbox", disabled: !item.passwordProtected});
    const save = element("button", "Mentés", {type: "submit", className: "button primary"});
    form.append(element("strong", item.reference), field("Csak a projekt szerkesztői", members),
      field("Olvasók szűkítése felhasználónévre", restrict), field("Felhasználónevek vesszővel elválasztva", editors),
      field("Új jelszó", password), field("Jelszó eltávolítása", clear), save, action("Vissza", list));
    form.addEventListener("submit", async event => {
      event.preventDefault();
      report("");
      save.disabled = true;
      try {
        await check(await fetch(endpoint, {method: "PATCH", headers: {
          "Content-Type": "application/json", "X-CSRF-Token": csrf,
        }, body: JSON.stringify({reference: item.reference, membersOnly: members.checked,
          editors: restrict.checked ? editors.value.split(/[\s,]+/).filter(Boolean) : null,
          password: password.value || null, removePassword: clear.checked})}));
        await list();
      } catch (error) { report(error.message); }
      finally { save.disabled = false; }
    });
    content.replaceChildren(form);
  }

  await list();
}
