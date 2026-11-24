# Hibák

Minden munkamenet elején át kell nézni, és a nyitott hibákkal foglalkozni kell (AGENTS.md).

## Nyitott

- **Teljesítmény (perf ág): nagyítás végén 80–190 ms-os képkocka; táblázatszerkesztés görgetése ~50 fps** (2026-11-24)
  - A `perf` ág mérései szerint ez a két terület nem javult eleget; részletek és a kipróbált megoldások: `server/docs/PERF.md` („Ami nem javult vagy nyitva maradt”).
  - A `contain: strict` gyorsította a táblázatgörgetést (42 → 54 fps), de Safariban a rétegződő elem foreignObject-ben nem kattintható, ezért kikerült.

- **Safari: a táblázatszerkesztő oszlopszélesség-fogója (`.tn-resize`) nem kattintható, a ragadó fejlécek ellenőrizendők** (2026-11-24)
  - A fogó abszolút pozicionált a ragadó (`sticky`) fejlécben; Safariban a foreignObject-beli pozicionált elemet a találatvizsgálat nagyított vásznon nem találja el (automatizált Safari 18.6: a fogó helyén a `th` a találat). Ugyanezért kérdéses a ragadó sor-/oszlopfejléc megjelenése görgetéskor.
  - Teendő: a fogót normál elrendezésben megoldani; a fejléceket kézzel ellenőrizni Safariban.

- **Megjelenítő (viewer): a Safaris saját görgetősáv nincs kipróbálva** (2026-11-24)
  - A `viewer.js` is megkapta az `attachScrollbars` hívást a fájldobozokra, de csak a szerkesztőben ellenőriztem.

- **A Swift `JSONDecoder` egyes lebegőpontos literálokat 1 ulp pontatlansággal olvas (macOS 13 Foundation)** (2026-11-24, tizedes-audit)
  - Példa: `0.0020293361140076467` → `0.0020293361140076476`. A `.tntable` értékei a szerveren az utolsó bináris jegyben elcsúszhatnak (a kiírt 15 jegyre nincs hatással).
  - Teszt: `platformJSONDecoderDoublePrecision` (figyelmeztet). Teendő: ellenőrizni élesben (Fedora, swift-foundation); ha ott is pontatlan, saját számolvasó a `.tntable`-höz. Részletek: server/docs/EXCEL.md 12. fejezet.

- **`Tests/Editor/gestures.mjs` elbukik** – már a TODO.md-ben is szerepel (`ownUnderlay`); a táblázat munka előtt is így volt (2026-11-24, ellenőrizve az eredeti `editor.js`-szel).
  - `markdownEditor` `adjust`: a teszt hamis DOM-jában a `getComputedStyle` / `el.style` hiányzik (`reading 'height'`).
  - 311. sor: `button("Mentés")` nem található (a Mentés gomb azóta átalakult).
  - A `perf` ágon a 253. sor állítása a kurzor-pajzshoz igazodott (`data-drag-cursor` húzás közben már nincs a vásznon); a teszt ugyanott bukik el, ahol a `main`-en.


