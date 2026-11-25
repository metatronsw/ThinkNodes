// Sorkizárás SVG-ben: a `data-justify` sorok (tspan) a szóközök tágításával érik el a kért szélességet.
// A `textLength`/`lengthAdjust="spacing"` a betűk közé osztaná szét a helyet (betűritkítás), a CSS `word-spacing`-et pedig
// a Safari SVG-szövegen nem alkalmazza. Ezért a sor `dx` listát kap: minden szóköz utáni betű ennyivel kerül jobbra
// (a lista betűnként egy értéket tartalmaz, a beágyazott tspan-ek betűire is érvényes).
// A szélességet a böngésző méri, így félkövér, dőlt és kódrészlet mellett is pontos.
// A mérés (getComputedTextLength) kényszerített elrendezés, ezért:
// - egy sor csak akkor kerül sorra, ha a tartalma, kért szélessége vagy betűje változott (a doboz mozgatása nem mér);
// - az azonos tartalmú sor természetes hosszát megjegyezzük (körbefuttatásnál a sorok nagy része változatlan marad);
// - a többit egy körben mérjük: előbb minden érintett sorról lekerül az eltolás, aztán jön az összes mérés, végül az
//   összes írás – így a böngésző egyszer rendez, nem soronként.
let fontEpoch = 0;
const lengths = new Map();
globalThis.document?.fonts?.addEventListener?.("loadingdone", () => { fontEpoch += 1; lengths.clear(); });

export function justifyRows(root) {
  const pending = [];
  for (const row of root?.querySelectorAll?.("[data-justify], [data-justified]") ?? []) {
    if (!row.hasAttribute("data-justify")) {
      // A sor már nem sorkizárt (kikapcsolták, vagy bekezdés utolsó sora lett): a korábbi eltolás megszűnik.
      row.removeAttribute("dx");
      row.removeAttribute("data-justified");
      row.__justified = undefined;
      continue;
    }
    const target = Number(row.getAttribute("data-justify"));
    const content = [row.getAttribute("font-size"), row.getAttribute("font-weight"),
      row.parentNode?.getAttribute?.("font-family"), row.innerHTML].join("|");
    const key = fontEpoch + "|" + target + "|" + content;
    if (row.__justified === key) continue;
    row.__justified = key;
    row.setAttribute("data-justified", "");
    const text = row.textContent;
    const gaps = (text.match(/ /g) ?? []).length;
    const known = lengths.get(content);
    if (known === undefined || !(target > 0) || !gaps) row.removeAttribute("dx");
    if (target > 0 && gaps) pending.push({row, target, text, gaps, content, known});
  }
  for (const item of pending) {
    if (item.known !== undefined) continue;
    item.known = item.row.getComputedTextLength?.() ?? 0;
    // Nem megjelenített (pl. rejtett) vásznon 0 a mért hossz: ilyenkor balra zárt marad, és a következő rajzoláskor újra mér.
    if (item.known > 0) {
      if (lengths.size > 4000) lengths.clear();
      lengths.set(item.content, item.known);
    } else item.row.__justified = undefined;
  }
  for (const {row, target, text, gaps, known} of pending) {
    if (!(known > 0) || known >= target) { row.removeAttribute("dx"); continue; }
    const extra = Math.round((target - known) / gaps * 100) / 100;
    let shifts = "";
    for (let i = 0; i < text.length; i++) shifts += (i ? " " : "") + (i && text[i - 1] === " " ? extra : 0);
    if (row.getAttribute("dx") !== shifts) row.setAttribute("dx", shifts);
  }
}
