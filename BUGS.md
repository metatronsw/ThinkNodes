# Hibák

Minden munkamenet elején át kell nézni, és a nyitott hibákkal foglalkozni kell (AGENTS.md).

## Nyitott

- **Safari 18: a szövegfájl- / táblázatdoboz görgetősávja egérrel nem húzható (a görgő működik)** (2026-11-24) – javítás bent, Safariban megerősítésre vár
  - Feltételezett ok: a görgetősáv-felismerés (`scrollbarPress`) a DOM-ból (`getBoundingClientRect`) számolt, ami Safariban a foreignObject-beli elemeknél nem követi a vászon nagyítását/eltolását; így a doboz húzása (`pressNode`: `preventDefault` + pointer capture) elkapta a kattintást.
  - Javítás: a sáv a doboz vászonbeli helyéből és az egér vászonkoordinátájából számolódik (`Public/editor.js`). Chromiumban ellenőrizve; Safariban nem tudtam kipróbálni (a WebDriverhez a „Távoli automatizálás engedélyezése” kell). Ha Safariban továbbra sem megy, az ok más.

- **A Swift `JSONDecoder` egyes lebegőpontos literálokat 1 ulp pontatlansággal olvas (macOS 13 Foundation)** (2026-11-24, tizedes-audit)
  - Példa: `0.0020293361140076467` → `0.0020293361140076476`. A `.tntable` értékei a szerveren az utolsó bináris jegyben elcsúszhatnak (a kiírt 15 jegyre nincs hatással).
  - Teszt: `platformJSONDecoderDoublePrecision` (figyelmeztet). Teendő: ellenőrizni élesben (Fedora, swift-foundation); ha ott is pontatlan, saját számolvasó a `.tntable`-höz. Részletek: server/docs/EXCEL.md 12. fejezet.

- **`Tests/Editor/gestures.mjs` elbukik** – már a TODO.md-ben is szerepel (`ownUnderlay`); a táblázat munka előtt is így volt (2026-11-24, ellenőrizve az eredeti `editor.js`-szel).
  - `markdownEditor` `adjust`: a teszt hamis DOM-jában a `getComputedStyle` / `el.style` hiányzik (`reading 'height'`).
  - 311. sor: `button("Mentés")` nem található (a Mentés gomb azóta átalakult).


