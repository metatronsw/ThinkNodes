// A 32 fekete avatar (24×24) előállítása. Használat: node docs/avatars.mjs Public/icons [áttekintő.svg]
// Az ikonok színe nincs megadva: a felület `<use href="/icons/avatar-N.svg#a">` hivatkozással, a fill-lel színezi.
import {writeFileSync} from "node:fs";
const [outDir, sheet] = process.argv.slice(2);
const f = n => +n.toFixed(2);
const circle = (cx, cy, r) => `M${f(cx - r)} ${f(cy)}a${r} ${r} 0 1 0 ${f(2 * r)} 0a${r} ${r} 0 1 0 ${f(-2 * r)} 0z`;
const ellipse = (cx, cy, rx, ry) => `M${f(cx - rx)} ${f(cy)}a${rx} ${ry} 0 1 0 ${f(2 * rx)} 0a${rx} ${ry} 0 1 0 ${f(-2 * rx)} 0z`;
const polar = (cx, cy, r, deg) => [cx + r * Math.cos(deg * Math.PI / 180), cy + r * Math.sin(deg * Math.PI / 180)];
const poly = points => "M" + points.map(([x, y]) => f(x) + " " + f(y)).join("L") + "z";
// A rectangle of the given width/length around (cx, cy), rotated by deg.
function bar(cx, cy, length, width, deg) {
  const a = deg * Math.PI / 180, ux = Math.cos(a), uy = Math.sin(a), vx = -uy, vy = ux;
  const l = length / 2, w = width / 2;
  return poly([[cx - ux * l - vx * w, cy - uy * l - vy * w], [cx + ux * l - vx * w, cy + uy * l - vy * w],
    [cx + ux * l + vx * w, cy + uy * l + vy * w], [cx - ux * l + vx * w, cy - uy * l + vy * w]]);
}
function star(cx, cy, outer, inner, spikes = 5) {
  const pts = [];
  for (let i = 0; i < spikes * 2; i++) pts.push(polar(cx, cy, i % 2 ? inner : outer, -90 + i * 180 / spikes));
  return poly(pts);
}
// Thick arc (annular sector) from angle a0 to a1 (degrees, clockwise on screen).
function arcBand(cx, cy, r0, r1, a0, a1) {
  const [x0, y0] = polar(cx, cy, r1, a0), [x1, y1] = polar(cx, cy, r1, a1);
  const [x2, y2] = polar(cx, cy, r0, a1), [x3, y3] = polar(cx, cy, r0, a0);
  const large = a1 - a0 > 180 ? 1 : 0;
  return `M${f(x0)} ${f(y0)}A${r1} ${r1} 0 ${large} 1 ${f(x1)} ${f(y1)}L${f(x2)} ${f(y2)}A${r0} ${r0} 0 ${large} 0 ${f(x3)} ${f(y3)}z`;
}

const sun = [circle(12, 12, 4.6), ...Array.from({length: 8}, (_, i) => bar(...polar(12, 12, 8.4, i * 45), 3.6, 2, i * 45))].join("");
const snowflake = [0, 60, 120].map(a => bar(12, 12, 20.4, 2, a + 90)).join("") +
  [0, 60, 120, 180, 240, 300].flatMap(a => {
    const t = a - 90, [x, y] = polar(12, 12, 5.4, t);
    return [bar(...polar(x, y, 1.9, t + 42), 4.4, 1.7, t + 42), bar(...polar(x, y, 1.9, t - 42), 4.4, 1.7, t - 42)];
  }).join("");
const flower = Array.from({length: 5}, (_, i) => circle(...polar(12, 12, 6.1, -90 + i * 72), 3.4)).join("") + circle(12, 12, 2.3);
const paw = ellipse(12, 16.4, 4.8, 4) + circle(5.6, 10.6, 2.1) + circle(9.3, 6.4, 2.3) + circle(14.7, 6.4, 2.3) + circle(18.4, 10.6, 2.1);
const club = circle(12, 7, 4.1) + circle(6.9, 13.6, 4.1) + circle(17.1, 13.6, 4.1) + circle(12, 12, 2.6) + "M12 11.5 9.8 21.5h4.4z";
const anchor = [circle(12, 4.3, 2.5) + circle(12, 4.3, 1.1), arcBand(12, 11, 7.2, 9.2, 15, 165), "M11 6.4h2v12.4h-2z", "M7.2 8.4h9.6v2.1H7.2z",
  poly([polar(12, 11, 5.6, 15), polar(12, 11, 10.8, 15), polar(12, 11, 8.2, -14)]),
  poly([polar(12, 11, 5.6, 165), polar(12, 11, 10.8, 165), polar(12, 11, 8.2, 194)])];
const key = [circle(7, 12, 5) + circle(7, 12, 2), "M11 10.8H22v2.4h-1.2V16.5h-2.4v-3.3h-1.2V15.5h-2.4v-2.3H11z"];

// [name, parts]: a string is split into separately filled subpaths; an array keeps each entry (with its holes) whole.
const shapes = [
  ["szív", "M12 21.2 10.6 20C5.4 15.4 2 12.3 2 8.5 2 5.4 4.4 3 7.5 3c1.7 0 3.4.8 4.5 2.1C13.1 3.8 14.8 3 16.5 3 19.6 3 22 5.4 22 8.5c0 3.8-3.4 6.9-8.6 11.5z"],
  ["csillag", star(12, 12.8, 10.6, 4.4)],
  ["korona", "M3 18.2h18v2.6H3zM3.2 16.8 2.2 7.2l5.4 4.4L12 4.2l4.4 7.4 5.4-4.4-1 9.6z" + circle(2.2, 6.4, 1.5) + circle(12, 3.3, 1.5) + circle(21.8, 6.4, 1.5)],
  ["bástya", "M4.8 21.5h14.4v-2.6H4.8zM6.6 17.9h10.8l-1.1-2.4H7.7zM8.4 14.5h7.2L15 8.4H9zM6.4 7.4h11.2V2.5h-2.5v2.2h-2V2.5h-2.2v2.2h-2V2.5H6.4z"],
  ["huszár", ["M4.8 21.5h14.4v-2.6H4.8z", "M6.8 17.9H18.4c.4-3.6 0-7-1.6-9.8-1.3-2.4-3.5-4-6.1-4.6L10 1.6 8.5 4.1C6.6 5.3 5.1 7.2 4.3 9.5l-.8 2.3c-.2.8.3 1.5 1.1 1.5h1.6l2.5-1.7c.7.4 1.6.5 2.3.1-.5 1.9-1.8 3.2-3.2 4.2z" + circle(9.6, 7.6, .9)]],
  ["gyalog", "M4.8 21.5h14.4v-2.4l-2-1.6H6.8l-2 1.6zM8.3 16.5h7.4c-1-2.2-2-4.4-2.1-6.8h-3.2c-.1 2.4-1.1 4.6-2.1 6.8zM7.8 9.6h8.4V7.9H7.8z" + circle(12, 4.9, 3)],
  ["pikk", "M12 2C9 6 3 9.4 3 14c0 2.8 2.2 4.6 4.6 4.6 1.5 0 2.7-.6 3.5-1.6L10 22h4l-1.1-5c.8 1 2 1.6 3.5 1.6 2.4 0 4.6-1.8 4.6-4.6C21 9.4 15 6 12 2z"],
  ["treff", club],
  ["káró", "M12 1.5 19.5 12 12 22.5 4.5 12z"],
  ["hold", "M14.6 2.4A9.6 9.6 0 1 0 21.6 15 7.6 7.6 0 0 1 14.6 2.4z"],
  ["nap", sun],
  ["felhő", "M6.6 19.5a4.6 4.6 0 0 1-.7-9.1 6.2 6.2 0 0 1 11.9-1.5 5.3 5.3 0 0 1-.2 10.6z"],
  ["villám", "M13.8 1.5 4.2 13.6h6.6L9.2 22.5l10.6-13h-6.6z"],
  ["hópehely", snowflake],
  ["csepp", "M12 2.2C9 6.8 5.2 10.4 5.2 14.6a6.8 6.8 0 0 0 13.6 0C18.8 10.4 15 6.8 12 2.2z"],
  ["láng", "M12 22.4c-4.2 0-7.4-3-7.4-7.1 0-3.5 2.3-5.9 4-8 .6 1.7 1.6 2.8 2.7 3.4C11 6.6 12.6 3.5 15.2 1.5c-.2 3.3 1.5 5.2 2.9 7.3 1 1.5 1.3 3.1 1.3 5.4 0 5-3.2 8.2-7.4 8.2z"],
  ["levél", "M21 2.6C12.4 2.6 4.4 5.6 4.4 13.8c0 1.6.4 3 1.1 4.2l-2.4 2.4 1.5 1.5 2.3-2.3c1.3 1 3 1.5 4.9 1.5 7.9 0 9.2-9.6 9.2-18.5z"],
  ["fenyő", "M12 1.2 6.2 8.8h2.9L4.4 15h3.5L3.4 20.6h17.2L16.1 15h3.5l-4.7-6.2h2.9zM10.7 20h2.6v3.2h-2.6z"],
  ["virág", flower],
  ["gomba", ["M2.4 12.2C2.4 6.6 6.7 2.8 12 2.8s9.6 3.8 9.6 9.4z" + circle(7.6, 8.4, 1.6) + circle(13.4, 5.9, 1.3) + circle(16.8, 9.6, 1.3), "M8.9 13.4h6.2l.8 7.3c0 1.3-1.7 2.1-3.9 2.1s-3.9-.8-3.9-2.1z"]],
  ["hal", ["M1.8 12C4.3 8 7.8 5.8 11.5 5.8c3.6 0 6.6 2.2 8.2 4.6L22.4 7v10l-2.7-3.4c-1.6 2.4-4.6 4.6-8.2 4.6-3.7 0-7.2-2.2-9.7-6.2z" + circle(7.2, 10.9, 1.3)]],
  ["macska", ["M3.6 2.4 8.4 7.2c1.1-.4 2.3-.6 3.6-.6s2.5.2 3.6.6l4.8-4.8v10.2c0 5-3.7 9-8.4 9s-8.4-4-8.4-9z" + ellipse(8.8, 13, 1.2, 1.7) + ellipse(15.2, 13, 1.2, 1.7) + "M10.8 16.6h2.4L12 18z"]],
  ["mancs", paw],
  ["szellem", ["M12 2.2c-4.3 0-7.4 3.2-7.4 7.6v11.4q1.23 1.6 2.47 0t2.47 0 2.46 0 2.47 0 2.46 0 2.47 0V9.8c0-4.4-3.1-7.6-7.4-7.6z" + ellipse(9.2, 10, 1.4, 1.9) + ellipse(14.8, 10, 1.4, 1.9)]],
  ["horgony", anchor],
  ["kulcs", key],
  ["harang", "M12 1.8a1.6 1.6 0 0 0-1.6 1.6v.8C7.5 5 5.4 7.6 5.4 10.9V16l-2.2 2.2v1.3h17.6v-1.3L18.6 16v-5.1c0-3.3-2.1-5.9-5-6.7v-.8A1.6 1.6 0 0 0 12 1.8zM9.4 20.6a2.6 2.6 0 0 0 5.2 0z"],
  ["rakéta", ["M12 1.2c3.3 2.6 5 6.2 5 10.8v5.2H7V12c0-4.6 1.7-8.2 5-10.8z" + circle(12, 9.2, 1.9), "M7 11.8 3.8 15.4v4.8L7 18z", "M17 11.8l3.2 3.6v4.8L17 18z", "M9.4 18.4h5.2L12 23z"]],
  ["esernyő", "M12 2.2C6.6 2.2 2.3 6.3 2 11.4c1-.9 2.3-1.4 3.6-1.4 1.3 0 2.5.5 3.4 1.4.8-.9 2-1.4 3-1.4s2.2.5 3 1.4c.9-.9 2.1-1.4 3.4-1.4 1.3 0 2.6.5 3.6 1.4-.3-5.1-4.6-9.2-10-9.2zM11 10.6v8a1.4 1.4 0 0 1-2.8 0H6.2a3.4 3.4 0 0 0 6.8 0v-8z"],
  ["hangjegy", "M8.6 5.6 21 2.4v13.4a3.4 3.4 0 1 1-2.2-3.2V7.6l-8 2v8.6a3.4 3.4 0 1 1-2.2-3.2z"],
  ["ház", "M12 2.4 1.6 11.6h3.1v9.6h5.7v-6.1h3.2v6.1h5.7v-9.6h3.1z"],
  ["villanykörte", "M12 1.6a7.2 7.2 0 0 0-4.2 13v2.6h8.4v-2.6a7.2 7.2 0 0 0-4.2-13zM7.8 18.6h8.4v1.8H7.8zM9.4 21.6h5.2a2.6 2.6 0 0 1-5.2 0z"],
];

if (shapes.length !== 32) throw Error("32 shapes expected, got " + shapes.length);
const parts = p => Array.isArray(p) ? p : p.split(/(?=M)/);
const body = parts_ => parts_.map(d => `<path d="${d}"/>`).join("");
shapes.forEach(([name, p], i) => {
  writeFileSync(`${outDir}/avatar-${i + 1}.svg`,
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><title>${name}</title><g id="a" fill-rule="evenodd">${body(parts(p))}</g></svg>\n`);
});
const cell = 60;
if (sheet) writeFileSync(sheet, `<svg xmlns="http://www.w3.org/2000/svg" width="${8 * cell}" height="${4 * cell}"><rect width="100%" height="100%" fill="white"/>` +
  shapes.map(([name, p], i) => `<g fill-rule="evenodd" transform="translate(${(i % 8) * cell + 6} ${Math.floor(i / 8) * cell + 4}) scale(2)">${body(parts(p))}</g><text x="${(i % 8) * cell + 30}" y="${Math.floor(i / 8) * cell + 58}" font-size="8" text-anchor="middle" font-family="sans-serif">${i + 1} ${name}</text>`).join("") + "</svg>");
