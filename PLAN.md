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

### C1 – Komponensbontás (folyamatban)
- **1. lépés kész:** `NodeView` dobozonként. Gépelés 300 doboznál: 15,8 ms → 1,1 ms leütésenként (medián; p90 32 → 1,6 ms).
- **2. lépés kész:** `EdgeView` vonalanként, a fogantyúk külön `HandleLayer` komponensben. Húzás 300 doboz/280 vonal mellett: 18,2 ms → 5,5 ms mozdulatonként (medián). A maradék nagy része a `HandleLayer` (minden vonal két fogantyúja minden képkockán) — következő lépés.
- **3. lépés kész:** a fogantyúk vonalanként (`EdgeHandles`), a csomópont-fogantyúk külön (`JunctionHandles`). Húzás: 5,5 ms → 2,1 ms mozdulatonként (összesen 18,2 → 2,1 ms).
- **4. lépés kész (C2/C3):** a nézet (`ViewLayer`) külön komponens, így nagyításkor/pásztázáskor nem rajzolódik újra a fejléc, a panelek és az ellenőrző; a fogantyúk mérete és a vonalak találati szélessége 25%-os nagyítási lépcsőkben (`zoomStep`) változik. Nagyítási lépés 300 doboznál: JS 11 ms → átlag 2,4 ms (medián 0,7 ms), böngésző-elrendezés 19 → 16 ms; összesen ~30 → ~19 ms. (Egy CSS-változós `--zoom` változat is ki lett próbálva: a teljes jelenet újrastílusozása miatt lassabb volt.)
- **Maradék nagyítási költség a böngészőben:** ~16 ms elrendezés lépésenként, főleg a 300 doboz szövegének újraszámolása. Következő lehetőségek: nagyítás közben az árnyékok/szűrők kikapcsolása (C4), csak a látható dobozok renderelése (C6).
- Ma a vászon egyetlen komponens (`CanvasScene`): bármely változásnál (gépelés egy dobozban, húzás, kijelölés, nagyítás) minden doboz és vonal virtuális DOM-ja újraépül és összehasonlítódik.
- Terv: `NodeView` és `EdgeView` komponens, csak a saját adataitól függő propokkal (doboz objektum, kijelöltség, foglaló résztvevő, húzási eltolás). Így gépeléskor csak a szerkesztett doboz, húzáskor csak a mozgatott doboz és a hozzá kötött vonalak rajzolódnak újra.
- A globális állapotot (gesture, peers, batch, marquee) a szülő bontsa le dobozonkénti egyszerű értékekre, hogy egy doboz ne függjön a teljes listától.
- Ellenőrzés: `Tests/Editor/gestures.mjs`, plusz egy ismételhető mérőszkript (300/1000 doboz, gépelés, húzás, nagyítás).

### C2 – Nagyítás ne rajzolja újra a jelenetet
- A fogópontok mérete és néhány vonalvastagság a nagyítástól függ (`10 / zoomScale`), ezért minden nagyítási lépés a teljes jelenetet újrarajzolja.
- Terv: a nagyításfüggő elemek külön kis komponensben (fogópontok), vagy CSS-változóval (`--k`) és `vector-effect: non-scaling-stroke`-kal.

### C3 – Pásztázás és nagyítás közvetlenül a DOM-on
- **Kész:** görgetéses nagyítás és egérrel pásztázás közben csak a vászon-SVG CSS-transzformja változik (`previewView`), a nézet a d3 `end` eseménykor véglegesedik (`commitView`); a d3-zoom a nem transzformált `.canvas-area` szülőn figyel. Mellékhatás: nagyítás közben a szöveg az elengedésig kicsit elmosódott lehet; kicsinyítéskor a réteg szélén a munkalap háttérszíne látszik rács nélkül. A programozott nézetváltás (Mind, keresés, érintéses csippentés, szóköz+húzás) azonnal véglegesedik, mint eddig.
- **Külön rácsréteg (kész):** a háttérrács a vászon alatti saját SVG-ben van (`GridLayer`), a mintája mozdulat közben közvetlenül az élő nézetet követi, így pásztázáskor/kicsinyítéskor a réteg szélén is látszik. A munkalap háttérszíne a `.canvas-area` háttere.
- **Túlméretezett vászonréteg (kész):** a vászon-SVG minden irányban a látható terület felével nagyobb (2× szélesség és magasság, `overscan`), mindig külön grafikus réteg (`will-change: transform`); kisebb pásztázásnál a már kirajzolt dobozok csúsznak be, nincs levágás. A pontok a jelenet origójához (`sceneOrigin`) mérve. Mérve (látható panel, 300 doboz, áttekintő és ráközelített nézet): nagyítás és pásztázás 60 fps vele és nélküle is, a véglegesítő képkocka 33 ms vs. 33 ms — mérhető többletköltség nincs.
- **Hibrid véglegesítés (kész):** ha a mozdulat közben a látható terület kilógna az előre kirajzolt rétegből, abban a képkockában azonnal valódi újrarajzolás jön, így levágott doboz sosem látszik. Mérve: 2400 px-es pásztázás ráközelített nézetben → 0 levágott képkocka, 2 közbenső újrarajzolás, leglassabb képkocka 18,8 ms.
- **Puffer mérete (döntés: oldalanként a látható méret 1×-e, a réteg 3× széles és magas):** mérve látható panelen, ráközelített nézetben, 300 doboz:

  | | puffer 0,5 (réteg 2×) | puffer 1,0 (réteg 3×) | puffer 1,0, rács a rétegben |
  |---|---|---|---|
  | kis pásztázás (600 px) | 60 fps, 0 újrarajzolás | 60 fps, 0 | 60 fps, 0 |
  | nagy pásztázás (2400 px) | 60 fps, 2 újrarajzolás | 60 fps, 1 | 60 fps, 1 |
  | kicsinyítés (30 lépés) p90 / max | 32,2 / 33,2 ms, 3 újrarajzolás | 17,7 / 34,1 ms, 2 | 17,8 / 33,4 ms, 2 |
  | levágott képkocka | 0 | 0 | 0 |
  | GPU-folyamat memóriája (footprint) | 218 MB (grafika 81 MB) | 218 MB (grafika 81 MB) | 249 MB (grafika 83 MB) |
  | JS-heap | 14,9 MB | 15,3 MB | – |

  A nagyobb puffer mérhető memória-többlet nélkül ritkítja az újrarajzolást: a böngésző a rétegnek csak a látható környékét raszterizálja előre. A külön rácsréteg marad: a sebesség és a memória azonos, de mozdulat közben a rács mindig pontos méretű (a rétegben a pontok a nagyítással együtt nőnének/zsugorodnának, és elengedéskor visszaugranának).
- A d3 zoom minden képkockán a Vue-állapotot (`view`) írja, ez a gyökér render függvényét futtatja (rács, defs, vezérlők).
- Terv: mozdulat közben a d3 közvetlenül a vászon `<g>` transzformációját írja; a Vue-állapot csak a mozdulat végén (vagy ritkítva) frissül.

### C4 – Árnyékok, elmosott és áttetsző dobozok
- **1. lépés kész:** mozgás közben (pásztázás, nagyítás, húzás) `data-moving` jelzés a munkaterületen (DOM-attribútum, nem Vue-állapot); ilyenkor ki van kapcsolva az elmosott doboz szűrője, a kijelölés- és vonal-glow, a keresési jelölés és az üvegpanelek `backdrop-filter`-e, a mozgás végén visszaállnak. A kijelölés pulzálása csak az átlátszóságot animálja, nem a `drop-shadow` szűrőt (az folyamatos újrafestést okozott). Böngészőben ellenőrizve (be/kikapcsolás), a festési idő rejtett panel miatt nem volt mérhető.
- Az árnyék (Kiemelés) és az áttetsző doboz már eddig is szűrő nélküli volt.
- Az SVG `filter` (árnyék, `feGaussianBlur`) dobozonként drága, és nagyításkor minden képkockán újraszámolódik.
- Terv: árnyékhoz előre elmosott alakzat vagy egyszerű eltolt, áttetsző kitöltés szűrő nélkül; elmosott háttérhez egy közös szűrő, kisebb `stdDeviation`; húzás/nagyítás közben a szűrők ideiglenes kikapcsolása (`.is-moving` osztály). Mérni kell, melyik hozza a legtöbbet.

### C5 – Gépelés
- **1. lépés kész:** mezőszerkesztés (gépelés) közben a mentés a szünetre vár (0,5 mp), de legfeljebb 2 mp-et; a mező elhagyásakor azonnal ment. Mérve (300 doboz, 32 leütés ~8 karakter/s): teljes mentés 16 → 2 db, feltöltés 1,5 MB → 188 KB, presence-ébresztés 16 → 2; a doboz szövege továbbra is ~100 ms-on belül (p90) frissül. Oldalbezáráskor a meglévő figyelmeztetés véd a mentetlen változásra.
- **Döntés (2026-11-23):** a doboz-markdown feldolgozása kliensre kerül (commonmark.js, a szerver cmark-gfm-jével azonos CommonMark-specifikáció), közös tesztkészlettel (bemenet → elvárt blokkok) a Swift- és a JS-oldalon; a szerver a megtekintőhöz, előnézetekhez és exporthoz marad. Az A1+A2 után következik.
- Minden leütés: `modified()` → `recordChanges()` a teljes munkalap JSON-másolatával és diffjével, majd 70 ms múlva teljes mentés, és a szerveren a szövegtördelés kérése.
- Terv: mezőszerkesztés közben csak a mező végén rögzíteni a visszavonási lépést (részben már így van), a mentést ritkítani (pl. 300 ms tétlenség), a szöveg-előfeldolgozást (`/api/text/canvas`) csak a szerkesztett dobozra kérni. C1 után a leütés csak egy dobozt rajzol újra.

### C6 – Csak a látható dobozok renderelése
- 300 doboznál a C3 után nem szükséges (minden mozdulat 60 fps). Nagyobb (1000+) munkalapnál újramérni.
- Nagy vásznon a nézeten kívüli dobozokat nem kell renderelni. Bonyolultabb (vonalak, konténerek), C1 után mérni, kell-e.

### C7 – Kisebb d3
- A teljes d3 (280 KB) csak a zoom miatt töltődik be; saját `d3-zoom` + `d3-selection` build. Csak betöltési idő.

### C8 – Tooltip
- Átfedő szövegű dobozra minden rámutatáskor `/api/text` kérés megy; gyorsítótárazni kell.

## A) Szerver

### A1 – Memóriabeli gyorsítótár
- **Kész:** munkalapok (dekódolva + validálva), mappánkénti házirendek és webhely-beállítások gyorsítótára a tárolóban (`WorksheetStore`), a fájl módosítási ideje + mérete szerint érvényesítve, a tárolón keresztüli írás azonnal érvényteleníti. Mérve (debug build, 300 dobozos munkalap, kérésenként medián): presence 49 → 6 ms, főoldal 50 → 8,5 ms, előnézeti kép 46 → 5 ms, munkalap-API 66 → 24 ms, megtekintő oldal 670 → 590 ms.
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

### Valós képkockaidők (2026-11-23, látható böngészőpanel, 300 doboz / 280 vonal, 100 elmosott, 100 áttetsző, 60 kiemelt)

| Állapot | Húzás (medián / p90) | Nagyítás (medián / p90) |
|---|---|---|
| Optimalizálás előtt (`e2e2a65`) | 33,3 / 49 ms (~30 fps) | 50,1 / 66,7 ms (~20 fps) |
| C1–C3 után (`7a50d10`) | 32,6 / 33,9 ms (~30 fps) | 33,4 / 50,6 ms (~30 fps) |
| C4/1 után (`13ce09a`) | 16,7 / 17,5 ms (60 fps) | 33,4 / 50 ms (~30 fps) |
| C3 GPU-nagyítás után | **16,6 / 17,4 ms (60 fps)** | **16,7 / 17,5 ms (60 fps)** |

Következtetés: húzásnál a C1–C3 a JS-t, a C4 a festést szüntette meg szűk keresztmetszetként. Nagyításnál a szűrők és a szöveg sem számított (kísérlet: szöveg helyett sávok — nincs változás; rács, vonalak, fogantyúk elrejtése — nincs változás): maga az SVG `transform` változása az egész jelenet újraelrendezését kérte (~20 ms). Megoldás: mozdulat közben a vászon-SVG HTML-rétegként, CSS-transzformmal skálázódik/tolódik a grafikus kártyán, a valódi nézet a mozdulat végén egyszer frissül.

Minden lépés előtt és után ugyanaz a mérés: 300 és 1000 dobozos tesztmunkalap ideiglenes adatkönyvtárban (sosem a valódi `Projects`), mért értékek: gépelés leütésenkénti ideje, húzás képkockaideje, nagyítás képkockaideje, távoli frissítés főszál-blokkolása.
