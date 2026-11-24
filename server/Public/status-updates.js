import {fetchPage, watchPageUpdates} from "./page-updates.js";

const status = document.querySelector("main[data-page-status]");
watchPageUpdates(async (signal, incoming) => {
  const target = status.dataset.watchNext;
  if (target) {
    const response = await fetch(target, {cache: "no-store", signal});
    if (!signal.aborted && response.ok && !response.redirected) {
      const page = new DOMParser().parseFromString(await response.text(), "text/html");
      if (!signal.aborted && page.querySelector("#worksheet-view, #editor")) location.assign(target);
    }
    return;
  }
  const {response, page} = incoming ?? await fetchPage(signal);
  if (signal.aborted) return;
  if (response.status >= 500) throw Error("Az oldal nem érhető el.");
  if (response.redirected || page.querySelector("main[data-page-status]")?.dataset.pageStatus !== status.dataset.pageStatus) {
    location.reload();
  }
});
