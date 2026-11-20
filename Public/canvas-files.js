const media = {"image/png": "image", "image/jpeg": "image", "image/webp": "image", "image/gif": "image", "audio/mpeg": "mp3"};
const extensions = {png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp", gif: "image/gif", mp3: "audio/mpeg"};

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

export async function importFile(blob, path, csrf) {
  const name = blob.name || (blob.type.startsWith("image/") ? "Beillesztett kép" : "Dokumentum");
  const title = Array.from(name.replace(/[\u0000-\u001f\u007f]/g, " ").trim()).slice(0,120).join("") || "Dokumentum";
  const ext = name.split(".").pop().toLowerCase();
  let mime = media[blob.type] ? blob.type : extensions[ext];
  if (!mime && (blob.type.startsWith("image/") || ["avif","bmp","svg","ico","tiff","heic"].includes(ext))) {
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
      const url = URL.createObjectURL(blob);
      try {
        const preview = new Image();
        preview.src = url;
        await preview.decode();
        const scale = Math.min(320 / preview.naturalWidth, 320 / preview.naturalHeight);
        dimensions = {width: Math.max(64, Math.round(preview.naturalWidth * scale)),
          height: Math.max(40, Math.round(preview.naturalHeight * scale))};
      } catch { throw Error("A böngésző nem tudja megjeleníteni ezt a képet."); }
      finally { URL.revokeObjectURL(url); }
      filename = name.replace(/\.[^.]+$/, "").trim();
      if (!validImageStem(filename)) throw Error("Érvénytelen képfájlnév.");
    }
    const upload = "/api/media/" + path + (image ? "?name=" + encodeURIComponent(filename) : "");
    const response = await fetch(upload, {method: "POST", headers: {"Content-Type": mime, "X-CSRF-Token": csrf}, body: blob});
    if (!response.ok) throw Error("A fájl feltöltése sikertelen (" + response.status + ").");
    const {asset} = await response.json();
    const file = {type: media[mime], asset};
    if (image) file.filename = filename;
    return {title: image ? "" : title, file, ...dimensions};
  }
  if (!["txt","md","json"].includes(ext)) throw Error("Támogatott fájlok: PNG, JPEG, GIF, WebP, TXT, MD, JSON és MP3.");
  if (blob.size > 100000) throw Error("A dokumentum legfeljebb 100 000 bájt lehet.");
  let text = await blob.text();
  if (ext === "json") {
    text = formatJSON(text);
  }
  return {title, text: checkText(text), file: {type: ext}, width: 340, height: 220};
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
