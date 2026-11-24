// Számformátumok és a beírt szöveg értelmezése (EXCEL.md 3. fejezet). Swift párja: Sources/ThinkTable/TableFormat.swift.
// A kerekítés saját (a feleket nullától elfelé), így a két oldal ugyanazt írja ki.

export const groupSeparator = " ";

// Lebegőpontos korrekció (a Swift TableFormat.nudge párja): az 1,005 binárisan 1,00499999…, ezért a szorzat egy
// hajszálnyival (~4 ulp) feljebb kerül, így a tizedes fél valóban felfelé kerekedik, mint az Excelben.
const nudge = 1 + Math.pow(2, -50);

export function roundHalfAway(value, digits) {
  if (!Number.isFinite(value)) return value;
  let rounded;
  if (digits >= 0) {
    const factor = Math.pow(10, digits);
    const scaled = Math.abs(value) * factor;
    if (scaled >= 4503599627370496) return value;  // 2^52 fölött már egész
    rounded = Math.floor(scaled * nudge + 0.5) / factor;
  } else {
    const factor = Math.pow(10, -digits);
    rounded = Math.floor(Math.abs(value) / factor * nudge + 0.5) * factor;
  }
  return value < 0 ? -rounded : rounded;
}

function grouped(digits) {
  let result = "";
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) result += groupSeparator;
    result += digits[i];
  }
  return result;
}

export function fixed(value, decimals, group = false) {
  if (!Number.isFinite(value)) return "#NUM!";
  // 10^15 fölött a tizedesjegyeknek nincs értelme (és a toFixed 10^21-től exponenst ad): általános alak.
  if (Math.abs(value) >= 1e15) return general(value);
  decimals = Math.max(0, Math.min(decimals, 15));
  // Legfeljebb 15 értékes jegy (mint az Excel): a további tizedeshelyek nullák (a Swift fixed párja).
  const integerDigits = Math.abs(value) >= 1 ? String(Math.trunc(Math.abs(value))).length : 0;
  const significant = Math.min(decimals, Math.max(0, 15 - integerDigits));
  const rounded = roundHalfAway(value, significant);
  const text = Math.abs(rounded).toFixed(significant);
  let [integer, fraction = ""] = text.split(".");
  fraction += "0".repeat(decimals - significant);
  if (group) integer = grouped(integer);
  const negative = rounded < 0 && Number(text) !== 0;
  return (negative ? "-" : "") + integer + (fraction ? "," + fraction : "");
}

function trimmed(text) {
  if (!text.includes(",")) return text;
  let result = text.replace(/0+$/, "").replace(/,$/, "");
  return result === "-0" ? "0" : result;
}

export function general(value) {
  if (!Number.isFinite(value)) return "#NUM!";
  if (value === 0) return "0";
  const magnitude = Math.abs(value);
  if (magnitude >= 1e11 || magnitude < 1e-9) {
    let exponent = Math.floor(Math.log10(magnitude));
    let mantissa = roundHalfAway(magnitude / Math.pow(10, exponent), 5);
    if (mantissa >= 10) { mantissa /= 10; exponent += 1; }
    const body = trimmed(fixed(mantissa, 5));
    return (value < 0 ? "-" : "") + body + "E" + (exponent < 0 ? "-" : "+") + String(Math.abs(exponent)).padStart(2, "0");
  }
  const integerDigits = magnitude >= 1 ? String(Math.trunc(magnitude)).length : 0;
  return trimmed(fixed(value, Math.min(10, Math.max(0, 10 - integerDigits))));
}

export function display(value, format) {
  if (value == null) return "";
  if (typeof value === "string") return value;
  if (typeof value === "boolean") return value ? "IGAZ" : "HAMIS";
  if (typeof value === "object") return value.err ?? "";
  if (!format) return general(value);
  switch (format.kind) {
    case "number": return fixed(value, format.dec ?? 2, format.group ?? false);
    case "currency": {
      const amount = fixed(value, format.dec ?? 0, true), symbol = format.symbol ?? "Ft";
      if (format.before) return amount.startsWith("-") ? "-" + symbol + " " + amount.slice(1) : symbol + " " + amount;
      return amount + " " + symbol;
    }
    case "percent": return fixed(value * 100, format.dec ?? 0) + "%";
    case "date": return date(value, format.pattern ?? "yyyy.MM.dd.");
    case "fraction": return fraction(value, format.dec ?? 99);
    default: return general(value);
  }
}

// Tört alak (a Swift TableFormat.fraction párja): egész rész + a legközelebbi p/q, q ≤ maxDenominator; döntetlennél a kisebb nevező.
export function fraction(value, maxDenominator = 99) {
  if (!Number.isFinite(value)) return "#NUM!";
  if (Math.abs(value) >= 1e15) return general(value);
  const magnitude = Math.abs(value);
  let whole = Math.floor(magnitude);
  const part = magnitude - whole;
  let bestP = 0, bestQ = 1, bestError = part;
  for (let q = 1; q <= Math.max(1, Math.min(maxDenominator, 999)); q++) {
    const p = roundHalfAway(part * q, 0);
    const error = Math.abs(part - p / q);
    if (error < bestError) { bestP = p; bestQ = q; bestError = error; }
  }
  if (bestP === bestQ) { whole += 1; bestP = 0; }
  const sign = value < 0 && (whole > 0 || bestP > 0) ? "-" : "";
  const wholeText = whole > 0 || bestP === 0 ? String(whole) : "";
  const partText = bestP > 0 ? (wholeText ? " " : "") + bestP + "/" + bestQ : "";
  return sign + wholeText + partText;
}

// Szerkeszthető, teljes pontosságú alak (15 értékes jegy, mint az Excel képletsorában), tizedesvesszővel.
// A formázott kiírás kerekít; ha a szerkesztő azt mutatná, F2+Enter után elveszne a pontosság (audit, 2026-11-24).
export function precise(value) {
  if (!Number.isFinite(value)) return "#NUM!";
  if (value === 0) return "0";
  return String(Number(value.toPrecision(15))).replace(".", ",");
}

// Dátum: napok 1899-12-30 óta (Excel). Polgári dátum ↔ napok 1970 óta: Howard Hinnant algoritmusa.
const epochOffset = 25569;
const div = (a, b) => Math.trunc(a / b);

function daysFromCivil(y, m, d) {
  const year = m <= 2 ? y - 1 : y;
  const era = div(year >= 0 ? year : year - 399, 400);
  const yoe = year - era * 400;
  const doy = div(153 * (m + (m > 2 ? -3 : 9)) + 2, 5) + d - 1;
  const doe = yoe * 365 + div(yoe, 4) - div(yoe, 100) + doy;
  return era * 146097 + doe - 719468;
}

function civilFromDays(z0) {
  const z = z0 + 719468;
  const era = div(z >= 0 ? z : z - 146096, 146097);
  const doe = z - era * 146097;
  const yoe = div(doe - div(doe, 1460) + div(doe, 36524) - div(doe, 146096), 365);
  const doy = doe - (365 * yoe + div(yoe, 4) - div(yoe, 100));
  const mp = div(5 * doy + 2, 153);
  const d = doy - div(153 * mp + 2, 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  return [yoe + era * 400 + (m <= 2 ? 1 : 0), m, d];
}

export const serial = (year, month, day, hour = 0, minute = 0, second = 0) =>
  daysFromCivil(year, month, day) + epochOffset + (hour * 3600 + minute * 60 + second) / 86400;

function date(value, pattern) {
  let days = Math.floor(value);
  let seconds = Math.trunc((value - days) * 86400 + 0.5);
  if (seconds >= 86400) { days += 1; seconds -= 86400; }
  const [y, m, d] = civilFromDays(days - epochOffset);
  const two = n => String(n).padStart(2, "0");
  return [["yyyy", String(y)], ["MM", two(m)], ["dd", two(d)], ["HH", two(div(seconds, 3600))],
    ["mm", two(div(seconds, 60) % 60)], ["ss", two(seconds % 60)]].reduce((text, [token, v]) => text.split(token).join(v), pattern);
}

const currencySuffixes = ["Ft", "HUF", "€", "EUR", "$", "USD"];
const currencyPrefixes = ["€", "$"];
const isDigit = ch => ch >= "0" && ch <= "9";
const trimSpaces = text => text.replace(/^[ \t\u00a0]+|[ \t\u00a0]+$/g, "");

// Beírt szöveg: {kind: "empty"} | {kind: "formula", formula} | {kind: "value", value, format}.
export function parseInput(raw) {
  const text = trimSpaces(raw);
  if (!text) return {kind: "empty"};
  if (text.startsWith("=") && text.length > 1) return {kind: "formula", formula: text.slice(1)};
  if (raw.startsWith("'")) return {kind: "value", value: raw.slice(1), format: null};
  const upper = text.toUpperCase();
  if (upper === "IGAZ" || upper === "TRUE") return {kind: "value", value: true, format: null};
  if (upper === "HAMIS" || upper === "FALSE") return {kind: "value", value: false, format: null};
  const fractionValue = parseFraction(text);
  if (fractionValue != null) return {kind: "value", value: fractionValue, format: {kind: "fraction"}};
  if (text.endsWith("%")) {
    const parsed = parseNumber(trimSpaces(text.slice(0, -1)));
    if (parsed) return {kind: "value", value: parsed[0] / 100, format: {kind: "percent", dec: parsed[1]}};
  }
  for (const symbol of currencySuffixes) if (text.endsWith(symbol)) {
    const parsed = parseNumber(trimSpaces(text.slice(0, -symbol.length)));
    if (parsed) return {kind: "value", value: parsed[0], format: {kind: "currency", dec: parsed[1], symbol}};
  }
  for (const symbol of currencyPrefixes) if (text.startsWith(symbol)) {
    const parsed = parseNumber(trimSpaces(text.slice(symbol.length)));
    if (parsed) return {kind: "value", value: parsed[0], format: {kind: "currency", dec: parsed[1], symbol, before: true}};
  }
  const dated = parseDate(text);
  if (dated) return {kind: "value", value: dated[0], format: {kind: "date", pattern: dated[1]}};
  const parsed = parseNumber(text);
  if (parsed) return {kind: "value", value: parsed[0], format: parsed[2] ? {kind: "number", dec: parsed[1], group: true} : null};
  return {kind: "value", value: raw, format: null};
}

// Tört: "3/4", "1 1/2", "-2 3/8" (a nevező nem 0). Az Excel a "1/2"-t dátumnak venné; itt szám (tört formátummal).
function parseFraction(text) {
  if (!/^[-+]?([0-9]+ +)?[0-9]+\/[0-9]+$/.test(text)) return null;
  const negative = text.startsWith("-");
  const parts = text.replace(/^[-+]/, "").split(/ +/);
  const [numerator, denominator] = parts[parts.length - 1].split("/").map(Number);
  if (denominator === 0) return null;
  const value = (parts.length === 2 ? Number(parts[0]) : 0) + numerator / denominator;
  return negative ? -value : value;
}

// [érték, tizedesjegyek, volt-e ezreselválasztás] vagy null.
export function parseNumber(text) {
  let body = text, negative = false;
  if (body.startsWith("-") || body.startsWith("+")) { negative = body[0] === "-"; body = body.slice(1); }
  const first = body[0];
  if (!first || !(isDigit(first) || first === "." || first === ",")) return null;
  const lower = body.toLowerCase().replace(/,/g, ".");  // exponensben a tizedesvessző is jó: "1,5e3"
  if (lower.includes("e")) {
    if (!/^([0-9]+\.?[0-9]*|\.[0-9]+)e[+-]?[0-9]+$/.test(lower)) return null;
    const value = Number(lower);
    return Number.isNaN(value) ? null : [negative ? -value : value, 0, false];
  }
  const separators = ". ,\u00a0";
  if (![...body].every(ch => isDigit(ch) || separators.includes(ch))) return null;
  const dots = body.split(".").length - 1, commas = body.split(",").length - 1;
  let mark = null;
  if (dots > 0 && commas > 0) mark = body.lastIndexOf(".") > body.lastIndexOf(",") ? "." : ",";
  else if (dots === 1) mark = ".";
  else if (commas === 1) mark = ",";
  let integer = body, fraction = "";
  if (mark) { const index = body.lastIndexOf(mark); integer = body.slice(0, index); fraction = body.slice(index + 1); }
  if (!/^[0-9]*$/.test(fraction)) return null;
  let grouped = false;
  if (/[., \u00a0]/.test(integer)) {
    // Ezreselválasztás: az első csoport 1–3 jegy, a többi pontosan 3.
    if (!/^[0-9]{1,3}([., \u00a0][0-9]{3})+$/.test(integer)) return null;
    grouped = true;
    integer = integer.replace(/[., \u00a0]/g, "");
  }
  if (!integer && !fraction) return null;
  const value = Number((integer || "0") + (fraction ? "." + fraction : ""));
  if (Number.isNaN(value)) return null;
  return [negative ? -value : value, fraction.length, grouped];
}

function parseDate(text) {
  const numbers = (s, separator) => {
    const parts = s.split(separator).map(trimSpaces).filter(Boolean);
    return parts.every(part => /^\d+$/.test(part)) ? parts.map(Number) : null;
  };
  const time = s => {
    if (!s.includes(":")) return null;
    const parts = numbers(s, ":");
    if (!parts || parts.length < 2 || parts.length > 3 || parts[0] >= 24 || parts[1] >= 60 || (parts.length === 3 && parts[2] >= 60)) return null;
    return [parts[0], parts[1], parts[2] ?? 0];
  };
  const only = time(text);
  if (only) return [(only[0] * 3600 + only[1] * 60 + only[2]) / 86400, only[2] > 0 ? "HH:mm:ss" : "HH:mm"];
  let datePart = text, timePart = null;
  const colon = text.indexOf(":");
  if (colon >= 0) {
    const space = text.slice(0, colon).lastIndexOf(" ");
    if (space >= 0) { datePart = text.slice(0, space); timePart = text.slice(space + 1); }
  }
  const dashed = datePart.includes("-");
  if (!dashed && !datePart.includes(".")) return null;
  const parts = numbers(datePart, dashed ? "-" : ".");
  if (!parts || parts.length !== 3) return null;
  if (dashed && datePart.replace(/ /g, "").split("-").filter(Boolean).length !== 3) return null;
  const [y, m, d] = parts;
  if (y < 1900 || y > 9999 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  const [cy, cm, cd] = civilFromDays(daysFromCivil(y, m, d));
  if (cy !== y || cm !== m || cd !== d) return null;
  let pattern = "yyyy.MM.dd.", value = serial(y, m, d);
  if (timePart != null) {
    const t = time(timePart);
    if (!t) return null;
    value += (t[0] * 3600 + t[1] * 60 + t[2]) / 86400;
    pattern += " HH:mm";
  }
  return [value, pattern];
}
