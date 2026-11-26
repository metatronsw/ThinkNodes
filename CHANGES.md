# Változások

## 2026-11-26 – Sötét módú kártyaárnyék, „Új projekt” / „Importálás” keret, előnézet-fájlnevek verziószám nélkül

- **Projektkártya sötét módban:** a kiemelkedés árnyéka sokkal erősebb (két, közel fekete árnyék: `0 30px 56px 6px` és `0 10px 18px 2px`), hogy a sötét háttéren is látsszon.
- **Új projekt / Projekt importálása (.zip):** rámutatáskor kiemelő színű keret (a kártyák gyors, 0,09 mp-es áttűnésével). Safariban ellenőrizve.
- **Előnézet-fájlnevek:** a `-v12` utótag kikerült: `.<lap>.preview.svg` / `.<lap>.preview-dark.svg` (rajz) és `.<lap>.preview.webp` / `.<lap>.preview-dark.webp` (főoldali kép). Verziószám nem kell: a gyorsítótár csak akkor érvényes, ha újabb a lapnál és a szerver indulásánál, a rajzolás minden változása pedig új build és újraindítás.
- Az `.svg` előnézet használati helyei: a `.webp` forrása; a főoldali kártyák tartaléka (eszközök nélkül, illetve `?previews=svg`); a projekt- és megtekintő oldal „További munkalapok” kártyái; a munkalapra mutató linkes doboz kitöltő képe (`?fill=1`, szerkesztő és megtekintő); a vászonpanel Megjelenés bélyegképe.
- Teszt: minden Swift-teszt átmegy (a gyorsítótár-fájlnevek a tesztekben is frissítve). Verzió: `app.css?v=72`; a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Projektkártya rámutatás: kivilágosodás nélkül, kétszer gyorsabb kiemelkedés

- A felhasználó jelezte: Safariban a kártya kivilágosodása miatt a többi kártya is felvillant. A kivilágosodás (a felület áttetsző fehér rétege, a keret és a háttérkép világosodása) kikerült – a szabály közös, így a régi SVG-s változatra (`?previews=svg`) is érvényes. Marad: 4 px kiemelkedés és árnyék, 0,18 helyett 0,09 mp alatt. A kártyák saját rétegen állnak (`will-change: transform`), hogy a kiemelkedés ne fesse újra a szomszédokat. Safariban ellenőrizve (mindkét változat): emelkedés és árnyék van, a keret, a háttérkép és a felület változatlan. Verzió: `app.css?v=71`; a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Főoldal: fix méretű, elmosott .webp előnézetek; kártya rámutatás-effekt

- **Előnézeti képek:** a projektkártyák háttere fix 320 × 180-as, már elmosott `.webp` (`PreviewRaster.swift`; a kártya csak méretezi, CSS-szűrő nélkül). Folyamat: forrás a munkalap SVG-előnézete vagy a szerkesztőben beállított előnézeti kép (PNG, JPG, GIF, WebP, SVG; data URI-ként egy burkoló SVG-ben) → `rsvg-convert` 336 × 196-os vásznon, 1 px elmosással (8 px túlnyúlás) → csövön `cwebp`, amely a közepéből kivágja a 320 × 180-at (minőség 70). Egyetlen statikus képkocka, átlátszóság nélkül; nincs ideiglenes fájl. Mentés: `.<lap>.preview.webp` / `.<lap>.preview-dark.webp`, mindig felülírva; elavult képnél egyszer még a meglévő megy ki, az új a háttérben készül. Eszközök nélkül a régi SVG-előnézet marad. API: `/api/preview/<lap>?format=webp`; a főoldal `?previews=svg` kapcsolója a régi változatot mutatja (méréshez).
- **Mérés** (`Tests/Perf/main-page.py`, Safari, 10 betöltés mediánja, 5 projekt, csendes gépen, két független kör):

  | | régi (SVG + CSS-elmosás) | új (.webp) | különbség |
  |---|---|---|---|
  | `load` esemény | 379 / 368 ms | 66 / 63 ms | −83 % |
  | képek letöltve és dekódolva | 502 / 365 ms | 70 / 70 ms | −81–86 % |
  | utána az első képkockák (festés) | 113 / 70 ms | 20 / 16 ms | −78–82 % |
  | **képek a képernyőn** | **595 / 518 ms** | **90 / 84 ms** | **−84–85 %** |
  | letöltött méret | 563 KB | 11 KB | −98 % |

  A képek egyenként 0,6–3,8 KB-osak; az első, egyszeri elkészítés lapként ~0,8–1,9 mp (a szerveren, a főoldal ezt csak a legelső alkalommal várja meg).
- **Rámutatás a projektkártyán:** a kártya 4 px-t emelkedik, alatta árnyék, a felülete (áttetsző fehér belső réteg, minden témában) és a kerete kivilágosodik, a háttérkép erősebb; csökkentett mozgásnál nincs emelkedés. A rétegzett „papírlap” árnyék megmarad.
- Telepítés: a `deploy/install.sh` Fedorán telepíti a `librsvg2-tools libwebp-tools` csomagot, macOS-en Homebrew-val (ha hiányzik); README „Főoldali előnézeti képek”.
- Teszt: `previewRasterIsAFixedSizeWebP` (320 × 180, egy statikus képkocka, nincs átlátszósági réteg, kicsi), a munkalap-integrációs teszt a `format=webp` választ és a `.preview.webp` fájlt is ellenőrzi; minden Swift- és JS-teszt átmegy. Verzió: `app.css?v=70`. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Takarítás (a felhasználó engedélyével)

- Törölve: a próbaprojekt (`projects/proba-igazitas`: próbalap, `jegyzet.md`, `tabla.tntable`, előnézetek), a 12 régi, hibás előnézeti gyorsítótár-fájl (`projects/**/.*.preview-v11*.svg`, a `.trash` kivételével; a v12-es fájlok újrakészülnek), és a teszthez a scratchpadban létrehozott ideiglenes git worktree. A főoldal a próbaprojekt nélkül töltődik be.

## 2026-11-26 – Előnézeti képek: teljes ellenőrzés és védőteszt

- A felhasználó jelezte: az előnézeti képek hibája nem a mai változtatásoktól volt, régóta fennállt. Az ok a táblázat lezáratlan `<col>` eleme volt (az önálló SVG, amiből az előnézet készül, szigorú XML); a javítás (önlezáró `<col/>`, előnézet-gyorsítótár v12) az előző commitban van.
- Ellenőrizve minden helyi munkalapon (7 lap): az előnézet (világos / sötét), a munkalapra mutató linkes doboz képe (`fill=1`), a vászonpanel bélyegképe és az SVG-letöltés mind érvényes XML (xmllint); Safariban a főoldal mind a 6 kártyája, a projektoldal allapkártyája és a Megjelenés panel bélyegképe betölt. A böngésző nem tartja meg a régi, hibás képet (az előnézet válasza `no-store`).
- Új védőteszt: `standaloneSVGIsWellFormedXMLForEveryBoxType` – egy lap minden doboztípussal (markdown listával, vonallal, sortöréssel, linkkel; .md, .txt, kód, CSV, táblázat, „Tartalom a dobozhoz” táblázat, kép, hang, dokumentum), a különleges karakterekkel (`<`, `&`), és az önálló SVG-t XML-elemzővel ellenőrzi. A régi hibát elkapja (lezáratlan `<col>` mellett elbukik).

## 2026-11-26 – Táblázat: fejlécek a dobozon kívül, „Tartalom a dobozhoz”; kurzorcsoport, témafüggő fogók, napló, 16:9 kártyák

- **Javítva (az előző kör hibája):** a jelenlévők gombjai a bal alsó sarokba kerültek – a levágás elleni `margin: -3px` felülírta a jobbra toló `margin-inline-start: auto`-t. Újra jobb alul vannak.
- **Táblázat szerkesztése, fejlécek a dobozon kívül (a felhasználó választása: „A”):** a sorszámok sávja a doboztól balra, az oszlopbetűk és a képletsor a doboz fölött (a fájlnév helyén); a görgethető rács pontosan az olvasó nézet helyén áll, azonos belső térközzel, betűvel és görgetéssel, így szerkesztésbe lépéskor a tartalom nem mozdul (Safariban mérve: 0,2 px-en belül; előtte a képletsor és a becsült görgetés miatt elugrott). A foreignObject szerkesztés közben 40 px-lel balra és 26 px-lel fölfelé nő. A fejlécsorok szerkesztéskor is az olvasó nézet hátterét kapják.
- **„Tartalom a dobozhoz” (a felhasználó választása: a tartalom nagyítása, torzítás nélkül):** új kapcsoló a táblázat panelen (és a gyors eszközökben, `content-fit`); a doboz tárolt `contentFit` tulajdonsága. A táblázat egyenletes nagyítással / kicsinyítéssel pontosan a doboz belsejébe kerül; a tárolt oszlopszélességek és sormagasságok nem változnak. Megvalósítás: a táblázat saját foreignObject-ben, SVG-szintű `scale()`-lel (mint a vászon nagyítása). Kipróbált és elvetett utak: CSS `zoom` és betűméret-szorzó (Safariban a legkisebb betűméret beállítás – ezen a gépen 14 px – visszanöveli a betűt), CSS `transform` a foreignObject-en belül (Safari nem rajzolja ki). Szerkesztéskor ugyanez a skála, a fejlécek közvetlenül a táblázat mellett; a megtekintő és az SVG-export ugyanígy (`Rendering.swift fittedTable`, `TableHTML.size`).
- **Átméretező fogó:** az egyedül kijelölt doboz jobb alsó fogója csak akkor látszik, ha a mutató a sarok közelében van; a fogók alakja témafüggő (`resizeHandle`; a téma `graphics.handle` értékével felülírható): Liquid Glass – kör, alap – négyzet, szabadkézi (WhiteBoard) – telt pötty, tervrajz (Blueprint) – rombusz, üveg (VectorStudio, NeonGlow) – lekerekített négyzet.
- **Kijelölt nyilak (javítás):** a nyílhegy körüli „árnyék-nyíl” helyett egyenletes körvonal a szár és a nyílhegyek körül; ami a csatlakozó dobozokba esne, azt maszk vágja le.
- **Kurzor-eszköz:** a kurzorgomb hosszú nyomásra (0,45 mp) vagy jobb kattintásra kinyit egy csoportot a többiek kurzorának megjelenésével: „csak avatar” (az avatar a mutató, nyíl nélkül), „nyíl + avatar”, „nyíl + név”; a sarkában kis jel mutatja, hogy van csoportja. A külön kurzorcímke-gomb megszűnt (szerkesztő és megtekintő).
- **Napló:** új „Vissza” gomb a hívó munkalapra (szerkesztő vagy megtekintő, a `from` paraméterből; csak a projekten belüli helyi címet fogadja el, egyébként a projekt megtekintője).
- **Főoldal:** a projektkártyák 16:9 arányúak.
- **Javítva (régi hiba):** a táblázatot tartalmazó munkalapok előnézeti képe (a főoldali kártyák háttere) betölthetetlen volt: a táblázat HTML-jének lezáratlan `<col>` eleme az SVG-ben (XML) érvénytelen. Most önlezáró; az előnézet-gyorsítótár v11 → v12 (a régi, hibás fájlok újrakészülnek).
- Teszt: új Swift-teszt `contentFitTableIsScaledAsAWhole` (skála, üres jegyzet, önlezáró `<col>`, mentés); `./test.sh --swift` és minden JS-teszt átmegy. Safariban ellenőrizve: jelenlévők helye, fogó közelségre, Liquid Glass kör-fogó, kurzorcsoport (JS-eseménnyel), kijelölt nyilak, táblázat szerkesztésbe lépése ugrás nélkül (normál és skálázott módban), skálázott táblázat olvasó / szerkesztő nézetben és a megtekintőben, napló „Vissza”, 16:9 kártyák és előnézeti képek. Verziók: `editor.js?v=100`, `app.css?v=69`, `viewer.js?v=32`. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Egységes gombok, eszköztár-állapotok, vászonpanel, vonal- és Liquid Glass-javítások, táblázatkeret

- **Egységes gombok:** minden gomb (eszköztár, panelek, gyors eszközök, helyi menü, jelenlévők, fejléc) ugyanazokból a változókból kapja a felületét, keretét, lekerekítését (`--btn-*`, app.css vége); a téma (sötét mód, üveg, Liquid Glass) csak a változókat állítja. Rámutatáskor minden gomb kiemelődik (háttér + kiemelőszínű keret + gyűrű, mint eddig csak a gyors eszközöknél).
- **Eszköztár: a bekapcsolt funkciók látszanak** (rács, rácsra illesztés, vászonzár, előadás, egérmegosztás, kurzorfelirat, lézer, csevegés, teljes képernyő) minden témában. Ok: a sötét mód egy túl erős szabálya (`:is()` listában egy `input[type=number]:disabled` választó) felülírta az `aria-pressed` jelzését. A teljes képernyő gomb (szerkesztő, megtekintő) új állapotjelzést kapott. A jelenlévők gombjai ugyanolyanok, mint az eszköztáré, és a soruk nem vágja le a szélüket.
- **Vászonpanel:** a Leírás üresen egysoros (pontosan a Cím mező magassága), a szöveggel legfeljebb 4 sorig nő, kézzel bármekkorára húzható. A „Megjelenés” gomb a vászon közepén felugró panelben nyitja meg a téma / paletta / háttérszín / rácsköz / előnézeti kép beállításait (Esc vagy Bezárás zárja). Új „Napló” gomb a projekt naplójára.
- **Vonalak:**
  - Vastag, animált vonal végpontjának húzásakor a nagy nyíl a dobozon maradt: Safari a futó `animateTransform` mellett nem rajzolta át a nyíl helyét. Húzás közben a vonal animációja (lüktetés, pötty) szünetel, és a lüktető nyíl / pötty helyváltozáskor új elemként készül (a távoli mozgatásnál is).
  - Mozgatás közben az animációs pötty nem marad a régi helyén: húzás alatt eltűnik.
  - Kijelölt vonal: a sáv a látható szárat követi, szögletes véggel (nem lóg a dobozba), a nyílhegyek is kapnak sávot (csúcsuk a nyíl csúcsa); a szár és a nyilak sávja közös, egyenletesen áttetsző csoport.
  - S-vonalon a pötty a látható görbét követi (eddig a csúcstól csúcsig tartó, eltérő görbét).
  - Csomópont: a kör körül 13 képpontos (nagyítástól független) fogható sáv a vonalvég fogantyúja fölött; Safariban 9–12 px-re a középponttól is kijelölődik.
- **Liquid Glass:** megszűnt a kattintáskor szétfutó gyűrű; a csevegőablak a panelekkel azonos üveghatást kap; a kép rámutatáskor nem tűnik el (a képre tett CSS-szűrőt Safari a foreignObject-ben nem rajzolta ki, a szűrő kikerült); a jelenlévők gombjai egységesek.
- **Táblázat:** a cellakeret átlátszatlan (a szövegszín a doboz felületével keverve, `--tn-paper`; a megtekintő is megkapja): félig átlátszó kerettel az összevont keretek a csomópontokban egymásra rajzolódtak, ott erősebbnek látszottak.
- Teszt: `gestures.mjs` (Megjelenés felugró panel, Napló link, Esc, a nyíl kijelölés-sávja, a vonal szára). Swift- és JS-tesztek átmennek. Safariban ellenőrizve: végponthúzás és dobozhúzás közben (lenyomva tartott egérrel), kijelölt vonal, csomópont kattintás, eszköztár három témában világos / sötét módban, vászonpanel, Megjelenés panel, csevegőablak (Liquid Glass), táblázat keretszíne. Verziók: `editor.js?v=98`, `app.css?v=66`, `viewer.js?v=30`. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Vászonszínű doboz textúrás vásznon: az alatta lévő elemeket is takarja

- A felhasználó döntése alapján: textúrás vásznon (Liquid Glass, WhiteBoard) a vászonszínű doboz nem valódi átlátszóság, hanem „ablak a vászonra”: a vászon textúrája látszik benne, a rács, a saját árnyéka és az alatta álló dobozok, vonalak, árnyékok nem.
- Szerkesztő: ami a rajzolási sorrendben a vászonszínű doboz alatt áll és átfedi (doboz az árnyékával, vonal), az maszkos csoportba kerül, a maszkban a doboz alakja kivágva (`underMasks`, `UnderMasks`). Így a valódi, mozgó Liquid Glass fényfoltok látszanak; a doboz gyermekei (a tartalma) fölötte vannak, azok látszanak. A maszkok helye külön komponensben frissül, a jelenet csak akkor rajzolódik újra, ha a takart elemek köre változik. A Liquid Glass árnyéka a vászonszínű dobozon álló (osztály nélkül), mert Safari a CSS-transzformos árnyékon a maszkot nem alkalmazta.
- Megtekintő és SVG-export: a doboz felülete a vászon hátterének (szín + fényfoltok / maszat, `canvas-art`) a doboz alakjára vágott másolata (`canvasCopy`); így eleve takarja a rácsot, az alatta lévőt és a saját árnyékát. (Mintázattal – `pattern` – Safari a nagy csempét hibásan rajzolta, ezért vágott másolat.)
- Teszt: `paletteColorZeroIsTheCanvasSurface` bővítve (Liquid Glass: vágott másolat). Swift- és JS-tesztek átmennek. Safariban ellenőrizve a szerkesztőben (Liquid Glass és WhiteBoard: az alatta álló doboz takarva, a textúra egyezik) és a megtekintőben. Verzió: `editor.js?v=97`. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Igazítás, elosztás, sarokfogó, rácsra illesztés a sarokkal, vászonszín a paletta 0. színeként, #hex színválasztó, .md szerkesztő

- **Igazítás (csak több kijelölt doboznál):** a gyors eszközök (jobb kattintás a kijelölésen) új „Dobozok igazítása” csoportja kinyitva 6 gombot ad: bal szél / függőleges közép / jobb szél egy vonalba (oszlop), felső szél / vízszintes közép / alsó szél egy vonalba (sor). A mérce a kijelölés befoglaló téglalapja; a dobozok a tartalmukkal együtt mozognak, a konténerbe tartozás nem változik (`editor.js arrangeBoxes`).
- **Egyenlő elosztás (legalább három kijelölt doboznál):** „Dobozok egyenlő elosztása” csoport, vízszintesen és függőlegesen: a két legszélső doboz helyben marad, a többi közéjük kerül egyenlő hézagokkal (`distributeBoxes`). Leíró: `quick-tools.json` új `arrange` / `distribute` csoport és `batch` elrendezés; új ikonok: `box-align-*`, `distribute-x/y`.
- **Rácsra illesztés:** a doboz bal felső sarka kerül rácspontra (eddig a közepe); csoportos húzásnál a megfogott dobozé. Bekapcsolt illesztésnél átméretezéskor a húzott sarok is rácspontra ugrik. Csomópont továbbra is a közepével illeszkedik.
- **Átméretezés sarokfogóval:** az egyedül kijelölt doboz jobb alsó sarkán fogó látszik (fehér négyzet, nagyobb fogható terület), billentyű nélkül húzható, mint az Alt+húzás. Alt lenyomásakor ez a fogó eltűnik (akkor az Alt-os fogók látszanak).
- **Vászonszín = a paletta 0. színe:** a külön „Vászonszín” háttérmód-gomb megszűnt. A színválasztóban a 0. szín (a téma vászonszíne) mindig elöl áll; dobozháttérként a felület a munkalap háttere, a rács nem látszik át. Textúrás / effektes vásznon (Liquid Glass, WhiteBoard) a felület átlátszó: a vászon textúrája látszik, a rács a doboz alatt ki van vágva (`gridHoles`, a rácsrajzoló vásznon), a doboz saját árnyéka a dobozon belül maszkolva nem látszik (`shadowMask`). A régi munkalapok `backgroundMode: "canvas"` értéke betöltéskor 0. színű kitöltés lesz (`Model.swift`); a szerver a 0. színű kitöltött dobozt vászonszínű felületként rajzolja (`Theme.swift painted`).
- **Színválasztó:** visszakerült a rendszer színválasztója (felugró), mellette #hex mező: mutatja az aktuális szín kódját, és elfogad #rgb / #rrggbb (# nélkül is) bevitelt Enterre vagy kilépéskor; a változatlan kód nem ír felül palettaszínt. A közvetlen szín `#rrggbb`-ként mentődik, témaváltáskor megmarad.
- **.md fájl szerkesztése (javítás):** a megjelenítésben minden sortörés duplán látszott (`white-space: pre-wrap` + a cmark `<br>`-je utáni sortörés). Most a sima sortörés egy új sor, a blokkok között pontosan annyi üres sor, ahány a forrásban áll (`markdownHTML(exactLines:)`: a cmark sorpozícióiból `data-gap`), és a szerkesztő ugyanazzal a betűvel és sormagassággal (20 px; füzetlapon a sorvonal) mutatja a nyers szöveget, így a sorok szerkesztésbe lépve nem mozdulnak. A fel / le nyíl saját kezelést kapott (mindegyik dobozon szerkesztőben): a kurzor a megjelenített (tördelt) sorok szerint lép, a vízszintes helyet megtartja, Shift-tel kijelöl; a böngésző saját léptetése Safariban a foreignObject-ben ugrált.
- Teszt: új Swift-tesztek `paletteColorZeroIsTheCanvasSurface`, `markdownExactLinesKeepTheSourceSpacing`; `gestures.mjs`: vászonszín a 0. színnel, #hex mező, sarokra illesztés. `./test.sh --swift`: 110 teszt átmegy; minden JS-teszt átmegy. Safariban (WebDriver, valódi egér és billentyű) ellenőrizve egy új próbaprojekten (`projects/proba-igazitas`): .md megjelenítés és szerkesztés, nyilak, igazítás 6 irányban, elosztás, visszavonás, sarokfogó, rácsra illesztés, #hex gépelés, Liquid Glass vászonszín (a rács kivágva). Verziók: `editor.js?v=96`, `app.css?v=65`. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Projektnapló

- Projektenként egy közös napló, saját oldalon: `/_naplo/<projekt>` (az aláhúzás miatt nem ütközhet projektnévvel); minden munkalap fejlécében „Napló” gomb (lista ikon) vezet ide. Bejegyzés: szerző (avatar, név a saját színével), idő, szöveg, jelzők: **Fontos**, **Elvégezve** (áthúzva), **Inaktív** (halvány); a módosítás rögzíti, ki és mikor módosított.
- Írni és jelölni minden szerkesztő tud (bejelentkezve, a projekt szerkesztője vagy admin, vendég szerepkör nélkül); olvasni bárki, aki a projektet látja. Szűrők (a böngészőben megjegyezve): újak felül, csak a fontosak, elvégzettek / inaktívak elrejtése. Új bejegyzés és szerkesztés: Ctrl/⌘+Enter. A lap 8 mp-enként frissül (szerkesztés közben nem).
- Tárolás: a projekt mappájában `.naplo.json`; bejegyzésenkénti műveletek (`POST /api/log/<projekt>`: `add` / `text` / `flag`), így ketten egyszerre is írhatnak ütközés nélkül. Új fájlok: `Sources/ThinkCore/ProjectLog.swift`, `Public/naplo.js`.
- Teszt: új `projectLogEntries` (Swift). Két valódi böngészővel ellenőrizve a helyi adatok másolatán (a próbabejegyzések nem kerültek a `projects` mappába): hozzáadás fontos jelzővel, a másik felhasználó a frissítés után látja, elvégzettre jelöli, szerkeszti, és ez visszalátszik. `./test.sh`: 108 Swift-teszt és minden JS-teszt átmegy. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Csevegés munkalaponként

- Új eszköztár gomb (`.chat-tool`, szerkesztőben és megtekintőben, csak bejelentkezett felhasználónak) olvasatlan-számlálóval; a panel a vászon jobb alsó részén. Enter: küldés, Shift+Enter: új sor, Esc: bezárás. A jelenlévők gombjára kattintva a csevegés megnyílik, és a másik résztvevő neve megemlítésként (@név) a mezőbe kerül. A téged említő üzenet kiemelt, és hangjelzés szól. A saját üzenet törölhető (admin bármelyiket).
- Tárolás: a munkalap mappájában `.chat.jsonl` (soronként egy üzenet: id, szerző, idő, szöveg), így a munkalappal együtt mozog (átnevezés, áthelyezés, lomtár), és nem ütközik a lap mentéseivel. A szerző színe és avatarja olvasáskor kerül hozzá. Legfeljebb 2000 karakter / üzenet, a lekérdezés a legutóbbi 200-at adja. Új fájl: `Sources/ThinkCore/Chat.swift`, `Public/chat.js`.
- API: `GET /api/chat/<lap>` (előzmények), `POST /api/chat/<lap>` `{text}` / `{delete}`; az új és törölt üzenet a WebSocketen azonnal megy a szoba bejelentkezett résztvevőinek. Az olvasottság böngészőnként tárolódik (localStorage).
- Javítva: a prezentációs commit (`128ec08`) elrontotta a `ui-names.json`-t (a „Ping nyila” sor eleje elveszett), így a felületnév-súgó nem töltődött be; helyreállítva.
- Teszt: új `worksheetChat` (Swift: jogosultság, üres / túl hosszú üzenet, törlés szerzőként és adminként, tárolási hely). Két valódi böngészővel ellenőrizve (küldés Enterrel, olvasatlan-jelző, megemlítés kiemelése és színe, válasz, törlés). Verziók: `editor.js?v=95`, `viewer.js?v=29`, `app.css?v=62`. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.
- A próba a helyi `projects/a` mappában egy üres `.chat.jsonl` fájlt hagyott (az üzenetek törölve); a fájl törlése engedélyre vár.

## 2026-11-26 – Előadás: a keret az előadó látható vászna, menet közben módosítható

- A felhasználó kérésére átdolgozva: az előadás területe **indításkor az előadó teljes látható vászna** (annak képaránya), nem rögzített 16:9. A követőknél pontosan kitölti a látható területet (96%-os ráhagyás nélkül): azonos felbontásnál és elrendezésnél (pl. mindkettő teljes képernyőn) a kép azonos. Két böngészővel ellenőrizve: azonos ablakméretnél a két nézet transzformációja egyezik.
- **Menet közben módosítható:** az előadó sávján „Keret rajzolása” (húzással új keret; Esc: mégse), kisebb keretnél sarokfogók (méretezés) és középső fogó (mozgatás), „Teljes nézet” (vissza a teljes vászonra). A keret az előadó képernyőjéhez kötött, ezért pásztázáskor / nagyításkor vele mozog, a követők követik.
- **Más képarány:** a kereten kívüli rész halványító maszkot kap, a keret szaggatott vonallal, az előadó színével látszik (követőnél és az előadónál is, ha kisebb keretet állított be). A maszk a vezérlők alatt van, a fogók fölöttük.
- A levált követő a vásznon szaggatott keretként látja, hol tart az előadás. Verziók: `editor.js?v=94`, `app.css?v=61`.

## 2026-11-26 – Előadás (prezentáció mód)

- Új eszköztár gomb a szerkesztőben (`.present-tool`, „lejátszás” ikon). Indításkor az előadó választ: **felkérés** (aki maga mozgatja / nagyítja a vásznat, leválik; a sávon „Vissza az előadáshoz” és „Leválás” gomb) vagy **kötelező követés** (a követő nem mozgathatja a nézetet).
- Az előadó egy 16:9-es **keretet** oszt meg: a látható vászonterülete közepén, annak 92%-ában (munkalap-koordinátában). A követők nézete úgy igazodik, hogy a keret kitöltse a saját látható területük 96%-át (a nyitott tulajdonságpanel nélkül), így eltérő képernyőn is nagyjából ugyanaz a tartalom látszik. A keret szaggatott vonallal, az előadó színével mindenkinél látszik (útmutató; a tartalom kilóghat).
- Sáv a vászon tetején: az előadónál a mód és a „Befejezés”, a követőnél ki ad elő (avatar, név a saját színével), a mód, ha az előadó nem aktív, és a leválás / visszatérés. Admin a futó előadást befejezheti és átveheti.
- Szerver: egyszerre egy előadó szobánként (`present` / `unpresent` művelet, mód: `invite` / `forced`); nem admin nem veheti át (423, „X már előad.”); az előadó távozásával vagy lejártával véget ér. A keret a WebSocketen megy (`{present, rect}`), a szoba megjegyzi, így a később belépő azonnal követ (`LiveState.presentation`).
- A követés a görgős nagyításhoz hasonló úton megy (mozdulat közben csak a CSS-réteg mozog, nyugalomban rajzol újra), így a folyamatos követés nem rajzolja újra a lapot minden lépésnél.
- Teszt: új `presentationOwnership` (Swift). Két valódi böngészővel ellenőrizve (Chromium ad elő, Safari követ): a keret a követőnél középen kitölti a területet, követi az előadó pásztázását; felkérésnél a saját húzás leválaszt, a „Vissza” visszaállít; kötelező módban a húzás nem mozdít; befejezéskor a sáv eltűnik. Verziók: `editor.js?v=92`, `app.css?v=59`. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Lézer pointer

- Új eszköztár gomb (`.laser-tool`, a szerkesztőben és a megtekintőben a tagoknak): bekapcsolva az egérrel húzott vonal a saját színeddel látszik mindenkinél, és kb. 1,2 mp alatt elhalványul (a vonal vége folyamatosan fogy, „csóva”). Fénylő szél + fehér közép, a nagyítástól független vastagság. Nem mentődik.
- Bekapcsolt lézernél a húzás nem jelöl ki, nem mozgat és nem pásztáz (az eseményeket a vászon tárolója elfogja), a felengedés utáni kattintás sem nyit meg semmit; a kurzor célkereszt.
- Átvitel a meglévő WebSocketen: `{laser, stroke, points: [x, y, …], end}`, üzenetenként legfeljebb 16 pont, ~30/mp; a szerver ellenőrzi (legfeljebb 32 pont, véges, ±100 000) és a küldő színével továbbadja; nem aktív (más ablakot néző) résztvevőé nem megy tovább. Új modul: `Public/laser.js`.
- Javítva: a megtekintőben a kurzorcímke-gomb a lap minden frissítésekor megduplázódott volna (most a frissítés a lézer- és kurzorgombokat is újraépíti).
- Súgó és felületnevek kiegészítve. Verziók: `editor.js?v=90`, `viewer.js?v=28`, `app.css?v=58`.
- Ellenőrizve két valódi böngészővel (Chromium rajzol, Safari látja a küldő színével; a rajzoló oldalon nincs kijelölés és pásztázás; 2 mp után mindkét oldalon eltűnik). JS-tesztek átmennek. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – Ping: a nyíl a valóban látható vászonterülethez igazodik; a pingelő neve felvillan; ping hang

- **Hiba: a képernyőn kívüli ping nyila sokszor nem jelent meg.** A vászon (`svg.editor-canvas`) a puffer miatt jóval nagyobb az ablaknál, ezért a teljes ablak számított látható területnek: a fejléc mögé, a nyitott tulajdonságpanel alá eső vagy a szélén épp csak belógó ping nem kapott nyilat. Most a vászonterület (`.canvas-area`) az ablakra vágva, a nyitott panelek nélkül számít (`visibleBounds`, `pingBounds`), és nyíl jár minden pinghez, amelynek a közepe nincs legalább 24 px-re a látható terület szélein belül.
- **A pingelő neve felvillan** a jobb alsó sarokban: a név szövege a saját színében háromszor felizzik (text-shadow), az avatarja is fénylik, a pinggel azonos ideig. A saját pingnél a saját neved villan. Ehhez a résztvevők nyilvános azonosítót kaptak (`Participant.id`, a pingüzenetben `peer`).
- **Ping hang:** rövid, csengő hang (Web Audio, hangfájl nélkül) a kapott és a saját pingnél. A böngésző csak felhasználói művelet után enged hangot: az oldalon az első kattintás vagy billentyű után szól.
- Verziók: `editor.js?v=89`, `viewer.js?v=27`, `app.css?v=57`, `ping.js?v=4`.
- Ellenőrizve két valódi böngészővel (Safari + fej nélküli Chromium, mindkét irányban): a nyíl a jobb szélen és a nyitott panel szélén, a név izzása a küldő színével, a hang (3 oszcillátor) Safariban. Tesztek: 105 Swift-teszt és minden JS-teszt átmegy. Szerverkód változott: a helyi tesztszerver (8888) újraindítva.

## 2026-11-26 – A saját résztvevő-gomb nem szürkül el

- Ha a saját ablakod nincs fókuszban, a többiek továbbra is szürkén látnak, de a saját jelenlévő-listádban a gombod színes marad (szerkesztő és megtekintő). Csak kliensoldali változás (`editor.js`, `viewer.js`); a szerver változatlan, nem kellett újraindítani.
- Ellenőrizve Safariban (kényszerített fókuszvesztés + szimulált második résztvevő); a JS-tesztek átmennek.

## 2026-11-26 – Közös munka: felhasználói színek, 32 avatar, kurzorcímke, nem aktív résztvevő, ping a képernyőn kívül

- **Felhasználói szín:** minden fióknak van színe (#rrggbb). Alapból automatikus egy 32 színű, globális, témától független alappalettából (`userPalette`, Radix-színek, világos és sötét háttéren is látszik); a fiókok név szerinti sorrendben, szétszórt sorrendben kapják a még szabad színeket, így az egymás utáni fiókok jól elkülönülnek. Az admin oldalon az „Avatar és szín” ablakban a palettából vagy egyedi színválasztóval adható meg, és visszaállítható automatikusra (`POST /admin/color`, `WorksheetStore.assignColor`, `SiteSettings.color(for:)`). A vendég (fiók nélkül) a szobában még nem használt palettaszínt kapja.
- **32 avatar:** új, jól felismerhető fekete alakzatok (szív, csillag, korona, sakkfigurák, kártyaszínek, hold, nap, felhő, villám, hópehely, csepp, láng, levél, fenyő, virág, gomba, hal, macska, mancs, szellem, horgony, kulcs, harang, rakéta, esernyő, hangjegy, ház, villanykörte). A felület `<use href="/icons/avatar-N.svg#a">` hivatkozással a felhasználó színére színezi (`avatarSymbol`, `presence.js`). Előállításuk: `server/docs/avatars.mjs`. A meglévő 1–12-es avatarok sorszáma megmaradt, de a kinézetük az új alakzatokra változott.
- **Kurzor:** a megosztott kurzor mellett a név (színes címkében) vagy az avatar látszik; hogy melyik, azt mindenki maga választja az eszköztár új gombjával (`.cursor-label`, a böngészőben megjegyezve). A kurzor a nagyítástól függetlenül állandó méretű a képernyőn.
- **Jelenlévők (jobb alsó sarok):** a név és az avatar a felhasználó színével. Aki nem nézi a lapot (rejtett fül vagy az ablak nincs fókuszban; a beágyazott keret fókusza nem számít), annak a gombja teljesen elszürkül, és a kurzora eltűnik. A kliens minden hosszú lekérdezéssel és változáskor külön `status` kéréssel jelzi (`away`); a szerver a nem aktív résztvevő kurzorát elrejti és nem továbbítja.
- **Ping:** a küldő színével rajzolódik (a saját ping is). Ha a ping a látható területen kívül esik, a vászon (megtekintőben az ablak) szélén a ping irányába mutató nyíl jelenik meg a küldő színével és avatarjával; a pinggel együtt halványul el (fölötte megáll), kattintásra a nézet odaugrik. A ping ideje 1,2 mp-ről 2 mp-re nőtt (`--ping-duration`), hogy a nyílra legyen idő rákattintani.
- Szerver: `Participant.away`, a kurzor- és pingüzenet a küldő nevét, avatarját és színét is viszi; `UserPreferences.color`, `User.color`; avatar-tartomány 1–32 (`avatarCount`).
- Súgó és felületnevek: új „Kurzorcímke váltása” sor (`docs/hotkeys.json`, `utmutato.html`, `ui-names.json`).
- Tesztek: új `userColorsAndAwayPeers` (automatikus és admin szín, érvénytelen szín, avatar-tartomány, színek és távollét a jelenlévők között); a `gestures.mjs` dokumentum-csonkja megkapta a fókusz-API-t. `./test.sh`: 105 Swift-teszt és minden JS-teszt átmegy.
- Safariban (WebDriver + szimulált második résztvevő) ellenőrizve: névcímke és avatarcímke, jelenlévők színe, szürke nem aktív résztvevő és eltűnő kurzora, a ping nyila és az odaugrás, az admin ablak, a megtekintő gombjai.
- Szerverkód változott: a helyi tesztszerver (8888) újraindítva.
- Ötletek a következő közös munka feladatokhoz (prezentáció mód, chat, napló, lézer pointer): TODO.md „Közös munka”.

## 2026-11-26 – Tesztek az új vonalméret-rendszerhez; test.sh a macOS bash-ével

- **Tesztek hozzáigazítva** (kód nem változott): `RenderingTests` – a legnagyobb vastagság a méretből és a témaszorzóból, az íves vonal 3-as mérettel, az animált sima vonalon futó pötty (a gradiens helyett); `WorksheetTests` – `width` helyett `size`; `Tests/Fixtures/wires.json` újraírva (csak a régi `w` értékű esetek változtak), új eset a `size` mezővel; `gestures.mjs` – futó pötty, csoporton belüli gombkeresés, vonalméret a megszűnt vastagságmező helyett, a szerkesztővel azonos `geometry.js`-példány.
- Ellenőrizve: a régi `w` mezőt a szerver és a szerkesztő ugyanúgy váltja át méretre (≤3,5 vékony, ≤7,5 közepes, fölötte vastag).
- **`test.sh`:** a macOS `/bin/bash` 3.2-je alatt egy telepített 4+ bash-sel indul újra.
- Eredmény: `./test.sh --all` – 104 Swift-teszt és minden JS-teszt átmegy.
- Új nyitott tétel (BUGS.md): két „Vastag” nevű gomb a vonal paneljén (átnevezés döntésre vár).

## 2026-11-25 – ThinkDefault: Radix és Catppuccin paletta; esti színek nélküli téma is működik

- **Radix paletta** (ThinkDefault, 3-as paletta, 37 szín): mind a 31 Radix Colors 3.0 színskála 9. fokozata világos és sötét változattal, plusz a lap, tinta, felület, grafit, finom árnyék, pasztell és köd szerepszín. Elöl a semlegesek (öt szürke családdal), utána színkör szerint.
- **Catppuccin paletta** (4-es paletta, 26 szín): nappal a Latte, este a Mocha változat, a hivatalos `catppuccin/palette` adatai szerint (MIT-licenc). Szerepek: lap = base, tinta = text, felület = surface0, jelzőszín = blue. Elöl a semlegesek (base → text), utána a Catppuccin saját sorrendje (rosewater → lavender).
- **Esti színek nélküli téma:** a témafájlban a `modes` mező elhagyható (ilyenkor `light`, és ha van esti szín, `dark` is); az esti szín bárhol elhagyható, sötét módban a nappali szín látszik. Ha egy palettának egyetlen esti színe sincs, a vászon sötét módban is teljesen nappali marad (szerkesztő: `editor.js mode`; szerver: `Theme.swift paintResolver`, `Palette.hasDark`). Eddig a `modes` nélküli témafájl be sem töltődött.
- Teszt: `themeWithoutDarkColors` átmegy; a régi bukó tesztek változatlanok.
- Szerverkód változott (`Theme.swift`, verziószám): release build, a helyi szerver újraindítva.

## 2026-11-25 – ThinkDefault: mindkét paletta 21 színű, hasonlóság szerint rendezve

- **Műhely** új színei (Radix Colors 3.0, világos és sötét változattal): Pünkösdi rózsa (pink 9), Rózsaszirom (ruby 4), Méz pasztell (amber 4), Fű (grass 9), Bíbor (purple 9).
- **Botanika** új színei: Szeder (plum 9), Barack (orange 4), Méz (amber 9), Rügy (lime 9), Homok (sand 5).
- **Sorrend:** elöl a semleges színek (papír → tinta), utána színkör szerint (rózsa → piros → narancs → sárga → zöld → cián → kék → ibolya), a pasztell a saját élénk színe mellett. A színválasztó a fájl sorrendjében mutatja őket.
- A szín-ID-k nem változtak, így a meglévő munkalapok színei is ugyanazok maradnak.
- A színértékek a Radix Colors forrásából (`radix-ui/colors`) származnak; a meglévő 16 szín is ebből van, és egyezik vele.
- Csak témafájl (`server/Public/themes/ThinkDefault.json`), kódmódosítás nélkül; a helyi szerver újraindítva (a témákat induláskor olvassa be).

## 2026-11-25 – Törölt téma vagy paletta: a munkalap az alaptémával nyílik meg

- Eddig a szerver minden betöltéskor és mentéskor elutasította (422) a nem létező témájú vagy palettájú munkalapot, így egy témafájl törlése után az azt használó lapok nem nyíltak meg.
- Most a lap az alaptémát kapja (ThinkDefault, ennek híján a katalógus első témája, annak első palettája); meglévő témánál a hiányzó paletta helyett a téma első palettája áll (`Worksheet.repairAppearance`, Theme.swift). Minden fájlbetöltésnél (lap, import, projektcsomag, korábbi változat: `Worksheet.decodeFile`) és mentéskor is fut (a szerkesztő még a törölt témát küldheti). Téma nélküli régi lap változatlan.
- Téma törlése így: a JSON törlése a `server/Public/themes/` mappából, a szerver újraindítása, és a témára név szerint hivatkozó tesztek eltávolítása (`server/docs/themes.md`, „Téma törlése”).
- Teszt: `missingThemeFallsBackToDefault` átmegy. A `worksheet` témakörben két régi teszt (`compactWorksheetKeysRoundTrip`, `worksheetRoundTrip`) a módosítás nélkül is bukik (BUGS.md).
- Szerverkód változott (`Theme.swift`, `WorksheetFile.swift`, `Model.swift`): release build, a helyi szerver újraindítva.

## 2026-11-25 – WhiteBoard téma: szabadkézi filcrajz, cetlik és füzetlapok; bemutató projekt

- **Új téma: WhiteBoard** (`server/Public/themes/WhiteBoard.json`, téma-ID 6): nappal fehér tábla filcszínekkel, este fekete tábla hozzáillő, élénk színekkel. Betűk: Chalkboard SE, Marker Felt, Bradley Hand.
- **Szabadkézi rajz** (`graphics.sketch`; `Public/sketch.js`, `Sources/ThinkCore/Sketch.swift`): a sarkos alakok egyetlen folytonos, kissé hajló vonalból állnak, a vége túlfut a kezdőponton; az ellipszis egyetlen, a bal oldalon pontosan össze nem érő vonal; a vonalak egy második, elcsúsztatott, halványabb húzást kapnak. A remegés a doboz azonosítójából számolódik (FNV-1a + Mulberry32), a szerkesztő és az SVG-export ugyanazt rajzolja (`Tests/Fixtures/sketch.json`, `Tests/Editor/sketch.mjs`, `sketchMatchesSharedFixtures`). A kattintható terület és a szöveg helye a szabályos alak marad. A rajz gyorsítótárazott (húzáskor nem számolódik újra), SVG-szűrő nincs.
- **Papírfelületek** (`graphics.paper`): a táblázat és a CSV cetli (ragasztószalag, felpödrődő sarok, árnyék, egyenesen), a szöveg- és kódfájl füzetlap (sorvonalak a szöveg alapvonalán, margóvonal, lyukak). A papír mindkét módban világos, rajta a paletta nappali színei és sötét tinta. Kiemelt szabadkézi dobozon az árnyék nem látszik át a tónuson (tábla színű alap).
- A tábla hátterén letörölt filcnyomok (álló, nem animált réteg). Saját kijelöléskor a szabadkézi vonal a kijelölés színére vált.
- Az esti krétautánzás (szaggatott vonalminta, porréteg) a felhasználó kérésére kikerült: sötét módban a rajz ugyanaz, csak a színek mások.
- **Új témamezők:** `sketch` (`roughness`, `passes`), `paper` (`grid`, `text`, `sheet`, `ink`, `rule`, `margin`). Leírás: `server/docs/themes.md`, séma: `theme.schema.json`. Más témában egyetlen plusz elem vagy szabály sem hat (teszt ellenőrzi).
- **Bemutató projekt** (csak helyben, `projects/WhiteBoard`): 65 objektum, 26 vonal.
- Safariban mérve (1600 × 948, kétszeres felbontás): WhiteBoard bemutató világos és sötét módban nyugalom, rámutatás, pásztázás, nagyítás, kijelölés 59,5–60 fps. Liquid Glass ellenőrzésként 55,7–60 fps (lassú nagyításnál egy 115 ms-os képkocka; korábban 57–58, a leghosszabb 63 ms – a különbség a mérés szórásán belül lehet, nincs a Liquid Glasst érintő kódváltozás).
- Tesztek: új `sketchMatchesSharedFixtures`, `whiteBoardTheme` (Swift) és `sketch.mjs` (JS) átmegy; a régi bukó tesztek változatlanok (BUGS.md). A `test.sh` a `/bin/bash` 3.2-vel nem fut (asszociatív tömb): bash 4+ kell (`/opt/local/bin/bash ./test.sh`).
- Szerverkód változott (`Sketch.swift` új, `Rendering.swift`, `Theme.swift`, `Model.swift`, verziószámok): release build, a helyi szerver újraindítva.

## 2026-11-25 – Felmérések a FUTURE.md-ben: WebAssembly, WebGL vászon, natív iOS/macOS kliens

- `server/docs/FUTURE.md` új fejezete („Felmérések: WebAssembly, WebGL és natív kliens”): mit adna a WASM (a szerver változatlan, de a rajzolási szűk keresztmetszeten nem segít; számításra és a Swift/JS kettős kód kiváltására jó), az `editor.js` felosztása és a WebGL-átírás nehéz pontjai (szöveg, HTML-tartalmú dobozok rétegsorrendje, találatvizsgálat), a natív kliens felmérése a mostani kódhoz (újrahasznosítható Swift-modulok, portolandó JS-részek, kis szerveroldali kiegészítések, Core Animation-alapú rajzolás, munkabecslés, a fejlesztőgép korlátai), összevetés.
- Kód nem változott.

## 2026-11-25 – Dobozkeret a témából (vastagság, szín, fényudvar); a NeonGlow vastag neon kereteket kap

- **Új témamező: `graphics.frame`** (`Theme.swift Frame`, `editor.js shape`, `Rendering.swift boxSurface`): `width` – a keret vastagsága (0,5–16, alap 1,6); `color: "fill"` – a keret a doboz saját színe, kitöltött dobozon is; `fillOpacity` – a kitöltött felület átlátszatlansága (áttetsző módban a fele); `halo` – fényudvar a keret körül (háromszoros vastagságú, áttetsző körvonal, szűrő nélkül). Leírás: `server/docs/themes.md`, séma: `theme.schema.json`.
- A zárolt konténer kerete a témakeretnél 3 egységgel vastagabb (legalább 6,4); a saját kijelölés kerete 2,4-gyel vastagabb a témakeretnél (`--frame-selected`). A kép és az előnézet saját keretét nem érinti. Keret nélküli témában semmi nem változik (teszt ellenőrzi).
- **NeonGlow:** `frame: {width: 4, color: "fill", fillOpacity: 0.14, halo: 0.28}` – minden doboz vastag, a saját színével világító keretet és halványan színezett belsőt kap. A paletta 2-es színe (az új dobozok alapszíne) sötét panel helyett neon ibolya („Neoncső”), hogy az alapdoboz kerete is világítson. A bemutató dobozai már nem „Üres” módban, hanem alapmódban állnak.
- Safariban (NeonGlow bemutató, esti mód, 1600 × 948): nyugalom, rámutatás, pásztázás, nagyítás, kijelölés egyaránt 60 fps. Képernyőképpel ellenőrizve nappali és esti módban.
- Tesztek: új `themedBoxFrame` átmegy; a négy régi bukó renderteszt változatlan (BUGS.md).
- Szerverkód változott (`Theme.swift`, `Rendering.swift`, verziószámok): release build, a helyi szerver újraindítva.

## 2026-11-25 – NeonGlow téma (retrowave, három paletta) és bemutató projekt – kódmódosítás nélkül

- **Új téma: NeonGlow** (`server/Public/themes/NeonGlow.json`, téma-ID 5), csak témafájl, a kód nem változott. Három paletta 16–16 színnel: Miami (neon rózsa, cián, ultraibolya), Tokió (jégkék, magenta, savzöld), Outrun (naplemente narancs, forró rózsa, aranysárga).
- **Sötét mindkét módban:** a nappali (világos) mód háttere mély alkonyat (pl. Miami: `#2e1d40`), az esti (sötét) módé majdnem fekete (`#06020d`). A neon színek árnyalatonként a legtelítettebb világosságon állnak, nappal egy fokkal mélyebbek.
- **Grafika:** vastag vonalak (`lineScale` 1,2–1,5 minden típusra és megjelenésre), vonalas rács, letört sarkú dobozok (`boxChamfer: 10`), rombusz csomópont, nagy kijelölés-glow (`glow: 14`), üvegpanelek.
- **Neon keret:** a doboz kerete „Üres” felületmódban a doboz színét veszi fel – a bemutató dobozai így kapnak neon keretet. A keret vastagsága a kódban rögzített (1,6), témából nem állítható: a kért vastag keret kódmódosítás nélkül nem érhető el (TODO.md).
- **Bemutató projekt** (csak helyben, `projects/NeonGlow`, nincs gitben): 65 objektum, 26 vonal – ugyanaz a készlet, mint a Liquid Glass bemutatóban (alakzatok, felületmódok, animációk, konténer, vonaltípusok, csomópontok, szöveg-, kód-, CSV- és táblázatfájl, grafikonok, három generált kép, hang, PDF, a paletta 16 színe).
- Safariban képernyőképpel ellenőrizve nappali és esti módban (Miami paletta). A helyi szerver újraindítva (a témákat induláskor olvassa be).

## 2026-11-25 – Liquid Glass téma (látványcsomag), vonalvastagság típus × megjelenés szerint a témából, bemutató projekt

- **Új téma: Liquid Glass** (`server/Public/themes/LiquidGlass.json`, téma-ID 4): öt paletta (Azúr, Aurora, Napnyugta, Lagúna, Grafit), mindegyikben 21 szín világos és sötét változattal (OKLCH-térben, azonos világosságon és telítettségen). 22-es saroksugár, ívelt egyenes vonalak, kerekített töréspontok.
- **Látványcsomag** (`graphics.effects: "liquid"`): áttetsző dobozfelület fénylő peremmel (`fx-rim`) és csillogással (`fx-sheen`), puha árnyék (`fx-shadow`, a Kiemelésnél nagyobb, képen is), lassan úszó háttérfények a paletta színeiből (`.canvas-aurora`), üvegpanelek és -menük erős háttérelmosással.
- **Effektek:** rámutatáskor a doboz csillogása kifényesedik, az árnyéka megnő, a pereme megvastagszik; vonal és csomópont fölött halvány fényudvar; kattintáskor szétfutó gyűrű; saját kijelölés felvillan, majd lélegző fényudvart kap a saját színnel; más felhasználó kijelölése erősebb, lüktető glow; a ping felvillanó, kétszer táguló, fénylő gyűrű.
- **Az alaptémák nem lassulnak:** minden szabály a `[data-effects="liquid"]` jelző alatt áll, a plusz elemek csak ebben a témában keletkeznek. Szűrő (glow) csak rövid életű elemen van; mozgás közben az áttűnések és a lélegzés áll.
- **Vonalvastagság a témából, vonaltípusonként és megjelenésenként:** a `lineScale` egy típusra egy szám, vagy megjelenésenként (`plain`, `thick`, `dashed`, `dotted`) külön szorzó (`Theme.swift LineScale`, `geometry.js edgePaint`). A három vonalméret megmaradt. A három meglévő téma `lineScale`-je az új, megjelenésenkénti alakra váltott (minden érték 1: a megjelenésük nem változott).
- **Új témamezők:** `boxRadius` (a lekerekített doboz saroksugara), `effects`. Leírás: `server/docs/themes.md`, séma: `server/docs/theme.schema.json`.
- **SVG-export és megtekintő:** a statikus rész (felület, perem, árnyék, álló háttérfények) megjelenik; a mozgás csak a böngészőben.
- **Bemutató projekt** (csak helyben, a `projects/LiquidGlass` mappában, nincs gitben): 70 objektum és 26 vonal – mind a nyolc alakzat, öt felületmód, négy animáció, konténer gyerekekkel, mind a hat vonaltípus és négy megjelenés, csomópontok, szöveg-, kód- (Swift, JS, CSS, JSON), CSV- és táblázatfájl, három grafikon, három (saját, generált) kép, hang, PDF, és a paletta 21 színe.
- **Mérés Safariban** (1600 × 948, kétszeres felbontás, a bemutató lapon, sötét és világos módban): nyugalomban, rámutatásnál, kijelölésnél és kijelölt állapotban 60 fps; pásztázás 59–60; nagyítás 57–58 (a leghosszabb képkocka 63 ms); dobozhúzás 58–59.
- **Valódi háttérelmosás a dobozokon nincs:** kipróbálva, a Safari az SVG-n belül nem alkalmazza a `backdrop-filter`-t (sem SVG-elemen, sem `foreignObject`-ben). Valódi elmosást a panelek és menük kapnak; a dobozok áttetszők, alattuk átsejlenek a háttérfények.
- Tesztek: `ThemeTests` új esetei (`lineScaleByTypeAndAppearance`, `liquidGlassTheme`) átmennek. Négy régi renderteszt és két JS-teszt már e változások előtt is bukott (BUGS.md).
- Szerverkód változott (`Theme.swift`, `Model.swift`, `Rendering.swift`, verziószámok): release build, a helyi szerver újraindítva.

## 2026-11-25 – Gyors eszközök: négyirányú terjeszkedés, minden objektumon; futó pötty a vonalon; három vonalméret

**Nincs tesztelve** (a felhasználó kérésére: tesztelés csak külön utasításra); a felhasználó kézzel próbálta ki. A meglévő tesztek egy része ezektől a változásoktól el fog törni (lásd BUGS.md).

- **Terjeszkedés a kattintás pontjától** (`renderQuickTools` fit): a kattintás az origó, a blokk alapból jobbra és lefelé nő; ha jobbra nem fér el, balra, ha lefelé nem, felfelé (tengelyenként). Az első sor első gombja mindig 5 képpontra áll a kattintástól; balra a sorok tükröződnek, felfelé a sorok alulról fölfelé következnek. A sorok nem törnek (egyoszlopos elrendezés nincs). A lenyíló listák és a színválasztó a blokk irányát követik (`placePopup`), és semmi nem lóg ki az ablakból.
- **Hagyományos helyi menü kikapcsolva minden objektumon** (`quick-tools.json` `noMenu: true`; a kód megmaradt, a vásznon a menü él). A menü parancsai gombok lettek: Törlés, Ping, Link másolása, Cellák szerkesztése, Grafikon létrehozása.
- **Leíró bővült** (`quick-tools.json`): elrendezésenként `rows` / `before` / `after` / `opposite` (a kattintás túloldalán megjelenő sorok – most a Ping), `"*"` = minden más típus. Doboz: a link külön sorban, Törlés az utolsó sorban. Vonal: a panel tagolása szerint (címke + szín + méret; vonaltípusok; megjelenés; végpontok; Törlés).
- **Szerkesztő gombok:** `edit-name` (doboz szövege a dobozon; vonal és csomópont címkéje a vásznon, nyitott panel mellett is – `editInline`; fájlnév a doboz fölötti feliratban helyben – `renderFileNameEdit`), `edit-comment` (megjegyzés a vásznon); mellettük a panel meglévő elrejtő kapcsolói (`hide-name`, `hide-comment`).
- **Csak ikonok:** a gyors eszközök feliratos gombjairól lekerül a szöveg (súgóként megmarad).
- **Vonalanimáció:** a sima vonal gradiens animációja törölve (szerkesztő, megjelenítő, szerver rajzoló, `wireGradientValues`). Helyette egy kis pötty fut végig a vonalon örök ismétléssel a nyíl irányában (csak kezdőnyílnál visszafelé, két nyílnál oda-vissza; `animateMotion`). A vastag vonal lüktetése és a szaggatott / pontozott minta haladása maradt.
- **Vonalméret:** az egyedi vastagság megszűnt (`w` mező, számmező a panelen). Minden vonalnak három mérete van (`size`: 1 vékony – alapértelmezett, 2 közepes, 3 vastag; alapvastagság 2 / 5 / 10,5 képpont), a téma vonaltípusonként szorozza (`themes/*.json graphics.lineScale`; a vastag megjelenés kétszeres). A régi egyedi vastagság betöltéskor a legközelebbi méretre vált. Panel: három gomb; gyors eszközök: lenyíló „Vonalméret”.
- Szerverkód változott (`Model.swift`, `Theme.swift`, `Rendering.swift`, verziószámok): release build, a helyi szerver újraindítva.

## 2026-11-25 – Gyors eszközök: szerkeszthető leíró (quick-tools.json), doboz lebegő menüje, semmit el nem toló lenyílók

- **Leíró: `server/Public/quick-tools.json`** (kézzel szerkeszthető, a fájl elején magyar leírással): `groups` – melyik gomb melyik lenyíló csoportba tartozik, és a csoport hogyan nyílik (`open`: `row` / `column` / `grid` + `columns`; `icon`: állandó ikon, nélküle az aktuális érték ikonja); `layouts` – típusonként a gombok sorai (kézi elrendezés); `noMenu` – mely típusokon nincs hagyományos menü; `tools` – a gombazonosítók jegyzéke (tájékoztató). A szerkesztő betöltéskor olvassa (gyorsítótár nélkül), a lap újratöltése elég, build nem kell. A korábbi `choiceSets` jegyzék (editor.js) megszűnt, ez váltotta fel.
- **Gombazonosítók:** a panel gombjait a forrásukban a `tool(azonosító, gomb)` jelöli (`data-tool`); a választócsoportok gombjai az `optionPicker` `set` paraméteréből kapnak nevet (pl. `shape-ellipse`).
- **Doboz:** első elrendezés a leíróban (két sor + linksor); a 9 szövegigazítás egy lenyíló csoport (3×3 rács). A dobozon a hagyományos helyi menü ki van kapcsolva (`noMenu: ["box"]`, a kód megmaradt) – így a dobozon jobb kattintással most nincs Törlés, Ping és Szerkesztés (Delete billentyű, panel).
- **Csak a menü fölött vannak gombok**, mellette nincsenek. A leíróban nem szereplő típusoknál a panel sorai jelennek meg, a csoportok lenyílóként.
- **Semmit nem tol el:** a lenyíló lista és a színválasztó listája rögzített helyzetű réteg (`placePopup`), sem a megnyomott gombot, sem a többit nem mozdítja. Arra nyílik, amerre több a hely (le / fel, jobbra / balra).
- **Képernyőn belül:** sem a keret, sem a kinyíló listák semmilyen része nem kerül az ablakon kívülre.
- **Kiemelés** kikerült a hagyományos menü felsorolásából (a gombok között szerepel).
- A tulajdonságpanel színválasztója még a régi módon nyílik (eltolja a többi gombot) – későbbi feladat (TODO.md).
- Safariban mérve (próbalap): dobozon nincs menü, a két sor megjelenik; mind az öt csoport és a színválasztó nyitásakor a rögzített gombok helye képpontra változatlan, és semmi nem lóg ki az ablakból; igazítás választása hat; fájldobozon a menü megvan (Kiemelés nélkül), gombok csak fölötte. A `gestures.mjs` rendben.
- Szerverkód: csak a szkript- és stíluslap-verzió változott; release build, a helyi szerver újraindítva.

## 2026-11-25 – Gyors eszközök: helyi menü vissza, gombok fölötte és mellette, rámutatás kiemelése, lenyíló választócsoportok

- **Helyi menü visszakapcsolva** objektumokon. Jobb kattintásra az objektum kijelölődik, a menü bal felső sarka a mutatónál áll; **fölötte** az első csoport (jellemzően a Text), **mellette** a többi csoport egymás alatt, térközzel elválasztva (`renderQuickTools`, kapcsoló: `quickTools`). Ha az objektum nem jelölhető ki (más fogja), csak a menü jelenik meg.
- **Rámutatás kiemelése:** a gyors eszközök minden gombja és a helyi menü minden eleme (a vászon menüjében is) kiemelt hátteret és keretet kap, amíg a mutató rajta áll.
- **Választócsoportok jegyzéke (`editor.js choiceSets`):** egy helyen szabályozható, hogy az egy tulajdonság értékei közül választó gombcsoportok közül melyik jelenjen meg a gyors eszközökben egyetlen gombként, amely kattintásra nyitja ki a többit (`flyout: true / false`). Most lenyíló: Forma, Animáció, Háttér mód, Betűtípus, Vonaltípus, Vonal megjelenése. A lenyíló gomb az aktuális érték ikonját mutatja (sarkában kis jel), választás után a lista bezárul, a gyors eszközök nyitva maradnak. Új csoport: a forrásában megjelölni (`optionPicker` `set` paramétere vagy `choiceSet`), és felvenni a jegyzékbe. A tulajdonságpanelen minden csoport kiterítve maradt.
- Safariban kipróbálva (próbalap): a menü a mutatónál, a gombok fölötte és mellette; Forma lenyitása, Rombusz választása hat, a lista bezárul, a gomb az új értéket mutatja; Háttér mód listája; a rámutatás kiemelése gombon és menüelemen. A `gestures.mjs` rendben.
- Szerverkód: csak a szkript- és stíluslap-verzió változott; release build, a helyi szerver újraindítva.

## 2026-11-25 – Próba: gyors eszközök a mutatónál (a tulajdonságpanel alternatívája)

- **Objektum fölötti helyi menü kikapcsolva** (nem törölve: `editor.js objectContextMenu = false`, a menü kódja megmaradt). A vászon üres részén a helyi menü változatlan.
- **Jobb kattintás objektumon:** az objektum kijelölődik, és a mutató mellett megjelennek a tulajdonságpanel gombjai (`renderQuickTools`), a panel csoportjai és sorai szerint, háttér és keret nélkül. A gombok ugyanazok, mint a panelen (`nodePanels` / `edgePanels` kimenetéből szűrve, `toolRows`), így a kettő nem térhet el. Szövegmező, számmező (betűméret, elforgatás, vonalvastagság), lista és felirat nincs benne; azok a panelen maradtak. Csoportos kijelölés tagjára kattintva a kijelölés megmarad.
- Kattintásra nyitva marad (több gomb is megnyomható); Esc, a vászonra kattintás, pásztázás / nagyítás zárja.
- Ami a helyi menüben volt, és most jobb kattintással nem érhető el: Törlés, Link másolása, Cellák szerkesztése, Grafikon létrehozása, vonal leválasztása / törlése (billentyűről és a panelről részben elérhetők) – a finomításnál eldöntendő, mi kerüljön át.
- Safariban kipróbálva (próbalap): doboz és fájldoboz jobb kattintása, gomb megnyomása (Üres) hat és a készlet nyitva marad, Esc zár, a vászon helyi menüje megjelenik. A `gestures.mjs` rendben.
- Szerverkód: csak a szkript- és stíluslap-verzió változott; release build, a helyi szerver újraindítva.

## 2026-11-25 – Vizuális módosítások: elmosott háttér törölve, vászonszín minden dobozon, szaggatott konténerkeret, dobozszöveg szerkesztése a dobozon

- **Elmosott háttér megszűnt:** a mód, a gombja, az ikonja (`box-blur`) és az SVG-szűrő (`box-background-blur`) kikerült a szerkesztőből és a szerver rajzolójából (`BoxBackgroundMode.blurred`). Régi munkalap „blurred” doboza kitöltött háttérrel töltődik be (ismeretlen háttérmód nem hiba), a következő mentéskor a mező eltűnik.
- **Vászonszín minden dobozon:** a korábban csak táblázatnál, CSV-nél és képnél elérhető mód (a háttér a munkalap háttérszíne, a rács nem látszik át) a Doboz csoport háttérgombjai között minden dobozon választható. A szerver rajzolója eddig is típustól függetlenül kezelte.
- **Konténerré válás jelzése:** pontozott helyett szaggatott keret (`10 7`, 3 képpont), amely körbejár; a vastagság pulzálása megszűnt, glow nincs rajta.
- **Doboz szövege a dobozon szerkeszthető, egy rétegben** (mint a `.txt` / `.md`): dupla kattintásra a megjelenített szöveg helyére a szerkeszthető szöveg kerül (nem fölé), ugyanazzal a betűvel, mérettel, igazítással és tördeléssel. A tördelést a `geometry.js editLabelLayout` adja: a `labelLayout` szabályai szerint tördel (AutoSize, körbefuttatás, függőleges igazítás, NAGYBETŰS), de minden karaktert megtart és nem csonkít. A fájlszerkesztő gépezete (`codeEdit`: saját bevitel, kijelölés, visszavonás) közös. Enter új sor, Esc vagy a doboz elengedése befejezi; belépéskor a teljes szöveg ki van jelölve; a gépelés egy visszavonási lépés. A markdown jelölés szerkesztéskor nyersen látszik, a sorkizárt szöveg balra zárt. Alt + dupla kattintás továbbra is a panel szövegmezőjét nyitja. A megjegyzés (fájl- és előnézetes doboz alatti szöveg), a csomópont és a vonal címkéje nem változott.
- Tesztek: `test.sh` (97 Swift-teszt, JS-tesztek) rendben; a `gestures.mjs` és a `RenderingTests` a fentiekhez igazítva.
- Safariban kipróbálva (ideiglenes próbalap): négy doboz (középre zárt, balra-felülre zárt régi „blurred” háttérrel, AutoSize ellipszis, konténer) szerkesztésbe lépve soronként ugyanúgy tördel, mint megjelenítéskor; gépelés, Enter, kattintás a kurzorhelyre, visszavonás, Esc működik; a `.txt` doboz szerkesztése változatlan; vászonszín közönséges dobozon; a szaggatott keret húzás közben megjelenik.
- Szerverkód változott (`Model.swift`, `Rendering.swift`, `WorksheetFile.swift`, verziószámok): release build, a helyi szerver újraindítva.

## 2026-11-25 – Idegen doboz húzása nem tördeli át a konténerek szövegét

- **Hiba:** bármelyik doboz húzásakor a körbefuttatott szövegű konténerek szövege átrendeződött, amíg a dobozt el nem engedték. Ok: a „ritkább újratördelés húzás közben” (12 képpontos kerekítés) minden konténer minden gyermekére vonatkozott, amíg bármilyen húzás tartott – a kerekített helyek miatt a szöveg kissé másképp tördelődött.
- **Javítás:** a kerekítés csak az éppen húzott gyermekre érvényes, és csak akkor, ha a konténere nem mozog vele (`editor.js flowObstacles`, a `liftedNodes` alapján). Idegen doboz vagy maga a konténer húzásakor a szöveg nem változik.
- Ellenőrzés: Safari, próbalap (konténer szöveggel és egy rácson kívüli helyű belső dobozzal, mellette idegen doboz), húzás közben megállítva: idegen doboz és a konténer húzásakor a sorok azonosak a nyugalmival, elengedés után is; a belső doboz húzásakor a szöveg újratördelődik. A javítás előtti kódot ezzel a szkripttel nem futtattam le. `test.sh editor` rendben. Csak kliensoldali változás.

## 2026-11-25 – Szövegfájlok (.txt, .md) is az egyrétegű szerkesztőben

- **Hiba:** a `.txt` doboz szerkesztésekor a szöveg áttördelt (pl. a sor utolsó szava új sorba került), kilépéskor visszaállt. Ok: a `.txt` / `.md` még külön szövegmezőben (`textarea`) volt szerkeszthető, amely más szélességen tördel, mint a megjelenítés.
- **Javítás:** minden szövegfájl ugyanazt az egyrétegű szerkesztőt használja, mint a kód (`renderTextEditor`): maga a megjelenített elem szerkeszthető, ugyanazokkal az osztályokkal, így a betű és a tördelés nem változik. A szövegmező és a hozzá tartozó kód / stílus megszűnt. A saját egérkijelölés, a kurzor követése és a visszavonás így a szövegfájlokra is érvényes. Tab (két szóköz) és a behúzás megtartása csak kódfájlban; a `.md` szerkesztéskor nyers szövegként látszik (megjelenítéskor formázva).
- **Tényleges méret:** sortöréssel végződő szövegnél a doboz a záró üres sornak is helyet hagy (szerkesztéskor oda áll a kurzor), így a tartalomra igazított dobozban szerkesztésbe lépve nem jelenik meg görgetősáv.
- Safariban kipróbálva (`test-container`): a `jegyzet.txt`-ben a „kicsit.” szó megjelenítéskor és szerkesztéskor ugyanott áll, a doboz nem görget; gépelés, Enter, törlés működik; a `demo.css` változatlan; a `leiras.md` nyers szövegre vált és vissza.
- Szerverkód: csak a szkript- és stíluslap-verzió változott; release build, a helyi szerver újraindítva.

## 2026-11-25 – Kódszerkesztő: azonos betű, saját egérkijelölés; „tényleges méret” szöveg- és kóddobozra

- **Betű és magasság:** szerkesztésbe lépve a kód betűje és a tartalom magassága megváltozott. Ok: megjelenítéskor a szöveg `<pre><code>` elemben áll (a `code` a böngésző saját egyenközű betűjét kapja), a szerkesztő viszont közvetlenül a `<pre>`-be írt. Most a szerkesztő is `<code>` elembe ír, a kettő azonos (Safariban mérve: 900 → 900 képpont).
- **Kijelölés ugrása:** ha a szöveg hosszabb volt a doboznál, egérhúzásra a kijelölés a szöveg végére ugrott, és a doboz az aljára görgetett (Safari: a foreignObject-en belül a böngésző saját húzásos kijelölése és automatikus görgetése téves). A kódszerkesztő egérkijelölése most saját: a mutató helyét a doboz vászonbeli helyéből számolja (mint a táblázat cellájánál), a karakterpozíciót a szöveg kurzorhelyeiből felezéssel keresi. Kattintás, Shift+kattintás, húzás, dupla kattintás (szó), tripla (sor); a doboz szélén túl húzva a tartalom görög. A kurzor követése (gépelés, nyílbillentyűk) is ebből a geometriából számol.
- **Tényleges méret gomb** a szöveg- és kódfájl dobozok paneljén is (Text csoport), ahogy a táblázatnál: a doboz a leghosszabb sor tördelés nélküli szélességére és a teljes magasságra áll; `.md` doboznál a szélesség marad, a magasság igazodik (`fitBoxToContent`). Szerkesztés közben előbb kilép a szerkesztésből.
- A `.txt` / `.md` szövegmező belső térköze a megjelenítéséhez igazítva (a jobb oldali sávhely miatt eltérő szélességen tördelt).
- Safariban kipróbálva, valódi egérmozgással: betű és magasság azonos megjelenítéskor és szerkesztéskor; kattintás görgetve is a várt sorra teszi a kurzort; dupla kattintás szót jelöl ki; húzásra a kijelölés nem ugrik, a görgetés marad; a doboz alá húzva lefelé görget és a kijelölés bővül; nyílbillentyűkkel a doboz követi a kurzort; a „tényleges méret” után a kód-, JSON-, szöveg- és markdown-doboz sem görget.
- Szerverkód: csak a szkript- és stíluslap-verzió változott; release build, a helyi szerver újraindítva.

## 2026-11-25 – Kódfájl szerkesztése egy rétegben

- **Egy réteg (kérés szerint):** szerkesztés közben nincs szövegmező a színezett szöveg fölött. Maga a böngészőben színezett szöveg szerkeszthető (`contenteditable`, `renderCodeEditor`); a szerver színezése szerkesztés alatt nem látszik, kilépéskor (mentés után) az váltja fel. A korábbi kétrétegű megoldás (átlátszó betűjű szövegmező a színezett réteg fölött) megszűnt: Safariban kijelöléskor a két réteg fél sorral elcsúszott egymáson.
- **Működés:** a szöveg egy helyen él (`codeEdit.text`); a bevitelt a `beforeinput` fogja el, a szöveget a szerkesztő írja át, újraszínezi, és a kurzort karakterpozíció szerint visszateszi. Összetett bevitel (holt billentyű, IME) a DOM-ba ír, a végén onnan olvassuk vissza. Beillesztés, kivágás, másolás sima szövegként. Saját visszavonás / újra (Cmd/Ctrl+Z, Shift+Z, Y), az egymást követő gépelés egy lépés. Tab: két szóköz; Enter: az előző sor behúzásával.
- **Javítások a szövegfájlok (`.txt`, `.md`) szövegmezőjén:** sötét módban a mező háttere eltakarta a doboz felületét és a panel szövegszínét vette fel (az általános űrlapmező-szabály erősebb volt) – most átlátszó, a doboz szövegszínével; a vászon kijelöléstiltását örökölte, így egérrel nem lehetett kijelölni – most lehet.
- Safariban kipróbálva (automatizálva, `demo.mjs`): egyetlen réteg van; gépelésre azonnal színez; Enter behúzással; törlés; visszavonás lépésenként; minden kijelölése; Esc után a szerver ugyanannyi színezett szakaszt ad. Szemmel nézendő tételek: BUGS.md.
- Szerverkód: csak a szkript- és stíluslap-verzió változott; release build, a helyi szerver újraindítva.

## 2026-11-25 – Kódszínezés szerkesztés közben (a böngészőben)

- **Szerkesztés közben is színes a kód:** a dobozon szerkesztett kódfájl gépelés közben azonnal színeződik. A színezést ilyenkor a böngésző végzi; a szerver színezése szerkesztés alatt nem látszik, kilépéskor (mentés után) az váltja fel.
- **Pontos másolat:** `Public/highlight/` – a `ThinkHighlight` Swift-modul mása JavaScriptben, nyelvenként egy fájl (`scanner.js`, `json.js`, `css.js`, `javascript.js`, `swift.js`, `html.js`, `index.js`), ugyanazzal a felépítéssel és nevekkel, hogy a két oldal sorról sorra összevethető legyen.
- **Közös tesztkészlet:** `Tests/Fixtures/highlight.json` – 191 rövid eset a szakaszok teljes listájával (nyelvenként a nehéz helyek, és hibás / lezáratlan bemenetek minden nyelven), és 5 valódi mintafájl (`Tests/Fixtures/highlight/`, kb. 100 KB kód) a szakaszok számával és ellenőrző összegével. Mindkét oldal ugyanezt ellenőrzi: `Tests/Editor/highlight.mjs` és `highlightMatchesSharedFixtures`. A két megvalósítás minden eseten egyezik. A fixture újraírása: `node Tests/Editor/highlight.mjs --write`.
- **Megjelenítés:** (első változat, a fenti bejegyzés váltotta) színezett réteg és fölötte átlátszó betűjű szövegmező. Nem színezhető szövegfájl (`.txt`, `.md`, más kód) változatlanul sima szövegmező.
- **Új nyelv ezentúl:** egy Swift-fájl (`Sources/ThinkHighlight`), egy JS-fájl (`Public/highlight`), egy-egy sor a két listában, és esetek a közös tesztkészletben.
- Tesztek: `test.sh highlight` (10 Swift-teszt és `highlight.mjs`) rendben; `--js editor` rendben.
- Ellenőrzés: fej nélküli Chromiumban a két réteg helye, mérete és betűje azonos, gépelésre a színezés azonnal frissül (41 → 63 szakasz), kilépés után a szerver HTML-je ugyanannyi szakaszt ad. **Safariban nincs ellenőrizve** (az automatizált Safari a munkamenet közben elakadt) – BUGS.md.
- Szerverkód: csak a szkript- és stíluslap-verzió változott (`Rendering.swift`); release build, a helyi szerver újraindítva.

## 2026-11-25 – Kódszínezés: JavaScript, Swift, HTML

- Három új nyelv a `ThinkHighlight` modulban, nyelvenként egy fájl:
  - **JavaScript** (`.js`, `.mjs`, `.cjs`): megjegyzés, szöveg, sablonszöveg `${…}` beágyazással, reguláris kifejezés, szám, kulcsszó, nagybetűs név, függvényhívás, pont utáni tulajdonság. A `/` jelről a megelőző szakasz dönt: érték után osztás, egyébként reguláris kifejezés.
  - **Swift** (`.swift`): egymásba ágyazott megjegyzés, szöveg `\(…)` beágyazással, többsoros (`"""`) és nyers (`#"…"#`) szöveg, attribútum (`@MainActor`), fordítási utasítás (`#if`), típus, függvényhívás, pont utáni tag. A helyzetfüggő kulcsszavak (`get`, `set`, `prefix`, `open`…) névként használva nem kapnak kulcsszó-színt.
  - **HTML** (`.html`, `.htm`): megjegyzés, `<!DOCTYPE>`, elemnév, attribútum és érték, karakterhivatkozás. A `<script>` tartalma JavaScriptként (JSON típusnál JSON-ként), a `<style>` tartalma CSS-ként színeződik.
- **Közös olvasó:** beágyazott nyelv olvasása résztartományon (`CodeScanner.scan(_:until:)`, `end`). A beágyazások mélysége korlátos (24), így a szándékosan mélyre ágyazott bemenet sem terheli a szervert.
- Tesztek: `test.sh highlight` (9 teszt; nyelvenként a nehéz esetek, és hibás / lezáratlan / mélyen ágyazott bemenetre a kimenet mindig a teljes forrás). `test.sh --swift highlight render`: 36 teszt rendben.
- Safariban kipróbálva (`projects/test-container`): a behúzott `demo.mjs`, `demo.swift`, `demo.html` doboz színezett szakaszokat kap (a DOM-ból ellenőrizve; a színek szemmel nézendők).
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Kódszínezés a letölthető SVG-ben

- Az önálló SVG-be (letöltés: `/export/svg/…`, és a lap előnézeti rajza) beágyazódnak a kódszínezés színszabályai és a kód alapformája (egyenközű betű, tördelés), ha a lapon van színezhető kódfájl (`codeStyle`, `Rendering.swift`). A megtekintő oldalon nincs beágyazás, ott az `app.css` adja.
- A szabályok egy helyen: `CodeHighlight.colourRules` (ThinkHighlight); teszt őrzi, hogy szó szerint egyeznek az `app.css` `.hl-*` szabályaival (`highlightColourRulesMatchTheStylesheet`), és hogy az export tartalmazza őket (`standaloneSVGEmbedsCodeColours`).
- Safariban kipróbálva: a `projects/test-container` letöltött SVG-je önállóan megnyitva színes (`demo.json`, `demo.css`).
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Kódszínezés (JSON, CSS) és dobozon szerkesztés

- **Kódszínezés:** a `.json` és a `.css` kódfájl doboza színezve jelenik meg a szerkesztőben és a megtekintőben. Saját, könnyű elemző (nem nyelvtani elemzés): megjegyzés, szöveg, szám, kulcsszó, kulcs / tulajdonságnév, szelektor, függvény, írásjel. A tévedés legfeljebb rossz szín, a fájl tartalmához a színező nem nyúl.
- **Külön modul:** `server/Sources/ThinkHighlight` (önálló SwiftPM cél, csak a Foundationtől függ; teszt: `Tests/ThinkHighlightTests`). Új nyelv: egy fájl a modulban (`CodeLanguage`) és egy sor a `CodeHighlight.languages` listában. Most: `JSONLanguage.swift`, `CSSLanguage.swift`.
- **A szerver színez, a kliens megjelenít:** a kész HTML a fájl tartalma szerint gyorsítótárazva (`highlightedCode`, `Rendering.swift`), így csak változáskor készül újra. A szerkesztő a doboz fájljához a `GET /api/attachment/<lap>?name=…&highlight=<kiterjesztés>` címről kéri (204: nincs hozzá nyelv). A fájl első 100 000 bájtja kap színt (`colouredLimit`), a többi sima szöveg.
- **Színek:** hat szín a doboz szövegszínéhez keverve (`.hl-*`, `app.css`), így világos és sötét háttéren is olvasható, témától függetlenül.
- **Tördelés:** a kódfájl sorai tördelődnek (eddig vízszintesen görgettek); sorszám nincs.
- **Dobozon szerkesztés (új fogalom):** a szövegfájl (`.txt`, `.md`, kód) a vásznon, a doboz helyén szerkeszthető. Dupla kattintás nyitja (Alt-tal a tulajdonságpanel), Esc vagy a doboz elengedése zárja. Közben sima szöveg látszik; a formázott / színezett nézet bezáráskor, a mentés után tér vissza. Kódfájlban a Tab két szóközt ír, az Enter megtartja a sor behúzását.
- **Panel:** a szövegfájlok szövegmezője megszűnt; helyette „Szerkesztés a dobozon” gomb. Marad a betűméret, a szövegszín, a mentés állapota (kódnál a NAGYBETŰS kapcsoló nincs). Nagy fájlnál (256 KB fölött) változatlanul a külön ablakos szerkesztés.
- **Mentés:** a doboz elengedése előtt a függő fájlmentés lefut (`saveFileText`, `selectNode`), így a `file.rev` akkor is lép, ha a szerkesztést máshová kattintva hagyják el – a többi résztvevő ebből tölti újra a fájlt. (A táblázat / CSV cellaszerkesztésére is érvényes.)
- Tesztek: `test.sh highlight` (5 teszt: JSON, CSS, HTML-védés, hibás bemenet, nagy fájl); `test.sh --swift render`, `--js editor` rendben.
- Safariban kipróbálva (`projects/test-container`): behúzott `demo.json` és `demo.css` színes, a sorok tördelődnek; dupla kattintásra szövegmező nyílik fókusszal, gépelés után Esc-re a doboz mentve, újraszínezve jelenik meg. A megtekintő oldalon a színezett szakaszok megvannak.
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Egységes konténer-fogalom: konténer az, amiben éppen van objektum

- **Szabály:** konténer az a doboz, amiben éppen van másik objektum (van, aminek ő a szülője). Eddig kétféle fogalom élt: a tárolt `container` jelző (a doboz kiürülve is konténer maradt) – ezt használta a rétegsorrend, a csomópont ejtése, a befogás, a panel és a szövegkörbefuttatás – és a „van benne doboz” – ezt a nyíl rárugrása. Most mindenhol az utóbbi érvényes.
- **Mi változik a gyakorlatban (csak kiürült konténernél):** a kiürült konténer újra sima doboz. A ráejtett csomópont feloldódik benne (nem a tartalma lesz); a rétegsorrendben a mérete szerint áll, nem a konténerek között legalul; mozgatva nem fog be más dobozt; a panelről eltűnnek a konténergombok (tartalom rögzítése, szövegkörbefuttatás). Ha újra dobozt ejtesz rá, megint konténer.
- **Tárolt jelző:** a `container` mező megmarad a fájlban, de a kód nem belőle dolgozik; a szerkesztő minden módosításkor a tényleges állapothoz igazítja (`syncContainerFlags`), a módosítással egy visszavonási lépésben. A szerver a rajzoláskor és az ellenőrzéskor a szülő–gyermek kapcsolatból indul ki: a szülőnek doboznak kell lennie (a jelző már nem feltétel), és megszűnt az a szabály, hogy `textFlow: true` csak konténeren állhat.
- Helye: `editor.js` (`containerIDs`, `syncContainerFlags`; az `occupiedContainers` megszűnt), `editor-history.js`, `collaboration.js` (a szülő érvényessége), `Model.swift` (`validate`), `Rendering.swift` (`containers`, `flowing`).
- Tesztek: a `gestures.mjs` érintett részei az új szabályhoz igazítva (kiürült konténer nem fog be dobozt; újra konténer lesz, ha dobozt ejtenek rá; üres dobozra ejtett csomópont feloldódik). `test.sh --all` rendben (86 Swift-teszt, minden JS-teszt).
- Safariban kipróbálva: tartalmas konténerben mozgatott és oda behúzott csomópont a konténer tartalma marad / lesz; a jelzős, de üres konténerre ejtett csomópont feloldódik benne, és a konténer jelzője a mentett fájlból eltűnik.
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Takarítás a konténer- és vonalátalakítás után (a működés nem változik)

- **Nem használt szűrők és CSS:** törölve az `ownSurface` és `ownWire` fényudvar-fajta (`glow.js`), a `--glow-own-surface` és `--glow-own-frame` CSS-változó (`editor.js`), és a mozgás közbeni szűrőkikapcsoló szabályból a három elavult elem (`app.css`). A doboz felülete és a vonal saját kijelölése már korábban szűrő nélküli lett.
- **Nem használt kód:** törölve a `viewer.js` felesleges importjai (`arrowLength`, `arrowTransform`), az `editor.js` felesleges importjai (`plainFirstLine`, `shapeOutline`) és a sehonnan nem hívott `sessionAction` (a korábbi munkamenet-mentés / visszaállítás függvénye), a `geometry.js` nem használt exportjai (`canvasBounds`, `edgeStyles`, `shapeOutline`), a `glow.js` `glowURL` függvénye és a szerveroldali rajz `nodeLayers` változója (a régi vonalréteg-számításhoz kellett). Megjegyzés: a `sessionAction` törlése után a `checkpointState` / `checkpointRevision` / `checkpointBusy` állapot még megvan (a szerver üzeneteit fogadja), de már semmi nem állítja – ez a régebbi mentési rendszer maradéka, nem ebben a körben került elő.
- **`home` mező:** törölve a modellből (`Model.swift`) és a szerkesztő visszaállító kódja (`restoreHomes`). Az első, rácsba rendező változat tárolta ide a gyermekdoboz kézi helyét; az a változat csak 2026-11-25-én, helyben élt. Előtte ellenőrizve: egyik helyi lap (`a`, `a/grafikon`, `test-container`) sem tartalmaz `home` mezőt. Ha egy fájlban mégis maradt, a szerver figyelmen kívül hagyja és a következő mentéskor elhagyja.
- **`autoLayout` → `textFlow`:** a konténer szövegkörbefuttatásának kapcsolója a fájlban és a kódban mostantól `textFlow` (alapból be, `false` kapcsolja ki). A szerver a régi `autoLayout` kulcsot olvasáskor még elfogadja, mentéskor az új néven írja ki; teszt: `formerAutoLayoutKeyLoadsAsTextFlow`. Érintett helyi lapok (`a`, `test-container`) a következő mentéskor írődnak át. Mivel a régi név már a távoli ágon is szerepelt, az éles szerveren lévő lapokat is a szerver olvasási szabálya kezeli.
- **Nyílhegy-rövidítés egy helyen:** a „vonal a nyílhegy talpáig tart” számítás a szerkesztőben és a megtekintőben külön volt megírva; most közös függvény (`geometry.js wireHeads`), mindkettő azt hívja. A szerveroldali párja (`Rendering.swift head`) marad. A megtekintőben három felesleges változó is megszűnt.
- **Körbefuttatás egyezés-teszt:** tíz közös eset (`Tests/Fixtures/text-flow.json`: doboz nélkül, egy / két dobozzal, sorkizártan, három igazítással, keskeny konténerben, kikapcsolva, túl hosszú szöveggel). A szerkesztő tördelését a `Tests/Editor/text-flow.mjs`, a szerverét a `textFlowMatchesSharedFixtures` teszt veti össze ugyanazzal az elvárt sorlistával (szöveg, hely, igazítás); a két oldal mind a tíz eseten egyezik. A `test.sh` `editor` és `render` témája is futtatja.
- **Vonalak egyezés-tesztje:** tizenkét közös eset (`Tests/Fixtures/wires.json`: nyíllal és anélkül, vastag vonal, két nyílhegy rövid vonalon, oda-vissza párok vékony / ferde / 12-es / vegyes vastagságú / ellipszis–doboz változatban, S-görbe, kötél, konténer és belső doboza). A szerkesztő útvonalát a `Tests/Editor/wires.mjs`, a szerverét a `wirePathsMatchSharedFixtures` teszt veti össze; mind a tizenkét eseten egyezik. Ez fedi az oda-vissza eltolást, a vastagságfüggő távolságot és a nyílhegy talpáig érő vonalat. (A vonalak rétegét a `wiresRenderAboveEveryBoxExceptElevatedOnes` ellenőrzi.)
- Lezárás: teljes tesztkör (`test.sh --all`) rendben, 86 Swift-teszt és minden JS-teszt. A kijelölt csomópont Safari-ellenőrzése nem sikerült (BUGS.md); a konténer-fogalom egységesítése döntésre vár (TODO.md). Szerverkód változott (`Model.swift`, `Rendering.swift`): release build, a helyi szerver újraindítva.
- **Csomópont világosítása törölve:** a kijelölt csomópont felületének CSS `brightness(1.3)` szabálya (`app.css`) megszűnt (döntés: a Safari SVG-n nem rajzolja ki, képen nem volt ellenőrizhető). A kijelölt csomópontot továbbra is a körvonala jelzi.

## 2026-11-25 – Másik konténerbe áthúzott doboz húzás közben is látszik

- **Hiba:** ha egy dobozt az egyik konténerből a másikba húztál, a doboz az egér elengedéséig eltűnt. Ok: húzás közben a doboz még a régi konténeréhez tartozik, és a konténer a tartalmával egy tömb a rajzolási sorrendben – a később rajzolt másik konténer ezért eltakarta.
- **Javítás:** az éppen húzott doboz (a tartalmával együtt), illetve a húzott csoport húzás közben minden nem kiemelt doboz fölé kerül; elengedéskor a végleges helyére áll a sorrendben (`containers.js layerOrder` `lifted`, `editor.js liftedNodes`).
- Ellenőrzés: Safari, két konténeres próbalap, húzás közben megállítva: a sorrend `nagy konténer, kis konténer, m, áthúzott doboz` (előtte a doboz a kis konténer előtt állt), a képernyőképen a doboz látszik; elengedve a kis konténer tartalma lett. `test.sh editor` rendben. Csak kliensoldali változás. Más szerkesztő húzásánál (távoli mozgás) nem vonatkozik.

## 2026-11-25 – Vonalak rétege: minden vonal minden doboz fölött

- **Egyetlen szabály:** minden vonal minden doboz fölött fut – konténer, a konténer tartalma és a sima dobozok fölött is. Kivétel a **Kiemelt** objektum: az a vonalak fölött van.
- **data-connection:** a táblázatot (vagy CSV-t) és grafikont összekötő különleges vonal (eddigi nevén adatvonal) neve mostantól data-connection; ez mindig minden objektum mögött van (változatlan).
- Megszűnt a korábbi, végpontoktól és konténerektől függő rétegszámítás („a vonal a végpontjai alatt, az őket tartalmazó konténerek fölött”; konténer és belső doboza közti vonal külön esete; szabad végű vonal konténerből). Következmény: a vonal láthatóan átmegy az útjába eső dobozokon, és a vonal eleje / vége a doboz szélén a doboz fölé rajzolódik.
- Szerkesztő és szerver párban (`editor.js wireLayers`, `Rendering.swift`). Tesztek az új szabályhoz igazítva: `wiresRenderAboveEveryBoxExceptElevatedOnes` (Kiemelt dobozzal bővítve), `containerStylesAndJunctionsSurviveRoundTrip`, `gestures.mjs` két elvárása. `test.sh render editor worksheet` rendben.
- Ellenőrzés: Safari, próbalap beágyazott konténerekkel és egy Kiemelt dobozzal: a szerkesztőben és a megtekintőben minden vonal az összes doboz után, a Kiemelt előtt rajzolódik.
- Visszalépési pont, ha nem válik be: az ezt megelőző commit (`ecc4d94`).
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Csomópont konténerben; sok kijelölt vonal gyorsabb

- **Csomópont ejtése:** dobozra ejtve változatlanul feloldódik a dobozban (a vonalai a dobozhoz kötődnek). Konténerre ejtve nem oldódik fel: a konténer tartalma lesz, megmarad a vonalaival, és a konténeren belül szabadon mozgatható (a konténer szövege nem kerüli ki). Konténeren belüli dobozra ejtve abban a dobozban oldódik fel. Eddig a konténer is „doboznak” számított, ezért a konténeren belüli csomópont az első mozdításra feloldódott a konténerben, és csomópontot nem lehetett a konténerbe húzni. (`editor.js junctionDropTarget`; csoportos mozgatásra és vonal kettévágására ugyanez a szabály.)
- **Sok kijelölt vonal (Alt + téglalap):** a saját kijelölésű vonal eddig vonalanként SVG-szűrőt (fényudvar) kapott a teljes befoglaló téglalapjára; sok vonalnál ez lassú volt, és a Safari a túl nagy szűrős vonalakat időnként nem rajzolta ki. Most szűrő helyett a vonal alá rajzolt szélesebb, áttetsző sáv jelzi a kijelölést (`wire-own-halo`); más felhasználó kijelölése változatlan. Safari, 300 dobozos mérőlap, 162 doboz + 209 vonal kijelölve: kijelölés húzása közben a leghosszabb akadás 247 → 83 ms, nagyításnál 295 → 143 ms, csoport húzása 9 → 14 képkocka/mp (leghosszabb akadás 1,1 → 0,19 mp).
- Tesztek: a `gestures.mjs` két elvárása az új csomópont-szabályhoz igazítva (konténerre ejtve gyermek lesz, egyenként és csoportban húzva). `test.sh editor` rendben. Safariban kipróbálva: csomópont mozgatása konténeren belül, behúzás konténerbe, ejtés belső dobozra, kihúzás.
- Csak kliensoldali változás.

## 2026-11-25 – Vastag vonal nem lóg túl a nyílhegyen (megtekintő, export)

- **Ok:** a szerveroldali rajzban (megtekintő, SVG-export, előnézeti kép) a vonal a nyílhegy csúcsáig futott, a nyílhegy csak rá volt téve; vastag vonalnál a vonal vége (lekerekített véggel) kilógott a nyílhegy mellett és a csúcsán túl. A szerkesztő eddig is a nyílhegy talpánál fejezte be a vonalat.
- **Javítás:** a szerver is a nyílhegy talpáig rajzolja a vonalat, a nyíljelölő a vonal végéről indul (`Rendering.swift`; a szerkesztő `wireDrawing` / `wireArrow` párja). Két nyílhegy rövid, egyenes vonalon – mint a szerkesztőben – legfeljebb a fél hosszig ér. A megtekintő a dobozok élő mozgatásakor ugyanígy frissíti a vonalat (`viewer.js`).
- Tesztek: két meglévő teszt elvárt útvonala a rövidebb vonalhoz igazítva (`experimentalAnchorsLoadAsAutomaticConnections`, `themeProjectRoundTrip`). `test.sh render worksheet editor` rendben.
- Ellenőrzés: Safari képernyőkép a megtekintőről 12 / 24 / 32-es vonalakkal minden vonaltípusból (egyenes, S-görbe, ív, kötél, villám), egy- és kétnyilas, hosszú és rövid változatban; a szerkesztővel egyezik. A villám típus vastag vonallal és sűrű töréssel továbbra is zsúfolt (a szerkesztőben is).
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Oda-vissza kötés: a távolság a vonalvastagsághoz igazodik

- Az oda-vissza kötés két vonala közti távolság eddig fix 12 képpont volt, így két vastag (pl. 12-es) vonal összeért. Most a két középvonal távolsága: az egyik nyílhegy fél szélessége + a másik vonal fél vastagsága + 4 képpont (a két irány közül a nagyobb), de legalább 12. Két 2-es vonalnál 12 (változatlan), két 12-esnél 27, két 24-esnél 45, 2-es és 12-es párnál 22 képpont. Így sem a vonalak, sem a nyílhegyek nem érnek a másik vonalhoz.
- A vastagság változtatásakor a pár mindkét vonala újraszámolódik. Szerkesztő, megtekintő és szerver párban (`geometry.js pairShift`, `wireRoutes`, `reverseWidth`; `Rendering.swift`).
- Ellenőrzés: Safari képernyőkép a szerkesztőről és a megtekintőről 12-es, 24-es és vegyes (2 + 12) párral. `test.sh render editor` rendben. Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Oda-vissza kötés: a két vonal egymás mellett fut

- Ha két doboz között mindkét irányban van vonal (A → B és B → A), a két vonal nem fedi egymást: mindkettő a saját haladási irányához képest jobbra tolódik 6 képponttal, így párhuzamosan, 12 képpontra egymástól futnak, és a csatlakozási pontjaik is egymás mellé kerülnek. Egyirányú kötés változatlan. Azonos irányú második vonal továbbra sem húzható.
- Megvalósítás: a páros vonal geometriája a két doboz eltolt helyéből számolódik (`geometry.js edgeGeometry`, `pairGap`; `wireRoutes` / `hasReverse` ismeri fel a párt), a szerkesztőben, a megtekintőben és a szerveroldali rajzban (`Rendering.swift`) egyformán. Konténer és a saját belső doboza közti (beágyazott) vonalra és az adatvonalra nem vonatkozik.
- Korlát: ferdén érkező vonalnál az eltolt végpont néhány képponttal a doboz szélén belülre / kívülre eshet (a vonal a doboz alatt fut, így a belülre eső rész nem látszik; kívül legfeljebb pár képpontos rés lehet).
- Sebesség: a párok felismerése csak vonal felvételekor / törlésekor / átkötésekor számol (a lap vonalainak száma szerint), mozgatáskor vonalanként egy halmazkeresés. Safari, 300 dobozos mérőlap (`perf.py --sheet p300`): dobozmozgatás 59,4, csoportmozgatás 59,9, gyors pásztázás 60 képkocka/mp – a korábbi méréssel azonos.
- Ellenőrzés: Safari képernyőkép a szerkesztőről és a megtekintőről (vízszintes, függőleges, ferde pár, ellipszis–doboz pár). Külön automatikus teszt nincs. `test.sh render editor` rendben. Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Nyilak konténerben: rárugrás csak a szélnél, látható előnézet, vonal a konténerek fölött

- **Rárugrás:** az a doboz, amiben van másik doboz (konténer tartalommal), a nyíl végét csak a széle körüli sávban (kb. 18 képernyőpont befelé, 8 kifelé) vonzza magához; a belsejében a nyíl szabadon áll, vagy a benne lévő dobozokra ugrik. Így a belső dobozból kifelé húzott nyíl nem ragad azonnal a konténerre, és a kívülről a konténer belsejébe húzott nyíl is eléri a belső dobozt (`editor.js snap`). Üres konténer és a sima doboz változatlanul a teljes felületén cél.
- **Húzott nyíl láthatósága:** az előnézeti vonal világos szegélyt kapott; a kék vonal a sötétkék konténeren belül húzva szinte nem látszott.
- **Vonal két konténer dobozai között:** a vonalat a második konténer eltakarta (a mai rétegsorrend-váltás mellékhatása: a konténer és a tartalma egy tömb). A vonal most a végpontjai alatt, de minden őket tartalmazó konténer fölött fut; szabad végű vonal konténerből a konténer fölött. Szerkesztő és szerver párban (`editor.js wireLayers`, `Rendering.swift`).
- Teszt: `wiresBetweenBoxesInDifferentContainersRenderAboveBothContainers`; `test.sh render editor` rendben. Safariban (WebDriver, a test-container másolatán) kipróbálva: Ctrl-húzás belső dobozból a másik konténer belső dobozára – közben nincs rárugrás a konténerekre, a kész vonal látszik mindkét konténer fölött; konténerből a belső dobozra húzva a vonal létrejön.
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Címsor nem sorkizárt; alulra igazítás körbefuttatásnál; test-container próbaprojekt

- **Címsor:** címsor sosem sorkizárt. Sorkizárt szövegű dobozban a címsor a vízszintes igazítást követi (bal / közép / jobb a 9 gombból), a törzsszöveg marad sorkizárt. Szerkesztő és szerver párban (`geometry.js labelLayout`, `Rendering.swift ideaDrawing`).
- **Alulra igazítás konténerben:** körbefuttatott szövegnél az „alul” (és a „közép”) eddig visszaesett felülre, ha a lejjebb kezdett szöveg új akadályba ütközött és kilógott volna. Most ilyenkor csak annyival kezdődik feljebb, amennyivel kilógna, így a szöveg az alsó szélhez (középnél a közép közelébe) kerül.
- **Projektek (helyi adat):** a `projects/b` törölve (a felhasználó kérésére); új `projects/test-container`: öt konténer (teljes markdown sorkizárva és belső konténerrel; középre; alulra-jobbra sorkizárva; keskeny; körbefuttatás kikapcsolva), egy sima doboz ugyanazzal a szöveggel és egy rálógó doboz. A szöveg minden támogatott markdown-elemet tartalmaz: három címsorszint, félkövér, dőlt, félkövér-dőlt, soron belüli kód, link, felsorolás három szinten, számozott lista, idézet, kódblokk, vízszintes vonal, soron belüli sortörés.
- Ellenőrzés: Safari képernyőképen a próbalap (szerkesztő): körbefuttatás, alulra igazítás, jobbra álló címsor sorkizárt szöveg fölött. `test.sh render editor markdown` rendben. Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Körbefuttatás: ritkább újratördelés húzás közben, nagyobb térköz a doboz két oldalán

- **Ritkább újratördelés:** húzás közben a konténer szövege csak akkor tördelődik újra, ha a belső doboz legalább 12 képpontot mozdult (a doboz helye ilyenkor 12-es lépésekre kerekítve számít); elengedéskor a pontos hellyel. A legfeljebb 6 képpontos eltérés a doboz körüli térközön belül marad. A konténer húzásakor a szöveg egyáltalán nem számolódik újra.
- **Térköz:** a szöveg a belső doboz bal és jobb oldalától 18 képpontra áll (eddig 8); fent és lent marad 8. Szerkesztő, megtekintő és export egyformán (`geometry.js labelLayout`, `Rendering.swift ideaDrawing`).
- Mérés (Safari, a `projects/b` másolata, a belső doboz gyors húzása): sorkizárással 42 → 45 képkocka/mp, anélkül 55 → 57; lassabb húzásnál a nyereség nagyobb, mert több képkocka marad újratördelés nélkül. A sorkizárás pontossága változatlan (0,05 képponton belül).
- Megjegyzés: mióta a sorkizárás Safariban ténylegesen működik, a sorkizárt doboz több soros címsora is kitöltődik (a szavak közé kerül a hely).
- `test.sh render editor markdown` rendben. Szerverkód változott (`Rendering.swift`): release build, a helyi szerver újraindítva.

## 2026-11-25 – Körbefuttatott konténerszöveg: a belső doboz húzása gyorsabb

- **Mérés (Safari, a `projects/b` lap másolata, 777 × 790-es konténer 1400 betűs szöveggel, benne egy doboz húzása):** előtte 14 képkocka/mp, egyes képkockák 230–320 ms; körbefuttatás nélkül 60 képkocka/mp. A saját számítás közben elhanyagolható (a körbefuttatás 0,4–1,5 ms, a rajzoló függvények összesen ~20 ms a teljes húzásra).
- **Ok:** amikor a doboz mozgása miatt a sorok átrendeződnek, a Vue soronként írta át a szöveget: egy képkockában 200–290 DOM-módosítás, 60–90 `tspan` törlése és beszúrása. A Safari minden beszúrt / törölt elem után újraépíti a teljes `<text>` elrendezését. (Egy sor szövegének vagy az összes sor helyének módosítása önmagában 2 ms.)
- **1. javítás – a szöveg egy lépésben cserélődik:** a doboz `<text>` eleme a sorok tartalmából képzett kulcsot kap; ha a tördelés változik, az új szöveg a dokumentumon kívül épül fel, és egyszer kerül be. Ha csak a sorok helye változik, a kulcs marad, és csak az x / y frissül. Eredmény: sorkizárás nélkül 14 → 55 képkocka/mp.
- **2. javítás – sorkizárás rajzolás előtt:** a sorkizárt sor eltolásai (`dx`) már a virtuális DOM-ban a sorra kerülnek, nem kirajzolás utáni méréssel és visszaírással. A sor hossza húzás közben vászon-szövegmérésből jön (0,3–4 képponttal eltérhet a Safari SVG-szövegétől); nyugalomban és a mozdulat végén a böngésző pontos mérése igazítja be, és a pontos hosszt megjegyzi (utána a jobb szél 0,05 képponton belül pontos). Eredmény sorkizárással: 14 → 42 képkocka/mp (95. percentilis 235 → 35 ms).
- Kipróbálva, de elvetve: a `<text>` kivétele a dokumentumból a `dx`-írások idejére (nem gyorsított).
- Helye: `Public/editor.js` (`renderNode`: a `<text>` kulcsa, `justified`), `Public/justify.js` (`justifyShifts`, `justifyRows`). `test.sh editor markdown` rendben. Csak kliensoldali változás; a helyi szerver újraindítva.

## 2026-11-25 – Sorkizárás Safariban, igazítás a körbefuttatott konténerben, kijelölt doboz háttere

- **Sorkizárás:** a kapcsoló Safariban hatástalan volt, mert a Safari SVG-szövegen nem alkalmazza a `word-spacing`-et. A sor most betűnkénti `dx` listát kap (a szóköz utáni betű tolódik), ez Safariban is működik. Kikapcsoláskor az eltolás lekerül a sorról (`Public/justify.js`; szerkesztő és megtekintő).
- **Igazítás körbefuttatásnál:** a függőleges igazítás (közép / alul) a körbefuttatott konténerszövegre is hat: a szöveg kezdőpontját néhány lépésben közelítjük, mert a sorok helye a magasságtól függ. A vízszintes igazítás a sor szabad helyén belül érvényes; sorkizárt szöveg balra zárt marad. Szerkesztő és szerver párban (`geometry.js labelLayout`, `Rendering.swift ideaDrawing`).
- **Belső doboz húzása:** a sorkizárás mérése kötegelve fut (előbb minden írás, aztán minden mérés: egy elrendezés soronkénti helyett), és az azonos tartalmú sor hosszát megjegyzi. Maga a körbefuttatás számítása 0,4–1,5 ms (Node.js, a `projects/a` és `b` konténerein mérve).
- **Kijelölt doboz háttere:** a saját kijelölés a doboz felületére SVG-szűrőt (fényudvar + világosítás) tett; nagy vagy a képernyőről kilógó dobozon a Safari a szűrős felületet nem rajzolta ki, a konténer háttere eltűnt (képernyőképpel reprodukálva). A felületen és a kereten már nincs szűrő: a világosítást szűrő nélküli fedőréteg adja (`.selection-own-tint`), a kijelölést a vastag keret jelzi; a fényudvar a dobozon megszűnt.
- Ellenőrzés: Safari képernyőképen a sorkizárás és az alsó igazítás látszik. **Nincs ellenőrizve böngészőben:** a kijelölt konténer új megjelenése és a belső doboz húzásának sebessége (a gép képernyője a próba alatt zárolva volt, egérműveletet nem lehetett küldeni). `test.sh render editor markdown` rendben. Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Konténer: a szövegkörbefuttatás alapból be van kapcsolva

- Minden konténer saját szövege kikerüli a benne lévő dobozokat, külön bekapcsolás nélkül. A konténer paneljén a rács ikonnal („Szöveg körbefuttatása a tartalom körül”) kikapcsolható (`autoLayout: false`).
- Következmény: a meglévő lapokon is, ahol egy konténernek szövege és gyermekdoboza is van, a szöveg mostantól felülről folyik és kikerüli a dobozokat (szerkesztő, megtekintő, export). Gyermek nélküli konténer változatlan.
- `test.sh render editor worksheet` rendben. A szerver kódja változott (`Rendering.swift`): release build készült, a helyi szerver újraindítva.

## 2026-11-25 – Sorkizárt szövegű doboz mozgatása gyorsabb

- **Ok:** a sorkizárás (`Public/justify.js`) a doboz minden újrarajzolásakor – húzás közben képkockánként – újramérte a sorok szélességét (`getComputedTextLength`, kényszerített elrendezés). A `projects/b` lap másolatán a 22 soros, sorkizárt konténer húzása Safariban 30 fps volt (60 képkocka alatt 732 mérés, kb. 1,5 mp).
- **Javítás:** a sor csak akkor mér újra, ha a tartalma, a kért szélessége vagy a betűje változott (soronkénti kulcs; betűkészlet betöltésekor érvénytelenedik). Ugyanaz a húzás most 54 fps, mérés nélkül.
- Mérés: automatizált Safari, `Tests/Perf/perf.py` rögzítője, release szerver. `test.sh editor` rendben. Csak kliensoldali változás.

## 2026-11-25 – Konténer: a saját szöveg kikerüli a benne lévő dobozokat

- **Mit csinál:** a konténer tulajdonságpaneljén (Doboz csoport, rács ikon) „Szöveg körbefuttatása a tartalom körül”. Bekapcsolva a konténer saját szövege felülről folyik, és soronként kikerüli a közvetlen gyermekdobozokat: a sor a doboz mellett, a legszélesebb szabad helyen folytatódik, vagy ha ott túl kevés a hely, a doboz alatt. A gyermekdobozok ott maradnak, ahová kézzel kerültek; a helyük és méretük nem változik.
- **Élő:** gyermek húzásakor a konténer szövege azonnal újratördelődik. A megtekintő és az SVG-export ugyanígy tördel (a két oldal kódja párban áll).
- **Korlátok:** a függőleges igazítás körbefuttatásnál nem hat (a szöveg felül kezdődik); a dobozok körül 8 képpont térköz van; ami nem fér ki, az a szokott módon „…”-tal rövidül (a konténer nem nő).
- **Az első változat megszűnt:** a rácsba rendezés (a gyermekek áthelyezése) félreértés volt, kikerült. Ahol az a változat már áthelyezett dobozokat, ott a szerkesztő a lap következő módosításakor visszateszi őket a kézi helyükre (`home` mező, utána törlődik).
- Adatmodell: a konténeren `autoLayout` (a név az első változatból maradt). Helye: `Public/geometry.js` (`textSlot`, `wrapRuns`, `labelLayout`), `Public/editor.js` (`flowObstacles`), `Sources/ThinkCore/CanvasMarkdown.swift` (`wrapMarkdown`, `TextSlot`), `Sources/ThinkCore/Rendering.swift` (`textSlot`, `ideaDrawing`).
- Kipróbálva Safariban (WebDriver, ideiglenes próbalap): szerkesztő, gyermek áthúzása, megtekintő. `test.sh render editor markdown worksheet` rendben. Külön automatikus teszt a körbefuttatásra nincs. A szerver kódja változott: release build készült, a helyi szerver újraindítva.

## 2026-11-25 – Konténer: a rálógó doboz a konténer tartalmát is kitakarja

- **Rétegsorrend:** a konténer és a teljes tartalma (beágyazott konténerekkel együtt) egy tömbként kerül a rajzolási sorrendbe. Ami a konténer fölött van és nem a része, az a tartalmát is kitakarja. Eddig a konténer kisebb gyermekdobozai „átütöttek” a rálógó, náluk nagyobb idegen dobozon.
- Testvérek között a szabály változatlan: előbb a konténerek, aztán a nagyobb doboz van alul. A kiemelt rétegben továbbra is csak a méret számít.
- Helye: `Public/containers.js` (`layerOrder`, a szerkesztő ezt használja), `Sources/ThinkCore/Rendering.swift` (megtekintő, SVG-export). Teszt: `boxesAboveAContainerAlsoCoverItsContents`; `test.sh render editor` rendben.
- Böngészőben (Safari) nincs külön kipróbálva. A szerver kódja változott (`Rendering.swift`): futó szervert újra kell indítani.

## 2026-11-25 – Grafikon önálló objektumként (D3), adatvonal, táblázat-igazítás

- **Grafikon (`chart` típus):** önálló objektum, saját fájl nélkül: oszlop-, vonal-, kör- és pontdiagram. Az adatát a vonallal bekötött táblázat (`.tntable`) vagy CSV adja; bekötött táblázat nélkül üres. A táblázat csak táblázat marad (a korábbi, ágon belüli „megjelenítés: grafikon” mód megszűnt). A grafikon törlése a táblázatot nem érinti; a táblázat törlése után a grafikon megmarad üresen.
- **Létrehozás:** a táblázat / CSV paneljén és helyi menüjében „Grafikon létrehozása”: új grafikon a táblázat mellett, bekötve. Az „Önálló táblázat (másolat)” gomb megszűnt.
- **Adatvonal:** a táblázat és a grafikon közti vonal automatikusan adatvonal (nem választható, nem tárolt tulajdonság: a két végpont típusa adja). Nyíl helyett mindkét végén félkorong áll, a lapos oldala a doboz oldalára simul; a nyílkapcsolók ezen a vonalon nem látszanak. Egy grafikonba egy táblázat köthető: újabb bekötésekor a korábbi adatvonal megszűnik, az oszlopkiosztás automatikusra áll. Más dobozból akárhány közönséges vonal mutathat a grafikonra.
- **Adatvonal helye:** mindig minden objektum mögött van (legalsó réteg), és a két doboz egymás felé eső oldalának közepéhez csatlakozik.
- **Hajtott lapsarok megszűnt:** a szövegfájl-, CSV- és táblázatdobozok jobb felső sarkából lekerült a hajtott sarok jele (szerkesztő, megtekintő, export).
- **Grafikon panel:** típus, forrás neve, kategóriaoszlop, értékoszlopok (legfeljebb 8; pont: 3, kör: 1), fejlécsor. Automatikus kiosztás: az első szöveges oszlop a kategória, a számoszlopok a sorozatok. A CSV számai magyar és angol írásmóddal is felismerődnek. Kördiagramon a nyolc fölötti szeletek „Egyéb” néven összevonódnak.
- **Megtekintő:** ugyanaz a modul (`Public/chart.js`) rajzol a bekötött táblázat fájljából. Szkript nélküli kimenetben (SVG-export, előnézeti kép) a grafikon doboza üres.
- **D3:** külön csomag a rajzoláshoz: `Public/lib/d3-chart.js` (d3-scale + d3-shape, 39 KB), a tárolóban; csak akkor töltődik le, ha a lapon van grafikon. Újraépítés: `deploy/d3-slim.sh` (mindkét csomagot építi).
- **Táblázat és CSV doboza:** a sarka 5 px-es lekerekítésű (a grafikoné a szokásos); a jobb oldalon megszűnt a görgetősávnak fenntartott sáv, így a tartalomhoz igazított dobozban nincs fölösleges margó.
- **Közös fájl változásszámlálója:** ha egy lapon több doboz mutat ugyanarra a fájlra, a mentés a legnagyobb számláló fölé lép (`latestRev`); a grafikon a forrás legfrissebb változatát olvassa.
- **Tesztek:** `chart.mjs` (JS: számfelismerés, kiosztás, a négy típus SVG-je, adatvonal és félkorong), `chartIsAStandaloneObjectFedByTheConnectedTable` (Swift).
- Helyi próbalap: `projects/a/grafikon` (kézzel létrehozva a teszthez).
- Szerverkód változott: újrafordítva és újraindítva.

## 2026-11-25 – Csomag: darabolt, folytatható feltöltés és közvetlen letöltés; nagy szövegfájl külön ablakban

- **Csomag-mérethatár:** 200 MiB helyett 4 GiB (a ZIP64 nélküli ZIP formátum határa; a saját export tömörítés nélküli), kibontva 8 GiB, 20 000 fájl. Induláskor szabadhely-ellenőrzés.
- **Feltöltés darabokban:** 8 MiB-os darabok, folyamatjelző a párbeszédablakban. Megszakadt kapcsolatnál a kliens magától újrapróbál (egyre hosszabb szünetekkel), utána „Folytatás” gomb; a kapcsolat visszatértekor magától folytat. A szerver csak a saját folytatási pontjától fogad el adatot, így darab nem kerülhet be kétszer és nem maradhat ki. Az oldal újratöltése vagy a szerver újraindítása után ugyanazt a fájlt kiválasztva onnan folytatódik (24 óráig). Részletek: `server/docs/migration.md`.
- **Letöltés:** a csomag a szerveren várja a letöltést (egy óráig, csak a készítőjének); a böngésző közvetlenül lemezre tölti, a saját letöltéskezelőjével folytathatóan – korábban az egész csomag a lap memóriájába töltődött.
- **Nagy szövegfájl (256 KB fölött):** az oldalsávon szövegmező helyett „Szerkesztés külön ablakban” gomb; a külön ablak a teljes fájlt szerkeszti, automatikus mentéssel és ütközésvédelemmel (ha közben más mentett, nem írja felül). A fájl eredeti sorvégei megmaradnak.
- **Döntések:** a megtekintő görgetése marad; a hozzáférés-kérelmező nem kap levelet; projektek között a beillesztett fájl másolat marad.
- **Tesztek:** `packageUploadsInChunksAndResumes`, `textFileEditorSavesAndDetectsConflicts` (Swift), `package-upload.mjs` (JS: hálózati hiba, elveszett válasz, folytatás, lejárat). Élő próba a helyi szerveren: letöltés részleges kéréssel, feltöltés két darabban megszakítással, rossz folytatási pontra 409. Automatizált Safariban a szövegszerkesztő oldal és a böngészőből indított darabolt feltöltés működik; képernyőkép nem készült (a kijelző aludt).
- Nincs kipróbálva: több GB-os csomag, valódi hálózati megszakadás, a párbeszédablak és a szövegszerkesztő kinézete.
- Szerverkód változott: újrafordítva és újraindítva.

## 2026-11-25 – Szűkített d3-csomag

- A szerkesztő a teljes d3 (280 KB, tömörítve 93 KB) helyett csak a használt részt kapja: `zoom`, `zoomIdentity`, `select`, `pointer` és a függőségeik – `server/Public/lib/d3-zoom.js`, 55 KB (tömörítve 18,6 KB). A fájl a tárolóban van, a saját szerver adja ki; a `deploy/build.sh` a d3-at már nem tölti le.
- Újraépítés (csak verzióváltáskor vagy új d3-függvény használatakor): `server/deploy/d3-slim.sh` – az npm-ről letölti a `d3-zoom` 3.0.0 és `d3-selection` 3.0.0 modult és az esbuildet egy ideiglenes mappába, és egy fájllá fűzi őket.
- Ellenőrizve: minden teszt zöld; automatizált Safariban a szerkesztő betölt, a görgős nagyítás működik, és ugyanaz a próba a teljes d3-mal pontosan ugyanazt az eredményt adta. A pásztázást az automatizált húzás egyik csomaggal sem mozdította (a tesztkörnyezet sajátja), ezt kézzel érdemes megnézni.
- A régi `server/Public/vendor/d3.js` törölve (engedéllyel; nem volt a tárolóban, a szerver már nem használta).
- Szerverkód változott (a szkript hivatkozása): újrafordítva és újraindítva.

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
