# A vászonszerkesztő teljesítménye – mérések és változatok (2026-11-24)

## Irányelvek a további fejlesztéshez (AI és ember) – kötelező

Cél: a szerkesztő maximális teljesítménye. Olcsó témák maradjanak olcsók; drága látvány csak téma-függően, mért költséggel.

**Szabályok – ezeket ne írd át mérés nélkül:**
1. **Nyugalomban nincs munka.** Mozdulat nélkül nem futhat végtelen animáció, időzítő vagy rAF-ciklus, ami rajzoltat. Kivétel csak a tartalom-animáció (2.) és a saját kijelölés fénye.
2. **Tartalom-animáció (doboz, vonal) a szerkesztőben csak CSS:** `app.css` „Tartalom-animációk”, `steps()`, minden szakasz 50 ms egész többszöröse, közös ütem (`editor.js queueMotionAlign`). SMIL a szerkesztőben tilos (Safariban animációnként 14–19% CPU). Csak `transform`, `opacity`, `stroke-width`, `stroke-dashoffset`, `offset-distance` animálható; CSS `d` tilos (Safari). Nincs elemenként eltérő ütem (pl. téma sebességszorzó).
3. **A letölthető SVG önálló:** SMIL maradhat benne; a látvány egyezzen a szerkesztővel, az időzítés nem.
4. **Kapcsolók:** minden új folyamatos animáció kerüljön a `[data-still]` („Animációk leállítása”), minden díszítő háttér / textúra a `[data-plain]` („Díszítő háttér kikapcsolása”) szabály alá. Díszítő háttér nem animált.
5. **Nézet:** mozdulat közben csak a réteg CSS-transzformja változik; a `view` rögzítése halasztott (`wheelCommit`, `panCommit`). A vászon gyökerén mozdulat közben ne változzon stílus / attribútum; `transform: none ↔ matrix` váltás tilos (`restingTransform`).
6. **Eseménykezelő (pointerdown stb.) kritikus útján nincs drága szinkron munka:** pl. `new AudioContext()` (290 ms volt), nagy fetch / parse, ciklusban kényszerített elrendezés (`getBoundingClientRect`, `getScreenCTM`), első modulbetöltés.
7. **Célzott újrarajzolás:** doboz / vonal csak a saját állapotát olvassa (`nodeUi` / `edgeUi` / `syncUi`); globális állapot (`view`, `gesture`, kijelölés) olvasása rajzoláskor minden elemet újrarajzoltat.
8. **CSP** (`style-src 'self'`): beszúrt `<style>` és inline `style` attribútum nem működik; dinamikus stílus Vue `style`-lal vagy CSSOM-mal.

**Mérés – minden rajzolást, animációt, témát, effektet vagy eseménykezelőt érintő változás után:**
- Böngésző: **valódi Chrome (elsődleges) és Safari.** Nem hiteles: a beépített böngészőpanel, a fej nélküli Chromium (szoftveres GPU), a takart ablak (a Safari ott a CSS-animációt leállítja, a SMIL-t nem).
- Szerver: release build (`deploy/build.sh --no-pull`), `run.sh --port:8888 --test`.
- Lapok: a legdrágább téma sok animációval (Liquid Glass lap), valamint egy nagy lap (`p300` / `p1000`: `node Tests/Perf/make-data.mjs`).
- **Üresjárat:** betöltés, 4 mp várakozás, 8–10 mp CPU a böngésző teljes folyamatfáján (Chrome: renderer + GPU + böngésző; Safari: WebContent + WindowServer). Elvárás: animáció nélkül ~0–2%; Liquid Glass lap ≤ ~25%; „Animációk leállítása” mellett ~0%.
- **Akadás:** frissen indított böngésző (hideg), majd újratöltés (meleg): első kijelölés, első mozgatás, **összetett pásztázás 100%-on** (az egész vászon bejárása oda-vissza, húzásonként rántás + lassú finomhúzás). Képkockaidő rAF-ből. Elvárás: 0 képkocka 50 ms fölött, lenyomás → képkocka < 50 ms.
- **Ha nem teljesül:** kizárásos keresés. Változatonként kapcsolj ki egy forrást (animációk szüneteltetése, elem eltávolítása, CSS-szabály), és mérj újra; a fogyasztó az, amelyiknek a kikapcsolása visszaadja a nullát. Utána nyomkövetés (CDP Tracing / JS-profil) a hosszú feladatokra.
- Buktatók: a beszúrt `<style>`-t a CSP tiltja (CSSOM / `Page.setBypassCSP`); a saját rAF-számláló maga is képkockát kér (CPU-mérésnél ne fusson); mérés közben ne fusson másik böngésző-teszt; a Safari WebDriverhez „Távoli automatizálás engedélyezése” kell.

**Jelenlegi eszközök (`Tests/Perf`) – mire valók, mikor avulnak el:**

| Eszköz | Mire | Elavul, ha |
|---|---|---|
| `chrome.mjs` | valódi Chrome külön profillal, CDP, CPU a folyamatfán | a Chrome helye (`TN_CHROME`) vagy a CDP változik |
| `chrome-idle.mjs`, `safari-idle-wd.py` + `Public/bench-idle.js` | üresjárati CPU változatonként (`?bench=NÉV&list=NÉV&hold=1`) | a kikapcsolt elemek osztályai változnak (`.canvas-aurora`, `.node-motion`, `wire-motion-*`, `.canvas-grid-draw`) |
| `chrome-pan.mjs`, `safari-pan.py` + `pan-plan.js` | összetett pásztázás 100%-on, hideg / meleg kör (`TN_TRACE=kör`: hosszú feladatok) | a pásztázás nem üres vászon húzása, vagy megszűnik a `.canvas-area.__zoom` (d3) |
| `chrome-hitch.mjs`, `chrome-first.mjs` | első kijelölés / mozgatás / pásztázás; a legelső kattintás profilja és kérései | változik a `recorder.js` felülete (`__perf.nodes`, `emptyPoint`, `latencies`) |
| `editor-anim-probe.js` | futnak-e a `tn-*` animációk, igazítva vannak-e, a pötty a vonalon van-e | változnak az animációk osztály- vagy kulcskockanevei |
| `anim-probe.*` + `Public/bench-anim.svg` | CSS-animációs képességek böngészőnként | csak új animációtípus bevezetésekor kell |
| `perf.py` (+ `summary.py`) | régi Safari-forgatókönyvek nagy lapon (`p300`) | a régi forgatókönyvek elemazonosítói változnak |
| `idle.mjs`, `trace-idle.mjs`, `layers.mjs` | fej nélküli Chromium: csak trend és nyomkövetés, abszolút szám nem | – |
| `safari-idle.py`, `safari-url-idle.py` | WebDriver nélkül (csak ha a Safari elöl van) / tetszőleges címek | – |

Ha egy eszköz hibát ad, vagy egy változat `[0 animáció]`-t, hiányzó elemet vagy gyanúsan 0%-ot jelez, előbb az eszközt kell javítani, csak utána szabad a számokban megbízni.

---


A `perf` ágon készült, 2026-11-24-én beolvasztva a `main`-be az alapbeállításokkal. Mérés: Safari 18.6, release szerver, tesztmód, ideiglenes mérő-adatmappa
(`server/.build/perf-data`, sosem a valódi `projects`). A mérőeszközök: `server/Tests/Perf/`.

## Hogyan mérünk

- `node Tests/Perf/make-data.mjs` – mérőprojektek: `p300` (376 doboz, 434 vonal), `p1000` (1202 doboz, 1434 vonal), `tabla`
  (1000×30-as és kisebb táblázatok). Mindegyikben doboz, konténer, kép, szöveg- és CSV-fájl, táblázat, nyíl, csomópont,
  animált, áttetsző, elmosott és kiemelt elemek.
- Szerver: `.claude/launch.json` → `thinknodes-perf` (release, `--test`, a mérő-adatmappával).
- `python3 Tests/Perf/perf.py CÍMKE --sheet p300 [--only pan_fast,select,…] [--perf '{"overscan":0.5}']` – Safarit vezérel
  WebDriveren (valódi egéresemények), a lapon a `recorder.js` rögzíti a képkockaidőket. Kell hozzá a Safari
  „Távoli automatizálás engedélyezése” beállítása. Összefoglaló: `… | python3 Tests/Perf/summary.py [--timeline]`.
- Többfelhasználós mérés: egy másik böngészőben a `Tests/Perf/peer.js` `peer(30000)` függvénye jelöl ki és húz dobozokat,
  közben `perf.py … --only peers`.
- A szerkesztőben opcionális számlálók vannak (`tally`, `timed`): csak akkor mérnek, ha a rögzítő be van töltve.

Mutatók: fps; a 25 / 50 ms-nál hosszabb képkockák száma (akadás); a leghosszabb képkocka; kijelölésnél a késés a
lenyomástól a következő kirajzolt képkockáig.

## Mit találtunk (Safari)

1. **Minden doboz és vonal újrarajzolódott szinte bármire.** A dobozok és vonalak rajzolása közvetlenül olvasta a közös
   állapotot (kijelölés, jelenlévők, mozdulat, Alt/Ctrl, keresés, konténer-célpontok). Egy doboz húzásakor egérmozdulatonként
   mind a 376 doboz, kijelöléskor a dobozok és vonalak is, másik felhasználó húzásakor másodpercenként 30-szor a teljes vászon.
2. **A vászon gyökerén változó stílus megakadást okoz.** A CSS-transzform be- és kikapcsolása (none ↔ matrix) 40–70 ms; a
   húzás-kurzor attribútuma és a `--zoom-step` változó a teljes vászon (10 000 elem) stílusát újraszámoltatta (30–60 ms).
   Ez adta a pásztázás és húzás eleji/végi akadást és a kijelölés késését. Mátrixról mátrixra váltani ingyen van.
3. **A háttérrács SVG-mintája drága.** Külön rétegként minden képkockában újrafestődött (nagyításnál egyre lassabban: ez volt
   a nagyítás fő lassítója), a vászon rétegében pedig a nézet minden rögzítését ~135 ms-mal lassította.
4. **Transzformált réteg alatt a HTML-tartalom (foreignObject) változása a teljes réteget újrafesti.** Ezért a nyugalmi
   transzform táblázatszerkesztés közben kikapcsol.
5. **Szűrők húzás közben.** A saját kijelölés glow-ja elemenként egy SVG-szűrő; csoport húzásakor ez ~100 ms képkockánként.
6. **Mentés után minden vonal újrarajzolódott** (a vonalak a teljes dobozlistától függtek).
7. Safari-sajátosság: a `position`-nel, `contain`-nel vagy más módon rétegződő elem foreignObject-ben nem kattintható
   nagyított vásznon (ezért nem használható a `contain: strict` gyorsítás).

## Változatok (commitok a `perf` ágon, egymásra épülnek)

| Változat | Tartalom |
|---|---|
| A | Célzott állapot dobozonként és vonalanként (`nodeUi` / `edgeUi`, `syncUi`): csak az érintett elem rajzolódik újra. |
| B | A réteg nyugalomban is transzformált (egységmátrix), a transzform a vásznat körülvevő rétegen van; kurzor-pajzs a gyökér-attribútum helyett; a „mozgás” jelző csak dobozhúzásnál. |
| C | Háttérrács CSS-háttérként saját rétegben; nagyítástól független fogantyúk és találati sávok (`non-scaling-stroke`). |
| D | Egérmozdulatok képkockánként egyszer; vonalanimációk szünetelnek mozgás közben; saját kijelölés glow-ja kikapcsol húzáskor; táblázatszerkesztő: kulcsolt sorok, nagyobb virtuális ablak. |

### Kapcsolók (kísérletezéshez, újratöltés után érvényes)

`localStorage.tnPerf = '{"overscan":1.5}'` a böngésző konzoljában; törlés: `localStorage.removeItem("tnPerf")`.

| Kulcs | Alap | Más értékek |
|---|---|---|
| `overscan` | `1` | 0–3: az előre kirajzolt puffer a látható terület körül, oldalanként (1 = 3×3 képernyőnyi réteg). Nagyobb érték: ritkább újrarajzolás gyors pásztázásnál, több memória (2 = 5×5). |
| `rest` | `true` | `false`: nincs nyugalmi transzform (régi); `"always"`: táblázatszerkesztés közben is marad. |
| `layer` | `"wrapper"` | `"svg"`: a transzform magán az SVG-n (régi). |
| `shield` | `true` | `false`: húzás-kurzor a vászon attribútumával (régi). |
| `moving` | `"gesture"` | `"all"`: pásztázásnál és nagyításnál is (régi); `"none"`: soha. |
| `grid` | `"draw"` | `"css"`: csempézett CSS-háttér (2026-11-24-ig az alap; Safariban nagyítás közben ugrál, mert a csempe mérete egész képpontra kerekül); `"separate"`: külön SVG-réteg (régi); `"canvas"`: a vászon rétegében; `"none"`: nincs rács. |
| `coalesce` | `true` | `false`: minden egérmozdulat külön feldolgozva (régi). |
| `pause` | `true` | `false`: az animációk mozgás közben is futnak (régi). |
| `sharp` | `true` | `false`: 100% fölötti nagyításnál is megmarad az előre raszterizált réteg (gyorsabb mozdulatindítás, de a táblázat / CSV / szövegfájl életlen). |

A régi viselkedéshez legközelebb: `{"rest":false,"layer":"svg","shield":false,"moving":"all","grid":"separate","coalesce":false,"pause":false}`
(az A változat és a nagyítástól független fogantyúk nem kapcsolhatók ki).

## Eredmények (régi = `main` kliens, új = `perf` alapbeállításokkal)

### 300 doboz (`p300`)

| Forgatókönyv | Régi | Új |
|---|---|---|
| Lassú pásztázás | 53,6 fps; 4 képkocka > 50 ms; max 100 ms | 60 fps; 0; max 22 ms |
| Gyors, nagy pásztázás | 49 fps; 4 > 50 ms; max 98 ms | 60 fps; 0; max 20 ms |
| Lassú nagyítás | 16,7 fps; 41 > 50 ms; max 271 ms | 53,4 fps; 3; max 123 ms |
| Gyors nagyítás | 20 fps; 35 > 50 ms; max 331 ms | 46,1 fps; 9; max 91 ms |
| Doboz kijelölése (késés) | 108 ms (max 164) | 26 ms (max 43) |
| Egy doboz húzása | 53,8 fps; 25 képkocka > 25 ms | 60 fps; 2 |
| Téglalapos kijelölés | 39,4 fps; 98 > 25 ms | 55,3 fps; 5 |
| Csoport húzása (15–17 doboz) | 17,4 fps; 119 > 50 ms | 48 fps; 1 |
| Táblázat görgetése (megjelenítés) | 60 fps | 60 fps |
| Táblázat görgetése (szerkesztés) | 43,8 fps; 36 > 25 ms | 51,3 fps; 12 |
| Cella kijelölése (késés) | 44 ms | 44 ms |
| Cellatartomány húzása | 49,5 fps; 41 > 25 ms | 45,7 fps; 49 (nem javult) |
| Másik felhasználó húz, mi figyelünk | 36,1 fps; 62 > 50 ms | 60 fps; 0 |
| … közben pásztázunk | 35,3 fps; 49 > 50 ms | 60 fps; 0 |
| … közben kijelölünk (késés) | 166 ms (max 295) | 23 ms (max 43) |

### 1000 doboz (`p1000`)

| Forgatókönyv | Régi | Új |
|---|---|---|
| Nyugalom (60 animált vonal fut) | 37,3 fps | 47,1 fps |
| Lassú pásztázás | 27,4 fps; 35 > 50 ms; max 272 ms | 53,5 fps; 2; max 133 ms |
| Gyors, nagy pásztázás | 20,7 fps; 19 > 50 ms; max 235 ms | 50,9 fps; 0; max 49 ms |
| Lassú nagyítás | 10,7 fps; 57 > 50 ms; max 427 ms | 43,5 fps; 8; max 194 ms |
| Gyors nagyítás | 9,8 fps; 69 > 50 ms; max 480 ms | 23,9 fps; 32; max 186 ms |
| Doboz kijelölése (késés) | 312 ms (max 356) | 28 ms (max 54) |
| Egy doboz húzása | 31,4 fps; 25 > 50 ms | 56 fps; 2 |
| Téglalapos kijelölés | 17,9 fps; 96 > 50 ms | 41,8 fps; 6 |
| Csoport húzása | 8 fps; 123 > 50 ms | 24,8 fps; 23 |

Újrarajzolások száma 300 doboznál (A változat): 12 kijelölés alatt 14 288 → 17 doboz; egy doboz húzása alatt 24 816 → 63;
mentés után 434 → 1–4 vonal.

### A puffer mérete (B változaton mérve, gyors pásztázás, 300 doboz)

| `overscan` | Újrarajzolás mozdulat közben | Megjegyzés |
|---|---|---|
| 0,25 | 4 | mindegyik egy ~50–60 ms-os képkocka |
| 0,5 | 4 | |
| 1 (alap) | 0–2 | |
| 2 | 0 | 5×5 képernyőnyi réteg: a memóriaigény kb. 2,8-szorosa az alapnak |

Egy újrarajzolás ideje nem függött érdemben a puffer méretétől, ezért a nagyobb puffer ritkább akadást jelent, a memória
rovására. A Safari nem adja meg az eszköz memóriáját (`navigator.deviceMemory` nincs), így automatikus méretezéshez más
jel kell (pl. a képernyő mérete és a `devicePixelRatio`).

## 2026-11-24 esti mérés (Safari 18.6, `p300`)

Új forgatókönyvek (egyszeri mérőszkript, nem része a `perf.py`-nak): egérgörgő-kattanások (200 ms-onként egy esemény), szakaszos nagyítás 100% fölött, táblázat húzása 700 képpont széles dobozzal.

| Forgatókönyv | Előtte | Utána |
|---|---|---|
| Egérgörgős nagyítás, kis nagyítás (minden doboz látszik) | 51,8 fps; 10 képkocka > 50 ms; max 134 ms | 59,5 fps; 1; max 59 ms |
| Egérgörgős nagyítás, 100% fölött | 59,2 fps; 1 > 50 ms | 59,5 fps; 1 |
| Gyors nagyítás (`zoom_fast`) | 46 fps; 6 > 50 ms; max 115 ms | 59,4 fps; 0; max 27 ms |
| Lassú nagyítás (`zoom_slow`) | 46,6 fps; 3 > 50 ms | 50,8 fps; 1 |
| Szakaszos nagyítás 100% fölött | 57,4 fps; 8 > 50 ms | 59,6 fps; 1 |
| Táblázat húzása (első, kijelöléssel) | 39,5 fps; max 382 ms | 59,5 fps; max 47 ms |
| Táblázat húzása (már kijelölve) | 51,6 fps; max 213 ms | 58,8 fps; max 46 ms |

- A nagyítás javulása a görgős rögzítés halasztásából jön (`wheelCommit`, alap 300 ms; 0 = régi viselkedés).
- A rács módja (`draw` / `css`) és az élesítés (`sharp`) egyik forgatókönyvben sem változtatott az eredményen.
- `overscan` 0,5 / 1 / 2 / 3: sebesség azonos; memória (`footprint`): a lap folyamata 163 / 163 / 165 / 165 MB betöltve, a grafikus folyamat 288 MB mindegyiknél. A korábbi „2,8-szoros memóriaigény” ezzel a módszerrel nem látszik (a réteg csempézett, csak a látható rész körül van háttértár).
- Táblázat húzása: a szkriptidő 295 → 6 ms (a táblázat fája nem épül újra képkockánként), a kijelölés- és elengedés-akadás a nagy felületű glow-szűrő elhagyásával szűnt meg.

## Ami nem javult vagy nyitva maradt

- **Nagyítás vége:** a nézet rögzítése nagyítás után még 80–190 ms-os képkocka (új méretarányon minden újrafestődik).
- **Táblázatszerkesztés:** a görgetés ~50 fps, a cellakijelölés késése (44 ms) és a tartomány húzása nem javult. A kizárásos
  próbák (ragadó fejléc, görgetősáv, rétegtranszform) nem mutatták meg az okot.
- **Alt / Ctrl lenyomása** egyszeri ~30 ms (a vászon osztálya változik, teljes stílusszámítás).
- **Animált vonalak nyugalomban:** 60 animált vonalnál 47 fps (mozgás közben szünetelnek).
- **Nem mértük:** csomópont és konténer húzása (a mérőszkript nem találta őket a látható részen), táblázat 1000 dobozos
  lapon, a `tabla` projekt végső futása, Chromium (ott csak működési ellenőrzés volt).
- **Szemmel ellenőrizendő:** a húzás közbeni kurzor (pajzs) Safariban és Chrome-ban; a CSS-rács kinézete a régihez képest;
  a saját kijelölés glow-jának eltűnése húzás közben.

## Betöltés és szerver – 2026-11-25

Mérés: release szerver helyben, `curl`; a megtekintőnél a folyamat mintavételezése (`sample`).

### Elkészült

- **Válasz-tömörítés** a szöveges típusokra (`responseCompression = .enabledForCompressibleTypes`): a szerkesztő első
  betöltése kb. 1 MB-ról a harmadára csökken (`editor.js` 280 → 80 KB, `d3.js` 280 → 93 KB, `vue.js` 103 → 39 KB,
  `app.css` 73 → 18 KB). Ára: `editor.js` kiadása 3 → 10 ms (menet közbeni tömörítés); a 304-es válaszokat nem érinti.
- **Táblázat dobozok HTML-je gyorsítótárazva** (`RenderedTables`, a fájl szövege szerint, 32 tétel / 48 MiB): a megtekintő
  a helyi `a` lapon 87–100 ms → 17 ms. Korábban minden kérés újradekódolta a `.tntable` fájlt (az idő ~70%-a).

### Lehetőségek (nincs megvalósítva)

Szerver:
- **HTTP/2** (`supportVersions`): a szerkesztő kb. 35 fájlt kér (27 modul); HTTP/1.1-en ez böngészőnként 6 párhuzamos
  kapcsolat. Élesben (TLS) kipróbálandó a WebSockettel együtt.
- **Előre tömörített statikus fájlok** (ETag szerint megőrzött gzip): a menet közbeni tömörítés 7 ms / nagy fájl.
- **Megtekintő oldal gyorsítótára** revízió, megjelenítési mód és jogosultság szerint: a maradék 15–17 ms a teljes vászon
  újrarajzolása kérésenként.
- **Fájldoboz törlése mentéskor:** a `usageLocked` a projekt minden munkalapját beolvassa törölt fájlonként; sok lapos
  projektben érdemes egyszer beolvasni kérésenként.
- **Munkalap megnyitása:** a `reconcile` minden betöltéskor kilistázza a mappa mellékleteit; mappa-módosítási idő
  szerint kihagyható.

Kliens:
- **Szűkített d3-csomag – kész (2026-11-25):** `Public/lib/d3-zoom.js` (`zoom`, `zoomIdentity`, `select`, `pointer`),
  280 → 55 KB, tömörítve 93 → 18,6 KB; újraépítés: `deploy/d3-slim.sh`.
  A grafikonok rajzoló csomagja külön fájl (`Public/lib/d3-chart.js`, 39 KB), és csak grafikont tartalmazó lapon töltődik le.
- **`modulepreload`** az `editor.js` importjaira: a modulok most lépcsőzetesen derülnek ki (2–3 körben).
- **`commonmark.js` halasztva** (99 KB): csak markdown-szöveg megjelenítésekor kell.
- A korábbi nyitott tételek változatlanok („Ami nem javult vagy nyitva maradt”); az új táblázat-fejlécsávok görgetési
  sebessége nincs mérve.

## Üresjárat és első-alkalmas akadások – 2026-11-26 (Liquid Glass lap, Chrome 158 + Safari 18.6)

Probléma: a megnyitott Liquid Glass munkalap a szerkesztőben mozdulat nélkül 130–200% CPU-t vitt; pásztázáskor, az első
kijelöléskor és mozgatáskor „véletlenszerű” akadások.

### Mérőeszközök (Tests/Perf)

- `chrome.mjs`: valódi Google Chrome külön, ideiglenes profillal (a felhasználóét nem érinti), valódi GPU-val, CDP-n;
  CPU a példány folyamatfáján (renderer / GPU / böngésző). `TN_CHROME` a Chrome helye.
- `chrome-idle.mjs LAP [mp] [változatok]`, `safari-idle-wd.py LAP --list …`: üresjárati CPU változatonként. A változatokat a
  `Public/bench-idle.js` kapcsolja (a szerkesztő `?bench=NÉV&list=NÉV&hold=1` címre tölti be). Stílust CSSOM-mal
  (`adoptedStyleSheets`) szúr be: a CSP (`style-src 'self'`) a beszúrt `<style>` elemet tiltja.
- `chrome-pan.mjs`, `safari-pan.py`: összetett pásztázás 100%-on (`pan-plan.js`: a teljes vászon bejárása oda-vissza,
  húzásonként rántás – a táv 60%-a 4 képkocka alatt – majd lassú finomhúzás), hideg és meleg körben; `TN_TRACE=1`: a hideg
  kör hosszú főszál-feladatai.
- `chrome-hitch.mjs` (első kijelölés / mozgatás / pásztázás), `chrome-first.mjs` (a legelső kattintás JS-profilja, kérései).
- Buktató: takart (nem látható) ablakban a Safari a CSS-animációkat leállítja, a SMIL-t nem; a vezérelt ablak legyen elöl.

### Okok és eredmények

| Ok | Chrome | Safari (WebContent) |
|---|---|---|
| SMIL-animációk (4 animált doboz, 4 animált vonal): Safariban animációnként 14–19% CPU (akkor is, ha semmi nem látszik); Chrome-ban minden 60 Hz-es animáció képkockánként a teljes vásznat rajzoltatja (egy futó pötty ~15%) | ~80% | ~66% |
| A háttérfények végtelen CSS-animációja (csak a szerkesztőben volt; a mozgás nem is látszott) | ~17% (GPU) | ~3% + WindowServer 5–10% |
| **Összesen, régi kód** | **94–98%** | **69–71%** (+ WindowServer 17%) |
| CSS-animáció 60 Hz-en | 50% | 45% |
| CSS-animáció, 20 lépés/mp, igazítás nélkül | 29% | 20% |
| **CSS-animáció, 20 lépés/mp, közös ütemre igazítva (új)** | **15%** | **17%** |
| Minden animáció áll („Animációk ki”) | ~1% | ~0% |

- A lépések igazítása a lényeg: ha az animációk lépései nem ugyanarra a pillanatra esnek, együtt megint szinte minden
  képkockára jut változás. Minden szakasz 50 ms egész többszöröse, és a szerkesztő az animációkat a közös idővonal
  nullpontjához állítja (`editor.js queueMotionAlign`); a Chrome a `steps()` lépései között nem rajzol képkockát.
- A letölthető SVG SMIL-t használ (önállóan működik), ugyanazokkal a mértékekkel; az időzítés nem kulcskocka-pontos.
- A kúpos vastag vonal lüktetése a szerkesztőben és az SVG-ben is a kitöltés köré rajzolt, vastagodó körvonal (a Safari a
  CSS `d` tulajdonságot nem animálja).

### Akadások

- **Első lenyomás (kijelölés / pásztázás):** a ping hangjának Web Audio-környezete (`new AudioContext()`) Chrome-ban
  250–290 ms-ig szinkron blokkolt. Most előre generált `Public/ping.wav` szól `<audio>` elemmel (a CSP `media-src 'self'`
  miatt nem futás közben előállított blob). Első kijelölés: 564 ms helyett 27 ms késés, a leghosszabb képkocka 650 helyett
  18,6 ms.
- **Pásztázás vége:** a felengedéskor a nézet azonnal rögzült (`commitView`: teljes újrarajzolás, kényszerített
  elrendezés) – Safariban minden betöltés után az első húzások végén 55–72 ms, Chrome-ban hidegen 83–118 ms. Most a görgős
  nagyításhoz hasonlóan 400 ms nyugalom után rögzül (`perfOptions.panCommit`); egymás utáni húzások között nincs rögzítés.
- Összetett pásztázás 100%-on (34 húzás): Chrome meleg körben hibátlan (60 fps, max 17,9 ms).
