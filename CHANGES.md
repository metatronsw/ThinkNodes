# Változások

## 2026-11-25 – Gyorsabb tesztek, válasz-tömörítés, táblázat-gyorsítótár a megtekintőben

- **Tesztelők:** a `gestures.mjs` gyorsított idővel fut (az időzítések és az óra nyolcszoros sebességgel; `TEST_SPEED=1` a valós idő): 11 mp → 2,9 mp, hat egymás utáni futás hibátlan. A `test.sh` a JS-teszteket a háttérben, párhuzamosan futtatja, miközben a Swift fordít.
- **Válasz-tömörítés (gzip) a szöveges típusokra:** `editor.js` 280 → 80 KB, `d3.js` 280 → 93 KB, `app.css` 73 → 18 KB; a megtekintő oldala a helyi `a` lapon 159 → 20 KB, a mérő `tabla` lapon 433 → 66 KB. A feltételes kérés (304) változatlanul működik, a kicsomagolt tartalom bájtra egyezik.
- **Megtekintő / előnézet:** a táblázat dobozok kész HTML-je a fájl tartalma szerint gyorsítótárazva (`RenderedTables`), a cellaérték dekódolása a leggyakoribb típussal kezd. A helyi `a` lap megtekintője 87–100 ms → 17 ms (a mintavétel szerint az idő ~70%-a a `.tntable` újradekódolása volt minden kérésnél).
- **Hiba javítva:** két lap azonos nevű szövegfájlja egy lapon ugyanazt a tartalmat mutatta a megtekintőben és az exportban (a tartalom kulcsa csak a fájlnév volt; most a forrással együtt egyedi, `CanvasFile.textKey`).
- Ellenőrzött, hibát nem találtam: útvonal-kijátszás a `/common`, a mellékletek, az előnézet és a tallózó címein (403 / 404); a linkelőnézet helyi és belső címre csak helyőrző képet ad.
- Nem sikerült mérni: a táblázatszerkesztő görgetése az új fejlécsávokkal (az automatizált Safari időzítői leálltak, valószínűleg takarásban volt az ablak).
- Szerverkód változott: újrafordítva és újraindítva. További gyorsítási lehetőségek: `server/docs/PERF.md` („Betöltés és szerver – 2026-11-25”).

## 2026-11-24 – TODO- és BUGS-tételek (`todo-bugs-2026-11-24` ág)

- **Tesztek:** a `Tests/Editor/gestures.mjs` újra átmegy; a szerkesztő mostani működéséhez igazítva (részletek: DONE.md).
- **Törölt projektek lomtára:** az adminoldalon („Törölt projektek”) a gyökér `.trash` mappájának projektjei visszaállíthatók az eredeti néven, vagy – a „Végleg” négyzet bejelölése után – véglegesen törölhetők; „Lomtár ürítése” mindet törli (`/admin/trash`, `deletedProjects`, `restoreProject`, `purgeDeletedProjects`).
- **`common` projektnév foglalt** (`WorksheetPath.reserved`).
- **Közös fájlok:** az átnevezett fájlnév és a publikus (pillangó) állapot minden lapon a tulajdonos mappából jön olvasáskor; a közös könyvtár szövegfájljai a megtekintőben is megjelennek; a lomtárba tett közös fájl visszavonáskor visszaáll.
- **Szerkesztő:** ugyanannak a projektnek másik lapjáról másolt fájldoboz beillesztéskor közös hivatkozás lesz (nem új feltöltés); a vászonra húzott `.thnode` az új allapra mutató laplinkes dobozt kap; a behúzott ThinkNodes-csomag ZIP-nél a szerkesztő felajánlja az importot allapként (`isPackageZip`, `package.js`).
- **CSV olvasó nézet:** a társak cellakijelölése és a dupla kattintással megnyitott cella üres sorokat tartalmazó fájlban is a jó sorra esik.
- **Táblázatszerkesztő (Safari):** a ragadó fejlécek helyett külön fejlécsávok (oszlopbetűk, sorszámok), amelyek a rács görgetését követik – Safariban a ragadó fejléc görgetés után nem látszott és nem volt kattintható; az oszlopszélesség-fogó így működik. A szerkesztő megnyitásakor a vászon nem ugrik el (a Safari a fókusz miatt elgörgette a vászonterületet). Automatizált Safariban ellenőrizve.
- Szerverkód változott: újrafordítva és újraindítva.

## 2026-11-24 – Safari-mérés: görgős nagyítás és táblázathúzás gyorsítása; puffer- és memóriamérés

Mérés: automatizált Safari 18.6, release szerver, mérő-adatmappa (`p300`: 376 doboz). Részletek: `server/docs/PERF.md` („2026-11-24 esti mérés”).

- **A mai rács- és élesítés-változtatás nem lassít:** a rajzolt / CSS-rács és az élesítés be / ki minden nagyítási és pásztázási forgatókönyvben azonos eredményt adott.
- **Az akadás oka a nézet rögzítése** (teljes újrarajzolás az új méretarányon, kis nagyításnál 30–130 ms-os képkocka), ami a görgetés minden 150 ms-os szünetében lefutott – egérgörgőnél kattanásonként.
- **Javítás:** görgős nagyításnál a rögzítés további 0,3 mp nyugalmat vár (`wheelCommitDelay`, `perfOptions.wheelCommit`); a kattanások egy mozdulattá olvadnak össze, kattintás előtt azonnal rögzül (`flushView`). Egérgörgős nagyítás kis nagyításnál: 51,8 → 59,5 fps, 18 → 1 lassú képkocka; gyors nagyítás: 46 → 59,4 fps; szakaszos nagyítás 100% fölött: 8 → 1 képkocka 50 ms fölött. Ára: a nagyítás után kb. 0,45 mp-ig a kép a korábbi felbontásban, nagyítva látszik.
- **Puffer (`overscan`) és memória:** 0,5 / 1 / 2 / 3 értékkel a nagyítás és a pásztázás sebessége nem változott; a lap folyamatának memóriája a mérési zajon belül azonos (163–165 MB betöltve), a grafikus folyamaté nem változott (288 MB). Nagyobb puffer tehát nem segít: nem a puffer fogy el, hanem az új méretarány kirajzolása drága. Az alap marad 1.
- **Táblázat húzása:** 39,5 → 59,5 fps, a leghosszabb képkocka 382 → 47 ms. Két ok volt: (1) a doboz minden képkockában újraépítette és összehasonlította a táblázat teljes fáját (295 ms szkript 64 képkockára → 6 ms; `cachedGrid`); (2) a saját kijelölés glow-szűrője a nagy felületen kijelöléskor és a húzás végén 200–300 ms-os megakadást okozott – szövegfájl-, CSV- és táblázatdobozon a saját kijelölés mostantól csak vastag keret, glow nélkül.
- A szerver újrafordítva és újraindítva (verziószámok). JS tesztek rendben, `gestures.mjs` változatlanul bukik.

## 2026-11-24 – Háttérrács vászonelemre rajzolva (Safari: ugráló rács nagyítás közben)

- Megfigyelés: Safariban a rács nagyítás közben mindenhol ugrált, kis nagyításnál jobban, nagynál kevésbé. Automatizált Safariban mérve a rács és a vászonréteg beállított értékei képkockánként egyeztek, a képkockaidő egyenletes volt – tehát nem a számolás és nem a rétegváltás az ok.
- Valószínű ok: a rács csempézett CSS-háttér volt (a teljesítményjavítás óta), és a böngésző a csempe méretét egész képpontra kerekíti. Tört rácsköznél a kerekítés csempénként összeadódik: sok csempénél (kis nagyítás) nagy, kevésnél kicsi az elcsúszás, és nagyítási lépésenként változik.
- Javítás: a rács `<canvas>` elemre rajzolódik (`drawGrid`, `perfOptions.grid = "draw"`, alap): minden pont és vonal a saját, pontos helyére kerül; sok pontnál egyetlen mintakitöltés, amelynek a léptéke tört is lehet. A korábbi mód visszakapcsolható: `{"grid":"css"}`.
- Ellenőrizve: automatizált Safari 18.6-ban a rács megjelenik (12% és 62%), Chromiumban is. Az ugrálás megszűnését szemmel nem tudtam megerősíteni. A szerver újrafordítva és újraindítva (verziószámok).

## 2026-11-24 – Safari: nagyítás közben ugrált a rács (az élesítés késleltetve)

- Feltételezett ok: az „éles kirajzolás nagyítva” javítás a nézet minden rögzítésekor ki-, a következő mozdulatnál visszakapcsolta az előre raszterizált réteget. Nagyítás közben a nézet többször is rögzül (görgőszünet, a kirajzolt réteg széle), a réteg váltása pedig Safariban megakadás.
- Javítás: a réteg a mozdulat alatt és közvetlenül utána megmarad; az élesítés csak 0,6 mp nyugalom után kapcsol be (`restLayer`, `sharpTimer`). A táblázat / CSV / szöveg így a nagyítás után 0,6 mp-cel lesz éles.
- Chromiumban ellenőrizve a rétegállapot (mozdulat közben és után megmarad, nyugalomban élesít, új mozdulatnál visszaáll). Safariban nem tudtam megnézni; ha ott továbbra is ugrál, a `localStorage.tnPerf = '{"sharp":false}'` kapcsolóval eldönthető, hogy ez-e az ok. Csak kliensoldali változás.

## 2026-11-24 – Táblázat / CSV: cellaszerkesztés közben nincs lekerekített keret

- Cellaszerkesztés közben a doboz nem kapja meg a saját kijelölés vastag, lekerekített, világító keretét (`syncUi`, `editor.js`); a többi résztvevő továbbra is látja, hogy a doboz foglalt.
- A szerkesztett cella kerete a cellán belül, szögletesen áll (az általános fókuszkeret 3 px-re kijjebb, lekerekítve rajzolódott); a szerkesztő gyökerének fókuszkerete megszűnt (`app.css`).
- Ellenőrizve Chromiumban. A szerver újrafordítva és újraindítva (csak a stíluslap és a szkript verziószáma változott benne).

## 2026-11-24 – Táblázat / CSV: az Enter szerkesztést indít

- Kijelölt cellán az Enter szerkesztést indít (mint az F2), nem lép a következő sorra. Szerkesztés közben az Enter elfogadja a beírást, és a cella kijelölve marad; továbblépni a nyilakkal vagy Tabbal lehet (`table-edit.js`, `keydown`).
- Ellenőrizve a vezérlő közvetlen próbájával (Node) és a táblázat-tesztekkel; böngészőben nem próbáltam külön. Csak kliensoldali változás.

## 2026-11-24 – Éles táblázat, CSV és szövegfájl nagyítva (800%-ig)

- Ok: a vászon előre raszterizált rétege (`will-change: transform`, a pásztázás gyors indulásához) a görgethető HTML-tartalmat a 100%-os felbontásában tartotta, ezért belenagyítva életlen volt. Cellaszerkesztés közben a nyugalmi transzform eddig is kikapcsolt, ezért volt ott éles.
- Javítás: nyugalomban, 100% fölötti nagyításnál a réteg nem marad külön réteg (`restLayer`, `editor.js`); a következő mozdulat elején visszakapja. Ára: 100% fölött a pásztázás / nagyítás indulásakor egy rövid megakadás lehet (docs/PERF.md 2. pont). Kikapcsolható: `localStorage.tnPerf = '{"sharp":false}'`.
- Ellenőrizve Chromiumban 470%-on (előtte–utána összevetve), pásztázás utána is működik. Safariban nem mértem, sem az élességet, sem a megakadás mértékét. Csak kliensoldali változás.

## 2026-11-24 – Közös görgetési helyzet minden görgethető fájltartalomra

- Aki egy szövegfájl-, CSV- vagy táblázatdobozt kijelölve görget (olvasó nézetben vagy cellaszerkesztés közben), annak a görgetési helyzetét a többi szerkesztő és a megtekintő élőben követi (új `scroll` üzenet az élő csatornán, legfeljebb 50 ms-onként; a szerver csak a dobozt fogó résztvevőtől fogadja el).
- A görgetés végén (0,4 mp nyugalom után) a helyzet a dobozhoz mentődik (`scroll: {x, y}`, `Model.swift`), így a később érkezők és a megtekintő is ugyanott látják a tartalmat (a megtekintő a `data-scroll-x/y` mezőből állítja be). A görgetés nem kerül a visszavonási előzménybe.
- A dobozt nem fogó résztvevő saját görgetése (pl. a görgetősáv húzásával) helyi marad, és a következő közös változás felülírja.
- Ellenőrizve két böngészőlappal (Chromium, mérő-adatmappa): élő követés szerkesztőben és megtekintőben, mentés, visszatöltés. A szerver kódja változott (újrafordítva, újraindítva). 72 Swift teszt és a három JS teszt rendben; `gestures.mjs` változatlanul bukik. Safariban nem ellenőriztem.

## 2026-11-24 – Táblázat / CSV: a többi résztvevő látja a cellakijelölést

- Amíg valaki egy táblázat- vagy CSV-doboz celláit szerkeszti, a többi szerkesztő az olvasó nézetben látja a kijelölt tartományt (az illető színével árnyalva), az aktív cellát (keret) és azt, hogy éppen szerkesztés alatt áll-e (szaggatott keret). A gépelt szöveg nem megy át, az érték a szokásos mentéssel érkezik.
- Új, rövid életű üzenet az élő csatornán (`cells`, `Collaboration.swift` `CellMark`; kliens: `live.cells`, `peerCells`, `peerMark`). Csak az küldheti, aki a dobozt fogja; a később csatlakozók megkapják az aktuális állapotot; kilépéskor, a doboz elengedésekor és a kapcsolat bontásakor törlődik. Legfeljebb 80 ms-onként megy ki.
- Nem része: a megtekintő (csak a szerkesztőben látszik), és a görgetési helyzet követése (külön tétel a TODO.md-ben) – a kijelölt cella a másik félnél lehet a látható részen kívül.
- Ellenőrizve két böngészőlappal (Chromium, mérő-adatmappa): szerkesztett cella, tartomány, törlés kilépéskor. A szerver kódja változott (újrafordítva, újraindítva). Tesztek: az érintett Swift tesztek és a három JS teszt rendben; `gestures.mjs` változatlanul bukik.

## 2026-11-24 – Táblázat / CSV: a kattintott cella nyílik meg, nincs villanás, gyorsabb frissítés

- Dupla kattintásra az a cella nyílik meg szerkesztésre, amelyik fölött kattintottak, és a képernyőn a helyén marad (`clickedCell`, `gridOffset`). A cellát a doboz vászonbeli helyéből és a táblázat elrendezéséből számoljuk, nem találatvizsgálatból. A panelről vagy menüből indított szerkesztés az olvasó nézet görgetési helyzetét veszi át; kilépéskor az olvasó nézet ott folytatódik, ahol a szerkesztő állt.
- Dupla kattintásnál a tulajdonságpanel fájlnév-mezője már nem veszi el a fókuszt a megnyitott cellától.
- Más résztvevő mentése után a doboz nem villan üresre („…”): az új fájlváltozat betöltéséig a régi tartalom marad látható, a görgetési helyzettel együtt (`lastFileTexts`; szövegfájlra is érvényes).
- Cellaszerkesztésnél a mentés késleltetése 1,5 mp helyett 0,25 mp. Két böngészőlappal mérve a másik résztvevőnél kb. 0,6 mp-en belül megjelent az új érték, üres állapot nélkül.
- Ellenőrizve Chromiumban a mérő-adatmappán; Safariban nem. Csak kliensoldali változás (a szerver kódja nem változott).

## 2026-11-24 – Vászon nézetkorlátok, közvetlenül szerkeszthető CSV, táblázat- és dobozjavítások, főoldal

A felhasználói lista „-” jelű tételei; a „+” jelűek megbeszélésre várnak (TODO.md „Megbeszélendő”).

**Vászon (szerkesztő)**
- Legnagyobb nagyítás 800% (eddig 400%). A legkisebb nagyítás a kompozíciótól függ: a teljes tartalom ekkor a képernyő negyedét tölti ki (oldalanként a felét); a 100% mindig elérhető.
- Pásztázni bármelyik irányba addig lehet, amíg a legszélső objektum éppen eltűnik a képernyő szélén (egér, görgő, érintés, szóköz+húzás; `constrainView`, `contentBox` az `editor.js`-ben).
- Betöltéskor és a „Mind” gombnál a kompozíció (az objektumok határoló dobozának) közepe kerül a képernyő közepére, mint a megtekintőben – eddig a vászon origója.
- A nagyítás értéke a vászon alján, középen jelenik meg (külön komponens, nem rajzolja újra a szerkesztő gyökerét).
- Görgethető tartalom (szövegfájl, CSV, táblázat) egérgörgővel csak a kijelölt dobozban görög; nem kijelölt doboz fölött a görgő a vásznat nagyítja.

**Táblázat**
- A táblázat szélessége rögzített (az oszlopszélességek összege): a félkövér betű már nem szélesíti az oszlopot (szerkesztő és szerver: `TableHTML`).
- Felülvonás helyett áthúzás (a fájlbeli `o` kulcs maradt; a régi felülvont cellák áthúzva jelennek meg). Az igazítás gombjai a szövegeknél megszokott ikonokat kapták, az Alaprács ikonja valódi rács (`table-grid`).
- Táblázat nem kaphat elmosott hátteret. Szerkesztés közben nem jelenik meg a rejtett Text buboréksúgója.
- Új háttérmód: „Vászonszín” (`backgroundMode: "canvas"`) táblázatra, CSV-re és képre (átlátszó kép, SVG): a doboz a munkalap háttérszínét mutatja, a vászon rácsa nem látszik át. Szerver: `BoxBackgroundMode.canvas`, `Rendering.swift`.
- Új gomb a panelen (táblázat és CSV): a doboz átméretezése a tartalom tényleges méretére (`fitBoxToContent`; legfeljebb 4096 × 4096).
- Megtekintő: a szövegfájl-, CSV- és táblázatdoboz tartalma kilógott a dobozból, és a táblázat cellaformázása sem érvényesült, mert az oldal tartalombiztonsági szabálya (`style-src 'self'`) nem engedi a szerver által beírt `style` attribútumot. A `viewer.js` most szkriptből állítja be ezeket.

**Önálló CSV**
- A CSV cellái közvetlenül a vásznon szerkeszthetők (dupla kattintás; kijelölés, törlés, átírás, beillesztés), formázás és képletek nélkül (`TableEditor` `plain` mód). Mentéskor az eredeti elválasztó, a sorvégek és a soronkénti mezőszám megmarad; korlát 1000 sor × 100 oszlop.
- A tulajdonságpanelen megszűnt a CSV tartalmának szövegszerkesztője (a Text megjegyzés maradt).

**Dobozok**
- Külső vizuális tartalom (kép, SVG, weboldal- és munkalap-előnézet) egységesen 5 px lekerekítést kap (szerkesztő, megtekintő, szerver).
- A buboréksúgó követi a szöveg igazítását (bal / közép / jobb); a megtekintőben a sablon `data-align` mezőjéből.

**Főoldal**
- Az Új projekt / Projekt importálása külön szekcióban áll, vonallal elválasztva a projektektől.
- Vendégeknek (nincs bejelentkezve, vagy vendég szerepkör) tájékoztató: létrehozáshoz és szerkesztéshez be kell jelentkezni, és csak a publikus projektek láthatók.

**Ellenőrzés:** Chromiumban, tesztmódban, a mérő-adatmappán (`server/.build/perf-data`): nagyítási és pásztázási korlát, kezdő nézet, görgetési szabály, táblázat (félkövér, áthúzás, méretre igazítás), CSV szerkesztése és a mentett fájl, vászonszín (szerkesztő és megtekintő), megtekintőbeli kilógás, főoldal, súgóigazítás; a vendégtájékoztató tesztmód nélküli szerveren. Safariban nem ellenőriztem. Tesztek: 72 Swift teszt, `table-engine`, `table-fuzz`, `canvas-markdown` rendben; a `gestures.mjs` ugyanott bukik, ahol eddig (BUGS.md). A szerver kódja változott (újrafordítva, újraindítva).

## 2026-11-24 – Teljesítményjavítás a vászonszerkesztőn (a `perf` ág beolvasztva a `main`-be)

- Négy egymásra épülő változat (A–D), mind beolvasztva az alapbeállításokkal (a mérésben leggyorsabb kombináció), kapcsolható kísérleti beállításokkal (`localStorage.tnPerf`); mérések, okok, eredménytáblák: `server/docs/PERF.md`.
- Fő eredmények Safari 18.6-ban, release szerveren (300 / 1000 doboz): kijelölés késése 108 → 26 ms / 312 → 28 ms; gyors pásztázás 49 → 60 fps / 21 → 51 fps; lassú nagyítás 17 → 53 fps / 11 → 44 fps; csoport húzása 17 → 48 fps / 8 → 25 fps; másik felhasználó húzása közben 36 → 60 fps.
- Nem javult eleget: a nagyítás végi újrafestés (80–190 ms) és a táblázat szerkesztési módjának görgetése (~50 fps).
- Új mérőeszközök: `server/Tests/Perf/` (adatgenerátor, Safari-mérő, képkocka-rögzítő, második felhasználó); új indítási beállítás: `thinknodes-perf`.
- Tesztek: `table-engine`, `canvas-markdown` rendben; a `gestures.mjs` egy állítása a kurzor-pajzshoz igazodott, a teszt ugyanott bukik, ahol eddig. Swift-kód nem változott.

## 2026-11-24 – Más által fogott fájldoboz nem görgethető

- Ha egy szövegfájl-, CSV- vagy táblázatdobozt másik felhasználó fog, a tartalma nem görgethető: sem a natív, sem a Safaris saját görgetősáv nem húzható (`Public/app.css`, `.node.occupied`). A görgő eddig is csak a saját kijelölt dobozon görgetett.
- Két böngészőlappal ellenőrizve (Chromium); Safariban nem próbáltam ki külön.

## 2026-11-24 – Safari: saját görgetősáv a fájldobozokon, kattintható táblázatszerkesztő

- Ok: Safariban (WebKit) az SVG-transzform alatti foreignObject-ben a natív görgetősáv nem húzható, és a sávra nyomott egér mozgását a lap sem kapja meg. Ezért WebKitben a szövegfájl-, CSV- és táblázatdoboz (megjelenítés és cellaszerkesztés) natív sávja rejtve van, helyette az elem mellett saját sávok állnak: a hüvelyk húzható, a sínre kattintva odaugrik (`Public/scrollbar-drag.js`; bekötve: `editor.js`, `table/table-view.js`, `viewer.js`; stílus: `app.css` `.tn-sb*`). Más böngészőben nincs változás.
- A táblázatszerkesztő gyökere (`.tn-table-editor`) és a billentyűzet-nyelő már nem pozicionált: Safariban emiatt a szerkesztőben semmi nem volt kattintható. A rács új tartót kapott (`.tn-table-scroll-host`).
- A korábbi két kísérlet (sáv felismerése vászonkoordinátából, védelem a `pressNode`-ban) bent maradt, a többi böngészőben ez dönti el, hogy a doboz húzása vagy a görgetés indul.
- Ellenőrizve automatizált Safari 18.6-ban és Chromiumban; JS tesztek (`table-engine`, `canvas-markdown`) rendben. Nyitva maradt: BUGS.md (oszlopszélesség-fogó Safariban, megjelenítő).

## 2026-11-24 – Hozzáférés-kérés Google-fiókkal, adminisztrátori jelzések, meghívási szabály

- **Hozzáférés-kérés.** Ismeretlen, a Google által igazolt címmel belépett látogató a `/login/request` oldalon kérelmet adhat be (kért felhasználónév). Az admin a Beállítások oldal „Hozzáférési kérelmek” paneljén jóváhagyja (felhasználónév, szerepkör; meglévő, Google-fiók nélküli felhasználó nevével a cím ahhoz kapcsolódik) vagy elutasítja; az elutasítás feloldható. Alapból kikapcsolva; az adminoldalon kapcsolható és e-mail-domainekre szűkíthető. Korlátok: címenként egy kérelem, legfeljebb 50 függő, 30 nap után lejár. Tárolás a `.settings.json`-ban (`googleAccess`, `accessRequests`, `rejectedGoogle`). Útvonalak: `GET/POST /login/request`, `POST /admin/requests`.
- **Adminisztrátori jelzések** (`AdminMessage`, `WorksheetStore.adminMessages()`): közös lista az adminokra váró teendőkről, későbbi fajtákkal bővíthető. A fejléc Admin gombján jelvény mutatja a darabszámot (minden oldalon), az adminoldal tetején „Teendők” panel. Most a függő hozzáférés-kérelmeket jelzi.
- **Új szabály: projektbe csak a létrehozója és az admin hívhat meg szerkesztőt** (és távolíthat el). Eddig bármelyik meghívott szerkesztő is megtehette. Új `DocumentAccess.invitable`; a `grant`/`revoke` művelet, az `/api/worksheet-users` és a „Szerkesztők kezelése” gomb/menüpont (`Public/cards.js`, `data-invite`) ezt követi. Fiók-szerepkört továbbra is csak admin ad; meghívni csak szerkesztő szerepkörű fiókot lehet.
- Javítás: szűk képernyőn a Google-fiók mezős felhasználósor nem váltott egyoszlopos elrendezésre (`app.css`).
- Tesztek: `unknownGoogleAccountCanRequestAccess`, a `projectPoliciesFollowDirectory` és a `worksheetRoundTrip` kiegészítve; 72 Swift teszt rendben. Böngészőben ellenőrizve (tesztmód, mintakérelmek): jelvény, „Teendők”, kérelmek panelje. Nem ellenőrzött böngészőben: a kérelem oldala és a „Szerkesztők kezelése” menüpont elrejtése (a `cards.js` módosítása); valódi Google-klienssel továbbra sem futott.
- Dokumentáció: `server/deploy/GOOGLE.md` („Hozzáférés-kérés”), README („Szerepkörök és meghívás”).

## 2026-11-24 – Google-bejelentkezés: éles beállítási útmutató, daemon.sh

- Új `server/deploy/GOOGLE.md`: a Google-bejelentkezés beállítása a Fedora szerveren (OAuth-kliens létrehozása, visszatérési cím, `thinknodes.env`, fiókok hozzárendelése, működés, hibakeresés, biztonság).
- `server/deploy/daemon.sh`: létrehozza a `/var/lib/thinknodes/thinknodes.env` beállítófájlt kommentezett mintasorokkal (`0600`, `thinknodes`), ha még nincs; a meglévőt nem írja felül. A végén kiírja a beállítófájl helyét és a Google-bejelentkezés állapotát. Csak szintaxisellenőrzés futott (`bash -n`), Fedorán nem próbáltam ki.
- Helyben a Google-bejelentkezés nem lesz használva; a helyi teszthez készített `server/.google.env` törölve.
- TODO.md: hozzáférés-kérés Google-fiókkal (javaslat).

## 2026-11-24 – Google-bejelentkezés

- Új `server/Sources/ThinkNodes/GoogleSignIn.swift`: OpenID Connect „authorization code” folyamat PKCE-vel, state és nonce ellenőrzéssel. Útvonalak: `GET /login/google` (átirányítás a Google-hoz), `GET /login/google/callback` (kódbeváltás, ID token ellenőrzése: kibocsátó, címzett, lejárat, nonce, igazolt e-mail).
- Bekapcsolás környezeti változókkal: `THINKNODES_GOOGLE_CLIENT_ID`, `THINKNODES_GOOGLE_CLIENT_SECRET` (és szükség esetén `THINKNODES_GOOGLE_REDIRECT`); nélkülük nincs gomb és nincs útvonal. Tesztmódban kikapcsolva. Indításkor a szerver kiírja, ha be van kapcsolva.
- A Google csak azonosít: a `User` új `google` mezője (e-mail-cím a `.settings.json`-ban) köti a Google-fiókot a ThinkNodes-fiókhoz, az admin a Beállítások oldalon állítja. Új fiók nem jön létre a Google-től; egy cím egy felhasználóhoz tartozhat. Jelszó nélküli új fiók Google-fiókkal létrehozható (véletlen jelszó-hash-t kap).
- A Google-lal indult munkamenet megszűnik, ha a hozzárendelést törlik vagy megváltoztatják.
- `deploy/daemon.sh`: a szolgáltatás beolvassa a `/var/lib/thinknodes/thinknodes.env` fájlt, ha létezik (a `daemon.sh` újrafuttatása kell hozzá).
- Teszt: `googleSignInOpensTheLinkedAccount` (71 Swift teszt rendben). Böngészőben ellenőrizve: gomb a belépőoldalon, átirányítás a Google-hoz, Google-fiók mező az adminoldalon. Valódi Google OAuth-klienssel nem próbáltam ki (nincs hozzá kliensazonosító), lásd TODO.md.
- README: „Google-bejelentkezés” fejezet.

## 2026-11-24 – Görgetősáv húzása fájldobozban (Safari 18)

- A szövegfájl-, CSV- és táblázatdoboz görgetősávjának felismerése a doboz vászonbeli helyéből és az egér vászonkoordinátájából számol, nem a DOM-ból (`Public/editor.js` `scrollbarPress`); Safariban a foreignObject-beli elemek mérete/helye megbízhatatlan, ezért ott a doboz húzása kapta el a görgetősávot.
- Chromiumban ellenőrizve (a görgetősáv-sávban a lenyomás nem indít dobozhúzást, a tartalmon igen); Safari 18-ban megerősítésre vár (BUGS.md). JS tesztek: `table-engine`, `canvas-markdown` rendben; a `gestures.mjs` a régi, ismert okból bukik.

## 2026-11-24 – Szövegfájl- és táblázatdoboz: palettát követő színek, keret nélküli módosító

- A szövegfájl-, kódfájl- és táblázatdoboz tartalma a szerkesztőben is a doboz szövegszínét használja (alapból a paletta 1-es színe), a háttér a doboz kitöltése (paletta 2), így világos és sötét módban is olvasható (`Public/editor.js` `renderFileBox`; a megjelenítő eddig is így működött).
- Új „Keret: be/ki” kapcsoló ezeken a dobozokon a Megjelenés panelen (`frame: false`), bármelyik háttérmóddal (Free = átlátszó, Üres, Elmosott, Áttetsző) kombinálható; a szerver oldali rajzolás is követi (`Rendering.swift` `boxSurface`). A táblázat Megjelenés paneljén Szövegszín választó.
- A táblázat szerkesztési módja (képletsor, oszlop- és sorfejléc, kijelölés, cellabevitel) rögzített fehér helyett a doboz hátteréből és szövegszínéből kevert színeket használ (`Public/app.css`, `--tn-paper`). A cellákra kézzel beállított színek változatlanok.
- Teszt: `textFileBoxFrameCanBeSwitchedOffInEveryBackgroundMode`; a Swift tesztek rendben (70). Böngészőben nem ellenőriztem: a helyi `projects` mappa üres volt, a JS tesztek pedig nem futottak (a `node` nincs a PATH-on). Doksi: `server/docs/node-types.md`.

## 2026-11-24 – Figyelmeztetés nem létező adatmappánál

- Ha a `--project:` mappa nem létezik, a szerver (és a `user` parancs) indításkor kiírja, hogy új, üres adatmappát hoz létre, és felsorolja a mellette lévő valódi ThinkNodes-adatmappákat (amelyekben van `.settings.json`), pl. elírásnál `ThinkProject` → `ThinkProjects`. Ez okozta a korábbi „nem lehet belépni” esetet is.
- Kipróbálva elírt és létező mappával (`user` paranccsal, szerver indítása nélkül); Swift tesztek rendben.

## 2026-11-24 – Debug build jelzése a nyitóoldalon

- Debug buildben a nyitóoldal jobb alsó sarkában figyelmeztető jelvény: „Debug build” és az adatmappa valós útvonala (szimbolikus linkek feloldva). Release buildben a jelvény nem kerül az oldalba (`#if DEBUG`, `Server.swift` `debugBadge`; stílus: `Public/app.css` `.debug-badge`).
- Teszt: `debugBuildShowsBadgeWithRealDataFolder`; böngészőben ellenőrizve (debug: látszik, release: nincs).
- `.claude/launch.json`: új `thinknodes-debug-test` konfiguráció (`run.sh --debug … --test`).

## 2026-11-24 – run.sh: futó példányok listája, foglalt port és adatmappa ellenőrzése

- A `server/run.sh` indítás előtt kilistázza a gépen futó ThinkNodes-szervereket (PID, felhasználó, port, adatmappa; a systemd `thinknodes.service` jelölve). A `ps -eo` minden felhasználó folyamatát látja, így a `thinknodes` felhasználóként futó daemon is megjelenik.
- Nem indul, ha a port foglalt (ThinkNodes vagy más program; utóbbinál `lsof`-fal kiírja, mi foglalja), vagy ha egy másik példány ugyanazt az adatmappát használja. Javasol szabad portot.
- Javítás: a relatív `--project:`, `--tls-dir:`, `--tls-cert:`, `--tls-key:` útvonalak eddig a `server/` mappához képest értelmeződtek (a `run.sh` `cd`-je miatt), most a hívó mappájához képest, ahogy a súgó írja; a `~/` is kibontva.
- Kipróbálva: két példány (8888 + 8889), azonos port, azonos adatmappa, idegen program a porton, relatív `--project:`, `user` parancs.

## 2026-11-24 – Adatmappa kiírása, figyelmeztetés fiók nélküli adatmappánál

- Ok (a `--project:~/Project/ThinkProject` „nem működött”): a kapcsoló jó volt, de az új, üres adatmappában nincs `.settings.json`, így felhasználói fiók sincs, a belépés ezért nem sikerült.
- Indításkor a szerver kiírja az adatmappát (`Data folder: …`); ha nincs egyetlen fiók sem (és nem tesztmód), kiírja, hogyan hozható létre az első admin (`./run.sh user NAME admin --project:…` vagy helyi böngészőből `/admin`). A `user` parancs is kiírja, melyik adatmappába mentett.
- A login oldal fiók nélküli adatmappánál figyelmeztet (helyi gépről linkkel az `/admin` oldalra). Teszt: `loginPageWarnsWhenTheDataFolderHasNoAccounts`.

## 2026-11-24 – Swift-modulok: ThinkCore és ThinkNodes

- A `ThinkNodes` futtatható modul kettévált. Új `ThinkCore` könyvtár: Model, Rendering, Theme, WebPresentation, ProjectPackage, TableFiles, NodeTypes, WorksheetFile, WorksheetLink, CanvasMarkdown, PageUpdates. A `ThinkNodes`-ban marad: Server, Collaboration, LinkPreview, Launch, LANCertificate.
- A szerver által használt mag-deklarációk `package` láthatóságot kaptak (a többi `internal` maradt). Explicit `package init` a memberwise inicializáló pontos másaként: `Worksheet`, `User`, `UserPreferences`, `SiteSettings`; továbbá `PageUpdates.init()`, `WebPresentationSessions.init(requireCookie:)`. Az `encodeQuery` a `Server.swift`-ből a `Rendering.swift`-be került. Más tartalmi változás nincs (a `package ` nélküli összevetés szerint).
- Tesztek: `@testable import ThinkCore` is; a `test.sh` útvonal-hozzárendelése mindkét modulra illeszkedik. 67 Swift teszt rendben.
- Release build egy módosítás után: szerverréteg 85 → 25 s, mag 85 → 65 s, változás nélkül 34 → 9 s. A debug build változatlan (9–13 s).

## 2026-11-24 – Témakörönkénti tesztfuttatás, gyorsabb típusellenőrzés

- Új `server/test.sh`: a commitolatlan módosításokból (vagy `--since REF`, illetve megadott témák alapján) csak az érintett Swift- és JS-teszteket futtatja; `--all`, `--swift`, `--js`, `--list`. Mindig debug build, ugyanazokkal a cache-útvonalakkal, mint a `deploy/build.sh`; a Vapor kérésnaplóját elrejti.
- A `Tests/ThinkNodesTests/WorksheetTests.swift` (1408 sor, 39 teszt) témák szerint szétbontva: `WorksheetTests`, `RenderingTests`, `CollaborationTests`, `AccessTests`, `AttachmentTests`, a közös HTTP-segédfüggvények a `HTTPTestSupport.swift`-ben. A tesztek tartalma változatlan.
- Lassú típusellenőrzésű kifejezések átírva (viselkedés változatlan): `VisualTheme.valid` (egy ~20 tagú `&&`-lánc → lépésenkénti `guard`), vegyes típusú tömb-összefűzések (`WebPresentationReference`, `CanvasFile.validSource` / `commonURL` / `sheet(from:)`), `CommonLibrary.list`, `number()`. A ThinkNodes modul típusellenőrzése 14,0 → 8,3 s (debug buildben érvényesül; a release build ideje, kb. 85 s, nem változott: ott az optimalizálás a meghatározó).
- Mérések: egy téma tesztje módosítás nélkül kb. 16 s (ebből kb. 7 s a SwiftPM üres buildje, kb. 7 s a tesztfolyamat indítása), az összes teszt kb. 20 s; Swift-fájl módosítása után a debug build kb. 10 s.
- README: `test.sh` és a debug binárissal történő helyi fejlesztés leírása.

## 2026-11-24 – Futtatókörnyezet áthelyezve a ~/X-Code/RunTime alá

- A Swift 6.0.3, a Node.js és a headless Chromium a `~/X-Code/RunTime/{Swift,NodeJS,Chromium}` alá került; az elérési utak frissítve:
  `server/deploy/build.sh`, `server/deploy/install.sh` (Swift, NodeJS `env.sh`), `server/Sources/ThinkNodes/WebPresentation.swift` (Chromium).
- A `~/X-Code/RunTime/NodeJS/env.sh` (a repón kívül) is az új helyre mutat.
- A `server/.build` a projekt korábbi helyére (`~/Work/ThinkNodes`) fordított, használhatatlan modul-cache-t tartalmazott; félretéve `server/.build.old-path` néven (törölhető), a build újra elkészült.
- Ellenőrzés: 67 Swift teszt rendben; JS: canvas-markdown, table-engine, table-fuzz rendben, `gestures.mjs` a BUGS.md-ben már nyilvántartott hibával bukik.
