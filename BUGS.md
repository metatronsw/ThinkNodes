# Hibák

Minden munkamenet elején át kell nézni, és a nyitott hibákkal foglalkozni kell (AGENTS.md).

## Nyitott

- **Safari: nagyítás közben ugrál a rács – a javítás Safariban nincs megerősítve** (2026-11-24)
  - Az élesítés késleltetése (0,6 mp nyugalom után) a feltételezett okot megszünteti, de Safariban nem volt mód kipróbálni. Ha megmarad: `{"sharp":false}` kapcsolóval ellenőrizni, hogy az élesítés okozza-e; ha nem, a nagyítási korlát (`constrainView`, `scaleExtent`) és a zoom-kijelző a következő gyanúsított.

- **Éles kirajzolás nagyítva: Safariban nincs mérve** (2026-11-24)
  - 100% fölött a nyugalmi réteg megszűnik (`restLayer`), hogy a táblázat / CSV / szövegfájl éles legyen. Safariban ellenőrizendő az élesség, és hogy a pásztázás / nagyítás indulásakor mekkora a megakadás (a réteg visszakapcsolása; PERF.md szerint 40–70 ms lehet).

- **Más résztvevő cellakijelölése a CSV olvasó nézetében elcsúszhat** (2026-11-24)
  - A CSV olvasó nézete kihagyja az üres sorokat, és legfeljebb 200 sort / 30 oszlopot mutat; a kijelölés és a dupla kattintással megnyitott cella a szerkesztő sorszámai szerint megy, így üres sorokat tartalmazó fájlban egy sorral elcsúszhat. A megtekintőben a cellakijelölés nem látszik.

- **A 2026-11-24-i vászon-, táblázat- és CSV-módosítások Safariban nincsenek kipróbálva** (2026-11-24)
  - Chromiumban ellenőrizve. Safariban külön nézendő: CSV cellaszerkesztés (ugyanaz a szerkesztő, mint a táblázaté, a ragadó fejlécekkel), a „méretre igazítás” gomb mérése (a saját görgetősáv tartója mellett), a 800%-os nagyítás, a zoom-kijelző helye.

- **Közös görgetés: a táblázat szerkesztő- és olvasó nézetének görgetési helyzete nem pontosan fedi egymást** (2026-11-24)
  - Cellaszerkesztés közben a rács görgetési értéke megy át változatlanul az olvasó nézetekbe; a fejlécsor és a belső térköz miatt a többieknél néhány képponttal (CSV-nél, ahol a sormagasság eltér, többel) máshol állhat a tartalom.

- **A megtekintőben a görgethető tartalom kijelölés nélkül is görög** (2026-11-24)
  - A „csak kijelölt dobozban görög” szabály a szerkesztőben él; a megtekintőben (ahol a látogató nem jelöl ki) a tartalom egérgörgővel továbbra is görgethető. Eldöntendő, hogy ott mi legyen a szabály.

- **Teljesítmény: nagyítás végén 80–190 ms-os képkocka; táblázatszerkesztés görgetése ~50 fps** (2026-11-24)
  - A mérések szerint ez a két terület nem javult eleget; részletek és a kipróbált megoldások: `server/docs/PERF.md` („Ami nem javult vagy nyitva maradt”).
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
  - A 253. sor állítása a kurzor-pajzshoz igazodott (`data-drag-cursor` húzás közben már nincs a vásznon); a teszt ugyanott bukik el, ahol a teljesítményjavítás előtt.


