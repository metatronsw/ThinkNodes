import {fetchPage, updateSection, watchPageUpdates} from "./page-updates.js";
function updateCardColors() {
  const dark = document.documentElement.dataset.display === "dark";
  for (const card of document.querySelectorAll(".project-card")) {
    card.style.setProperty("--sheet-color", dark ? card.dataset.colorDark : card.dataset.colorLight);
  }
}
window.addEventListener("thinknodes-display", updateCardColors);
updateCardColors();

if (document.querySelector("#worksheet-cards")) {
  watchPageUpdates(async (signal, incoming) => {
    const {page, response} = incoming ?? await fetchPage(signal);
    if (signal.aborted) return;
    if (response.status >= 500) throw Error("Az oldal nem érhető el.");
    if (response.redirected || !page.querySelector("#worksheet-cards")) { location.reload(); return; }
    if (!response.ok) throw Error("A projektlista nem érhető el.");
    updateSection(document, page, "#worksheet-cards");
    updateSection(document, page, ".site-header .header-actions");
    updateCardColors();
  });
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

async function editorsDialog(card) {
  try {
    const response = await fetch("/api/worksheet-users" + card.pathname);
    if (!response.ok) throw Error("A szerkesztőfiókok listája nem érhető el.");
    const accounts = await response.json();
    const members = new Set(card.dataset.editors.split(" ").filter(Boolean));
    const dialog = document.createElement("dialog");
    dialog.className = "panel password-dialog";
    dialog.setAttribute("aria-label", "Szerkesztők kezelése");
    const heading = document.createElement("h3");
    heading.textContent = "Szerkesztők kezelése";
    const rows = document.createElement("div");
    rows.className = "stack";
    for (const name of new Set([...members, ...accounts])) {
      if (name === card.dataset.owner) continue;
      const row = document.createElement("div");
      row.className = "editor-membership";
      const label = document.createElement("span");
      label.textContent = name;
      const button = document.createElement("button");
      button.className = "button small";
      button.textContent = members.has(name) ? "Eltávolítás" : "Hozzáadás";
      button.setAttribute("aria-label", button.textContent + " · " + name);
      button.onclick = () => change(card, members.has(name) ? "revoke" : "grant", name);
      row.append(label, button);
      rows.append(row);
    }
    if (!rows.childElementCount) rows.textContent = "Nincs hozzáadható szerkesztőfiók.";
    const close = document.createElement("button");
    close.className = "button";
    close.textContent = "Bezárás";
    close.onclick = () => dialog.close();
    dialog.append(heading, rows, close);
    dialog.addEventListener("close", () => dialog.remove(), {once: true});
    document.body.append(dialog);
    dialog.showModal();
  } catch (error) { alert(error.message); }
}

export function documentEntries(card) {
  const entries = [["Megnyitás", () => location.assign(card.href), "folder"]];
  if (card.dataset.manage !== "true") return entries;
  const input = (label, action, question, icon) => [label, () => {
    const value = window.prompt(question);
    if (value != null) change(card, action, value.trim());
  }, icon];
  if (card.dataset.scope === "attachment") return entries;
  entries.push(
    ["Törlés", () => { if (confirm("Lomtárba helyezed?")) change(card, "delete"); }, "trash"],
    [card.dataset.hidden === "true" ? "Megjelenítés" : "Elrejtés", () => change(card, "hide"), "eye"],
    card.dataset.password === "true" ? ["Jelszár feloldása", () => change(card, "password", ""), "unlock"] : ["Jelszár beállítása", () => passwordDialog(card), "lock"],
    [card.dataset.frozen === "true" ? "Szerkesztés feloldása" : "Szerkesztés zárolása", () => change(card, "freeze"), "hand"],
    input("Átnevezés", "rename", "Új útvonalnév", "edit"),
  );
  if (card.dataset.scope === "project") entries.push(
    ["Szerkesztők kezelése", () => editorsDialog(card), "plus"],
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
  if (event.target.closest("[data-manage-editors]")) {
    const card = document.querySelector("[data-current-document][data-scope=project][data-manage=true]");
    if (card) await editorsDialog(card);
    return;
  }
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
