// Vászonobjektum-típusok regisztere (Public/node-types.json, docs/node-types.md). A szerver NodeTypes.swift ugyanezt olvassa.
const registry = globalThis.ThinkNodesNodeTypes
  ?? await fetch("/node-types.json").then(response => response.json());
export const nodeTypes = registry.types;

export function rootType(type) {
  const seen = new Set();
  while (nodeTypes[type]?.base && !seen.has(type)) { seen.add(type); type = nodeTypes[type].base; }
  return type;
}

const traitCache = new Map();
export function traits(type) {
  if (traitCache.has(type)) return traitCache.get(type);
  const definition = nodeTypes[type];
  if (!definition) return new Set();
  const result = new Set(definition.traits ?? (definition.base ? traits(definition.base) : []));
  for (const trait of definition.addTraits ?? []) result.add(trait);
  traitCache.set(type, result);
  return result;
}

export const hasTrait = (node, trait) => traits(node?.type).has(trait);
export const isType = (node, type) => rootType(node?.type) === type;

export function fileKind(type) {
  const seen = new Set();
  while (type && !seen.has(type)) {
    seen.add(type);
    if (nodeTypes[type]?.file) return nodeTypes[type].file;
    type = nodeTypes[type]?.base;
  }
  return null;
}

export const typeLabel = type => nodeTypes[type]?.label ?? type;

export function mediaType(extension) {
  const ext = extension.toLowerCase();
  return ["image", "audio"].find(type => nodeTypes[type]?.extensions?.includes(ext)) ?? null;
}

// Importált fájl típusa: médiánál kiterjesztés, egyébként tartalom (UTF-8, NUL bájt nélkül → szöveg).
export function classify(filename, bytes) {
  const ext = filename.includes(".") ? filename.split(".").pop().toLowerCase() : "";
  const media = mediaType(ext);
  if (media) return media;
  if (nodeTypes.document?.extensions?.includes(ext) || !isPlainText(bytes)) return "document";
  return Object.keys(nodeTypes).sort().find(id => id !== "text" && rootType(id) === "text"
    && nodeTypes[id].extensions?.includes(ext)) ?? "text";
}

// Szöveg: érvényes UTF-8, és a tabulátoron, soremelésen, lapdobáson kívül nincs benne vezérlőkarakter (NodeTypes.swift).
export function isPlainText(bytes) {
  if (bytes.some(byte => (byte < 0x20 && ![9, 10, 12, 13].includes(byte)) || byte === 0x7f)) return false;
  try { new TextDecoder("utf-8", {fatal: true}).decode(bytes); return true; } catch { return false; }
}
