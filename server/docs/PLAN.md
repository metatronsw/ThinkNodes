# Teljesítmény- és architektúraterv — hátralévő munka

Állapot: 2026-11-23. Ami már kész, a git-előzményekben és a commit-üzenetekben van. A hibák a BUGS.md-ben vannak.

## Alapelvek

- **Megtekintő: minél kevesebb JavaScript.** Szerveroldali HTML + SVG; a JS csak kiegészítés (élő frissítés, jelenlét).
- **Szerkesztő: minél gyorsabb kliensoldali munka.** A szerver csak az előnézetet, exportot és a mentést kezeli.
- **Adatkönyvtár: egyelőre csak a szerver írja.** Fájlrendszer-figyelés később.
- **Mentés kétféle:** az aktuális állapot folyamatosan megy (A3), a „Mentés” a teljes munkalapot rögzíti.
- **Minden lépés előtt és után ugyanaz a mérés:** 300 és 1000 dobozos tesztmunkalap ideiglenes adatkönyvtárban (sosem a valódi `projects`).

## Hátra van

### Szerver (A)

- **A2 – Presence betöltés nélkül (elhalasztva).** Csak akkor kell, ha sok egyidejű szerkesztőnél újra szűk keresztmetszet lesz: a szoba tartsa a revíziót és a doboz/vonal azonosítókat. Előtte újramérni.
- **A3 – Folyamatos mentés + rögzített állapotok.**
  - Aktuális állapot: a változáslista (`editor-history.js` már előállítja) megy a szervernek a teljes munkalap helyett; a válasz csak a revízió. A szerver memóriában alkalmazza, és ritkítva írja lemezre.
  - Mentés = rögzítés: a teljes munkalap pillanatképe; az utolsó 10 megmarad és visszaállítható.
  - Tisztázandó: a rögzített állapotok helye (pl. `.versions/`), a visszaállítás jogosultsága, a mellékletek verziózása. Részletes tervezés kell előtte.
- **A4 – Tömörítés és cache.** Gzip a válaszokra; verziózott statikus URL-ek hosszú cache-sel (ma minden fájl `no-cache`).
- **A5 – Főoldal.** A projektkártyák számlálója minden munkalapot betölt. A gyorsítótár után újramérni; ha még lassú, mappaszámlálással megoldani.
- **A6 – Változások küldése WebSocketen.** Távoli mentéskor a többi kliens ma a teljes munkalapot tölti le; A3 után a változáslista mehet a meglévő WebSocketen.
- **Release buildben újramérni** a megtekintő idejét (debug: ~211 ms). Ha a `plainFirstLine` (reguláris kifejezés) vagy a tördelés a fő költség, azt kell gyorsítani.

### Kliens (C)

- **C9 – Célzott újrarajzolás, réteg- és rácskezelés (kész a `perf` ágon, 2026-11-24).** Mérések, változatok, kapcsolók és nyitott tételek: `docs/PERF.md`.
- **C4 – Árnyékok és átlátszó dobozok (maradék).** A mozgás közbeni szűrő-kikapcsolás kész. Hátra: mérni, hogy a dobozonkénti elmosás (`feGaussianBlur`) festési költsége állandó nagyításnál jelentős-e. Ha igen, elmosott háttér helyett közös szűrő vagy előre elmosott alakzat.
- **C7 – Kisebb d3.** A teljes d3 (280 KB) csak a zoom miatt töltődik be; saját `d3-zoom` + `d3-selection` build. Csak betöltési idő.
- **C8 – Tooltip.** Átfedő szövegű dobozra minden rámutatáskor `/api/text` kérés megy; gyorsítótárazni kell.

### Megtekintő (B)

- **B1 – JS nélkül is teljes értékű.** Navigáció, letöltések, jegyzet-linkek `noscript` mellett. Ellenőrizni.
- **B2 – Élő frissítés kisebb adattal.** Ma a teljes oldal HTML-je jön le, és a kliens szekciónként cseréli; elég lenne csak a vászon SVG-t (vagy a változott szekciót) lekérni.

## Sorrend

1. Release-mérés (megtekintő, főoldal) — eldönti, mi a következő szerveroldali lépés
2. A3 (tervezés után) → A6
3. A4, A5 (a release-mérés alapján)
4. C4 maradék mérése, C8, C7
5. B1, B2
6. A2, ha a mérés szükségessé teszi
