export const linkIcons = {
  website: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20ZM2 12h20M12 2c-5 5-5 15 0 20 5-5 5-15 0-20Z",
  worksheet: "m10 13 4-4m-5 6-2 2a3.5 3.5 0 0 1-5-5l5-5a3.5 3.5 0 0 1 5 0m0 10a3.5 3.5 0 0 0 5 0l5-5a3.5 3.5 0 0 0-5-5l-2 2",
};

export function worksheetLink(raw, currentPath) {
  const value = raw?.trim();
  if (!value || value.length > 2048 || /[\\\u0000-\u001f\u007f]/u.test(value)) return null;
  try {
    if (/^https?:\/\//i.test(value)) {
      const url = new URL(value);
      if (!url.hostname || url.username || url.password) return null;
      const internal = url.host === globalThis.location?.host && worksheetLink(url.pathname, currentPath);
      return {kind: internal ? "worksheet" : "website", href: url.href};
    }
    if (value.includes("//")) return null;
    const relative = !value.startsWith("/") || value === "/.." || value.startsWith("/../");
    const parts = relative ? currentPath.split("/").filter(Boolean).map(decodeURIComponent) : [];
    for (const segment of value.split("/")) {
      if (!segment || segment === ".") continue;
      if (segment === "..") parts.pop();
      else {
        const decoded = decodeURIComponent(segment).normalize("NFC");
        if (!/^[\p{L}\p{M}\p{Nd}_-]+$/u.test(decoded) || new TextEncoder().encode(decoded).length > 180) return null;
        parts.push(decoded);
      }
    }
    if (parts.length > 12 || /^(admin|api|edit|export|login|logout|health|open|vendor)$/i.test(parts[0])) return null;
    return {kind: "worksheet", href: "/" + parts.map(encodeURIComponent).join("/")};
  } catch { return null; }
}

export function openExternalLink(href) {
  window.open(href, "_blank", "popup,noopener,noreferrer");
}
