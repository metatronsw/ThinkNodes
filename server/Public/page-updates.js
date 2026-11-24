export async function fetchPage(signal) {
  const response = await fetch(location.href, {cache: "no-store", signal});
  return {
    response,
    page: new DOMParser().parseFromString(await response.text(), "text/html"),
  };
}

let pageUpdated = false;
export function updateSection(current, incoming, selector) {
  const existing = current.querySelector(selector);
  const replacement = incoming.querySelector(selector);
  if (!existing || !replacement || existing.isEqualNode(replacement)) return;
  existing.replaceWith(replacement);
  if (pageUpdated) return;
  pageUpdated = true;
  queueMicrotask(() => {
    pageUpdated = false;
    window.dispatchEvent(new Event("thinknodes-page-updated"));
  });
}

export function watchPageUpdates(onChange) {
  const meta = document.querySelector('meta[name="thinknodes-updates"]');
  if (!meta?.dataset?.id) return;
  let {id} = meta.dataset;
  let since = meta.content;
  let controller;

  async function start() {
    controller?.abort();
    controller = new AbortController();
    const {signal} = controller;
    while (!signal.aborted) {
      try {
        const response = await fetch("/api/page-changes/" + id + "?since=" + since, {cache: "no-store", signal});
        if (response.status === 410) {
          const current = await fetchPage(signal);
          const replacement = current.page.querySelector('meta[name="thinknodes-updates"]');
          if (!replacement) {
            await onChange(signal, current);
            return;
          }
          await onChange(signal, current);
          if (signal.aborted) return;
          id = replacement.dataset.id;
          since = replacement.content;
        } else {
          if (!response.ok) throw Error("A frissítések nem érhetők el.");
          const version = await response.text();
          if (!signal.aborted && version !== since) {
            await onChange(signal);
            if (signal.aborted) return;
            since = version;
          }
        }
      } catch (error) {
        if (!signal.aborted) await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
  }

  window.addEventListener("pagehide", () => controller?.abort());
  window.addEventListener("pageshow", event => { if (event.persisted) start(); });
  start();
}
