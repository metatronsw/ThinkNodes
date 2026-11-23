// .web előnézet frissítése: a szerver azonnal a meglévő képet adja, és a háttérben renderel
// (WebPresentation.swift WebScreenshot.schedule). Ez a modul az állapotot figyeli (`&state=1`),
// és ha elkészült az új kép, visszaadja a változatát; a hívó ezzel tölti újra a képet (`&v=`).
const started = new Map();

// `source`: az előnézet címe a mérettel (pl. /p/web/nev/_tn-preview?w=320&h=200). Ígéret: az új változat vagy null.
export function awaitWebPreview(source) {
  if (started.has(source)) return started.get(source);
  const task = (async () => {
    let sawPending = false;
    for (let attempt = 0; attempt < 60; attempt++) {
      await new Promise(resolve => setTimeout(resolve, attempt === 0 ? 800 : 1500));
      try {
        const state = await (await fetch(source + "&state=1", {cache: "no-store"})).json();
        if (state.pending) { sawPending = true; continue; }
        // Elkészült (vagy már friss volt): a változat a kép újratöltéséhez.
        if (sawPending || attempt >= 1) return state.version;
      } catch { return null; }
    }
    return null;
  })();
  started.set(source, task);
  return task;
}

// Megtekintő: a vászon minden .web előnézetét figyeli, és elkészüléskor újratölti.
export function refreshWebPreviews(root) {
  for (const image of root.querySelectorAll('image.node-site-preview[href*="_tn-preview?w="]')) {
    const href = image.getAttribute("href");
    if (href.includes("&live=0") || href.includes("&v=")) continue;
    awaitWebPreview(href).then(version => { if (version && image.isConnected) image.setAttribute("href", href + "&v=" + version); });
  }
}
