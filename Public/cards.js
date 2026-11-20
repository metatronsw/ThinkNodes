for (const card of document.querySelectorAll(".project-card")) {
  card.style.setProperty("--sheet-color", card.dataset.color);
}

export function contextMenu(event, entries) {
  event.preventDefault();
  close();
  menu = document.createElement("div");
  menu.className = "context-menu panel";
  for (const [label, action, icon] of entries) {
    const button = document.createElement("button");
    button.className = "button";
    button.innerHTML = '<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><use href="/icons.svg#' + icon + '"/></svg>';
    button.append(document.createTextNode(label));
    button.onclick = () => { close(); action(); };
    menu.append(button);
  }
  document.body.append(menu);
  menu.style.left = Math.max(0, Math.min(event.clientX, innerWidth-menu.offsetWidth)) + "px";
  menu.style.top = Math.max(0, Math.min(event.clientY, innerHeight-menu.offsetHeight)) + "px";
}

let menu;
function close() { menu?.remove(); menu = null; }

async function change(card, action, value) {
  const csrf = card.closest("[data-csrf]")?.dataset.csrf;
  try {
    const response = await fetch("/api/document" + (card.dataset.document ? "/" + card.dataset.document : card.pathname), {method: "POST", headers: {
      "Content-Type": "application/json", "X-CSRF-Token": csrf,
    }, body: JSON.stringify({scope: card.dataset.scope, filename: card.dataset.filename, action, value})});
    const result = await response.json();
    if (!response.ok) throw Error(result.reason || "A művelet sikertelen.");
    if (action === "rename" && card.matches("[data-current-document]")) location.assign("/" + result.path);
    else if (action === "delete" && card.matches("[data-current-document]")) {
      location.assign(card.pathname.slice(0, card.pathname.lastIndexOf("/")) || "/");
    } else location.reload();
  } catch (error) { alert(error.message); }
}

function passwordDialog(card) {
  const dialog = document.createElement("dialog");
  dialog.className = "panel password-dialog";
  const form = document.createElement("form");
  form.className = "stack";
  form.method = "dialog";
  const label = document.createElement("label");
  label.textContent = "Új jelszó";
  const password = document.createElement("input");
  password.type = "password";
  password.required = true;
  password.autocomplete = "new-password";
  label.append(password);
  const save = document.createElement("button");
  save.className = "button primary";
  save.textContent = "Mentés";
  const cancel = document.createElement("button");
  cancel.className = "button";
  cancel.type = "button";
  cancel.textContent = "Mégse";
  cancel.onclick = () => dialog.close();
  form.onsubmit = () => change(card, "password", password.value);
  form.append(label, save, cancel);
  dialog.append(form);
  dialog.addEventListener("close", () => dialog.remove(), {once: true});
  document.body.append(dialog);
  dialog.showModal();
}

export function documentEntries(card) {
  const entries = [["Megnyitás", () => location.assign(card.href), "folder"]];
  if (card.dataset.manage !== "true") return entries;
  const input = (label, action, question, icon) => [label, () => {
    const value = window.prompt(question);
    if (value != null) change(card, action, value.trim());
  }, icon];
  const people = [
    input("Felhasználó hozzáadása", "grant", "Felhasználónév", "plus"),
    input("Felhasználó eltávolítása", "revoke", "Felhasználónév", "minus"),
  ];
  if (card.dataset.scope === "attachment") return [...entries, ...people];
  entries.push(
    ["Törlés", () => { if (confirm("Lomtárba helyezed?")) change(card, "delete"); }, "trash"],
    [card.dataset.hidden === "true" ? "Megjelenítés" : "Elrejtés", () => change(card, "hide"), "eye"],
    card.dataset.password === "true" ? ["Jelszár feloldása", () => change(card, "password", ""), "unlock"] : ["Jelszár beállítása", () => passwordDialog(card), "lock"],
    [card.dataset.frozen === "true" ? "Szerkesztés feloldása" : "Szerkesztés zárolása", () => change(card, "freeze"), "hand"],
    input("Átnevezés", "rename", "Új útvonalnév", "edit"),
    ...people,
  );
  if (card.dataset.scope === "project") entries.push(
    card.dataset.public === "true" ? ["Belső mód", () => change(card, "mode", "internal"), "folder"] : ["Nyilvános mód", () => change(card, "mode", "public"), "butterfly"],
  );
  return entries;
}

document.addEventListener("contextmenu", event => {
  const card = event.target.closest("a[data-scope]");
  if (card) contextMenu(event, documentEntries(card));
});
document.addEventListener("pointerdown", event => { if (menu && !menu.contains(event.target)) close(); });
document.addEventListener("keydown", event => { if (event.key === "Escape") close(); });

document.addEventListener("click", async event => {
  const button = event.target.closest(".new-worksheet");
  if (!button) return;
  const parent = button.closest("[data-current-sheet]")?.dataset.currentSheet;
  const name = window.prompt(parent ? "Új munkalap útvonalneve" : "Új projekt útvonalneve")?.trim();
  if (!name) return;
  if (!/^[\p{L}\p{M}\p{Nd}_-]+$/u.test(name)) {
    alert("Az útvonalnév betűket, számokat, kötőjelet és aláhúzást tartalmazhat.");
    return;
  }
  const path = (parent ? parent + "/" : "") + encodeURIComponent(name);
  try {
    const response = await fetch("/api/subworksheet/" + path, {method: "POST", headers: {
      "X-CSRF-Token": button.closest("[data-csrf]").dataset.csrf,
    }});
    if (!response.ok) throw Error((await response.json()).reason || "A létrehozás sikertelen.");
    location.assign("/edit/" + path);
  } catch (error) { alert(error.message); }
});
