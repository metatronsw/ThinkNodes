import {classify, mediaType, rootType} from "./node-types.js";

// Médiafájlok MIME-típusa kiterjesztés szerint (Model.swift canvasMediaTypes).
const extensions = {png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp", gif: "image/gif",
  svg: "image/svg+xml", mp3: "audio/mpeg", wav: "audio/wav", ogg: "audio/ogg", flac: "audio/flac", m4a: "audio/mp4", aac: "audio/aac"};
export function attachmentURL(path, name) {
  return "/api/attachment/" + path + "?name=" + encodeURIComponent(name);
}

export function assetURL(path, asset) {
  return "/api/attachment/" + path + "?inline=1&name=" + encodeURIComponent(asset);
}

export function validImageStem(stem) {
  return Boolean(stem) && !stem.startsWith(".") && !/[\/\\:\u0000-\u001f\u007f-\u009f]/u.test(stem)
    && new TextEncoder().encode(stem).length <= 200;
}

export function imageStem(file) {
  return file.filename ?? file.asset.replace(/\.[^.]+$/, "");
}

// Fájlnév tő és kiterjesztés; képnél a tárolt tő + fileExtension.
export function fileNameParts(file, image = false) {
  if (image) return {stem: imageStem(file), extension: file.fileExtension ?? file.asset.split(".").at(-1)};
  const name = file.filename ?? file.asset;
  const dot = name.lastIndexOf(".");
  return dot > 0 ? {stem: name.slice(0, dot), extension: name.slice(dot + 1)} : {stem: name, extension: ""};
}

export function fileName(file, image = false) {
  const {stem, extension} = fileNameParts(file, image);
  return extension ? stem + "." + extension : stem;
}

// Az objektum rövid neve (Model.swift Idea.name): fájlnév, illetve a szöveg első sora formázójelek nélkül.
export function nodeName(node) {
  if (node?.file) return fileName(node.file, rootType(node.type) === "image");
  return plainFirstLine(node?.text ?? "");
}

export function plainFirstLine(text) {
  const line = text.split(/\r?\n/).find(row => row.trim()) ?? "";
  return line.trim().replace(/^[#>*+\- ]+/, "").replace(/^\d+[.)]\s+/, "")
    .replace(/[*_`~]|\[([^\]]*)\]\([^)]*\)/g, "$1").trim().slice(0, 120);
}

export function objectURL(path, id) {
  return new URL("/" + path + "#object-" + id, location.origin).href;
}

export async function writeText(text) {
  if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text);
  const field = document.createElement("textarea");
  field.value = text;
  document.body.append(field);
  field.select();
  try {
    if (!document.execCommand("copy")) throw Error("A böngésző nem engedélyezte a másolást.");
  } finally { field.remove(); }
}

export function checkText(text) {
  if (new TextEncoder().encode(text).length > 100000) throw Error("A szöveg legfeljebb 100 000 bájt lehet.");
  return text;
}

// Keep number literals and string escapes intact while adding indentation.
function formatJSON(source) {
  try { JSON.parse(source); } catch { throw Error("Érvénytelen JSON-dokumentum."); }
  const tokens = source.match(/"(?:\\.|[^"\\])*"|[{}\[\],:]|[^\s{}\[\],:"]+/g) ?? [];
  const output = [];
  let depth = 0;
  const newline = () => "\n" + "  ".repeat(Math.min(depth, 16));
  tokens.forEach((token, index) => {
    const open = token === "{" || token === "[";
    const close = token === "}" || token === "]";
    if (close) {
      depth--;
      if (!["{","["].includes(tokens[index-1])) output.push(newline());
    }
    output.push(token);
    if (open) {
      depth++;
      if (!["}","]"].includes(tokens[index+1])) output.push(newline());
    } else if (token === ",") output.push(newline());
    else if (token === ":") output.push(" ");
  });
  return output.join("");
}

async function storeAttachment(blob, path, csrf, name) {
  if (blob.size > 12*1024*1024) throw Error("A fájl legfeljebb 12 MiB lehet.");
  const response = await fetch(attachmentURL(path, name), {
    method: "POST", headers: {"Content-Type": "application/octet-stream", "X-CSRF-Token": csrf}, body: blob,
  });
  if (!response.ok) {
    const detail = await response.json().catch(() => ({}));
    throw Error(detail.reason || "A fájl feltöltése sikertelen (" + response.status + ").");
  }
  return response.headers.get("X-ThinkNodes-Asset") ?? name;
}

// Importált fájlból objektum (docs/node-types.md): kép és hang médiaként, minden más tartalom szerint szöveg vagy dokumentum.
export async function importFile(blob, path, csrf) {
  const name = blob.name || (blob.type.startsWith("image/") ? "Beillesztett kép.png" : "Dokumentum");
  const ext = name.includes(".") ? name.split(".").pop().toLowerCase() : "";
  if (ext === "thnode") {
    if (blob.size > 12*1024*1024) throw Error("A fájl legfeljebb 12 MiB lehet.");
    const response = await fetch("/api/worksheet-file/" + path + "?name=" + encodeURIComponent(name), {
      method: "POST", headers: {"Content-Type": "application/octet-stream", "X-CSRF-Token": csrf}, body: blob,
    });
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      throw Error(detail.reason || "A munkalap feltöltése sikertelen.");
    }
    return null;
  }
  if (blob.size > 12*1024*1024) throw Error("A fájl legfeljebb 12 MiB lehet.");
  const pastedImage = !ext && blob.type.startsWith("image/");
  const media = pastedImage ? "image" : mediaType(ext);
  if (media) {
    const mime = pastedImage ? blob.type : extensions[ext];
    const image = media === "image";
    let dimensions = {width: 320, height: 130};
    let filename;
    if (image) {
      const previewBlob = mime === "image/svg+xml" && blob.type !== mime ? blob.slice(0, blob.size, mime) : blob;
      const url = URL.createObjectURL(previewBlob);
      try {
        const preview = new Image();
        preview.src = url;
        await preview.decode();
        const width = preview.naturalWidth || 300, height = preview.naturalHeight || 150;
        const scale = 320 / Math.max(width, height);
        dimensions = {width: Math.max(64, Math.round(width * scale)),
          height: Math.max(40, Math.round(height * scale))};
      } catch { throw Error("A böngésző nem tudja megjeleníteni ezt a képet."); }
      finally { URL.revokeObjectURL(url); }
      filename = name.replace(/\.[^.]+$/, "").trim();
      if (!validImageStem(filename)) throw Error("Érvénytelen képfájlnév.");
    }
    const original = name.includes(".") ? name.split(".").pop() : "";
    const extension = extensions[original.toLowerCase()] === mime ? original : Object.keys(extensions).find(key => extensions[key] === mime);
    const mediaName = image ? filename + "." + extension : name;
    const upload = "/api/media/" + path + "?filename=" + encodeURIComponent(mediaName);
    const response = await fetch(upload, {method: "POST", headers: {"Content-Type": mime, "X-CSRF-Token": csrf}, body: blob});
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      throw Error(detail.reason || "A fájl feltöltése sikertelen (" + response.status + ").");
    }
    const {asset} = await response.json();
    const file = image ? {asset, filename, fileExtension: extension, showFilename: false} : {asset, filename: mediaName, showFilename: true};
    return {type: media, file, ...dimensions};
  }
  let bytes = new Uint8Array(await blob.arrayBuffer());
  const type = classify(name, bytes);
  if (rootType(type) !== "text") {
    const asset = await storeAttachment(blob, path, csrf, name);
    return {type, file: {asset, filename: name, showFilename: true}, width: 260, height: 120};
  }
  let upload = blob;
  if (ext === "json") {
    const formatted = formatJSON(new TextDecoder().decode(bytes));
    upload = new Blob([formatted], {type: "application/json"});
  }
  const asset = await storeAttachment(upload, path, csrf, name);
  return {type, file: {asset, filename: name, showFilename: true}, fontSize: 13, width: 340, height: 240};
}

export async function pngForClipboard(url) {
  const image = new Image();
  image.src = url;
  await image.decode();
  if (image.naturalWidth * image.naturalHeight > 32_000_000) throw Error("A kép túl nagy a PNG-átalakításhoz.");
  const canvas = document.createElement("canvas");
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  canvas.getContext("2d").drawImage(image, 0, 0);
  return new Promise((resolve, reject) => canvas.toBlob(blob => blob ? resolve(blob) : reject(Error("A kép másolása sikertelen.")), "image/png"));
}
