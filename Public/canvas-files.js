const media = {"image/png": "image", "image/jpeg": "image", "image/webp": "image", "image/gif": "image",
  "image/svg+xml": "image", "audio/mpeg": "mp3"};
const extensions = {png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp", gif: "image/gif",
  svg: "image/svg+xml", mp3: "audio/mpeg"};
const textExtensions = ["txt", "md", "json"];
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
}

export async function importFile(blob, path, csrf) {
  const name = blob.name || (blob.type.startsWith("image/") ? "Beillesztett kép" : "Dokumentum");
  const title = Array.from(name.replace(/[\u0000-\u001f\u007f]/g, " ").trim()).slice(0,120).join("") || "Dokumentum";
  const ext = name.split(".").pop().toLowerCase();
  let mime = media[blob.type] ? blob.type : extensions[ext];
  if (!mime && (blob.type.startsWith("image/") || ["avif","bmp","ico","tiff","heic"].includes(ext))) {
    if (blob.size > 12*1024*1024) throw Error("A kép legfeljebb 12 MiB lehet.");
    const source = URL.createObjectURL(blob);
    try { blob = await pngForClipboard(source); mime = "image/png"; }
    catch { throw Error("A böngésző nem tudja megjeleníteni ezt a képet."); }
    finally { URL.revokeObjectURL(source); }
  }
  if (mime) {
    if (blob.size > 12*1024*1024) throw Error("A médiafájl legfeljebb 12 MiB lehet.");
    const image = media[mime] === "image";
    let dimensions = {width: 320, height: 106};
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
    const originalExtension = /\.([^.]+)$/.exec(name)?.[1];
    const mediaName = image
      ? filename + "." + (extensions[originalExtension?.toLowerCase()] === mime ? originalExtension :
          Object.keys(extensions).find(extension => extensions[extension] === mime))
      : originalExtension?.toLowerCase() === "mp3" ? name : name + ".mp3";
    const upload = "/api/media/" + path + "?filename=" + encodeURIComponent(mediaName);
    const response = await fetch(upload, {method: "POST", headers: {"Content-Type": mime, "X-CSRF-Token": csrf}, body: blob});
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      throw Error(detail.reason || "A fájl feltöltése sikertelen (" + response.status + ").");
    }
    const {asset} = await response.json();
    const file = {type: media[mime], asset};
    if (image) file.filename = filename;
    return {title: image ? "" : title, file, ...dimensions};
  }
  if (ext === "thnode") throw Error("A .thnode kiterjesztés a munkalapoké.");
  if (!textExtensions.includes(ext) || blob.size > 100000) {
    await storeAttachment(blob, path, csrf, name);
    return {title, file: {type: "attachment", asset: name}, width: 260, height: 100};
  }
  let text = await blob.text();
  if (ext === "json") {
    text = formatJSON(text);
  }
  checkText(text);
  await storeAttachment(blob, path, csrf, name);
  return {title, text, file: {type: ext}, width: 340, height: 220};
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
