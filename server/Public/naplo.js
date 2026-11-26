import {avatarSymbol} from "./presence.js";

// Projektnapló oldal (/_naplo/<projekt>): bejegyzések idő szerint, jelzők (fontos, elvégezve, inaktív), szűrők,
// új bejegyzés és helyben szerkesztés. Írni a projekt szerkesztői tudnak (a szerver ellenőrzi); a lap 8 mp-enként
// (és visszatéréskor) frissül, szerkesztés közben nem.
const main = document.querySelector("#project-log");
const {project, csrf} = main.dataset;
const prefsKey = "thinknodes:log-view";
let view = {hideDone: false, hideInactive: true, importantOnly: false, newestFirst: true};
try { view = {...view, ...JSON.parse(localStorage.getItem(prefsKey) ?? "{}")}; } catch {}
let log = {entries: [], writable: false}, editing = null, problem = "";

const element = (tag, props = {}, children = []) => {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") el.className = value;
    else if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
    else if (key === "text") el.textContent = value;
    else if (value === true) el.setAttribute(key, "");
    else if (value !== false && value != null) el.setAttribute(key, value);
  }
  el.append(...children.filter(Boolean));
  return el;
};
const when = value => new Date(value).toLocaleString("hu-HU", {year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit"});

async function request(body) {
  const response = await fetch("/api/log/" + encodeURIComponent(project), body ? {method: "POST",
    headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify(body)} : {});
  if (!response.ok) throw Error((await response.json().catch(() => ({}))).reason || "A napló nem érhető el.");
  return response.json();
}
async function act(body) {
  try { log = await request(body); problem = ""; }
  catch (error) { problem = error.message; }
  render();
}
async function refresh() {
  if (editing || document.hidden) return;
  try { log = await request(); problem = ""; } catch (error) { problem = error.message; }
  if (!editing) render();
}

function flagButton(entry, flag, label, symbol) {
  return element("button", {type: "button", class: "log-flag", "data-flag": flag, "aria-pressed": String(entry[flag]),
    disabled: !log.writable, title: label, text: symbol + " " + label,
    onclick: () => act({action: "flag", id: entry.id, flag, value: !entry[flag]})});
}
function entryView(entry) {
  const author = element("strong", {text: entry.author});
  if (entry.color) author.style.color = entry.color;
  const head = element("div", {class: "log-head"}, [
    avatarSymbol(entry.avatar || 1, entry.color), author,
    element("time", {datetime: entry.created, text: when(entry.created)}),
    entry.edited ? element("span", {class: "log-edited", text: "módosította: " + entry.editedBy + ", " + when(entry.edited)}) : null,
  ]);
  let body;
  if (editing === entry.id) {
    const area = element("textarea", {class: "log-edit", rows: "4", maxlength: "5000"});
    area.value = entry.text;
    const save = () => { editing = null; act({action: "text", id: entry.id, text: area.value}); };
    area.addEventListener("keydown", event => {
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) save();
      if (event.key === "Escape") { editing = null; render(); }
    });
    body = element("div", {class: "log-editor"}, [area, element("div", {class: "log-actions"}, [
      element("button", {type: "button", class: "button primary", text: "Mentés", onclick: save}),
      element("button", {type: "button", class: "button", text: "Mégse", onclick: () => { editing = null; render(); }}),
    ])]);
    setTimeout(() => area.focus());
  } else {
    body = element("div", {class: "log-text", text: entry.text});
  }
  return element("li", {class: "log-entry", "data-important": entry.important, "data-done": entry.done, "data-inactive": entry.inactive}, [
    head, body,
    element("div", {class: "log-flags"}, [
      flagButton(entry, "important", "Fontos", "★"),
      flagButton(entry, "done", "Elvégezve", "✓"),
      flagButton(entry, "inactive", "Inaktív", "–"),
      log.writable && editing !== entry.id ? element("button", {type: "button", class: "log-flag", text: "✎ Szerkesztés",
        onclick: () => { editing = entry.id; render(); }}) : null,
    ]),
  ]);
}
function toggle(key, label) {
  const box = element("input", {type: "checkbox"});
  box.checked = view[key];
  box.addEventListener("change", () => { view[key] = box.checked; try { localStorage.setItem(prefsKey, JSON.stringify(view)); } catch {} render(); });
  return element("label", {class: "log-filter"}, [box, document.createTextNode(" " + label)]);
}
let draft = "", draftImportant = false;
function render() {
  const visible = log.entries.filter(e => !(view.hideDone && e.done) && !(view.hideInactive && e.inactive) && !(view.importantOnly && !e.important));
  if (view.newestFirst) visible.reverse();
  const composer = log.writable ? (() => {
    const area = element("textarea", {class: "log-new", rows: "3", maxlength: "5000", placeholder: "Új bejegyzés… (Ctrl/⌘+Enter: hozzáadás)", "aria-label": "Új bejegyzés"});
    area.value = draft;
    area.addEventListener("input", () => { draft = area.value; });
    const important = element("input", {type: "checkbox"});
    important.checked = draftImportant;
    important.addEventListener("change", () => { draftImportant = important.checked; });
    const add = async () => {
      if (!area.value.trim()) return;
      const text = area.value;
      draft = "";
      draftImportant = false;
      await act({action: "add", text, value: important.checked});
    };
    area.addEventListener("keydown", event => { if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) add(); });
    return element("section", {class: "panel log-composer"}, [area, element("div", {class: "log-actions"}, [
      element("label", {class: "log-filter"}, [important, document.createTextNode(" Fontos")]),
      element("button", {type: "button", class: "button primary", text: "Hozzáadás", onclick: add}),
    ])]);
  })() : element("p", {class: "muted", text: "A naplót olvashatod; írni a projekt szerkesztői tudnak."});
  const filters = element("div", {class: "log-filters"}, [
    toggle("newestFirst", "Újak felül"), toggle("importantOnly", "Csak a fontosak"),
    toggle("hideDone", "Elvégzettek elrejtése"), toggle("hideInactive", "Inaktívak elrejtése"),
    element("span", {class: "muted", text: visible.length + " / " + log.entries.length + " bejegyzés"}),
  ]);
  const list = element("ol", {class: "log-list"}, visible.length ? visible.map(entryView) : [element("li", {class: "muted", text: "Nincs megjeleníthető bejegyzés."})]);
  const focused = document.activeElement?.classList.contains("log-new");
  for (const old of main.querySelectorAll(".log-composer, .log-filters, .log-list, .log-problem")) old.remove();
  main.querySelector(".log-readonly")?.remove();
  if (!log.writable) composer.classList.add("log-readonly");
  main.append(...[problem ? element("p", {class: "log-problem", role: "alert", text: problem}) : null, composer, filters, list].filter(Boolean));
  if (focused) main.querySelector(".log-new")?.focus();
}

await refresh();
render();
setInterval(refresh, 8000);
document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
