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

async function post(url, csrf, body, method = "POST") {
  const response = await fetch(url, {method, headers: {"Content-Type": "application/json", "X-CSRF-Token": csrf}, body: JSON.stringify(body)});
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw Error(error.reason ?? "A weboldal művelete sikertelen.");
  }
  return response;
}

// Publikus jog ki/be: publikus .web oldalt bárki megnézhet, bejelentkezés nélkül is.
export function setWebPublic(path, csrf, reference, publicWeb) {
  return post("/api/web-presentations/" + path, csrf, {reference, publicWeb}, "PATCH");
}

// A .web mappa a projekt lomtárába kerül.
export function trashWeb(path, csrf, reference) {
  return post("/api/web-trash/" + path, csrf, {reference});
}
