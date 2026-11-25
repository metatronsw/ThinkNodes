// Nagy szövegfájl külön ablakos szerkesztője (docs/node-types.md, text típus): a lap szerkesztőjének oldalsávja helyett
// itt szerkeszthető a teljes tartalom. Mentés: gomb, Ctrl/Cmd+S, és gépelés után néhány másodperccel magától.
// A szerver a doboz változásszámlálóját (`rev`) ellenőrzi: ha közben más mentett, nem írja felül, hanem szól.
const root = document.querySelector("#text-editor");
if (root) {
  const {path, node, csrf} = root.dataset;
  const area = root.querySelector("textarea"), status = root.querySelector(".text-editor-status"), save = root.querySelector("[data-save]");
  let rev = Number(root.dataset.rev) || 0, saved = "", saving = false, timer = null, blocked = false, crlf = false;
  const size = text => (new Blob([text]).size / 1024).toLocaleString("hu-HU", {maximumFractionDigits: 0}) + " KB";
  const dirty = () => area.value !== saved;
  const show = (text, problem = false) => { status.textContent = text; status.classList.toggle("error", problem); };
  const refresh = () => { save.disabled = saving || blocked || !dirty(); };

  async function load() {
    const response = await fetch("/api/box-file/" + path + "?id=" + encodeURIComponent(node), {cache: "no-store"});
    if (!response.ok) throw Error("A fájl nem tölthető be (" + response.status + ").");
    const raw = await response.text();
    // A szövegmező a sorvégeket egységesíti (CRLF → LF): az összehasonlítás a mező értékével történik, mentéskor pedig
    // a fájl eredeti sorvége áll vissza – különben a megnyitás önmagában módosításnak számítana.
    crlf = /\r\n/.test(raw);
    area.value = raw;
    saved = area.value;
    area.disabled = false;
    blocked = false;
    show("Betöltve · " + size(saved));
    refresh();
  }

  async function store() {
    clearTimeout(timer);
    if (saving || blocked || !dirty()) return;
    saving = true;
    refresh();
    const text = area.value;
    show("Mentés…");
    try {
      const response = await fetch("/api/text-file/" + path + "?id=" + encodeURIComponent(node) + "&rev=" + rev, {method: "PUT",
        headers: {"X-CSRF-Token": csrf, "Content-Type": "text/plain; charset=utf-8"}, body: crlf ? text.replace(/\n/g, "\r\n") : text});
      if (response.status === 409) {
        // Közben más mentett: nem írjuk felül. A saját szöveg a mezőben marad (kimásolható), az újratöltés a szerverit hozza.
        blocked = true;
        show("A fájlt közben más is módosította. A mentéshez töltsd újra az oldalt (a mostani szöveged előtte másold ki).", true);
        return;
      }
      if (!response.ok) {
        const detail = await response.json().catch(() => ({}));
        throw Error(detail.reason || "A mentés sikertelen (" + response.status + ").");
      }
      rev = (await response.json()).rev;
      saved = text;
      show("Mentve · " + size(text) + " · " + new Date().toLocaleTimeString("hu-HU"));
    } catch (error) {
      show(error.message + " Újrapróbálás a következő módosításkor vagy a Mentés gombbal.", true);
    } finally {
      saving = false;
      refresh();
      // Mentés közben tovább gépelt: a maradék is menjen ki.
      if (!blocked && dirty() && !status.classList.contains("error")) timer = setTimeout(store, 2500);
    }
  }

  area.addEventListener("input", () => {
    refresh();
    if (blocked) return;
    show("Módosítva");
    clearTimeout(timer);
    timer = setTimeout(store, 2500);
  });
  save.addEventListener("click", store);
  document.addEventListener("keydown", event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") { event.preventDefault(); store(); }
  });
  // Tabulátor: behúzás a mezőben (nem fókuszváltás).
  area.addEventListener("keydown", event => {
    if (event.key !== "Tab" || event.ctrlKey || event.metaKey || event.altKey) return;
    event.preventDefault();
    area.setRangeText("\t", area.selectionStart, area.selectionEnd, "end");
    area.dispatchEvent(new Event("input"));
  });
  addEventListener("beforeunload", event => { if (dirty()) { event.preventDefault(); event.returnValue = ""; } });
  load().catch(error => show(error.message, true));
}
