// Sorkizárás SVG-ben: a `data-justify` sorok (tspan) a szóközök tágításával érik el a kért szélességet.
// A `textLength`/`lengthAdjust="spacing"` a betűk közé osztaná szét a helyet (betűritkítás), ezért nem azt használjuk.
// A szélességet a böngésző méri, így félkövér, dőlt és kódrészlet mellett is pontos.
// A mérés (getComputedTextLength) kényszerített elrendezés: soronként csak akkor ismétlődik, ha a sor tartalma, kért
// szélessége vagy betűje változott – a doboz mozgatása (újrarajzolás változatlan szöveggel) nem mér újra.
let fontEpoch = 0;
globalThis.document?.fonts?.addEventListener?.("loadingdone", () => { fontEpoch += 1; });

export function justifyRows(root) {
  for (const row of root?.querySelectorAll?.("[data-justify]") ?? []) {
    const target = Number(row.getAttribute("data-justify"));
    const key = [fontEpoch, target, row.getAttribute("font-size"), row.getAttribute("font-weight"),
      row.parentNode?.getAttribute?.("font-family"), row.innerHTML].join("|");
    if (row.__justified === key) continue;
    row.__justified = key;
    const gaps = (row.textContent.match(/ /g) ?? []).length;
    row.style.wordSpacing = "";
    if (!(target > 0) || !gaps) continue;
    const measured = row.getComputedTextLength?.() ?? 0;
    // Nem megjelenített (pl. rejtett) vásznon 0 a mért hossz: ilyenkor balra zárt marad, és a következő rajzoláskor újra mér.
    if (!(measured > 0)) row.__justified = undefined;
    if (measured > 0 && measured < target) row.style.wordSpacing = (target - measured) / gaps + "px";
  }
}
