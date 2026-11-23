# Teljesítmény- és architektúraterv

Állapot: 2026-11-23. A döntések a felhasználóval egyeztetve. A hibák külön a BUGS.md-ben.

## Alapelvek (döntések)

- **Megtekintő: minél kevesebb JavaScript.** A megtekintő szerveroldali HTML + SVG; a JS csak kiegészítés (élő frissítés, jelenlét, sorkizárás finomítása). JS nélkül is használható legyen.
- **Szerkesztő: minél gyorsabb kliensoldali munka.** A szerkesztő interaktív vászon marad a böngészőben; a szerverre csak az kerül, ami nem a gépelés/húzás útjában áll (markdown-feldolgozás, export, előnézet). A tördelés vagy a panelek szerverre vitele minden leütésnél körutazást jelentene, ezért nem.
- **Adatkönyvtár: egyelőre csak a szerver írja.** Fájlrendszer-figyelés később; addig a gyorsítótár a fájl módosítási idejével és méretével ellenőriz.
- **Mentés kétféle (lásd A3):** az *aktuális* állapot folyamatosan, optimalizáltan mentődik; a *Mentés* a teljes munkalap rögzítése visszaállítható állapotként.
- **Sorkizárás: szokásos** (a bekezdés utolsó sora és az egysoros bekezdés balra zárt).
- **Tördelés csak a Text tartalmú dobozokra.** Minden más felirat (megjegyzés, fájlnév, link, csomópontcímke, vonalcímke) a legegyszerűbb módon, egy sorban jelenik meg, túl hosszan „…”-tal rövidítve.

## Felhasználó által jelzett lassúságok

Gépelés, árnyékok és átlátszó (elmosott/áttetsző) dobozok, nagyítás. Elsőként a **C1** készül.

## Már elkészült (2026-11-23)

- Bcrypt a zárakon kívül (feloldás, jelszó beállítása) — a szerver nem áll meg hash-elés idejére.
- Fájlműveletek és SVG-renderelés a thread poolon az event loop helyett.
- Szerkesztő: mentés/távoli frissítés után a változatlan dobozok megtartják az objektumazonosságukat (`keepUnchanged`) — 300 doboznál frissítésenként 60–80 ms főszál-blokkolás → ~0 ms.
- Sorkizárás szóköztágítással (`Public/justify.js`) betűritkítás helyett; kalibrált, szélességalapú tördelés.

## C) Kliens — szerkesztő (elsőbbség)

### C1 – Komponensbontás (következő lépés)
- Ma a vászon egyetlen komponens (`CanvasScene`): bármely változásnál (gépelés egy dobozban, húzás, kijelölés, nagyítás) minden doboz és vonal virtuális DOM-ja újraépül és összehasonlítódik.
- Terv: `NodeView` és `EdgeView` komponens, csak a saját adataitól függő propokkal (doboz objektum, kijelöltség, foglaló résztvevő, húzási eltolás). Így gépeléskor csak a szerkesztett doboz, húzáskor csak a mozgatott doboz és a hozzá kötött vonalak rajzolódnak újra.
- A globális állapotot (gesture, peers, batch, marquee) a szülő bontsa le dobozonkénti egyszerű értékekre, hogy egy doboz ne függjön a teljes listától.
- Ellenőrzés: `Tests/Editor/gestures.mjs`, plusz egy ismételhető mérőszkript (300/1000 doboz, gépelés, húzás, nagyítás).

### C2 – Nagyítás ne rajzolja újra a jelenetet
- A fogópontok mérete és néhány vonalvastagság a nagyítástól függ (`10 / zoomScale`), ezért minden nagyítási lépés a teljes jelenetet újrarajzolja.
- Terv: a nagyításfüggő elemek külön kis komponensben (fogópontok), vagy CSS-változóval (`--k`) és `vector-effect: non-scaling-stroke`-kal.

### C3 – Pásztázás és nagyítás közvetlenül a DOM-on
- A d3 zoom minden képkockán a Vue-állapotot (`view`) írja, ez a gyökér render függvényét futtatja (rács, defs, vezérlők).
- Terv: mozdulat közben a d3 közvetlenül a vászon `<g>` transzformációját írja; a Vue-állapot csak a mozdulat végén (vagy ritkítva) frissül.

### C4 – Árnyékok, elmosott és áttetsző dobozok
- Az SVG `filter` (árnyék, `feGaussianBlur`) dobozonként drága, és nagyításkor minden képkockán újraszámolódik.
- Terv: árnyékhoz előre elmosott alakzat vagy egyszerű eltolt, áttetsző kitöltés szűrő nélkül; elmosott háttérhez egy közös szűrő, kisebb `stdDeviation`; húzás/nagyítás közben a szűrők ideiglenes kikapcsolása (`.is-moving` osztály). Mérni kell, melyik hozza a legtöbbet.

### C5 – Gépelés
- Minden leütés: `modified()` → `recordChanges()` a teljes munkalap JSON-másolatával és diffjével, majd 70 ms múlva teljes mentés, és a szerveren a szövegtördelés kérése.
- Terv: mezőszerkesztés közben csak a mező végén rögzíteni a visszavonási lépést (részben már így van), a mentést ritkítani (pl. 300 ms tétlenség), a szöveg-előfeldolgozást (`/api/text/canvas`) csak a szerkesztett dobozra kérni. C1 után a leütés csak egy dobozt rajzol újra.

### C6 – Csak a látható dobozok renderelése
- Nagy vásznon a nézeten kívüli dobozokat nem kell renderelni. Bonyolultabb (vonalak, konténerek), C1 után mérni, kell-e.

### C7 – Kisebb d3
- A teljes d3 (280 KB) csak a zoom miatt töltődik be; saját `d3-zoom` + `d3-selection` build. Csak betöltési idő.

### C8 – Tooltip
- Átfedő szövegű dobozra minden rámutatáskor `/api/text` kérés megy; gyorsítótárazni kell.

## A) Szerver

### A1 – Memóriabeli gyorsítótár
- Munkalapok (dekódolt + validált), a `.settings.json` és a házirendek gyorsítótára; érvényesség: módosítási idő + méret, írásnál közvetlen frissítés.
- Ma minden kérés lemezről olvas, a munkamenet-ellenőrzés is (`authenticatedUser` → `settings.json`).

### A2 – Presence betöltés nélkül
- A szoba tartsa a revíziót és a doboz/vonal azonosítókat; mentéskor frissül. Ma minden `poll`/`select`/`ping` teljes `store.load`, N résztvevőnél egy mentés N betöltést indít (BUGS.md).

### A3 – Folyamatos mentés + rögzített állapotok
- **Aktuális állapot:** minden mozgatás/szerkesztés változáslistaként (az `editor-history.js` már előállítja) megy a szervernek, nem a teljes munkalap; a válasz csak a revízió. A szerver memóriában alkalmazza, és ritkítva írja lemezre.
- **Mentés = rögzítés:** a teljes munkalap pillanatképe; az utolsó 10 megmarad, később bármelyik visszaállítható (a mostani „visszaállítási pont” általánosítása). Lomtár-szemantika a fájlokra marad.
- Tisztázandó: a rögzített állapotok tárolási helye (pl. `.versions/`), a visszaállítás jogosultsága, és hogy a fájlmellékletek verziózódnak-e.

### A4 – Tömörítés és cache
- Gzip a válaszokra, verziózott statikus URL-ek hosszú cache-sel (ma minden fájl `no-cache`, betöltéskor ~15 újraellenőrzés).

### A5 – Főoldal
- A projektkártyák számlálója minden munkalapot betölt; A1-gyel vagy mappaszámlálással megszűnik.

### A6 – Változások küldése WebSocketen
- Távoli mentéskor a többi kliens ma a teljes munkalapot tölti le; A3 után a változáslista mehet a meglévő WebSocketen.

## B) Megtekintő (kevés JS)

- B1 – JS nélkül is teljes értékű legyen (navigáció, tooltipek helyett jegyzet-link, letöltések). Ellenőrizni `noscript` mellett.
- B2 – Élő frissítéskor ma a teljes oldal HTML-je jön le, és a kliens szekciónként cseréli; elég lenne csak a vászon SVG-t (vagy a változott szekciót) lekérni.
- B3 – A sorkizárás JS nélkül balra zárt; ez elfogadott.

## Sorrend

1. C1 (komponensbontás) → C2, C3 (nagyítás/pásztázás) → C4 (árnyék/átlátszóság) → C5 (gépelés)
2. A1 + A2 (szerver-gyorsítótár, presence)
3. A3 (folyamatos mentés + 10 rögzített állapot) — részletes tervezés előtte
4. A4, B1–B2, majd A6, C6–C8

## Mérés

Minden lépés előtt és után ugyanaz a mérés: 300 és 1000 dobozos tesztmunkalap ideiglenes adatkönyvtárban (sosem a valódi `Projects`), mért értékek: gépelés leütésenkénti ideje, húzás képkockaideje, nagyítás képkockaideje, távoli frissítés főszál-blokkolása.
