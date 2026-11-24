// Sorkizárás SVG-ben: a `data-justify` sorok (tspan) a szóközök tágításával érik el a kért szélességet.
// A `textLength`/`lengthAdjust="spacing"` a betűk közé osztaná szét a helyet (betűritkítás), ezért nem azt használjuk.
// A szélességet a böngésző méri, így félkövér, dőlt és kódrészlet mellett is pontos.
export function justifyRows(root) {
  for (const row of root?.querySelectorAll?.("[data-justify]") ?? []) {
    const target = Number(row.getAttribute("data-justify"));
    const gaps = (row.textContent.match(/ /g) ?? []).length;
    row.style.wordSpacing = "";
    if (!(target > 0) || !gaps) continue;
    const measured = row.getComputedTextLength?.() ?? 0;
    // Nem megjelenített (pl. rejtett) vásznon 0 a mért hossz: ilyenkor balra zárt marad.
    if (measured > 0 && measured < target) row.style.wordSpacing = (target - measured) / gaps + "px";
  }
}
