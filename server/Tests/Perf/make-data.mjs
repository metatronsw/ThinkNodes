// Mérő-adatkönyvtár a szerkesztő teljesítményméréséhez (docs/PLAN.md: sosem a valódi `projects`).
// Használat: node Tests/Perf/make-data.mjs [CÉLMAPPA]   (alapból: .build/perf-data)
// Projektek: p300 és p1000 (dobozok + vonalak + fájldobozok), tabla (egy nagy és egy közepes táblázat).
import {mkdirSync, writeFileSync} from "node:fs";
import {join, dirname} from "node:path";
import {deflateSync, crc32} from "node:zlib";
import {fileURLToPath} from "node:url";

const root = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), "../../.build/perf-data");
let seed = 12345;
const random = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32;
const id = (prefix, i) => prefix + String(i).padStart(5, "0");
const words = "terv mérés doboz vonal hálózat szerver adat forrás cél jegyzet ötlet vázlat modul réteg kapcsolat állapot".split(" ");
const sentence = n => Array.from({length: n}, () => words[Math.floor(random() * words.length)]).join(" ");

function tableDocument(rows, cols) {
  const cells = {};
  const name = c => { let s = ""; for (let n = c + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; };
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    const key = name(c) + (r + 1);
    if (r === 0) cells[key] = {v: "Oszlop " + name(c)};
    else if (c === 0) cells[key] = {v: sentence(3)};
    else if (c === cols - 1) cells[key] = {f: "SUM(" + name(1) + (r + 1) + ":" + name(cols - 2) + (r + 1) + ")", v: 0};
    else if (c % 4 === 3) cells[key] = {v: sentence(6)};
    else cells[key] = {v: Math.round(random() * 100000) / 100};
  }
  return {format: "thinknodes-table", version: 1, id: "tbl-perf" + rows, size: {rows, cols}, grid: true, styles: [{}], cells};
}

// Egyszerű színátmenetes PNG (zajjal, hogy ne legyen triviálisan tömöríthető/gyorsan dekódolható).
function png(width, height, hue) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const at = y * (width * 4 + 1) + 1 + x * 4, noise = random() * 40;
    raw[at] = (x / width * 255 + hue * 40 + noise) & 255; raw[at + 1] = (y / height * 255 + noise) & 255; raw[at + 2] = (hue * 70 + noise) & 255; raw[at + 3] = 255;
  }
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type), data]), out = Buffer.alloc(body.length + 8);
    out.writeUInt32BE(data.length, 0); body.copy(out, 4); out.writeUInt32BE(crc32(body) >>> 0, body.length + 4);
    return out;
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

function csv(rows, cols) {
  return Array.from({length: rows}, (_, r) => Array.from({length: cols}, (_, c) => r === 0 ? "Fejléc " + (c + 1) : c % 3 ? Math.round(random() * 1000) : sentence(2)).join(",")).join("\n");
}

function project(name, boxes, {files = 0, tables = [], images = 0, containers = 0, junctions = 0} = {}) {
  const folder = join(root, name);
  mkdirSync(folder, {recursive: true});
  const nodes = [], edges = [], media = {};
  const columns = Math.ceil(Math.sqrt(boxes * 1.6));
  const shapes = ["rounded", "rectangle", "ellipse", "rounded", "rounded", "diamond"];
  for (let i = 0; i < boxes; i++) {
    const column = i % columns, row = Math.floor(i / columns);
    const text = i % 7 === 0 ? "# " + sentence(2) + "\n\n" + sentence(8) : i % 3 === 0 ? sentence(6) : sentence(2);
    nodes.push({id: id("n", i), type: "box", text, shape: shapes[i % shapes.length], fill: 2 + i % 6, textCol: 1, fontSz: 16, align: "center",
      pos: {x: column * 260 + (random() - .5) * 60, y: row * 170 + (random() - .5) * 50}, w: 150 + Math.round(random() * 80), h: 70 + Math.round(random() * 50),
      ...(i % 11 === 0 ? {elevated: true} : {}), ...(i % 13 === 0 ? {backgroundMode: "translucent"} : {}), ...(i % 29 === 0 ? {backgroundMode: "blurred"} : {})});
  }
  const types = ["straight", "sCurve", "arc"];
  for (let i = 0; i < boxes; i++) {
    const right = i + 1, below = i + columns;
    if ((i + 1) % columns && right < boxes && i % 3 !== 2)
      edges.push({id: id("e", edges.length), source: id("n", i), target: {node: id("n", right)}, type: types[i % 3], ...(i % 5 === 0 ? {label: sentence(1)} : {}), ...(i % 17 === 0 ? {animated: true} : {})});
    if (below < boxes && i % 2 === 0)
      edges.push({id: id("e", edges.length), source: id("n", i), target: {node: id("n", below)}, type: types[(i + 1) % 3], ...(i % 9 === 0 ? {appearance: "dashed"} : {}),
        ...(i % 4 === 0 ? {startArrow: true} : {}), ...(i % 10 === 0 ? {endArrow: false} : {})});
  }
  // Csomópontok: a rács négy doboza közé, mindegyikhez nyíllal kötve.
  for (let j = 0; j < junctions; j++) {
    const base = Math.floor(random() * (boxes - columns - 2)), corner = nodes[base];
    if ((base + 1) % columns === 0) continue;
    const junction = id("j", j);
    nodes.push({id: junction, type: "junction", text: j % 3 ? "" : "J" + j, fill: 5, textCol: 1, pos: {x: corner.pos.x + 130, y: corner.pos.y + 85}, w: 14, h: 14});
    for (const member of [base, base + 1, base + columns, base + columns + 1])
      edges.push({id: id("e", edges.length), source: id("n", member), target: {node: junction}, type: "straight", endArrow: member % 2 === 0});
  }
  // Konténerek a rács alatt: mindegyikben négy gyerekdoboz, köztük vonalakkal.
  const rowsUsed = Math.ceil(boxes / columns);
  for (let k = 0; k < containers; k++) {
    const x = (k % 8) * 520, y = (rowsUsed + 1) * 170 + Math.floor(k / 8) * 400, container = id("c", k);
    nodes.push({id: container, type: "box", container: true, text: "Konténer " + k, shape: "rounded", fill: 3, textCol: 1, fontSz: 16, align: "center", vAlign: "top",
      pos: {x, y}, w: 460, h: 340, ...(k % 3 === 0 ? {locked: true} : {})});
    for (let m = 0; m < 4; m++) {
      nodes.push({id: container + "m" + m, type: "box", parent: container, text: sentence(2), shape: "rounded", fill: 4 + m, textCol: 1, fontSz: 14, align: "center",
        pos: {x: x - 105 + (m % 2) * 210, y: y - 50 + Math.floor(m / 2) * 120}, w: 170, h: 80});
      if (m) edges.push({id: id("e", edges.length), source: container + "m" + (m - 1), target: {node: container + "m" + m}, type: "sCurve"});
    }
  }
  const addFile = (type, filename, content, x, y, w, h) => {
    const asset = "file-" + id("a", Object.keys(media).length);
    media[asset] = filename;
    writeFileSync(join(folder, filename), content);
    nodes.push({id: id("f", nodes.length), type, text: "", fill: 2, textCol: 1, fontSz: 13, align: "center", shape: "rounded",
      file: {asset, filename, showFilename: true}, pos: {x, y}, w, h});
  };
  for (let i = 0; i < files; i++) {
    const x = -500 - (i % 3) * 380, y = Math.floor(i / 3) * 300;
    if (i % 2) addFile("csv", `adat-${i}.csv`, csv(60, 8), x, y, 340, 240);
    else addFile("text", `jegyzet-${i}.md`, Array.from({length: 40}, () => sentence(12)).join("\n\n"), x, y, 340, 240);
  }
  for (let i = 0; i < images; i++) {
    // A képek a mappában UUID-nevű fájlként állnak (canvasAssetType), a megjelenő név külön mező.
    const asset = "00000000-0000-4000-8000-" + String(i).padStart(12, "0") + ".png", filename = "kep-" + i;
    writeFileSync(join(folder, asset), png(640, 420, i));
    nodes.push({id: id("f", nodes.length), type: "image", text: i % 2 ? "Kép " + i : "", fill: 2, textCol: 1, fontSz: 13, align: "center", shape: "rounded",
      file: {asset, filename, showFilename: true}, pos: {x: -520 - (i % 4) * 360, y: 1000 + Math.floor(i / 4) * 280}, w: 320, h: 210, ...(i % 3 === 0 ? {frame: true} : {})});
  }
  tables.forEach(([rows, cols, w, h], i) =>
    addFile("table", `tabla-${i}-${rows}x${cols}.tntable`, JSON.stringify(tableDocument(rows, cols)), -500 - i * 900, -700, w, h));
  writeFileSync(join(folder, name + ".thnode"), JSON.stringify({schemaVersion: 3, revision: 1, title: name, creator: "Tester1",
    appearance: {theme: 1, palette: 1}, nodes, edges}, null, 1));
  writeFileSync(join(folder, ".settings.json"), JSON.stringify({guestReadable: false, owner: "Tester1", mediaFiles: media}, null, 1));
  console.log(name, "dobozok:", nodes.length, "vonalak:", edges.length);
}

mkdirSync(root, {recursive: true});
writeFileSync(join(root, ".settings.json"), JSON.stringify({requireLogin: false, users: []}, null, 1));
project("p300", 300, {files: 6, tables: [[200, 12, 760, 520], [60, 8, 520, 360]], images: 8, containers: 8, junctions: 20});
project("p1000", 1000, {files: 6, tables: [[200, 12, 760, 520], [60, 8, 520, 360]], images: 16, containers: 24, junctions: 60});
project("tabla", 12, {tables: [[1000, 30, 900, 600], [300, 12, 760, 520], [300, 12, 760, 520], [60, 8, 520, 360]]});
console.log("Kész:", root);
