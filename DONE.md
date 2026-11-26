# Javított hibák

A BUGS.md-ből ide kerülnek a megoldott hibák (AGENTS.md), a legújabb felül.

Megjegyzés: 2026-11-24 óta a `Model.swift`, `Rendering.swift`, `Theme.swift`, `WebPresentation.swift`, `WorksheetFile.swift` és a többi mag-fájl a `server/Sources/ThinkCore/` alatt van; a régebbi bejegyzések `Sources/ThinkNodes/…` útvonalai erre értendők.

## Javítva

- **.web oldal: `../` hivatkozás a projektmappán belül (2026-11-26)**
  - Ok: a .web kiszolgáló csak a saját mappájából adott fájlt; a `../kepek/x.png` hivatkozás 404 lett. A közös könyvtár (`/common/...`) abszolút címmel eddig is működött.
  - Javítás: minden HTML oldal tükrözött `<base>`-t kap (`_tn-assets/{bérlet|public}/{projektbeli útvonal}`), így a `../` a projekt gyökeréig feloldódik, fölötte 404. A projekt fájljaira a projekt olvasási joga vonatkozik; rejtett, `.thnode`, HTML fájl és link nem szolgálható ki. Teszt: `presentationParentReferencesStayInsideProject`; Chrome-ban (CDP, homokozóval) ellenőrizve. Részletek: server/docs/node-types.md „.web mappa”.

- **WhiteBoard: elcsúszó füzetvonalak, vonalazott kódfájl, textúrák (2026-11-26)**
  - Ok: a nagyobb betűs címsor alapvonala nem a sáv vonalára esett (5 px-ig), a markdown kódblokk 12 px-es belső térköze és a vízszintes vonal kerete eltolta az utána következő összes sort (kb. 5 px).
  - Javítás: a címsor sávja a sormagasság egész többszöröse, a felső térköze az alapvonalat a vonalra teszi, a negatív alsó margó visszaveszi; a kódblokk térköze csak oldalt, a vízszintes vonal egy sor. Chrome-ban mérve: minden sor alapvonala 0,6–0,9 px-lel a vonal fölött (a dokumentum végéig). A kódfájl (`type: "code"`) már nem füzetlap. Új: ismétlődő webp textúrák a témában (`graphics.textures`), a „Díszítő háttér kikapcsolása” elrejti őket. Részletek: server/docs/themes.md „Textúrák”.
  - Utána (felhasználói visszajelzés): a szöveg alapvonala 2 px-lel a vonal fölött; a textúra nem látszott (a képek szinte egyszínűek voltak): kontrasztemelt képek; a tábla filcnyomai (háttérfények) megszűntek. A tesztek a törölt VectorStudio helyett a LiquidGlass témát használják.
  - Safariban a sorok fokozatosan elcsúsztak: a Safari „legkisebb betűméret” beállítása a 13 px-es betűt 14-re emelte, és a px-ben megadott sormagasságot arányosan megnövelte (21 → 22,6 px), a vonalak és a margók maradtak. Javítás: egység nélküli sormagasság (1.6), a sorköz (`--pitch`) a tényleges betűméretből; Chrome-ban és Safariban mérve nincs csúszás.
  - A textúra nagyításkor ugrott (képernyőhöz kötött csempe, a nagyítás rögzítésekor igazodott): a vászon textúrája vászonegységben, részletességi szintekkel (2^n, két szomszédos szint áttűnve, mint a Blender rácsa); a doboz nem kap külön textúrát (a vászoné átlátszik), a papír a lap saját koordinátáiban.
  - A képek kikerültek a téma JSON-jából (base64 helyett): `Public/themes/WhiteBoard.paper.webp`, `WhiteBoard.cardboard.webp`, a JSON-ban csak a fájlnevük; a szerkesztő a `/themes/…` címről tölti (gyorsítótárazható), az SVG-exportba a szerver a betöltéskor beolvasott tartalmat ágyazza.
  - Az SVG-export önálló: a képdobozok képe, a hang, a fájldobozok letöltése (`download` névvel), az ikonok (`icons.svg` használt szimbólumai) és a textúrák a fájlba ágyazva, a szerverre mutató cím nem marad (Server.swift `selfContainedSVG`, belső kérés a letöltő munkamenetével; teszt: ExportTests `svgExportIsSelfContained`). Chrome-ban helyi fájlként megnyitva a képek és ikonok látszanak.

- **Kapcsolatvesztéskor villogó szerkesztő és megtekintő (2026-11-26)**
  - Ok: a szerver újraindulása után (memóriában tartott munkamenet) új token jött, és mindkét lap teljesen újratöltötte magát; kapcsolat nélkül a megtekintő másodpercenként újraírta a jelzést. Javítás: tartós munkamenetek (`FileSessions`), tokenátvétel újratöltés helyett, fokozatos újrapróbálkozás, egyszeri jelzés. Chrome-ban mérve; részletek: CHANGES.md.

- **Minimalist téma és keret nélküli dobozok (2026-11-26):** új téma (minden effekt ki, nincs dobozkeret, hasonló világos / sötét mód, 5 × 21 szín); a téma `frame.kind: "none"` mezővel elhagyhatja a kitöltött dobozok keretét; `glow: 0` mellett nincs szűrő. Részletek: CHANGES.md, server/docs/themes.md „Minimalist”.

- **Napló-zaj: lapbezárásonként egy „Abort.410: Gone” figyelmeztetés a szerver naplójában (2026-11-26)**
  - Ok: a jelenlét hosszú lekérdezése (`/api/presence`) a várakozás végén már nem találta a közben távozott (leave, újratöltés) vagy lejárt résztvevőt; a lapváltozás-lekérdezés (`/api/page-changes`) lejárt csatornánál (pl. szerver-újraindítás után) ugyanígy. A dobott 410-et a Vapor hibakezelője figyelmeztetésként naplózta.
  - Javítás: várt esetként csendes 410-es válasz, dobás nélkül (`Server.swift goneResponse`, `quietGone`); a kliens viselkedése változatlan. Chrome-ban 5 újratöltés és bezárás után a napló tiszta.

- **Liquid Glass szerkesztő: üresjáratban 130–200% CPU, akadások első kijelöléskor és pásztázáskor (2026-11-26)** (server/docs/PERF.md „Üresjárat”)
  - Okok: a doboz- és vonalanimációk SMIL-esek voltak (Safariban animációnként 14–19% CPU, Chrome-ban minden 60 Hz-es animáció a teljes vásznat rajzoltatta); a háttérfények végtelen animációja; az első lenyomáskor szinkron létrejövő Web Audio-környezet (250–290 ms); a pásztázás végén azonnali teljes újrarajzolás.
  - Javítás: a szerkesztőben CSS-animációk 20 lépés/mp-re korlátozva, a közös idővonalhoz igazítva; álló háttérfény; a ping hangja `ping.wav`; a pásztázás 400 ms nyugalom után rögzül. Az SVG-export SMIL-es maradt (önállóan működik).
  - Eredmény (Liquid Glass, üresjárat): Chrome 94–98% → 17–21%, Safari 71% (+17% WindowServer) → 25% (+5%). Első kijelölés: 564 ms → 8–27 ms késés. Összetett pásztázás 100%-on: Safari 16–31 képkocka 25 ms fölött → 0, Chrome hidegen is 0.
  - Új: „Animációk leállítása” és „Díszítő háttér kikapcsolása” a vezérlősávon (böngészőnként tárolva).

- **„Tartalom a dobozhoz” CSV-n is (2026-11-26)**
  - Eddig csak táblázatdobozon volt. A CSV illesztve a szerkesztő táblázatdokumentumaként (csvDocument) skálázódik, a szerver ugyanezt rajzolja (`csvGridDocument`, `csvEditorRows` – a szerkesztő CSV-elemzőjének pontos párja). Teszt: `contentFitCSVUsesTheEditorTable`.

- **BUGS.md átnézése, 2. kör (2026-11-26)**
  - Élénk kitöltésen a beállított szövegszín nem igazodott (pl. fehér szöveg a világos módú, 64%-os üveg zöldjén). Javítás: ha a szöveg és a felület (kitöltés a vászon fölött, a téma átlátszatlanságával) kontrasztja 3 alatt van, a téma tintájának jobban olvasható változata jön; szerver: `Rendering.swift labelInk`, `Idea.labelInk`, `Worksheet.painted`; szerkesztő: `editor.js boxInk`. Teszt: `unreadableBoxTextGetsThemeInk`.
  - A CSV olvasó nézet 200 sor × 30 oszlopnál megállt: a korlát 1000 × 60 (`csvPreviewRows`, `csvPreviewColumns`; editor.js `parseCSV`). Teszt a `WorksheetTests`-ben.
  - Engedéllyel törölve: a 12 régi `.preview-v12*.svg` gyorsítótár-fájl és az üres `projects/a/.chat.jsonl`.

- **BUGS.md átnézése, 2026-11-26: javítva és döntéssel lezárva**
  - Lap átnevezésekor a régi nevű előnézeti gyorsítótár (`.<lap>.preview[-dark].svg/.webp`) a mappában maradt. Javítás: az átnevezés a gyorsítótár-fájlokat is az új névre viszi (a módosítás ideje megmarad, így érvényesek maradnak), `Model.swift moveDocument`; teszt: `uploadedWorksheetsUseTheirOwnFolder`. Törléskor nem volt hiba (a teljes mappa a lomtárba kerül).
  - Gyors eszközök: a kinyitott lenyíló lista máshová kattintva nyitva maradt. Javítás: a listán kívüli kattintás és az Esc bezárja (az Esc ilyenkor csak a listát, a gyors eszközöket nem), `editor.js openFlyout`.
  - Gyors eszközök: hiányzott a „Szerkesztés” (tulajdonságpanel megnyitása). Új `properties` gomb dobozon, csomóponton és vonalon, a Törlés előtt; a panelt ki is nyitja (`quick-tools.json`, `editor.js renderQuickTools`). Fej nélküli Chromiumban ellenőrizve.
  - Döntéssel lezárva (felhasználó, 2026-11-26): csökkentett mozgás beállításnál a ping animációja marad (a kijelölés-gyűrű már addig is leállt); az új doboz nem kap automatikusan eltérő színt (ötlet a TODO.md-ben).

- **Előnézeti képek (főoldali kártyák háttere) táblázatos lapokon: régóta fennálló hiba** (2026-11-26)
  - Ok: a táblázat lezáratlan `<col>` eleme az önálló SVG-ben (XML) érvénytelen, a böngésző a képet nem töltötte be. Javítás: önlezáró elem, előnézet-gyorsítótár v12; minden helyi lapon és előnézet-változaton ellenőrizve; védőteszt: `standaloneSVGIsWellFormedXMLForEveryBoxType`.

- **Jelenlévők a bal alsó sarokban; kijelölt nyíl „árnyék-nyila”; előnézeti képek táblázatos lapokon** (2026-11-26)
  - A jelenlévők sorát a levágás elleni negatív margó tolta balra; a nyílhegy kijelölés-sávja hátrafelé nagyobb háromszög volt; a táblázat lezáratlan `<col>` eleme miatt az SVG-előnézet érvénytelen XML volt. Javítások: CHANGES.md 2026-11-26 „Táblázat: fejlécek a dobozon kívül…”.
- **Táblázat: szerkesztésbe lépéskor elugrott a tartalom; nem volt mód a tartalmat a dobozhoz igazítani** (2026-11-26)
  - Megoldva a felhasználó választása szerint (fejlécek a dobozon kívül; „Tartalom a dobozhoz” torzítás nélküli nagyítással).

- **Vonal és eszköztár: a 2026-11-26-i hibalista** (2026-11-26)
  - Vastag, animált vonal végpontjának húzásakor a nyíl a dobozon maradt; mozgatáskor az animációs pötty a helyén maradt és megállt; a kijelölés sávja a dobozba lógott, a nyílhegy nem kapott sávot; S-vonalon a pötty nem a látható görbén futott; a csomópontot túl pontosan kellett eltalálni; az eszköztár nem jelezte a bekapcsolt funkciókat (sötét és üveg témákban); Liquid Glass: a kép rámutatáskor eltűnt, a jelenlévő-gomb sarka levágódott; a táblázat kerete a csomópontokban erősebb volt. Javítások: CHANGES.md 2026-11-26 „Egységes gombok…”.

- **.md fájldoboz: megjelenítéskor minden sortörés dupla volt, szerkesztéskor a fel / le nyíl ugrált** (2026-11-26)
  - Ok: a `.node-file .formatted-text` `white-space: pre-wrap` szabálya a cmark `<br />` utáni sortörését is megjelenítette; a nyilaknál a böngésző saját függőleges léptetése a foreignObject-ben (Safari) téves sorhelyet mért.
  - Javítás: formázott szövegben `white-space: normal`; a .md doboz a forrás sorait pontosan követi (`markdownHTML(exactLines:)`, `.md-lines`), a szerkesztő ugyanazzal a betűvel és sormagassággal; fel / le nyíl saját kezeléssel (`moveCodeLine`). Safariban ellenőrizve.

- **A képernyőn kívüli ping nyila sokszor nem jelent meg** (2026-11-26)
  - Ok: a látható terület a teljes ablak volt (a vászon a puffer miatt nagyobb az ablaknál), így a fejléc / nyitott panel alá eső vagy a szélén épp belógó ping „láthatónak” számított.
  - Javítás: a vászonterület az ablakra vágva, a nyitott panelek nélkül; nyíl jár, ha a ping közepe nincs 24 px-re a széleken belül (`ping.js`, `editor.js pingBounds`). Safari + Chromium próbával ellenőrizve.

- **A saját résztvevő-gombod is elszürkült, ha a saját ablakod nem volt fókuszban** (2026-11-26)
  - Döntés (felhasználó): a saját gomb kivétel. A szerver továbbra is jelzi a többieknek, hogy nem nézed a lapot (náluk szürke vagy), de a saját listádban a gombod mindig színes (`editor.js`, `viewer.js`: `away && !mine`). Safariban ellenőrizve kényszerített fókuszvesztéssel és egy második résztvevővel.

- **Bukó tesztek a vonalméret- és vonalanimáció-változás után (6 Swift, 2 JS)** (2026-11-26)
  - Ok: a 2026-11-25-i változás (egyedi vastagság helyett három méret, gradiens helyett futó pötty) után a teszteket nem igazították hozzá; a `gestures.mjs` első hibája további, régebbi hibákat takart el.
  - Javítás: `RenderingTests` (legnagyobb vastagság, íves vonal, animált vonal), `WorksheetTests` (`width` → `size`), a közös vonalminta (`Tests/Fixtures/wires.json`) újraírva a régi `w` esetekre és egy új `size` esettel; `gestures.mjs`: futó pötty, csoporton belüli gombkeresés (két „Vastag” gomb), a megszűnt vastagságmező helyett vonalméret, a szerkesztővel azonos `geometry.js`-példány (a verzió az `editor.js` importjából). Teljes készlet: 104 Swift-teszt és minden JS-teszt átmegy.

- **A `test.sh` nem futott a macOS `/bin/bash` 3.2-vel** (2026-11-26)
  - Javítás: régi bash alatt a szkript egy telepített 4+ bash-sel indul újra (MacPorts, Homebrew), ennek híján érthető hibaüzenettel áll le.

- **Törölt témájú munkalap nem nyílt meg (422)** (2026-11-25)
  - Ok: a szerver betöltéskor és mentéskor is elutasította a katalógusban nem szereplő téma- vagy paletta-ID-t.
  - Javítás: a lap az alaptémát (illetve a téma első palettáját) kapja (`Worksheet.repairAppearance`); teszt: `missingThemeFallsBackToDefault`.

- **A .txt doboz szerkesztésekor a szöveg áttördelt (a sor utolsó szava új sorba került), kilépéskor visszaállt** (2026-11-25)
  - Ok: a `.txt` / `.md` külön szövegmezőben volt szerkeszthető, amely más szélességen tördel, mint a megjelenítés.
  - Javítás: a szövegfájlok is az egyrétegű szerkesztőt használják (a megjelenített elem szerkeszthető, `renderTextEditor`); a szövegmező megszűnt.

- **Safari: kódfájl szerkesztésébe lépve megváltozott a betű és a tartalom magassága** (2026-11-25)
  - Ok: megjelenítéskor a szöveg `<pre><code>` elemben áll, a szerkesztő közvetlenül a `<pre>`-be írt, a `code` elem pedig a böngésző saját egyenközű betűjét kapja.
  - Javítás: a szerkesztő is `<code>` elembe ír (`renderCodeEdit`).

- **Safari: hosszú kódfájlban egérhúzásra a kijelölés a szöveg végére ugrott, a doboz az aljára görgetett** (2026-11-25)
  - Ok: a foreignObject-en belül a böngésző saját húzásos kijelölése és automatikus görgetése téves helyről számol.
  - Javítás: saját egérkijelölés a doboz vászonbeli helyéből (`codePointerDown`, `codeOffsetAt`, `editor.js`).

- **Safari: kódfájl szerkesztésekor kijelöléstől a szöveg fél sorral elugrott, és megjelent alatta a másik réteg** (2026-11-25)
  - Ok: a szerkesztő két rétegből állt (színezett szöveg, fölötte átlátszó betűjű szövegmező), és Safariban kijelöléskor a kettő elcsúszott egymáson.
  - Javítás: egyetlen réteg – maga a színezett szöveg szerkeszthető (`renderCodeEditor`, `editor.js`).

- **Sötét módban a dobozon szerkesztett szövegfájl mezője szürke hátteret kapott; egérrel nem lehetett benne kijelölni** (2026-11-25)
  - Ok: az általános sötét módú űrlapmező-szabály erősebb volt a mező saját szabályánál; a mező a vászontól örökölte a `user-select: none` értéket.
  - Javítás: `.node-text-editor` háttere és színe `!important`, `user-select: text` (`app.css`).

- **A megtekintőben a görgethető tartalom kijelölés nélkül is görög** (2026-11-25) – döntés: így marad (a látogató nem jelöl ki), nem hiba.

- **Megtekintő: két lap azonos nevű szövegfájlja ugyanazt a tartalmat mutatta** (2026-11-25)
  - Ok: a szövegfájlok tartalma fájlazonosító szerint volt kulcsolva; a tallózóból beillesztett, névvel hivatkozott fájloknál a saját és a másik lap azonos nevű fájlja ütközött.
  - Javítás: a kulcs a forrással együtt egyedi (`CanvasFile.textKey`, `textContents`); teszt: `sameNamedFilesFromTwoSheetsKeepTheirOwnText`.

- **Safari: a táblázatszerkesztő fejlécei görgetés után eltűntek, az oszlopszélesség-fogó nem volt kattintható** (2026-11-25)
  - Ok: a ragadó (`sticky`) fejléccellákat a Safari foreignObject-en belül görgetés után nem rajzolta ki, és a helyükön az alattuk lévő cella kapta a kattintást (automatizált Safari 18.6-ban mérve: a fejléc helyén `TD` a találat).
  - Javítás: az oszlopbetűk sora és a sorszámok oszlopa külön sávban áll a rács mellett, rácselrendezésben, és a rács görgetését követi (`tn-grid`, `syncHeads`, `table-view.js`); a fogó normál elrendezésű elem, és a fejléccella széle is fogóként működik. Safariban ellenőrizve: a fejlécek látszanak, a fogó a találat (`col-resize`), egy oszlop 69 → 109 képpontra húzható és vissza.

- **Safari: a táblázatszerkesztő megnyitásakor a vászon egy képernyőnyit elugorhatott** (2026-11-25)
  - Ok: a szerkesztő fókuszálásakor a Safari elgörgette a (nem görgethető, `overflow: hidden`) vászonterületet (`.canvas-area` scrollLeft / scrollTop = a látható méret).
  - Javítás: a vászonterület a görgetését azonnal visszaállítja (`keepUnscrolled`, `editor.js`); a cella beviteli mezője görgetés nélkül kap fókuszt. Safariban ellenőrizve: a doboz a helyén marad.

- **Más résztvevő cellakijelölése a CSV olvasó nézetében elcsúszott az üres sorok miatt** (2026-11-24)
  - Ok: az olvasó nézet kihagyja az üres sorokat, a kijelölés és a dupla kattintással megnyitott cella viszont a fájl sorai szerint számol.
  - Javítás: a nézet sorai a fájlbeli sorszámukat viszik (`parseCSV` `index`, `data-row`); a társak kijelölése és a kattintott cella ebből számol (`editor.js`).

- **`Tests/Editor/gestures.mjs` elbukott** (2026-11-24)
  - Ok: a teszt a szerkesztő korábbi állapotát ellenőrizte (Mentés gomb és „Resign”, kurzor a vászon attribútumán, SVG-mintás rács, `confirm`-os fájltörlés, kör alakú végpontfogó, külön alátét a saját vonal-kijelöléshez).
  - Javítás: a teszt a mostani működéshez igazodik (automatikus mentés, kurzor-pajzs, vászonra rajzolt rács, lomtár-párbeszéd, `wire-own` osztály); a hamis DOM megkapta a hiányzó részeket. A szerkesztő kódja emiatt nem változott. Új esetek: `.thnode` behúzás, csomag-ZIP felismerése, fájltörlés a lomtár-párbeszéddel.

- **Közös fájlok: a pillangó ikon és az átnevezett fájlnév a többi lapon régi állapotot mutatott** (2026-11-24)
  - Javítás: olvasáskor a szerver adja a tulajdonos mappa szerinti fájlnevet és publikus állapotot (`resolvedFileNames`, `Model.swift`); .web hivatkozásnál a .web mappa beállításából.

- **Közös könyvtárbeli szövegfájl tartalma nem jelent meg a megtekintőben** (2026-11-24)
  - Javítás: a `fileTexts` a `Public/common` fájljait is beolvassa (`CommonLibrary.file`).

- **Lomtárba tett közös fájl visszavonással nem jött vissza** (2026-11-24)
  - Javítás: a lomtárba tétel feljegyzi a fájl lomtárbeli helyét (`archivedFiles`), a visszakerülő doboz mentésekor a fájl visszaáll – saját és másik lapról hivatkozott doboznál is (`trashTarget`, `restoreArchivedShared`).

- **`common` nevű projekt létrehozható volt** (2026-11-24) – a név foglalt (a `/common/` a közös könyvtár címe).

- **Safari: nagyítás közben ugrált a háttérrács** (2026-11-24)
  - Ok: a rács csempézett CSS-háttér volt, a böngésző a csempe méretét egész képpontra kerekíti; tört rácsköznél ez csempénként összeadódik (kis nagyításnál nagy, nagy nagyításnál kicsi elcsúszás, lépésenként változva).
  - Javítás: a rács `<canvas>` elemre rajzolódik, pontos helyekre (`drawGrid`, `editor.js`; `perfOptions.grid = "draw"`). A felhasználó Safariban megerősítette, hogy az ugrálás megszűnt. A rajzolt rács sebessége Safariban nincs mérve.

- **Táblázat: szerkesztés elfogadása után lassan frissült, és a többi résztvevőnél az egész doboz villant** (2026-11-24)
  - Ok: 1,5 mp-es mentési késleltetés; a többi kliens az új fájlváltozat betöltéséig „…”-ot rajzolt a tartalom helyett.
  - Javítás: cellaszerkesztésnél 0,25 mp a késleltetés; betöltés közben a régi tartalom marad látható (`editor.js`, `editFileText`, `renderFileText`).

- **Táblázat: dupla kattintásra mindig az A1 cella és a bal felső sarok jelent meg** (2026-11-24)
  - Javítás: a kattintott cella nyílik meg szerkesztésre, a görgetési helyzet megmarad (belépéskor és kilépéskor is).

- **Megtekintő: a szövegfájl-, CSV- és táblázatdoboz tartalma kilógott a dobozból** (2026-11-24)
  - Ok: az oldal tartalombiztonsági szabálya (`style-src 'self'`) nem engedi érvényesülni a szerver által beírt `style` attribútumot, így a doboz magassága, a táblázat oszlopszélességei és a cellák formázása elveszett.
  - Javítás: a `viewer.js` (`bindCanvas`) a fájldobozok `style` attribútumát szkriptből állítja be. Chromiumban ellenőrizve (a dobozok a saját méretükben, görgethető tartalommal).

- **Szerkesztő: betöltéskor a vászon origója került középre, nem a kompozíció** (2026-11-24)
  - Javítás: a kezdő nézet és a „Mind” gomb az objektumok határoló dobozának közepére áll (`contentBox`, `fit`), mint a megtekintő.

- **Táblázat: a félkövér betű megváltoztatta a táblázat szélességét** (2026-11-24)
  - Ok: a `table-layout: fixed` kifejezett táblázatszélesség nélkül nem érvényesül, a böngésző a tartalomhoz igazította az oszlopokat.
  - Javítás: a táblázat szélessége az oszlopszélességek összege (szerkesztő: `tableWidth`, szerver: `TableHTML.render`).

- **A buboréksúgó nem követte a szöveg igazítását, és táblázat szerkesztése közben is megjelent** (2026-11-24)
  - Javítás: `showTooltip` igazítás-paramétere (szerkesztő: a doboz igazítása; megtekintő: `data-align`); szerkesztett táblázaton / CSV-n nincs súgó.

- **Más felhasználó által fogott szövegfájl- / táblázatdoboz görgethető volt** (2026-11-24)
  - Ok: a foglaltság csak a doboz megfogását és a görgőt zárta; a görgetősáv (natív, illetve Safariban a saját) húzása nem ment át a foglaltság-ellenőrzésen.
  - Javítás: foglalt dobozon a görgethető rész és a saját görgetősáv nem kap egéreseményt (`.node.occupied :is(.node-note, .tn-sb)`, `Public/app.css`). Két böngészőlappal ellenőrizve: a fogott táblázaton a sáv helyén a kattintás a doboz felületére esik, a szabad dobozon minden változatlan.

- **Safari 18: a szövegfájl-, CSV- és táblázatdoboz görgetősávja egérrel nem volt húzható (a görgő működött)** (2026-11-24)
  - Ok: WebKit-hiba. SVG foreignObject-beli görgethető elem natív görgetősávja nem húzható, ha fölötte SVG-transzform áll (próbaoldallal igazolva: eltolásnál a függőleges, nagyításnál mindkét sáv halott). A sávra nyomott egér mozgását a WebKit a sávnak adja, a lap `pointermove`-ot sem kap, ezért kívülről nem pótolható. Az első két kísérlet (a sáv felismerése vászonkoordinátából, védelem a `pressNode`-ban) ezért nem segített.
  - Javítás: WebKitben a natív sáv rejtve van, a görgethető elem mellett saját, normál elrendezésű sávok állnak (`Public/scrollbar-drag.js`, `.tn-sb*` az `app.css`-ben); más böngészőben marad a natív sáv. Automatizált Safari 18.6-ban ellenőrizve (hüvelyk húzása, sínre kattintás, mindkét irány; CSV, táblázat, táblázatszerkesztő).
- **Safari: a táblázat szerkesztési módjában semmi nem volt kattintható** (2026-11-24, a fenti hiba keresésekor)
  - Ok: a `.tn-table-editor` `position: relative` volt; Safariban a foreignObject-beli pozicionált elem és minden leszármazottja nagyított vásznon kiesik a találatvizsgálatból (a kattintás a mögötte lévő `.node-note`-ra ment).
  - Javítás: a szerkesztő gyökere és a billentyűzet-nyelő (`.tn-sink`) nem pozicionált. Automatizált Safariban ellenőrizve: a cellakattintás kijelöl.

- **Sötét kitöltésű szövegfájl- és táblázatdobozon a tartalom olvashatatlan volt** (2026-11-24)
  - Ok: a szerkesztőben a `.node-file` rögzített sötét szövegszíne (`#182335`) felülírta a doboz szövegszínét; a doboz kitöltése a palettából jött, így sötét témában sötét alapon sötét szöveg állt. A táblázat szerkesztési módja rögzített fehér volt.
  - Javítás: a tartalom a doboz szövegszínét (`textColor`, paletta 1) használja a szerkesztőben is; a táblázatszerkesztő a doboz hátteréből és szövegszínéből kevert színeket kap. Új: Keret be/ki kapcsoló (`frame: false`) szövegfájl-, kódfájl- és táblázatdobozon, és Szövegszín választó a táblázat Megjelenés paneljén. Teszt: `textFileBoxFrameCanBeSwitchedOffInEveryBackgroundMode`. Böngészőben nem ellenőriztem (a helyi `projects` mappa üres volt).

- **`run.sh`: a relatív `--project:` / `--tls-*` útvonal a `server/` mappához képest értelmeződött** (2026-11-24)
  - Ok: a `run.sh` `cd`-vel a `server/` mappába lép, mielőtt a kapcsolókat a binárisnak adja, így a relatív útvonal nem a hívó mappájához képest értendő, ahogy a súgó írja.
  - Javítás: a `run.sh` a `--project:`, `--tls-dir:`, `--tls-cert:`, `--tls-key:` relatív értékét (és a `~/`-t) a hívó mappája alapján abszolúttá teszi (`a651dbb`).

- **`--project:~/Project/ThinkProject` mellett nem lehetett belépni** (2026-11-24)
  - Ok: a kapcsoló működött, de az új, üres adatmappában nincs `.settings.json`, így felhasználói fiók sincs; erről semmi nem tájékoztatott.
  - Javítás: indításkor kiírja az adatmappát, fiók nélkül indításkor és a login oldalon is jelzi, hogyan hozható létre az első admin (`5b1259a`). Teszt: `loginPageWarnsWhenTheDataFolderHasNoAccounts`.

- **A projekt áthelyezése után a build és a tesztek nem indultak** (2026-11-24)
  - Ok: a `server/.build` a régi helyre (`~/Work/ThinkNodes`) fordított modul-cache-t tartalmazott; a Swift, a Node.js és a Chromium a `~/X-Code/RunTime` alá került, a szkriptek a régi helyen keresték.
  - Javítás: elérési utak frissítve (`build.sh`, `install.sh`, `WebPresentation.swift`, `RunTime/NodeJS/env.sh`), a régi build törölve és újraépítve (`942dc78`).


- **Táblázat: tizedesjegyek és törtek kezelése** (2026-11-24, audit; részletek: server/docs/EXCEL.md 12. fejezet)
  - `ROUND(1,005;2)` = 1 volt (lebegőpontos hiba), F2+Enter adatvesztés (10 jegyre kerekített érték), `0,1+0,2=0,3` HAMIS volt, `=1,5*2` hibát adott,
    10^21 fölötti formázott szám hibás volt, „1,5e3” szöveg maradt, magyar CSV-ben „1.234” = 1,234 lett.
  - Javítás Swiftben és JS-ben azonosan, közös tesztesetekkel és 3544 esetes differenciális fuzz-teszttel (`Tests/Editor/table-fuzz.mjs`). Új: tört bevitel és tört formátum.

- **Szövegfájl-doboz „…” maradt újratöltés után, ha a fájlt korábban szerkesztették** (2026-11-24, a táblázat tesztelésekor)
  - Ok: a szöveget betöltő figyelő a `file.rev` régi értékével (0) kérte le a fájlt; a `rev` utána a figyelőn kívül változott meg (1), így az aktuális változat sosem töltődött be.
  - Javítás: közös `loadFileText`; a kirajzolás is elindítja a hiányzó változat betöltését (`Public/editor.js`). Szöveg- és táblázatdobozra egyaránt érvényes.

- **`ThemeTests.themeProjectRoundTrip` elbukott** (2026-11-24)
  - Ok: a teszt még a régi, 3-as vastagságú üvegkeretet várta; a renderelés szándékosan egységes, 1,6-os keretet ad („minden doboz kerete egyforma vastag”).
  - Javítás: a teszt elvárása frissítve (`Tests/ThinkNodesTests/ThemeTests.swift`).

- **Linkes doboz szövege kétszer látszott, ha az előnézet ki volt kapcsolva** (2026-11-24)
  - Ok: `staticPreview: true` mellett a szöveg a dobozban is kirajzolódott (`labelLayout`), és megjegyzésként a doboz alatt is.
  - Javítás (döntés szerint a doboz alatti marad el): a doboz alatti megjegyzés csak akkor jelenik meg, ha az előnézeti kép tölti ki a dobozt (`Rendering.swift` `noteBelow` + `fillsWithPreview`, `Public/editor.js` ugyanígy). Teszt: `staticPreviewLinkBoxShowsTextOnlyOnce`.

- **A szerkesztő `.web` előnézet-frissítése hibát dobott: `awaitWebPreview is not defined`** (2026-11-23)
  - Ok: a `168ca5b` commit az `editor.js`-ben használja az `awaitWebPreview`-t, de az importja kimaradt; minden `.web` dobozos lapon konzolhiba, a háttérben elkészült előnézet nem töltődött újra.
  - Javítás: `import {awaitWebPreview} from "./web-preview-refresh.js"` (`Public/editor.js`).

- **Kijelölt kép eltűnt, csak a Kiemelés árnyéka maradt** (2026-11-23)
  - Ok: a saját kijelölés `filter: brightness(1.15)`-öt tett a foreignObjectben lévő `<img>`-re; a WebKit a transzformált SVG-ben lévő HTML-elemre tett CSS-szűrőt gyakran nem rajzolja ki.
  - Javítás: a szabály törölve (`Public/app.css`); a kijelölést a meglévő `selection-own` SVG-körvonal jelzi, a Kiemelés árnyéka megmarad.

- **A munkalap minden presence-kérésnél teljes lemezolvasással töltődik be** (2026-11-23, teljesítmény)
  - A `Collaboration.presence` minden `poll`/`select`/`ping` műveletnél `store.load`-ot hív (beállítások, házirend-lánc, munkalapfájl dekódolása és validálása, mappa listázása), a két globális zár alatt. N résztvevőnél egy mentés N teljes betöltést indít sorban.
  - Az optimalizálási tervben szerepel (memóriabeli munkalap-gyorsítótár); megbeszélendő.
  - Javítás: memóriabeli gyorsítótár (munkalapok, házirendek, beállítások), presence 49 → 6 ms (`87e94f6`).

- **A sorok túl rövidre tördelődtek, sorkizáráskor nagy hézagokkal** (2026-11-23)
  - Ok: a tördelés fix oszlopszámmal dolgozott (`betűméret × 0,65` karakterenként), a valódi átlag ~0,45–0,5 em, így a sorok csak 55–75%-ig teltek.
  - Javítás: szélességalapú tördelés böngészőben kalibrált betűszélesség-táblával (kis/nagybetű, keskeny/széles jelek, számok, félkövér ×1,07, rögzített szélességű betűtípus 0,62 em). A JS (`Public/geometry.js` `letterWidth`, `wrapRuns`) és a Swift (`Rendering.swift` `letterWidth`, `CanvasMarkdown.swift` `wrapMarkdown(limit:width:)`) pontosan ugyanott tör; böngészőben ellenőrizve hat dobozon (címsor, félkövér, kód, lista, idézet, három betűtípus, automatikus méret).
  - Sorkizárás: szokásos (a bekezdés utolsó sora balra zárt), döntés szerint.
  - Tördelés csak a Text tartalmú dobozokra: a fájldoboz megjegyzése egysoros, formázás nélküli felirat („…”, teljes szöveg a `title`-ben), a link felirata összenyomás helyett „…”-tal rövidül (`fitCaption`).

- **Sorkizárás betűritkításként jelent meg** (2026-11-23, a TODO.md-ből)
  - Ok: a sorkizárt sor `textLength` + `lengthAdjust="spacing"` attribútumot kapott; ez az SVG-ben a betűk közé osztja szét a helyet („s o r k i z á r á s”), nem a szavak közé.
  - Javítás: a sor `data-justify` célszélességet kap, és a `Public/justify.js` a böngészőben mért valódi szélesség alapján `word-spacing`-gel tágítja a szóközöket (szerkesztő: `CanvasScene` mount/update; megtekintő: `bindCanvas`). JavaScript nélkül (SVG-export, előnézeti kép) a sor balra zárt.
  - Érintett kód: `Public/justify.js`, `Public/editor.js`, `Public/viewer.js`, `Sources/ThinkNodes/Rendering.swift`.

- **Jelszó-hash (bcrypt) a globális tárolózár alatt fut, közben az egész szerver áll** (2026-11-23)
  - Feloldás, `.web` feloldás, jelszó beállítása (dokumentum és prezentáció) a `WorksheetStore`, illetve a `Collaboration` zárját tartva futtatta a bcryptet (~0,1–0,3 s), ezalatt minden más kérés (presence, mentés, megtekintő) várt.
  - Javítás: a hash-elés és az ellenőrzés a záron kívül történik; zár alatt csak a hash-ek kiolvasása és a beírás marad.
  - Érintett kód: `Sources/ThinkNodes/Model.swift` (`unlock`, `unlockWeb`, `manage`, `setWebPresentation`), `Collaboration.swift`, `Server.swift`.

- **Blokkoló fájlműveletek és SVG-renderelés a NIO event loopon** (2026-11-23)
  - A megtekintő oldal (`access`, `contents`, `fileTexts`, gyerekek jogai), a szerkesztő oldal jogellenőrzése, a főoldal és a melléklet `settings()` olvasása, valamint az SVG-export renderelése az event loopon futott, így a lassú lemez vagy nagy munkalap a többi kapcsolatot is megakasztotta.
  - Javítás: ezek a `threadPool`-on futnak.
  - Érintett kód: `Sources/ThinkNodes/Server.swift`.

- **Mentés és távoli frissítés után a szerkesztő minden dobozt és vonalat újraszámol** (2026-11-23, teljesítmény)
  - A `rebaseWorksheet` és a `copy()` minden csomópontból új objektumot csinált, így az objektumazonosság szerinti gyorsítótárak (`nodeLayout`, `wireGeometry`, `cachedWireDrawing`) minden mentéskor (gépelésnél, húzás végén ~70 ms-onként) kiürültek, és a teljes vászon újra tördelődött és újrarajzolódott.
  - Javítás: a változatlan csomópontok és vonalak a régi objektumot kapják vissza (`keepUnchanged()`), így csak a ténylegesen változott elemek számolódnak újra.
  - Érintett kód: `Public/editor.js`, `Public/editor-history.js` (`sameValue` export).

- **Hibás munkalapelem csendben elveszhet mentéskor** (2026-11-22)
  - Javítás: a `Worksheet` dekódolója már nem dobja el csendben a hibás elemeket; hibás elem esetén a mentés hibát ad.
  - Érintett kód: `Sources/ThinkNodes/Model.swift` `Worksheet.init(from:)`.

- **Kicsinyítésnél vagy kis dobozban a felirat túllóghat** (2026-11-22)
  - Javítás: ha egy sor sem fér el a dobozban, a címke nem rajzol sort vagy pontokat (`Public/geometry.js` `labelLayout()`, `Sources/ThinkNodes/Rendering.swift` `ideaDrawing()`).

- **A `.web` előnézeti kép hiányzik** (2026-11-22)
  - Javítás: az `_tn-preview` végpont nem ad 404-et; ha nincs `preview.png`/`screen.png`, helyettes SVG-t ad. Valódi előnézethez a mappába kell képet tenni.
  - Érintett kód: `Sources/ThinkNodes/WebPresentation.swift`, `Sources/ThinkNodes/Server.swift`.

- **Régi, 2-es sémájú munkalap nem nyitható meg** (2026-11-22)
  - Javítás: a 2-es séma betöltéskor 3-as sémára konvertálódik (`Sources/ThinkNodes/WorksheetFile.swift` `decodeFile`); a `WorksheetTests` lefedi.

- **.web prezentáció előnézeti képe nem jelenik meg a dobozon** (2026-11-22)
  - Javítás: a linkes doboz a `_tn-preview` címet feloldott prezentációnál mindig megkapja, a 404 helyett helyettes kép látszik (`Rendering.swift` `target()`, `Model.swift` `webPresentations`).

- **Sorkizárás nem működik és újraállítja a pozicionáló gombokat** (2026-11-22)
  - Javítás: a pozicionáló gombok már nem törlik a sorkizárást; a gomb állapota csak az igazítástól függ (`Public/editor.js`).
  - Megjegyzés: a sorkizárás tényleges vizuális megjelenése böngészőben még nincs ellenőrizve.

- **A bal felső sarokban kódrészlet vagy hibás keret látható** (2026-11-22)
  - Javítva: a felhasználó szerint már nincs jelen; nem történt célzott javítás, a forrását nem azonosítottuk.

- **Sok szöveget tartalmazó (sorkizárt) doboz mozgatása nagyon lassú** (2026-11-25)
  - Javítva: a sorkizárás húzás közben képkockánként újramérte a sorokat; most csak változáskor mér (`Public/justify.js`). Safari, `projects/b` másolata: 30 → 54 fps.

- **Sorkizárás kapcsoló hatástalan (mindig balra zárt)** (2026-11-25)
  - Javítva: a Safari SVG-szövegen nem alkalmazza a `word-spacing`-et; a sorok `dx` listával tolódnak (`Public/justify.js`). Safari képernyőképen ellenőrizve.

- **Konténerben a 9 gombos igazítás hatástalan** (2026-11-25)
  - Javítva: a körbefuttatott szövegre is hat a függőleges igazítás; a vízszintes a sor szabad helyén belül. Safari képernyőképen az alsó igazítás ellenőrizve.

- **Kijelölt / mozgatott konténer háttere eltűnik** (2026-11-25)
  - Ok: SVG-szűrő a kijelölt doboz felületén, amit a Safari nagy dobozon nem rajzol ki. Javítva: szűrő helyett fedőréteg. Az új megjelenés szemmel még nincs megnézve (BUGS.md).

- **Körbefuttatott konténerben a belső doboz mozgatása nagyon lassú** (2026-11-25)
  - Javítva: a megváltozott szöveg egy lépésben cserélődik, a sorkizárás rajzolás előtt számolódik (CHANGES.md). Safari: 14 → 42 képkocka/mp sorkizárással, 55 anélkül. A felhasználó a kijelölt konténer háttérhibájának megszűnését is megerősítette.

- **Konténerben az alulra igazítás nem működik (mindig felül vagy középen)** (2026-11-25)
  - Javítva: a kezdőpont keresése nem esik vissza felülre, csak annyival megy feljebb, amennyivel a szöveg kilógna.

- **Sorkizárt dobozban a címsor is sorkizárt** (2026-11-25)
  - Javítva: a címsor sosem sorkizárt, a vízszintes igazítást követi.

- **Vastag vonal túllóg a nyílhegyen a megtekintőben / exportban** (2026-11-25)
  - Javítva: a szerveroldali rajz is a nyílhegy talpáig húzza a vonalat (CHANGES.md). Safari képernyőképen ellenőrizve.

- **Alt + téglalappal kijelölt sok vonal: lassulás, időnként eltűnő vonalak** (2026-11-25)
  - Javítva: a saját kijelölésű vonal nem kap SVG-szűrőt, hanem a vonal alá rajzolt sávot (CHANGES.md).

- **Konténerben lévő csomópont az első mozdításra feloldódik a konténerben; csomópont nem húzható konténerbe** (2026-11-25)
  - Javítva: konténerre ejtve a csomópont a konténer tartalma lesz; dobozra ejtve változatlanul feloldódik.

- **Másik konténerbe áthúzott doboz az elengedésig eltűnik** (2026-11-25)
  - Javítva: a húzott doboz húzás közben a többi doboz fölé kerül.

- **Bármelyik doboz húzásakor átrendeződik a konténerek körbefuttatott szövege** (2026-11-25)
  - Javítva: a húzás közbeni kerekítés csak az éppen húzott belső dobozra vonatkozik.

