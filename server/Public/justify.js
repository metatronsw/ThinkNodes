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
globalThis.document?.fonts?.addEventListener?.("loadingdone", () => { fontEpoch += 1; lengths.clear(); widths.clear(); });

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
    // A szerkesztő a sor kulcsát maga adja (data-justify-key), így a megjegyzett pontos hosszt rajzoláskor is megtalálja.
    const content = row.getAttribute("data-justify-key") ?? [row.getAttribute("font-size"), row.getAttribute("font-weight"),
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
    const shifts = known > 0 && known < target ? shiftList(text, (target - known) / gaps) : null;
    if (row.getAttribute("dx") === shifts) continue;
    if (shifts === null) row.removeAttribute("dx"); else row.setAttribute("dx", shifts);
  }
}

// A `dx` lista: minden szóköz utáni betű `extra` képponttal kerül jobbra.
function shiftList(text, extra) {
  const value = Math.round(extra * 100) / 100;
  let shifts = "";
  for (let i = 0; i < text.length; i++) shifts += (i ? " " : "") + (i && text[i - 1] === " " ? value : 0);
  return shifts;
}

// Sorkizárás a szerkesztőben, rajzolás előtt: a `dx` lista már a virtuális DOM-ban a sorra kerül, így a szöveg rögtön a
// végleges alakjában jelenik meg (a kirajzolás utáni mérés és visszaírás húzás közben, amikor a körbefuttatott sorok
// képkockánként változnak, minden képkockában második szövegelrendezés volt). A sor természetes hossza: ha a sort
// (`key`) a justifyRows már megmérte, a pontos érték; különben vászon-szövegmérés (futásonként megjegyezve), ami a
// Safari SVG-szövegétől néhány képponttal eltérhet – nyugalomban a justifyRows pontosítja.
// `runs`: [{text, weight, italic, family}], `size` képpontban.
let pen;
const widths = new Map();
export function justifyShifts(runs, size, target, key) {
  if (!(target > 0)) return undefined;
  pen ??= globalThis.document?.createElement?.("canvas")?.getContext?.("2d") ?? null;
  if (!pen) return undefined;
  let text = "", natural = 0;
  for (const run of runs) {
    const font = (run.italic ? "italic " : "") + run.weight + " " + size + "px " + run.family;
    const key = fontEpoch + "|" + font + "|" + run.text;
    let width = widths.get(key);
    if (width === undefined) {
      pen.font = font;
      width = pen.measureText(run.text).width;
      if (widths.size > 20000) widths.clear();
      widths.set(key, width);
    }
    natural += width;
    text += run.text;
  }
  natural = lengths.get(key) ?? natural;
  const gaps = (text.match(/ /g) ?? []).length;
  return gaps && natural > 0 && natural < target ? shiftList(text, (target - natural) / gaps) : undefined;
}
