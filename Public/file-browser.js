// Tallózó: a projekt mappáiban lévő fájlok és .web oldalak beillesztése.
// Saját, böngészőn belüli ablak (nem az operációs rendszer fájlválasztója): a lista a szervertől jön
// (/api/browse), amely csak a projekt fáján belül enged mozogni, így helyi szerverrel sem látszik más.

function element(tag, text, attrs = {}) {
  const item = document.createElement(tag);
  Object.assign(item, attrs);
  if (text) item.textContent = text;
  return item;
}

function icon(name) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", "ui-icon");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", "/icons.svg#" + name);
  svg.append(use);
  return svg;
}

const kindIcon = {folder: "folder", web: "website", file: "file"};

// Visszaadja a választott elemet: {kind: "file" | "web", name, source} — `source` a munkalap útvonala
// a projekt után ("" = projekt gyökere). Mégse esetén null.
export function openFileBrowser(path, csrf) {
  const project = path.split("/")[0];
  return new Promise(resolve => {
    let chosen = null;
    const dialog = element("dialog", "", {className: "panel file-browser-dialog"});
    dialog.setAttribute("aria-label", "Tallózás");
    const heading = element("h3", "Beillesztés – Tallózás");
    const location = element("p", "", {className: "muted file-browser-path"});
    const status = element("p", "", {hidden: true});
    status.setAttribute("role", "alert");
    const list = element("div", "", {className: "file-browser-list stack"});
    const close = element("button", "Mégse", {type: "button", className: "button"});
    close.addEventListener("click", () => dialog.close());
    dialog.append(heading, location, status, list, close);
    dialog.addEventListener("close", () => { dialog.remove(); resolve(chosen); }, {once: true});
    document.body.append(dialog);
    dialog.showModal();

    function row(label, symbol, onClick, extra = []) {
      const button = element("button", "", {type: "button", className: "button file-browser-row"});
      button.append(icon(symbol), element("span", label), ...extra);
      button.addEventListener("click", onClick);
      return button;
    }

    // Jobb gombos menü: publikus jog ki/be (fájl: a mappa .settings.json-jában; .web: a .web mappában).
    let menu = null;
    const closeMenu = () => { menu?.remove(); menu = null; };
    dialog.addEventListener("pointerdown", event => { if (menu && !menu.contains(event.target)) closeMenu(); });
    function contextMenu(event, entry, listing, source) {
      event.preventDefault();
      closeMenu();
      menu = element("div", "", {className: "context-menu panel file-browser-menu"});
      const label = entry.publicAccess ? "Publikus jog elvétele" : "Publikus jog hozzáadása";
      const button = element("button", "", {type: "button", className: "button"});
      button.append(icon("butterfly"), element("span", label));
      button.addEventListener("click", async () => {
        closeMenu();
        try {
          const next = !entry.publicAccess;
          const [url, body] = entry.kind === "web"
            ? ["/api/web-presentations/" + listing.path, {reference: (source ? source + "/" : "") + entry.name, publicWeb: next}]
            : ["/api/file-public/" + listing.path, {name: entry.asset ?? entry.name, publicAccess: next}];
          const response = await fetch(url, {method: "PATCH", headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify(body)});
          if (!response.ok) throw Error((await response.json().catch(() => ({}))).reason ?? "A jog módosítása sikertelen.");
          await show(listing.path);
        } catch (error) { status.textContent = error.message; status.hidden = false; }
      });
      menu.append(button);
      const box = dialog.getBoundingClientRect();
      menu.style.left = (event.clientX - box.left) + "px";
      menu.style.top = (event.clientY - box.top) + "px";
      dialog.append(menu);
    }

    async function show(sheet) {
      status.hidden = true;
      list.replaceChildren(element("p", "Betöltés…"));
      const common = sheet === "@common" || sheet.startsWith("@common/");
      try {
        const endpoint = common ? "/api/browse-common/" + sheet.split("/").slice(1).join("/") : "/api/browse/" + sheet;
        const response = await fetch(endpoint, {cache: "no-store"});
        if (!response.ok) throw Error((await response.json().catch(() => ({}))).reason ?? "A mappa nem nyitható meg.");
        const listing = await response.json();
        const parts = listing.path.split("/").map(decodeURIComponent);
        // Közös könyvtárnál a forrás maga az útvonal ("@common/…"), projektben a projekt utáni rész.
        const source = common ? parts.join("/") : parts.slice(1).join("/");
        location.textContent = common ? "Közös könyvtár /" + parts.slice(1).join("/") : "/" + parts.join("/");
        const rows = [];
        if (!common) rows.push(row("Közös könyvtár (csak olvasható)", "package", () => show("@common")));
        if (listing.parent) rows.push(row("..", "parent-up", () => show(listing.parent)));
        else if (common) rows.push(row("..", "parent-up", () => show(path)));
        for (const entry of listing.entries) {
          const mark = entry.publicAccess ? [icon("butterfly")] : [];
          if (entry.kind === "folder") {
            rows.push(row(entry.name, "folder", () => show(listing.path + "/" + encodeURIComponent(entry.name))));
          } else if (common && entry.kind === "file") {
            rows.push(row(entry.name, "file", () => { chosen = {kind: "file", name: entry.name, source, project, common}; dialog.close(); }));
          } else {
            const item = row(entry.kind === "web" ? entry.name.replace(/\.web$/, "") : entry.name, kindIcon[entry.kind], () => {
              chosen = {kind: entry.kind, name: entry.name, asset: entry.asset ?? null, source, project, common};
              dialog.close();
            }, mark);
            if (listing.manageable && csrf) item.addEventListener("contextmenu", event => contextMenu(event, entry, listing, source));
            rows.push(item);
          }
        }
        list.replaceChildren(...(rows.length ? rows : [element("p", "Üres mappa.", {className: "muted"})]));
      } catch (error) {
        list.replaceChildren();
        status.textContent = error.message;
        status.hidden = false;
      }
    }
    show(path);
  });
}

// Törlés közös elemnél: más lapok is használják. Válasz: "keep" | "delete" | "unlink" | null (Mégse).
export function chooseRemoval(names, others) {
  return new Promise(resolve => {
    let answer = null;
    const dialog = element("dialog", "", {className: "panel removal-dialog"});
    dialog.setAttribute("aria-label", "Törlés");
    const list = element("ul");
    for (const other of others) list.append(element("li", other.title + (other.count > 1 ? " (" + other.count + " doboz)" : "")));
    const choice = (label, value, className = "button") => {
      const button = element("button", label, {type: "button", className});
      button.addEventListener("click", () => { answer = value; dialog.close(); });
      return button;
    };
    dialog.append(element("h3", "Más lapok is használják"), element("p", names.join(", ")), list,
      element("div", "", {className: "stack"}));
    dialog.lastChild.append(
      choice("Csak ez a doboz törlődik (a fájl marad)", "keep", "button primary"),
      choice("Lomtárba, a többi doboz is törlődik", "delete", "button danger"),
      choice("Lomtárba, a többi doboz üres doboz lesz", "unlink", "button danger"),
      choice("Mégse", null));
    dialog.addEventListener("close", () => { dialog.remove(); resolve(answer); }, {once: true});
    document.body.append(dialog);
    dialog.showModal();
  });
}
