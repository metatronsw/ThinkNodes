# Vászonobjektum-típusok

Tervezési leírás: a dobozfajták egységesítése. Itt rögzítjük a döntéseket, mielőtt a kód átépül.
A 2-es sémájú munkalap megnyitáskor és importáláskor a 3-as objektummodellre alakul. A következő mentés már az új formátumot írja.

## Felépítés

- **Típus (`type`):** egyetlen mező az objektumon, ez váltja ki a mai `kind` + `file.type` + link-alapú megkülönböztetést.
- **Típusregiszter:** egy közös leírófájl, amelyet a szerver és a szerkesztő is beolvas. Típusonként megadja
  az alaptípust (`base`), a felismerési szabályt (kiterjesztés, tartalom) és a képességek listáját.
- **Alkategória:** új sor a regiszterben `base` megadásával; az alaptípus képességeit örökli, felülírhatja vagy bővítheti.
- **Képesség (trait):** újrahasznosítható tulajdonságcsoport. Egyszerre adja a mezőket, a viselkedést és a
  tulajdonságpanel egy elemét. A panel a típus képességeiből áll össze, nem típusonként kézzel.
- **Többes kijelölés:** a panel a kijelölt objektumok közös képességeit mutatja, a módosítás mindegyikre érvényes.
- **CSS:** `node is-<type>`, vonal: `wire`. A konténer állapot: `has-children`.

## Fő típusok

| Kategória | `type` | Megjegyzés |
|---|---|---|
| Alap doboz / konténer | `box` | Konténer = doboz, amibe már húztak valamit. Konténer marad úgy, mint most: csak `box` lehet az. |
| Szöveges fájl | `text` | Minden nem bináris fájl (.txt, .md, .json, .css, .js, .mjs, .swift, …) egy viselkedést követ. |
| Táblázat | `table` | `base: text`, `.tntable` fájl; képletek, formázás, CSV-import. Terv és állapot: `docs/EXCEL.md`. |
| Kép | `image` | |
| Dokumentum | `document` | Minden más (bináris) fájl: .pdf, .doc, .docx, .zip, … |
| Hang | `audio` | Minden hangfájl egy viselkedést követ; a lejátszó egyelőre csak mp3-at játszik. |
| Hivatkozás | – | Nem külön típus: linkes `box` (`link` képesség). Fajtái: külső cím, munkalap, .web mappa. |
| .web mappa | – | Nem külön típus: .web mappára mutató linkes `box`. |
| Vonal | `wire` | |
| Csomópont | `junction` | |
| Munkalap (vászon) | `canvas` | Saját tulajdonságpanel: cím, leírás, téma, háttér, előnézeti kép. |

## Eddigi döntések

1. **Beillesztett szöveg:** sima `box` jön létre, a vágólap tartalma a Text részébe kerül.
2. **Szöveges fájlok:** minden plain text fájl `text`, kiterjesztéstől függetlenül.
3. **Hang:** minden hangfájl `audio`; amelyikhez még nincs lejátszó, az is ebbe a típusba tartozik.
4. **.thnode import:** későbbi feladat (TODO.md).
5. **Link:** nincs külön `link` / `sheet` típus. A link képesség (`link`), amelyet a `box` és az `image` kaphat meg.
   Fajtái: külső cím, munkalap, .web mappa; a doboz kinézete a link fajtájától függ.
   A `web` típus is beolvad ebbe: .web mappára mutató linkes `box`.
6. **Konténer:** marad a mostani működés.
7. **Munkalap panel:** fő kategória.
8. **Többes kijelölés:** közös képességek egyszerre szerkeszthetők (ezért kellenek a képességek).
9. **Vonal szabad végponttal:** most nem foglalkozunk vele.

## Képességek (tervezet)

A mai tulajdonságpanelekből kigyűjtve. Minden képesség egy panelelem és a hozzá tartozó mezők/viselkedés.

| Képesség | Panel / viselkedés |
|---|---|
| `text` | Text (markdown) szerkesztő, tipográfia, igazítás, sorkizárás, összecsukás (lásd: Text képesség). A külön Cím megszűnt. |
| `shape` | Forma |
| `surface` | Háttér mód (Free / Üres / Áttetsző) és háttérszín (a paletta 0. színe a vászonszín: a rács nem látszik át, textúrás vásznon átlátszó) |
| `elevation` | Kiemelés (árnyék) |
| `motion` | Animáció |
| `size` | Méretezés (dobozon fogók, csomópontnál átmérő) |
| `link` | Hivatkozás: fajta (külső cím / munkalap / .web mappa), cél, megnyitás; hivatkozásjel és fajtafüggő megjelenés a dobozon |
| `children` | Konténer: tartalmazhat dobozt, tartalom rögzítése |
| `file` | Fájlnév szerkesztése, megjelenítése, letöltés |
| `comment` | Megjegyzés: **mindig a doboz alján**, minden típusnál egyformán. Markdown; panelen balra / középre / jobbra igazítás és elrejtés gomb |
| `alpha` | Kép átlátszósága és háttérszíne |
| `player` | Lejátszó |
| `stroke` | Vonal: szín, vastagság, típus, megjelenés, animáció, nyilak, felirat |

Mai állapot típusonként (az átalakítás előtt, összehasonlításhoz):

| Típus | Képességek most |
|---|---|
| `box` | title (teljes), body, shape, surface, elevation, motion, size, link, children |
| `text` | title (egyszerű + elrejtés), file, surface, elevation, size, body (csak sorkizárás), source |
| `image` | alpha, title, file, surface, elevation, size, body („Megjegyzés”) |
| `document` | title, file, surface, elevation, size |
| `audio` | title, file, surface, elevation, size, player, body („Megjegyzés”) |
| `web` | title, webFolder, surface, elevation, size |
| `junction` | title (címke), size, szín |
| `wire` | stroke |

**Link szabály (döntés):** a `link` képességet a `box` és az `image` kaphatja meg (ahol a kattintásnak nincs saját feladata).

## Típusonkénti meghatározás

Sorban végigmegyünk: viselkedés, tulajdonságpanel, megjelenés a vásznon.

### box

Alap doboz; ha belehúznak valamit, konténer lesz (`has-children`).

**Képességek:** `text`, `shape`, `motion`, `surface`, `elevation`, `size`, `children`, `link`.

**Viselkedés (mai állapot, megtartásra javasolva):**
- Létrehozás: dupla kattintás üres vásznon, jobb kattintás → Objektum létrehozása, szöveg beillesztése.
  Alapértékek: 176×80, `rounded`, félkövér 16-os cím középen, cím: „Új ötlet”.
- Kijelölés kattintással, tulajdonságok dupla kattintással, szövegszerkesztés Alt+dupla kattintással.
- Mozgatás húzással, klónozás Alt+húzással, összekötés Ctrl+húzással, méretezés Alt+sarokhúzással.
- Cím és szöveg igazítása Ctrl+Alt+húzással a kilenc hely egyikére.
- Konténer: az a doboz, amiben éppen van másik objektum; a belehúzott doboz a gyereke lesz, együtt mozognak. A kiürült konténer újra sima doboz. „Tartalom rögzítése” zárja a tartalmát. „Szöveg körbefuttatása a tartalom körül” (`textFlow`; alapból be, `false` kapcsolja ki): a konténer saját szövege kikerüli a benne lévő dobozokat.
  Kiemelt (`elevation`) doboz nem lehet gyerek. Csak `box` lehet konténer.
- Beillesztett szöveg: új `box`, a szöveg a Text részbe kerül. Kijelölt `box` esetén hozzáfűződik a szövegéhez.

**Tulajdonságpanel (sorrend):** Cím + tipográfia → Doboz (forma, animáció, háttér, kiemelés, rögzítés) → Text + tipográfia → Link.

**Megjelenés a vásznon:** 8 forma (rounded, rectangle, ellipse, diamond, triangle, pentagon, hexagon, parallelogram);
háttér: kitöltött / Free / Üres / Áttetsző, vászonszín a paletta 0. színével; automatikus keretszín; árnyék kiemeléskor; animáció
(pulse, blink, rock, hop); cím lehet a dobozon kívül; szöveg elrejthető vagy automatikusan méretezett;
linkes doboznál szaggatott keret és hivatkozásjel (új helye: alul középen).
Olvasható szöveg: ha a beállított szövegszín kontrasztja a felülettel (kitöltött, áttetsző vagy vászonszínű háttér; a
kitöltés a vászon fölött, a téma átlátszatlanságával) 3 alatt van, kirajzoláskor a téma tintájának jobban olvasható
változata jön (`Rendering.swift labelInk`, `editor.js boxInk`); a tárolt szín nem változik.

**Döntések:**
- **A Cím megszűnik**, csak a Text marad (lásd: Text képesség). A külön cím egysoros, nem formázható, és a kettő együtt nehézkes.
- **Link hozzáadása:** a link mező csak akkor látszik a panelen, ha már van link. A linket kapható objektum
  a helyi menüből vagy a panel felirat nélküli Link gombjával kapja meg. Hozzáadáskor rögtön meg kell
  adni a link fajtáját: másik munkalap, .web mappa vagy külső cím.

**Nyitott:** konténernek legyen-e saját megjelenése.

## Text képesség (tervezet)

**Mai állapot:** két külön rész.
- Cím (`title`): egysoros sima szöveg, saját méret, szín, félkövér/dőlt/aláhúzott, igazítás, AutoSize, „dobozon kívül”.
- Text (`text` + `textStyle`): markdown, a szerver (cmark-gfm) blokkokra bontja: bekezdés, címsor (egyféle méret),
  idézet, kódblokk; a listák sima sorokká lapulnak. Félkövér, dőlt, kód, link a sorokon belül.
- A vásznon SVG-szövegként, saját tördeléssel rajzolódik ki, a szerverben (Swift) és a szerkesztőben (JS) is.
- A címet használja még: gyorskereső, akadálymentes felirat, tooltip, többes kijelölés, fájltípusoknál a fájlnév.

**Javaslat:**
1. **Egy mező:** csak `text` (markdown). A címet egy `#` címsor váltja ki.
2. **Név:** ahol egy rövid név kell (kereső, akadálymentes felirat, listák), ott a szöveg első sora,
   formázójelek nélkül, számított érték, nem tárolt. Fájltípusoknál a fájlnév.
3. **Stílus:** egy közös alapstílus a dobozra (méret, szín, igazítás, függőleges igazítás, sorkizárás, AutoSize).
   A kiemelést a markdown adja: `#`, `##`, `###` címsor az alapméret 1,6×, 1,3×, 1,15×-ese, félkövér;
   **félkövér**, *dőlt*, `kód`, lista, idézet.
   **Döntés:** a félkövér, dőlt, aláhúzott gomb megmarad, és az egész szövegre hat a markdown fölött.
   A kettő összeadódik: ami a markdownban félkövér, az bekapcsolt félkövér gombnál még nagyobb és vastagabb.

   | | Félkövér gomb ki | Félkövér gomb be |
   |---|---|---|
   | Sima szöveg | 400 | 650 |
   | Markdown félkövér | 700 | 900, 1,1× méret |
   | Címsor | 700, címsorméret | 900, címsorméret × 1,1 |

   - Dőlt gomb: az egész szöveg dőlt; a markdownban dőlt rész ilyenkor egyenes lesz (kiválik).
   - Aláhúzott gomb: az egész szöveg aláhúzott; a link eleve aláhúzott.
4. **Döntés:** a „dobozon kívül” beállítás megszűnik, a szöveg mindig a dobozon belül van (9 igazítási hely marad).
5. **Elrejtés:** a mostani „•••” helyett összecsukás: csak az első sor látszik, a többi tooltipben.
6. **Szerkesztés:** a vásznon dupla kattintásra helyben, a panelen szövegmezőben; a panelen formázógombok
   (címsor, félkövér, dőlt, lista, kód), amelyek markdown-jeleket szúrnak be.
7. **Döntés – megjelenítés:** marad az SVG-szöveg (szerveres megtekintő, SVG-export, előnézeti képek miatt),
   és bővül: több címsorszint, listajelek, behúzás. A konténerkezelésnél erre még visszatérünk.
8. **Döntés – panel:** Text csoport: szövegmező fölötte formázógombokkal (címsor, félkövér, dőlt, lista, kód, link);
   stílussor (méret, AutoSize, szín, félkövér/dőlt/aláhúzott, sorkizárás, összecsukás „…” ikonnal); 9 helyes igazítórács.
   A `box` panel: Text → Doboz (forma, animáció, háttér, kiemelés, rögzítés) → Link (csak ha van).
9. **Új doboz:** üres szöveggel jön létre, és azonnal helyben szerkeszthető. Beillesztéskor a vágólap tartalma lesz a szöveg.

### text

Importált szöveges fájl: minden nem bináris fájl (UTF-8, NUL bájt nélkül), kiterjesztéstől függetlenül.

**Mai állapot:**
- Csak .txt, .md, .json lesz szövegdoboz; a többi szöveges fájl (.css, .js, .swift…) és a 100 KB fölötti fájl dokumentum lesz.
- A vásznon HTML-ként jelenik meg (`foreignObject`): lap (a hajtott sarok jele 2026-11-25-én megszűnt), fölötte a cím, alatta a fájlnév.
  .md formázva, .txt és .json egyszerű, nem tördelt (`pre`) szövegként; .json importkor formázva.
  Kijelölve a lapon belül görgethető.
- A szöveg másolata a munkalapon is tárolódik (`text`); a panel Mentés / Újratöltés gombja írja vissza a fájlba, illetve olvassa be onnan.
- Panel: Cím (+ elrejtés), Fájlnév, Megjelenés (háttér, kiemelés, fájlnév mutatása), Szöveg (szerkesztő, sorkizárás, mentés, újratöltés).

**Kódszínezés és dobozon szerkesztés (2026-11-25):**
- A `code` doboz sorai tördelődnek. A `.json`, `.css`, `.js` / `.mjs` / `.cjs`, `.swift`, `.html` / `.htm` színezve jelenik meg; a színezést a szerver készíti
  (`Sources/ThinkHighlight`, saját könnyű elemző, nyelvenként egy fájl), a kliens a kész HTML-t mutatja
  (`<span class="hl-…">`, színek: `app.css`). A szerkesztő a `GET /api/attachment/…&highlight=<kiterjesztés>` címről kéri.
- Dobozon szerkesztés: a szövegfájl (`.txt`, `.md`, kód) a vásznon szerkeszthető, a panelen nincs szövegmező.
  Dupla kattintás nyitja (Alt-tal a panel), Esc vagy a doboz elengedése zárja. Színezhető kódfájl szerkesztés közben
  is színes, egy rétegben: maga a színezett szöveg szerkeszthető (nincs fölötte szövegmező). A színezést ilyenkor a böngésző végzi (`Public/highlight`, a Swift-modul pontos mása; egyezésüket a
  `Tests/Fixtures/highlight.json` őrzi), kilépéskor a szerver színezése váltja fel. A `.txt` és a `.md` ugyanebben az egyrétegű
  szerkesztőben szerkeszthető (színezés nélkül; a `.md` közben nyers szövegként látszik); külön szövegmező nincs.
  Nagy fájl (256 KB fölött) továbbra is külön ablakban szerkeszthető.

**Döntések:**
1. **Felismerés tartalom alapján:** ami UTF-8 és nincs benne NUL bájt, az `text`. A kiterjesztés csak a megjelenítést választja ki.
2. **Megjelenítés:** marad a HTML-es lap. Alkategóriák már az első változatban:
   - `text` (alap): egyszerű szöveg; `.md` formázva jelenik meg.
   - `code` (`base: text`): `.json`, `.js`, `.mjs`, `.swift`, `.css` … egyenközű betű, nem tördel, vízszintesen görgethető;
     `.json` importkor formázva. Szintaxiskiemelés később.
   - `csv` (`base: text`): táblázatként jelenik meg (olvasó nézetben legfeljebb 1000 sor × 60 oszlop). „Tartalom a dobozhoz”
     (`contentFit`, mint a táblázatnál): a szerkesztő táblázatdokumentuma arányosan a dobozhoz skálázva (`editor.js fitDocument`,
     `Rendering.swift csvGridDocument`).
3. **Fejléc és megjegyzés:** felül a fájlnév (elrejthető), nincs külön cím. Alul megjegyzés: markdown,
   balra / középre / jobbra igazítható, elrejthető.
4. **Egy forrás, mentés:** egy dobozt egyszerre csak egy felhasználó foghat és szerkeszthet (a kijelölés zárol),
   így nincs szerkesztési ütközés. A szöveg a fájlban van, a panelen szerkesztve automatikusan oda mentődik;
   a Mentés / Újratöltés gomb megszűnik. A munkalapon nincs másolat: gépelés közben néhány másodpercenként
   automatikus mentés, a szerver értesíti a többieket, náluk a doboz újratölti a fájlt.
5. **Méret:** nincs 100 KB-os határ; a lap mindig görgethető. Nagy fájlnál (256 KB fölött, `largeTextLimit`) a vásznon
   az eleje látszik, az oldalsávon szövegmező helyett „Szerkesztés külön ablakban” gomb van. A külön ablak
   (`/edit/<lap>?text=<doboz>`, `text-editor.js`) a teljes fájlt szerkeszti; mentés gombbal, Ctrl/Cmd+S-sel és gépelés
   után 2,5 mp-cel magától (`PUT /api/text-file/<lap>?id=<doboz>&rev=N`). A szerver a doboz `file.rev` számlálóját
   ellenőrzi: ha közben más mentett, nem írja felül (409). A fájl felső határa változatlanul 12 MiB.
6. **Képességek:** `text` (betűméret, szín, sorkizárás; a félkövér/dőlt/aláhúzott itt nem kell), `comment`, `file`, `surface`, `elevation`, `size`. Link: nem (a kattintás görget).
7. **Panel:** Fájlnév (+ mutatás) → Text → Megjegyzés → Megjelenés (háttér, kiemelés).
8. **Színek és keret:** a tartalom szövegszíne a doboz szövegszíne (`textColor`, alapból a paletta 1-es színe), a háttér a doboz
   kitöltése (`fill`, alapból a paletta 2-es színe), így a világos/sötét mód követi a témát. A Megjelenés panelen a háttérmódok
   (Free, Üres, Áttetsző; vászonszín: a paletta 0. színe) mellett külön kapcsolható a keret (`frame: false` = keret nélkül), bármelyik móddal együtt.
   A táblázat (`table`) szövegszíne is itt állítható; a táblázat szerkesztési módja (képletsor, fejlécek, kijelölés) a doboz
   hátteréből és szövegszínéből kevert színeket használ (`--tn-paper`, `Public/app.css`).

### chart (grafikon)

Önálló objektum, saját fájl nélkül: az adatát a vonallal bekötött táblázat (`table`) vagy CSV (`csv`) fájlja adja
(`Public/chart.js`, D3: `Public/lib/d3-chart.js`). Bekötött táblázat nélkül üres.

- **Mező:** `chart: {kind, labels, values, header}` – `kind`: `bar` / `line` / `pie` / `scatter`; `labels`: a kategóriák
  (pontdiagramnál az x értékek) oszlopa, hiányzik = automatikus, `-1` = sorszám; `values`: értékoszlopok, hiányzik = minden
  számoszlop (legfeljebb 8, pont: 3, kör: 1); `header: false` = az első sor is adat. A mező csak `chart` típuson érvényes.
- **Képességek:** `chart`, `comment`, `surface`, `elevation`, `size`. Táblázat-beállítása, fájlneve nincs.
- **Létrehozás:** a táblázat / CSV paneljén vagy helyi menüjében „Grafikon létrehozása”: új grafikon a táblázat mellett, bekötve.
- **data-connection (adatvonal):** táblázatot (vagy CSV-t) és grafikont összekötő vonal; mindig minden objektum mögött van (a többi vonal minden doboz fölött, a Kiemelt objektumok alatt fut). Nem tárolt tulajdonság és nem választható: a két
  végpont típusa adja (`isDataLink`: geometry.js, Rendering.swift). Nyíl helyett mindkét végén félkorong áll, a lapos oldala a
  doboz oldalára simul (`plugTransform`); a nyílkapcsolók a panelen nem látszanak. A vonal egyébként közönséges: törölhető,
  átköthető, a színe, vastagsága, típusa állítható.
  Mindig minden objektum mögött van (legalsó réteg), és a két doboz egymás felé eső oldalának közepéhez csatlakozik
  (`sideMidpoint`).
- **Egy táblázat:** egy grafikonba egy táblázat köthető; újabb bekötésekor a szerkesztő a korábbi adatvonalat törli, és az
  oszlopkiosztás automatikusra áll (`tidyChartLinks`). Más dobozból akárhány közönséges vonal mutathat a grafikonra; egy
  táblázatból több grafikon is táplálkozhat.
- **Törlés:** a grafikon törlése a táblázatot nem érinti; a táblázat törlése után a grafikon megmarad, üresen.
- **Frissülés:** a grafikon a forrás fájljának legfrissebb változatát olvassa (`latestRev`), szerkesztés közben a még el nem
  mentett állapotot is.
- **Megtekintő:** a szerver helyőrzőt ír (`.node-chart`, `data-chart`, `data-chart-source`), a `viewer.js` tölti be a modult
  és a fájlt, és rajzol. Szkript nélkül (SVG-export, előnézeti kép) a doboz üres.
- **Színek:** rögzített sorrendű kategóriaszínek, világos és sötét felületre külön lépcsővel; a szöveg a doboz szövegszíne.

**Táblázat és CSV doboza:** 5 px-es lekerekítésű téglalap (mint a kép és az előnézet); a grafikoné a szokásos.

### Név (doboz)

Minden sima doboznak (`box`) lehet neve: `name` mező (Swiftben `Idea.boxName`), legfeljebb 255 karakter, egy bekezdés
(sortörés nélkül), sima szöveg (nem markdown).

- **Megjelenés:** a doboz fölött, mint a fájlnév: félkövér, 13 px, a doboz szélességére (8 képpont ráhagyással) tördelve,
  a doboz szövegének igazításával (balra / középre / jobbra; sorkizárás nincs). A sorok magassága 17, a doboztól 4 képpont.
  SVG-szöveg (`text.node-name`), nem HTML: sok dobozon is olcsó. A tördelés a szerkesztőben (geometry.js `nameLayout`) és a
  szerveren (Rendering.swift `nameLayout`) pontosan egyezik; közös teszt: `Tests/Fixtures/box-names.json`
  (`Tests/Editor/box-names.mjs`, Swift `boxNamesMatchSharedFixtures`). Az export határoló doboza a nevet is tartalmazza.
- **Szerkesztés:** Shift + dupla kattintás a dobozon, vagy a gyors eszközök „Név szerkesztése” gombja (`box-name`). A
  felirat helyén szerkeszthető, tördelődő mező (egy réteg); Enter / a mező elhagyása ment, Esc elvet.
- **Rövid név:** ha van név, a kereső és az akadálymentes felirat azt mutatja (`nodeName`, `Idea.name`).
- **Jel a név előtt (`nameNote`):** halványan, legfeljebb 24 karakter; a struktúra-konténer adja (JSON: `Int` / `Double` /
  `Bool`, Swift: `let` / `var` / `ƒ`). Név nélkül (tömbelem) a jel egymagában áll. Kézzel nem szerkeszthető.
- **Számított érték (`computed`):** szaggatott keret (Swift-forrás számított változója).
- Előnézetes (linkes) dobozon a név tárolható, de nem látszik (ott a link felirata áll a doboz fölött).

### Struktúra-konténer (doboz-konténer forrásfájlból: .json kétirányú, .swift csak olvasás)

Sima doboz (`box`), amely a vonallal bekötött forrásfájllal (`.json`) kétirányúan össze van kötve: a JSON szerkezete
valódi dobozokként jelenik meg benne, és a dobozok szerkesztése visszaíródik a fájlba (`Public/structure-boxes.js`, teszt:
`Tests/Editor/structure-boxes.mjs`). A táblázat–grafikon párosítás mintájára működik.

- **Leképezés (mindkét irányban ugyanaz):** a doboz **neve a kulcs, a szövege az érték**. Konténer: `list: false` =
  objektum `{}` (a gyermekek neve a kulcs), `list: true` = tömb `[]` (a gyermekek neve csak felirat, pl. az elem `name`
  mezője; nem exportálódik). A jelző a név után halványan látszik (`{}` / `[]`), a gyors eszközökben váltható
  (`structure-list`). Érték: `3` szám, `true` / `false`, `null`, idézőjelben (`"3"`) mindig szöveg, minden más szöveg; a
  szöveg markdown-jelei generáláskor semlegesítve (visszaper), visszafelé a visszaperek lekerülnek. Sorrend: a gyermekek
  tárolt sorrendje a lapon. Jelző nélküli (kézzel épített) konténer: ha minden gyermeknek egyedi neve van, objektum,
  egyébként tömb. Objektumban két azonos név: a második „név (2)” kulcsot kap.
- **Mezők:** a konténeren `structure: {digest, boxes}` – a forrás és a dobozokból írt JSON ujjlenyomata az utolsó
  szinkronkor (csak `box` típuson); a konténereken `list`.
- **JSON-típusjelek:** a nem szöveg értékek típusa automatikus: szám → `Int` (egész alak) vagy `Double` (tizedespont vagy
  kitevő: `39.12`, `1e3`), `true` / `false` → `Bool`; halvány jel a név előtt és típusszín. A számok a forrásbeli
  alakjukkal jelennek meg és íródnak vissza (`39.10` marad, a 2^53 fölötti egész pontos; a böngésző JSON.parse
  forrásszöveg-hozzáférésével, ahol nincs, a számból). Az idézőjeles szám szöveg, jel nélkül. Standard JSON-ban idézőjel
  nélkül csak szám, `true`, `false`, `null`, objektum és tömb állhat.
- **Típusszavak:** ha az érték `Int` (és `Int8`…`Int64`, `UInt`…`UInt64`), `Float` (`Float16`, `Float32`, `Float80`),
  `Double` (`Float64`, `CGFloat`, `Decimal`), `Bool`, `String` (`Character`, `Substring`), `Date`, `URL`, `UUID`, illetve
  `T?`, `[T]`, `[K: V]`, a doboz kitöltése az alaptípus (családja) színe (`Public/structure-types.json`, a paletta 0–15 sorszámai, minden témában
  megvannak; a szöveg kontrasztját a rajzolás javítja). A szín nem kerül a JSON-ba; a kézzel állított szín felülírja.
  Az adatban véletlenül ilyen szövegű érték is típusszínt kap.
- **Létrehozás:** a `.json` fájl dobozán (gyors eszközök / helyi menü) „Doboz-konténer létrehozása”: új konténer a fájltól
  jobbra, az első olyan helyen, ahol a végső méretével nem takar más dobozt; neve a fájlnév; adatvonallal bekötve.
  Fordítva: bármely konténeren „Mentés .json fájlba” (`structure-save`): új `.json` fájl a projektben, a konténer mellett,
  kétirányúan bekötve; a konténerek `list` jelzője ekkor rögzül.
- **Adatvonal:** a forrás és a konténer közti vonal adatvonal (félkorong, nyíl nélkül; `isDataLink`, `isStructureFileNode` /
  `Idea.isStructureSource`). Egy konténerbe egy forrás köthető (`tidyChartLinks`).
- **Szinkron, csak jóváhagyáskor (gépelés közben nem):**
  - forrás → dobozok: a kódszerkesztő elhagyásakor (Escape, kattintás máshova), illetve ha a fájlt más mentette
    (.json és .swift);
  - dobozok → forrás: egy doboz szövegének / nevének jóváhagyásakor, doboz hozzáadásakor / törlésekor / kihúzásakor, a
    `list` váltásakor; húzás és szerkesztés közben vár. A dobozokból írt JSON a forrás behúzását követi; utána az
    elrendezés a visszaírt forrásból frissül (a szöveg normalizálódik, pl. `3 ` → `3`).
  - A saját írás ujjlenyomata a konténerbe kerül, így nincs oda-vissza ping-pong. Ha mindkét oldal változott, a forrás nyer.
  - Hibás forrásnál (pl. félkész JSON) a dobozok maradnak; a hiba a konténer „Újragenerálás” gombján látszik.
- **Párosítás és megőrzés:** újrageneráláskor a meglévő dobozok a szülőjük és a kulcsuk szerint kapják meg az új tartalmat
  (objektumban a név; tömbben az elem neve vagy egyszerű értéke, ha egyedi, egyébként a helye; a párosítatlan maradékok
  sorrendben, így az átnevezett kulcs is megtartja a dobozát). A megmaradó doboz **azonosítója, vonalai, kézzel állított
  színe és betűbeállításai nem változnak**; csak a ténylegesen változott mezők íródnak (a többi doboz nem rajzolódik újra).
  Új doboz azonosítója a konténerből és az útvonalból képzett hash. A helyet és a méretet mindig az elrendezés adja (a
  nevek helyével együtt). A struktúrába tett más objektum (kép, fájl) érintetlen marad, és nem kerül a JSON-ba.
- **Korlátok:** 600 doboz (fölötte csak az első elemek látszanak, és nincs visszaírás – adatvesztés lenne), 12 szint,
  255 karakteres kulcs (sortörés nélkül), 100 000 karakteres érték; túllépésnél hibaüzenet, a dobozok maradnak.
- **Figyelem:** a konténerből kihúzott doboz a JSON-ból is kikerül (kétirányú kapcsolat); visszavonással (Ctrl+Z) a doboz
  visszakerül, és a JSON is.
- **Gyors eszközök:** Újragenerálás a forrásból; Leválasztás a forrásról (a dobozok maradnak); Tömb / objektum; Mentés .json
  fájlba (jelző nélküli konténeren).
- **Megtekintő, export:** a dobozok közönséges dobozok, a nevük a szerver rajzán is látszik.
- **Swift-forrás (`.swift`, csak olvasás):** ha a fájlban egy felső szintű struct van, maga a konténer az a struct (neve
  a struct neve, generikusnál `Doboz<T>`; szövege az átvett protokollok listája, dőlten); több felső szintű structnál
  mindegyik külön konténer a fájl nevét viselő konténerben. A beágyazott struct (és a bővítményben, `extension A { struct
  B }`, megadott) a szülője konténerében áll, a tagok között, a forrás sorrendjében.
  - Tulajdonság → doboz: név = a tulajdonság neve, előtte halványan `let` / `var`; szöveg = „Típus = alapérték” (típus
    nélküli alapértéknél a típus a literálból: `Int`, `Double`, `String`, `Bool`, `Típus(…)`).
  - Számított tulajdonság (`var x: T { … }`, `get` / `set` is) → doboz, jel `ƒ`, szaggatott keret, szöveg =
    „Típus = képlet” (egyetlen `return` kifejezésnél csak a kifejezés, több utasításnál a törzs soronként); az érték nincs
    kiszámolva. Függvény (`func`, `mutating` is) → doboz, jel `func`, szaggatott keret, szöveg az aláírás (`(paraméterek) -> Típus`).
    Minden tag lekerekített doboz (a 2026-11-27-i köztes változat rombusza betöltéskor dobozzá válik).
  - Nyilak (halvány, pontozott, kezelt vonal): a képletben / függvénytörzsben használt testvér-tagtól **a számított
    tulajdonság, illetve a függvény felé**; a struct típusú tulajdonságtól a struct konténeréhez. Az azonosítójuk a
    konténerből és a két végpontból képzett hash (`structureEdgeId`); ami már nem következik a forrásból, törlődik.
  - Nem jelenik meg: `static` / `class` tag, `init`, figyelő (`didSet` / `willSet`), más típus (class / enum / protocol)
    tagjai. Kommentet, szövegliterált (interpolációval, többsoros, nyers) kezel, de nem teljes Swift-elemző. A dobozok
    szerkesztése nem írja át a kódot (a forrás következő változásakor felülíródik).
- **Üres érték (nil / null):** JSON `null`, Swift `= nil`, illetve alapérték nélküli opcionális `var` (kezdetben nil):
  a doboz csak keretet kap (`backgroundMode: empty`, a keret a típus színe), a szövege dőlt.
- **Automatikus megjelenés és kézi beállítás:** a kitöltés (típusszín), az alak (lekerekített doboz), az üres háttér és a
  dőlt betű automatikus; ha a dobozon kézzel más áll (eltér a korábbi automatikustól), az megmarad. Az ujjlenyomat
  verziója (`textDigest`, „structure:10”) a generálás szabályainak változásakor nő: a meglévő konténerek betöltéskor
  újraépülnek (ha nem foglalja más a konténert vagy egy dobozát).
- **Elrendezés:**
  - objektum, struct: az elemek egymás alatt, a forrás (kód) sorrendjében, akkor is, ha több hely van (a kézzel
    szélesebbre húzott konténerben a fölösleg üres marad); új oszlop csak akkor, ha egy oszlop 3600 képpontnál magasabb
    lenne (a doboz legfeljebb 4096);
  - JSON-tömb (`[]`): rács, balról jobbra, majd soronként lefelé (mint az írott szöveg); az oszlopok száma, amelynél a
    tartalom aránya a legközelebb esik az 1:1-hez; egy sorban a dobozok teteje egy vonalban;
  - Swift-struct számított tulajdonsággal / függvénnyel: a tárolt tagok és a beágyazott structok bal oldalt egymás alatt,
    a számított tulajdonságok és a függvények jobb oldalt, ahol lehet, a legfelső használt tag magasságában (egymást nem
    fedve, a forrás sorrendjében);
  - az egyszerű dobozok oszloponként egyforma szélesek; a hely és a méret mindig az elrendezésből adódik.
- **Összecsukás (`collapsed`):** a struktúrán belüli konténer (vagy maga a struktúra-konténer) a gyors eszközökkel
  (`structure-collapse`) összecsukható: csak a neve és egy összegzés látszik („▸ 12 elem”, objektumnál „mező”,
  Swift-structnál „tag” és a protokollok), a konténer kicsi, a tartalma nem rajzolódik (szerkesztő: `hiddenNodes`;
  szerver: `collapsedView`), a rejtett dobozokra mutató vonalak a konténerhez futnak (a modellben változatlanok). Az adat
  nem változik; kibontáskor az elrendezés visszaáll.
- **Rátakarás jelzése:** csak az élő adatkapcsolatú (a forrásfájlhoz bekötött) struktúra-konténeren: ha más (nem a saját
  tartalmába, nem az őseibe tartozó) dobozra lóg, a jobb felső sarkában figyelmeztető jel áll (csak a szerkesztőben), a
  súgója a rálógó dobozok neve (`structureOverlaps`). Sima dobozon és konténeren nincs.
- **Formázás átméretezéssel (`layoutWidth`, `layoutHeight`):** amíg a forrással fennáll a kapcsolat, a struktúrán belüli
  konténer vagy doboz átméretezése után a mérete megmarad (`layoutWidth` 64–4096, `layoutHeight` 40–4096, csak dobozon;
  a nagyobbra húzott doboz a felesleges helyet is megtartja, nem vágódik vissza), és az elrendezés azonnal újraépül hozzá.
  Ha a konténer egyetlen eleme konténer (pl. `{"tagok": [...]}`), a belső (saját kézi méret nélkül) kitölti a külsőt, így
  a külső átméretezése a belsőt is újrarendezi: a tömb annyi oszlopba rendez (soronként balról jobbra), amennyi elfér; az
  objektum / struct elemei egymás alatt maradnak, a kód sorrendjében (a fölösleg üres); ha a tartalom nem fér el, a
  konténer nagyobb lesz. Az egyszerű doboz a megadott szélességet
  tartja, a szövege ahhoz tördel. A forrás következő változásakor is megmarad. „Automatikus elrendezés” (gyors eszköz a
  struktúra-konténeren, `structure-auto`): a kézi méretek törlése a konténerben és a dobozain.
- **Bővítés:** a forrásformátum a `formats` jegyzékben bővíthető (kiterjesztés → `parse` + `write`, vagy `tree`); a
  kiterjesztés a `geometry.js` `structureSourcePattern` és a `Model.swift` `isStructureSource` listájába is kell.
- **Húzás:** a konténer a tartalmával közös eltolással mozog (docs/PERF.md „Konténer húzása”).

### image

Importált kép: .png, .jpg, .gif, .webp, .svg (legfeljebb 12 MiB, tartalom-ellenőrzéssel).

**Mai állapot:**
- Importkor a doboz a kép arányához igazodik (a hosszabbik oldal 320). Átméretezéskor az arány nem kötött,
  a kép a dobozon belül arányosan illeszkedik (`contain`), így üres sáv maradhat.
- Fölötte a cím (alapból üres), alatta a fájlnév (alapból rejtett). A Megjegyzés nem látszik a vásznon, csak tooltipben.
- Átlátszóság: alfa-csatorna be/ki, a kép mögötti háttérszín (csak átlátszó képnél).
- Ctrl+C PNG-ként másolja a képet. A fájlnév átnevezhető.
- Panel: Átlátszóság → Cím → Fájlnév → Megjelenés (háttér, kiemelés, fájlnév mutatása) → Megjegyzés.

**Döntések (elfogadva):**
1. **Fejléc és megjegyzés, mint a `text`-nél:** felül a fájlnév (elrejthető, alapból rejtett), alul `comment`
   (markdown, igazítás, elrejtés). A vásznon látszik, nem csak tooltipben.
2. **Arány:** átméretezéskor a doboz tartja a kép arányát; Shift-tel szabad.
3. **Link:** kaphat linket (`link` képesség); ilyenkor a kattintás a linket nyitja, a hivatkozásjel a sarokban.
4. **Átlátszóság:** marad (alfa be/ki, háttérszín).
5. **Képességek:** `alpha`, `file`, `comment`, `surface`, `elevation`, `size`, `link`.
6. **Panel:** Fájlnév (+ mutatás) → Megjegyzés → Átlátszóság → Megjelenés (háttér, kiemelés) → Link (csak ha van).

### document

Minden más (bináris) fájl: .pdf, .doc, .docx, .xlsx, .pptx, .zip, …

**Mai állapot:**
- A doboz a címet és egy letöltés gombot mutat (csomag ikon + fájlnév). Letöltés a gombbal, a megtekintőben dupla kattintással is.
- Panel: Cím → Fájlnév → Megjelenés (háttér, kiemelés, fájlnév mutatása). Szöveg nincs.

**Döntések (elfogadva):**
1. **Felépítés, mint a többi fájlnál:** felül a fájlnév (elrejthető), középen a fájltípus ikonja
   (pdf, szöveg, táblázat, bemutató, tömörített, egyéb) a kiterjesztéssel, alul `comment`.
2. **Letöltés:** a dobozon a letöltés gomb; dupla kattintás a szerkesztőben a panelt nyitja (mint mindenhol),
   a megtekintőben letölt.
3. **Előnézet:** később alkategóriaként (pl. `pdf`: első oldal képe). Most nem.
4. **Link:** nem (a doboz saját feladata a letöltés).
5. **Képességek:** `file`, `comment`, `surface`, `elevation`, `size`.
6. **Panel:** Fájlnév (+ mutatás) → Megjegyzés → Megjelenés (háttér, kiemelés).

### audio

Minden hangfájl: .mp3, .wav, .ogg, .flac, .m4a, .aac, …

**Mai állapot:**
- Csak .mp3 lesz hangdoboz (tartalom-ellenőrzéssel); a .wav, .ogg, .flac dokumentumként jön be.
- A dobozon: cím, lejátszó (lejátszás/szünet gomb, csúszka), alatta a Megjegyzés kis betűvel, letöltés gomb.
- Panel: Cím → Fájlnév → Megjelenés (háttér, kiemelés, fájlnév mutatása) → Megjegyzés.

**Döntések (elfogadva):**
1. **Felismerés:** minden hangformátum `audio` (fejléc-ellenőrzéssel).
2. **Lejátszó:** amit a böngésző le tud játszani (mp3, wav, ogg, flac, m4a/aac a legtöbb böngészőben), azt lejátssza:
   lejátszás/szünet, csúszka, eltelt / teljes idő. Amit nem, annál „A böngésző nem játssza le” felirat, és csak letöltés.
3. **Felépítés, mint a többi fájlnál:** felül a fájlnév (elrejthető), középen a lejátszó, alul `comment`; letöltés gomb.
4. **Egyszerre egy:** ha elindul egy hang, a többi megáll.
5. **Link:** nem.
6. **Képességek:** `player`, `file`, `comment`, `surface`, `elevation`, `size`.
7. **Panel:** Fájlnév (+ mutatás) → Megjegyzés → Megjelenés (háttér, kiemelés).

### link (képesség)

**Döntés:** nincs külön `link` típus; a hivatkozás a `box` (és az `image`) `link` képessége.

- **Hozzáadás:** helyi menüből vagy a panel felirat nélküli Link gombjával; ekkor kell választani a fajtát:
  külső cím, munkalap, .web mappa. A Link csoport csak akkor látszik a panelen, ha már van link.
- **Döntés – automatikus link:** ha a vágólapon http(s) cím van, vagy http(s) linket húznak a vászonra
  (drag & drop), linkes `box` jön létre a címmel mint külső linkkel. Kijelölt dobozba illesztve sem fűződik a szövegéhez.
- **Megjelenés külső címnél:** a webhely ikonja (favicon) és domainje, alatta a Text (ha üres, a cím maga).
  Később: a lap címe és előnézeti képe.
- **Megnyitás:** szerkesztőben a hivatkozásjelre kattintva vagy Ctrl+kattintással a dobozra, megtekintőben
  kattintásra. Külső cím új ablakban, munkalap ugyanabban (előtte ment). Dupla kattintás a szerkesztőben a panelt nyitja.
- **Döntés – hivatkozásjel:** a dobozon belül, alul középen jelenik meg (a mai jobb alsó sarok helyett).
  Képnél, ahol alul megjegyzés is lehet, a hivatkozásjel a megjegyzés fölött van.
- **Döntés – panel:** Link csoport: fajta, cél, megnyitás gomb; a csoport szélén [X] gomb, amely rákérdezés után törli a linket.

### .web mappa (link fajta)

**Döntés:** nincs külön `web` típus; a .web mappára mutató linkes `box` veszi át.

- **Mai állapot:** a `web` doboz a prezentáció előnézeti képét és a mappa útvonalát mutatja; panel: Cím,
  Prezentációs mappa (Kiválasztás gomb), Megjelenés. Kattintásra megnyílik a prezentáció.
- **Új működés:** linkes `box`, a link fajtája .web mappa. A dobozon a prezentáció előnézeti képe látszik,
  alatta a Text. Kattintásra (megtekintőben) / hivatkozásjelre (szerkesztőben) megnyílik a prezentáció.
- **Panel:** a Link csoportban a mappa kiválasztása (a mai Kiválasztás gomb).
- **Munkalap linknél ugyanígy:** a dobozon a céllap előnézeti képe (a szerver már készít ilyet) – javaslat.
- **Fájlhivatkozások a .web oldalból (2026-11-26):**
  - saját fájl: relatív cím (`css/main.css`, `kepek/a.png`);
  - a projektmappa többi fájlja: `../` hivatkozás, a lemez szerint (pl. `anyag/prezi.web` oldalából `../../kepek/logo.png`
    = `projekt/kepek/logo.png`). A projekt gyökere fölé nem lehet lépni; rejtett (`.`), `.thnode`, HTML fájl és
    szimbolikus link nem érhető el. Joga: a projekt olvasási joga (publikusnak jelölt .web zárt projektben a
    vendég csak a .web saját fájljait látja);
  - közös könyvtár: abszolút cím, `/common/...` (pl. `/common/icons/x.png`).
  - Megvalósítás: a szerver minden HTML oldalba `<base href="{.web cím}_tn-assets/{bérlet | public}/{mappa}/{név}.web/…">`
    elemet tesz; a `_tn-assets/…/` utáni rész a projekt gyökeréhez képesti útvonal, így a böngésző által
    feloldott `../` a projekten belül a jó fájlra mutat, a projekt fölé lépő cím pedig 404.
### wire

Vonal két doboz, csomópont vagy szabad pont között.

**Mai állapot:**
- Létrehozás: Ctrl+húzás dobozról (dobozra vagy üres helyre → szabad végpont). Végpont húzással áthelyezhető,
  jobb kattintással leválasztható / újraköthető. Ctrl+húzás a vonal belsejében csomópontot szúr be.
- Tulajdonságok: címke (felirat, 120 karakter), szín, alapvastagság, vonaltípus (egyenes, S-forma, villám,
  zigzag, íves, kötél), megjelenés (sima, vastag, szaggatott, pontozott), felirat a vonalban, animáció,
  nyíl az elején / végén.
- Panel: Vonal (címke, szín, vastagság) → Vonaltípus → Megjelenés → Végpontok.
- A munkalap panelén vonal-alapértékek állíthatók.
- Megjegyzés: a `zigzag` és a `lightning` felirata fel van cserélve („Villám” / „Zigzag”).

**Döntések (elfogadva):**
1. **Felirat = `text` képesség, egyszerűsítve:** a címke egysoros marad (markdown nélkül), mert a vonal mentén fut.
   Méret, félkövér, dőlt a vonal stílusából jön.
2. **Képességek:** `stroke` (szín, vastagság, típus, megjelenés, animáció), `arrows` (eleje / vége), `label`
   (felirat, felirat a vonalban), `endpoints` (leválasztás, újrakötés).
3. **Többes kijelölés:** több vonal kijelölésekor a `stroke` és az `arrows` egyszerre állítható – ez adja a fő hasznát.
4. **Panel:** marad a mai sorrend: Felirat → Vonal (szín, vastagság) → Vonaltípus → Megjelenés → Végpontok.
5. **Hiba javítása:** a „Villám” / „Zigzag” felirat cseréje.
6. **Végpontok csoport:** a két leválasztás ikon a panel jobb szélére igazodik.
### junction

Csomópont: vonalak találkozási pontja.

**Mai állapot:**
- Létrehozás: Ctrl+húzás a vonal belsejében (a vonal két szakaszra válik), vagy szabad végpont dobozra kötésekor.
- Kétágú csomópont törlésekor a két ág egyesül; ha egy csomópontnak 2-nél kevesebb vonala marad, automatikusan törlődik.
- Tulajdonságok: címke (a pont jobb oldalán), átmérő (4–128), szín. Az alakja (kör / négyzet) a téma beállítása, nem csomópontonként.
- Panel: Címke → Megjelenés (átmérő, szín).
- Konténerbe húzható, de nem lehet konténer.

**Döntések (elfogadva):**
1. **Képességek:** `label` (egysoros címke, mint a vonalnál), `size` (átmérő), szín, `endpoints` nélkül.
2. **Alak:** maradjon témabeállítás (egységes kinézet).
3. **Címke helye:** a címke a csomópont középpontja körül elforgatható (szög a panelen); külön helyválasztás nincs.
4. **Többes kijelölés:** átmérő és szín egyszerre állítható.
5. **Panel:** Címke (szöveg, elforgatás) → Megjelenés (átmérő, szín).

### canvas

A munkalap maga (jobb alsó nyíllal nyíló panel).

**Mai állapot:**
- Panel: Cím (egysoros, 120 karakter) → Szöveg (a munkalap leírása, a megtekintőben a vászon alatt) →
  Megjelenés (téma, paletta) → Előnézeti kép (alapból a munkalap SVG-je) → Háttér (szín) → Fájl feltöltése gomb.
- A rácsköz (`gridSpacing`) a modellben megvan, de a panelen nem állítható (alapból 32).

**Döntések (elfogadva):**
1. **Cím:** marad egysoros – ez a munkalap neve (fejléc, útvonal, listák), nem dobozszöveg.
2. **Leírás:** a `text` képesség markdown szerkesztője és formázógombjai, tipográfia nélkül.
3. **Megjelenés csoport:** téma, paletta, háttérszín együtt.
4. **Rács:** új mező a rácsköznek a Megjelenés csoportban.
5. **Előnézeti kép:** marad, és a kiválasztott kép kicsiben megjelenik a panelen.
6. **Fájl feltöltése:** marad a panel alján (a vászonra húzás és a helyi menü mellett).
7. **Panel:** Cím → Leírás → Megjelenés (téma, paletta, háttér, rácsköz) → Előnézeti kép → Fájl feltöltése.
