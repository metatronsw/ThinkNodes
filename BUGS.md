# Hibák

Minden munkamenet elején át kell nézni, és a nyitott hibákkal foglalkozni kell (AGENTS.md).

## Nyitott

- **A Swift `JSONDecoder` egyes lebegőpontos literálokat 1 ulp pontatlansággal olvas (macOS 13 Foundation)** (2026-11-24, tizedes-audit)
  - Példa: `0.0020293361140076467` → `0.0020293361140076476`. A `.tntable` értékei a szerveren az utolsó bináris jegyben elcsúszhatnak (a kiírt 15 jegyre nincs hatással).
  - Teszt: `platformJSONDecoderDoublePrecision` (figyelmeztet). Teendő: ellenőrizni élesben (Fedora, swift-foundation); ha ott is pontatlan, saját számolvasó a `.tntable`-höz. Részletek: server/docs/EXCEL.md 12. fejezet.

- **Sötét kitöltésű szövegfájl- és táblázatdobozon a tartalom olvashatatlan** (2026-11-24, a táblázat tesztelésekor)
  - A `.node-note` szövegszíne rögzített sötét (`rgb(24, 35, 53)`), a doboz kitöltése viszont a palettából jön; a szerver által automatikusan felvett fájldobozok (`fill: "@2"`) sötét témában sötétek, így a tartalom nem látszik (pl. `MassTest/TablaTeszt`: `lista.csv`, `feltoltott.tntable`).
  - Dönteni kell: a fájl „lapja” mindig világos papír legyen (a hajtott sarkú lap mintájára), vagy a szövegszín kövesse a doboz kitöltését.

- **`Tests/Editor/gestures.mjs` elbukik** – már a TODO.md-ben is szerepel (`ownUnderlay`); a táblázat munka előtt is így volt (2026-11-24, ellenőrizve az eredeti `editor.js`-szel).
  - `markdownEditor` `adjust`: a teszt hamis DOM-jában a `getComputedStyle` / `el.style` hiányzik (`reading 'height'`).
  - 311. sor: `button("Mentés")` nem található (a Mentés gomb azóta átalakult).


