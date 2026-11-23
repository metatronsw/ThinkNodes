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
export function openFileBrowser(path) {
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

    async function show(sheet) {
      status.hidden = true;
      list.replaceChildren(element("p", "Betöltés…"));
      try {
        const response = await fetch("/api/browse/" + sheet, {cache: "no-store"});
        if (!response.ok) throw Error((await response.json().catch(() => ({}))).reason ?? "A mappa nem nyitható meg.");
        const listing = await response.json();
        const parts = listing.path.split("/").map(decodeURIComponent);
        const source = parts.slice(1).join("/");
        location.textContent = "/" + parts.join("/");
        const rows = [];
        if (listing.parent) rows.push(row("..", "parent-up", () => show(listing.parent)));
        for (const entry of listing.entries) {
          const mark = entry.publicAccess ? [icon("butterfly")] : [];
          if (entry.kind === "folder") {
            rows.push(row(entry.name, "folder", () => show(listing.path + "/" + encodeURIComponent(entry.name))));
          } else {
            rows.push(row(entry.kind === "web" ? entry.name.replace(/\.web$/, "") : entry.name, kindIcon[entry.kind], () => {
              chosen = {kind: entry.kind, name: entry.name, asset: entry.asset ?? null, source, project};
              dialog.close();
            }, mark));
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
