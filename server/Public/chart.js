// Grafikon a táblázat- és CSV-dobozokhoz (docs/node-types.md, „Grafikon”). A doboz `chart` mezője a beállítás:
// {kind, labels, values, header}. Ugyanez a modul rajzol a szerkesztőben (editor.js) és a megtekintőben (viewer.js);
// csak akkor töltődik be, ha a lapon van grafikon. A rajz SVG-szöveg, megjelenítő attribútumokkal (style nélkül:
// a megtekintő tartalombiztonsági szabálya a style attribútumot nem engedi).
import {scaleLinear, scaleBand, scalePoint, line, arc, pie} from "./lib/d3-chart.js";
import {decodeTable, cellName} from "./table/table-document.js";
import {detectSeparator, parseCSVRows} from "./table/table-csv.js";

export const chartKinds = {bar: "Oszlop", line: "Vonal", pie: "Kör", scatter: "Pont"};
export const maximumSeries = 8;
// Pontdiagramon bármely két sorozat egymás mellé kerülhet, ott csak az első három szín különül el biztosan.
const scatterSeries = 3, pieSlices = 8;
const rowLimits = {bar: 200, pie: 200, line: 5000, scatter: 5000};

// Kategóriaszínek rögzített sorrendben (világos és sötét felületre külön lépcső); a sorozat színe a helyéhez kötött.
const palette = {
  light: ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"],
  dark: ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#0ca30c", "#9085e9", "#e66767"],
};

// A fájl tartalma sorokként: táblázatnál a tárolt (a szerver által számolt) értékek, CSV-nél a mezők szövege.
export function fileRows(type, text, filename = "") {
  if (text == null) return null;
  if (type === "table") {
    let doc;
    try { doc = decodeTable(text); } catch { return null; }
    return tableRows(doc);
  }
  const part = text.slice(0, 2_000_000);
  return parseCSVRows(part, detectSeparator(part, filename.split(".").pop() ?? "")).rows;
}

export function tableRows(doc) {
  const rows = [];
  for (let r = 0; r < doc.size.rows; r++) {
    const row = [];
    for (let c = 0; c < doc.size.cols; c++) {
      const value = doc.cells[cellName(r, c)]?.v;
      row.push(value == null || typeof value === "object" ? "" : value);
    }
    rows.push(row);
  }
  return rows;
}

// Szám a cellából: a táblázat számai változatlanul, a szöveg magyar és angol írásmóddal is (1 234,5 · 1,234.5 · 12%).
export function toNumber(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value !== "string") return null;
  let text = value.replace(/[\s  ]/g, "");
  if (!text) return null;
  const percent = text.endsWith("%");
  if (percent) text = text.slice(0, -1);
  if (!/^[-+]?[0-9.,]*[0-9][0-9.,]*$/.test(text)) return null;
  const dots = text.split(".").length - 1, commas = text.split(",").length - 1;
  if (dots && commas) {
    const decimal = text.lastIndexOf(".") > text.lastIndexOf(",") ? "." : ",";
    text = text.split(decimal === "." ? "," : ".").join("");
    if (text.split(decimal).length > 2) return null;
    text = text.replace(decimal, ".");
  } else if (commas === 1) text = text.replace(",", ".");
  else if (commas > 1) text = text.split(",").join("");
  else if (dots > 1) text = text.split(".").join("");
  const number = Number(text);
  return Number.isFinite(number) ? number : null;
}

const filled = value => value !== "" && value != null;

// A táblázat oszlopai a grafikon szemszögéből: név (fejléc vagy betűjel) és hogy számoszlop-e.
// Számoszlop: van benne szám, és a kitöltött cellák legalább fele szám.
export function chartColumns(rows, chart = {}) {
  const header = chart.header !== false && rows.length > 1;
  const body = (header ? rows.slice(1) : rows).filter(row => row.some(filled));
  const count = Math.max(0, ...rows.slice(0, 5000).map(row => row.length));
  const columns = [];
  for (let c = 0; c < count; c++) {
    let numbers = 0, used = 0;
    for (const row of body) {
      if (!filled(row[c])) continue;
      used++;
      if (toNumber(row[c]) != null) numbers++;
    }
    const title = header && filled(rows[0][c]) ? String(rows[0][c]).trim() : "";
    columns.push({index: c, name: title || letters(c), numeric: numbers > 0 && numbers * 2 >= used, used});
  }
  return {columns, body, header};
}

function letters(col) {
  let n = col + 1, result = "";
  while (n > 0) { result = String.fromCharCode(65 + (n - 1) % 26) + result; n = Math.floor((n - 1) / 26); }
  return result;
}

// A kirajzolandó adatok. `labels`: a kategóriák (vagy pontdiagramnál az x értékek) oszlopa; nincs megadva: az első
// szöveges oszlop (pontdiagramnál, vagy ha csak számoszlopok vannak, az első számoszlop), ennek híján a sorszám. `values`: az értékoszlopok; nincs megadva:
// minden további számoszlop.
export function chartData(rows, chart = {}) {
  const kind = chartKinds[chart.kind] ? chart.kind : "bar";
  const {columns, body} = chartColumns(rows ?? [], chart);
  const scatter = kind === "scatter";
  const valid = index => Number.isInteger(index) && index >= 0 && index < columns.length;
  let labelColumn = valid(chart.labels) ? chart.labels : null;
  if (chart.labels == null) {
    const numeric = columns.filter(column => column.numeric);
    // Csupa számoszlop (pl. év és érték): az első a tengely, különben önmaga is sorozatként jelenne meg.
    labelColumn = (scatter ? numeric[0] : columns.find(column => !column.numeric && column.used) ?? (numeric.length > 1 ? numeric[0] : null))?.index ?? null;
  }
  if (scatter && labelColumn != null && !columns[labelColumn].numeric) labelColumn = columns.find(column => column.numeric)?.index ?? null;
  const limit = kind === "pie" ? 1 : scatter ? scatterSeries : maximumSeries;
  const chosen = Array.isArray(chart.values) ? chart.values.filter(index => valid(index) && columns[index].numeric && index !== labelColumn) : [];
  const valueColumns = (chosen.length ? [...new Set(chosen)] : columns.filter(column => column.numeric && column.index !== labelColumn).map(column => column.index))
    .slice(0, limit);
  const used = body.slice(0, rowLimits[kind]);
  const labels = used.map((row, index) => labelColumn == null ? String(index + 1) : filled(row[labelColumn]) ? String(row[labelColumn]) : "");
  return {
    kind, columns, labelColumn, valueColumns, labels,
    labelName: labelColumn == null ? "" : columns[labelColumn].name,
    x: scatter && labelColumn != null ? used.map(row => toNumber(row[labelColumn])) : null,
    series: valueColumns.map(index => ({index, name: columns[index].name, values: used.map(row => toNumber(row[index]))})),
    truncated: body.length > used.length,
  };
}

const escapeXML = text => String(text).replace(/[&<>"']/g, ch => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"})[ch]);
const round = value => Math.round(value * 100) / 100;
const plain = new Intl.NumberFormat("hu-HU", {maximumFractionDigits: 2});
const compact = new Intl.NumberFormat("hu-HU", {notation: "compact", maximumFractionDigits: 1});
export const formatValue = value => plain.format(value);
const textWidth = (text, size = 11) => String(text).length * size * 0.56;
const fit = (text, width, size = 11) => {
  const room = Math.max(1, Math.floor(width / (size * 0.56)));
  const value = String(text);
  return value.length <= room ? value : room < 3 ? "" : value.slice(0, room - 1) + "…";
};

function message(width, height, text) {
  return `<svg xmlns="http://www.w3.org/2000/svg" class="tn-chart" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeXML(text)}">`
    + `<text x="${width / 2}" y="${height / 2}" text-anchor="middle" font-size="12" fill="currentColor" fill-opacity="0.7">${escapeXML(fit(text, width - 12, 12))}</text></svg>`;
}

// Jelmagyarázat két vagy több sorozatnál, a rajz fölött; a szöveg a doboz szövegszínét viseli, a színt a jel hordozza.
function legend(names, colors, width) {
  if (names.length < 2) return {height: 0, svg: ""};
  let x = 0, y = 0, svg = "";
  for (const [index, name] of names.entries()) {
    const label = fit(name, Math.min(160, width - 18)), size = 18 + textWidth(label) + 12;
    if (x > 0 && x + size > width) { x = 0; y += 16; }
    svg += `<rect x="${round(x)}" y="${y + 2}" width="10" height="10" rx="2" fill="${colors[index]}"/>`
      + `<text x="${round(x + 14)}" y="${y + 11}" font-size="11" fill="currentColor" fill-opacity="0.85">${escapeXML(label)}</text>`;
    x += size;
  }
  return {height: y + 22, svg};
}

// Felül lekerekített (negatív értéknél alul lekerekített) oszlop; az alapvonalnál szögletes.
function barPath(x, y0, y1, width) {
  const radius = Math.min(4, width / 2, Math.abs(y1 - y0)), up = y1 < y0 ? 1 : -1;
  return `M${round(x)},${round(y0)}V${round(y1 + up * radius)}Q${round(x)},${round(y1)} ${round(x + radius)},${round(y1)}`
    + `H${round(x + width - radius)}Q${round(x + width)},${round(y1)} ${round(x + width)},${round(y1 + up * radius)}V${round(y0)}Z`;
}

function axes(data, width, height, colors, options) {
  const {kind, series, labels} = data;
  const scatter = kind === "scatter";
  const key = legend(series.map(item => item.name), colors, width - 8);
  const values = series.flatMap(item => item.values).filter(value => value != null);
  let low = Math.min(...values), high = Math.max(...values);
  if (kind === "bar" || low >= 0 && low < high * 0.5) low = Math.min(0, low);
  if (kind === "bar") high = Math.max(0, high);
  if (low === high) { low -= 1; high += 1; }
  const top = 6 + key.height, bottom = height - 22;
  const y = scaleLinear().domain([low, high]).nice(Math.max(2, Math.floor((bottom - top) / 34))).range([bottom, top]);
  const ticks = y.ticks(Math.max(2, Math.floor((bottom - top) / 34)));
  const big = Math.max(Math.abs(y.domain()[0]), Math.abs(y.domain()[1])) >= 10000;
  const tickText = value => big ? compact.format(value) : plain.format(value);
  const left = Math.min(width * 0.3, Math.max(...ticks.map(tick => textWidth(tickText(tick)))) + 10), right = width - 8;
  if (right - left < 30 || bottom - top < 24) return message(width, height, "Kevés a hely a grafikonhoz.");
  let svg = `<g transform="translate(4 0)">${key.svg}</g>`;
  for (const tick of ticks) {
    svg += `<line x1="${round(left)}" x2="${round(right)}" y1="${round(y(tick))}" y2="${round(y(tick))}" stroke="currentColor" stroke-opacity="${tick === 0 ? 0.45 : 0.14}"/>`
      + `<text x="${round(left - 5)}" y="${round(y(tick) + 3.5)}" text-anchor="end" font-size="11" fill="currentColor" fill-opacity="0.7">${escapeXML(tickText(tick))}</text>`;
  }
  const tip = (name, label, value) => `<title>${escapeXML((series.length > 1 || !label ? name + (label ? " · " : "") : "") + label + ": " + plain.format(value))}</title>`;
  const axisLabel = (x, text, anchor = "middle") =>
    `<text x="${round(x)}" y="${bottom + 14}" text-anchor="${anchor}" font-size="11" fill="currentColor" fill-opacity="0.7">${escapeXML(text)}</text>`;

  if (scatter) {
    const xs = data.x.filter(value => value != null);
    if (!xs.length) return message(width, height, "A pontdiagram x tengelyéhez számoszlop kell.");
    let from = Math.min(...xs), to = Math.max(...xs);
    if (from === to) { from -= 1; to += 1; }
    const x = scaleLinear().domain([from, to]).nice(Math.max(2, Math.floor((right - left) / 70))).range([left + 6, right - 6]);
    const wide = Math.max(Math.abs(x.domain()[0]), Math.abs(x.domain()[1])) >= 1000000;
    for (const tick of x.ticks(Math.max(2, Math.floor((right - left) / 70)))) svg += axisLabel(x(tick), wide ? compact.format(tick) : plain.format(tick));
    for (const [s, item] of series.entries()) {
      for (const [i, value] of item.values.entries()) {
        if (value == null || data.x[i] == null) continue;
        svg += `<circle cx="${round(x(data.x[i]))}" cy="${round(y(value))}" r="4" fill="${colors[s]}" fill-opacity="0.8" stroke="${options.surface}" stroke-width="1">`
          + tip(item.name, (data.labelName ? data.labelName + " " : "x ") + plain.format(data.x[i]), value) + "</circle>";
      }
    }
    return svg;
  }

  // Kategóriatengely: annyi felirat, amennyi egymás mellett elfér (a többi kimarad, a buboréksúgó mindet mutatja).
  const count = labels.length;
  const longest = Math.min(90, Math.max(...labels.map(label => textWidth(label)), 8));
  const every = Math.max(1, Math.ceil(count * (longest + 8) / (right - left)));
  const labelRoom = (right - left) / Math.ceil(count / every) - 6;
  if (kind === "bar") {
    const band = scaleBand().domain(labels.map((_, index) => index)).range([left, right]).paddingInner(0.25).paddingOuter(0.12);
    const slot = band.bandwidth() / series.length, bar = Math.max(1, Math.min(24, slot - (slot > 4 ? 2 : 0)));
    const zero = y(Math.max(y.domain()[0], Math.min(0, y.domain()[1])));
    for (const [i, label] of labels.entries()) {
      for (const [s, item] of series.entries()) {
        const value = item.values[i];
        if (value == null || value === 0) continue;
        svg += `<path d="${barPath(band(i) + s * slot + (slot - bar) / 2, zero, y(value), bar)}" fill="${colors[s]}">${tip(item.name, label, value)}</path>`;
      }
      if (i % every === 0) svg += axisLabel(band(i) + band.bandwidth() / 2, fit(label, labelRoom));
    }
    return svg;
  }
  const x = scalePoint().domain(labels.map((_, index) => index)).range([left, right]).padding(count > 1 ? 0.5 : 0.5);
  const path = line().defined(point => point[1] != null).x(point => x(point[0])).y(point => y(point[1]));
  const dots = count <= 60;
  for (const [s, item] of series.entries()) {
    svg += `<path d="${path(item.values.map((value, index) => [index, value])) ?? ""}" fill="none" stroke="${colors[s]}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`;
    for (const [i, value] of item.values.entries()) {
      if (value == null) continue;
      // Sok pontnál látható jel nincs, de a buboréksúgóhoz átlátszó célpont marad.
      svg += `<circle cx="${round(x(i))}" cy="${round(y(value))}" r="${dots ? 3.5 : 3}" fill="${colors[s]}"${dots ? ` stroke="${options.surface}" stroke-width="1.5"` : ` fill-opacity="0"`}>${tip(item.name, labels[i], value)}</circle>`;
    }
  }
  for (const [i, label] of labels.entries()) if (i % every === 0) svg += axisLabel(x(i), fit(label, labelRoom));
  return svg;
}

function pieChart(data, width, height, colors, options) {
  const item = data.series[0];
  let slices = data.labels.map((label, index) => ({label: label || String(index + 1), value: item.values[index]})).filter(slice => slice.value > 0);
  if (!slices.length) return message(width, height, "A kördiagramhoz pozitív számok kellenek.");
  // A kilencedik szelet nem kap új színt: a legkisebbek „Egyéb” néven összevonódnak.
  if (slices.length > pieSlices) {
    const sorted = [...slices].sort((a, b) => b.value - a.value), kept = new Set(sorted.slice(0, pieSlices - 1));
    const rest = slices.filter(slice => !kept.has(slice)).reduce((sum, slice) => sum + slice.value, 0);
    slices = [...slices.filter(slice => kept.has(slice)), {label: "Egyéb", value: rest}];
  }
  const total = slices.reduce((sum, slice) => sum + slice.value, 0);
  const share = value => new Intl.NumberFormat("hu-HU", {maximumFractionDigits: 1}).format(value / total * 100) + "%";
  // Jelmagyarázat a kör mellett (széles doboz) vagy alatta (keskeny doboz); benne a szelet neve és aránya.
  const beside = width >= height * 1.25 && width >= 260;
  const rowHeight = 16, rows = slices.length;
  const keyWidth = beside ? Math.min(width * 0.5, Math.max(...slices.map(slice => textWidth(slice.label + "  " + share(slice.value)))) + 26) : width - 12;
  const keyHeight = beside ? 0 : Math.min(rows * rowHeight + 4, height * 0.45);
  const shown = beside ? rows : Math.max(0, Math.floor((keyHeight - 4) / rowHeight));
  const plotWidth = beside ? width - keyWidth - 8 : width, plotHeight = height - keyHeight;
  const radius = Math.min(plotWidth, plotHeight) / 2 - 6;
  if (radius < 12) return message(width, height, "Kevés a hely a grafikonhoz.");
  const cx = plotWidth / 2, cy = plotHeight / 2;
  const shape = arc().innerRadius(0).outerRadius(radius);
  let svg = `<g transform="translate(${round(cx)} ${round(cy)})">`;
  for (const [index, part] of pie().sort(null).value(slice => slice.value)(slices).entries()) {
    svg += `<path d="${shape(part)}" fill="${colors[index]}" stroke="${options.surface}" stroke-width="${slices.length > 1 ? 2 : 0}" stroke-linejoin="round">`
      + `<title>${escapeXML(part.data.label + ": " + plain.format(part.data.value) + " (" + share(part.data.value) + ")")}</title></path>`;
  }
  svg += "</g>";
  const keyX = beside ? plotWidth + 4 : 6, keyY = beside ? Math.max(4, (height - rows * rowHeight) / 2) : plotHeight + 2;
  for (const [index, slice] of slices.slice(0, shown).entries()) {
    const y = keyY + index * rowHeight, percent = share(slice.value);
    svg += `<rect x="${round(keyX)}" y="${round(y + 1)}" width="10" height="10" rx="2" fill="${colors[index]}"/>`
      + `<text x="${round(keyX + 14)}" y="${round(y + 10)}" font-size="11" fill="currentColor" fill-opacity="0.85">`
      + `${escapeXML(fit(slice.label, keyWidth - 22 - textWidth(percent) - 8))} <tspan fill-opacity="0.6">${escapeXML(percent)}</tspan></text>`;
  }
  return svg;
}

// `surface`: a doboz háttérszíne (a pontok és szeletek elválasztó szegélye); `dark`: sötét felület (a színek sötét lépcsője).
export function chartSVG(rows, chart, {width, height, dark = false, surface = dark ? "#1a1a19" : "#ffffff"} = {}) {
  width = Math.max(40, Math.round(width)); height = Math.max(30, Math.round(height));
  if (!rows) return message(width, height, "A táblázat nem olvasható.");
  const data = chartData(rows, chart);
  if (!data.series.length || !data.labels.length) return message(width, height, "Nincs ábrázolható számoszlop.");
  const colors = dark ? palette.dark : palette.light, options = {surface};
  const inner = data.kind === "pie" ? pieChart(data, width, height, colors, options) : axes(data, width, height, colors, options);
  if (inner.startsWith("<svg")) return inner;
  const name = chartKinds[data.kind] + "diagram: " + data.series.map(item => item.name).join(", ");
  return `<svg xmlns="http://www.w3.org/2000/svg" class="tn-chart" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeXML(name)}" font-family="system-ui, sans-serif">${inner}</svg>`;
}

// Sötét-e a szín (#rgb / #rrggbb): a sötét felületű dobozon a színek sötét lépcsője kell.
export function isDarkColor(color) {
  const match = /^#([0-9a-f]{6}|[0-9a-f]{3})(?:[0-9a-f]{2})?$/i.exec(color ?? "");
  if (!match) return false;
  const hex = match[1].length === 3 ? [...match[1]].map(ch => ch + ch).join("") : match[1];
  const [r, g, b] = [0, 2, 4].map(at => parseInt(hex.slice(at, at + 2), 16));
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.45;
}

// Sötét-e a doboz felülete: a háttérszínből, ha van; háttér nélküli doboznál a szövegszínből (világos tinta = sötét felület).
export function darkSurface(surface, ink) {
  if (/^#[0-9a-f]{3}/i.test(surface ?? "")) return isDarkColor(surface);
  return /^#[0-9a-f]{3}/i.test(ink ?? "") && !isDarkColor(ink);
}
