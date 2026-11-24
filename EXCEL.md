# Táblázat doboz (`table`) – terv

Új vászonobjektum-típus: kis, élő táblázat a vásznon. Alapműveleteket (`+ - * /`) és összegzést (SUM) számol,
a cellák formázhatók, és táblázatfájlok importálhatók belőle. Szerkesztéskor azonnal újraszámol.
A típusrendszer szabályai: `docs/node-types.md`. **Állapot: az első kör elkészült (lásd 11. fejezet), a második és harmadik kör hátravan.**

## 0. Döntések (2026-11-24)

1. **A számított értéket a szerver is kiszámolja**, nem csak a böngésző. Ez később fontos lesz: a táblázatok egymásra
   hivatkoznak majd, és a szerver adja a megtekintő, az export és az előnézeti kép értékeit.
2. **Jól elkülönített kód Swiftben és JavaScriptben is.** A táblázat saját modulokba kerül, nem az `editor.js`-be
   vagy a `Rendering.swift`-be (lásd 2. fejezet). Így később könnyen szerkeszthető.
3. **Minden táblázat külön doboz.** Az első változat egyszerű: a képletek csak a saját táblázatukra hivatkoznak.
   A táblázatok közötti hivatkozást a kód már most előkészíti (lásd 9. fejezet), és később a vonallal összekötött táblázatok
   hivatkozhatnak egymásra.
4. **Több munkalapos fájl:** munkalaponként külön `table` doboz.
5. **Ütemezés:** az első körben csak `.csv` / `.tsv` import. Az `.xlsx`, `.xls`, `.ods` a második körben jön.
6. **A meglévő `csv` dobozok maradnak** csak olvasható szövegnézetek, nem alakulnak át. Fájl feltöltésekor vagy beemelésekor
   a program rákérdez: táblázat doboz legyen belőle, vagy szövegfájl (7. fejezet). Új táblázat doboz létrehozásakor is
   megadható forrásfájl.
7. **Számformátumok már az első körben** (tizedesjegyek, ezreselválasztó, pénznem, százalék, dátum; 3. fejezet).
8. **Táblázatközi hivatkozás:** csak vonallal összekötött táblázatok hivatkozhatnak egymásra, kölcsönösen; a vonal iránya nem számít (9. fejezet).
9. **`.xls`: saját Swift-importer**, egyszerűsített: az alapvető képleteket és a színeket hozza át (7. fejezet). Nincs LibreOffice-függőség.
10. **Rácsvonalak (cellakeretek):** cellánként és oldalanként vastagíthatók és színezhetők, és az import ezeket is megpróbálja átvenni.
11. **Export `.xls`-be is:** a saját táblázat letölthető `.xls`, `.xlsx` és `.csv` formátumban.
12. **Forrásfájl figyelése:** ha a forrás megváltozik, a program felajánlja az újraolvasást; a kézi gomb is megmarad (7. fejezet).

## 1. Helye a típusrendszerben

| | |
|---|---|
| `type` | `table` (Táblázat). Nem `sheet`, mert az a munkalapra mutató link fajtája. |
| Regiszter | `"table": {"label": "Táblázat", "file": "table", "extensions": ["tntable"], "traits": ["file", "table", "comment", "surface", "elevation", "size"]}` |
| Új képesség | `table`: cellák, képletek, formázás, rácsbeállítások (panelelem + szerkesztési mód) |
| Link | Nincs, mert a kattintás cellát jelöl ki. |
| Konténer | Nem lehet konténer, de lehet gyerek. |
| Vonal | A táblázatok összeköthetők vonallal; ez a későbbi táblázatközi hivatkozás alapja (9. fejezet). |

A mostani `csv` altípus (`base: text`) megmarad. A `.csv` / `.tsv` feltöltésekor a felhasználó választ: `table` vagy `csv` (7. fejezet).

## 2. Kódszerkezet

A táblázat önálló modulcsoport. A szerkesztő, a renderelő és a szerver csak a modulok nyilvános felületét hívja.

### Swift: `Sources/ThinkTable/` (önálló SwiftPM target, Vapor nélkül)

| Fájl | Feladat |
|---|---|
| `TableDocument.swift` | Adatmodell (`TableDocument`, `CellAddress`, `CellValue`, `CellStyle`), `Codable`, validálás, korlátok |
| `TableFormula.swift` | Lexer, parser → AST, függvénytár |
| `TableEngine.swift` | Kiértékelés, függőségi gráf, újraszámolás, körfelismerés, hivatkozás-eltolás |
| `TableCSV.swift` | CSV/TSV beolvasás és kiírás (elválasztó-felismerés, BOM, kódolás) |
| `TableHTML.swift` | Táblázat HTML-je a megtekintőhöz és az SVG-exporthoz |
| `TableFormat.swift` | Számformátumok: érték → megjelenített szöveg (magyar alapértelmezés) |
| `TableImport*.swift` | Második kör: `TableImportXLSX`, `TableImportODS`, `TableImportXLS` (`BIFF/` almappa: OLE-tároló, rekordok, képletek) |
| `TableExport*.swift` | `TableExportCSV` (első kör), `TableExportXLSX`, `TableExportXLS` (második kör) |

A Vapor oldal (`Sources/ThinkNodes/`) csak összeköt: import végpont, fájlmentés, `fileBox`-ból a `TableHTML` hívása.
Az önálló target a `PLAN.md` natív kliensében is újrahasznosítható.

### JavaScript: `Public/table/`

| Fájl | Feladat |
|---|---|
| `table-document.js` | Adatmodell, betöltés / mentés, címkezelés (`A1` ↔ sor/oszlop) |
| `table-formula.js` | Lexer, parser, függvénytár (DOM nélkül) |
| `table-engine.js` | Kiértékelés, függőségek, újraszámolás (DOM nélkül) |
| `table-format.js` | Számformátumok (a Swift `TableFormat` párja) |
| `table-view.js` | Vue-komponens: rács kirajzolása, virtualizálás, fejlécek |
| `table-edit.js` | Szerkesztési mód: kijelölés, billentyűzet, képletsor, eszközsor |
| `table-clipboard.js` | Másolás / beillesztés (TSV, HTML) |

Az `editor.js` csak a komponenst illeszti a dobozba, és a panelen a `table` képességet köti be. A `viewer.js` a `table-view.js`-t használja szerkesztés nélkül.

### Közös tesztek: a két motor egyezzen

- `Tests/TableFixtures/*.json`: esetek (cellák + képletek → elvárt értékek és hibák).
- Mindkét oldal ugyanezeket futtatja: Swift `Tests/ThinkTableTests`, JS `Tests/Editor/table-engine.mjs`.
- A számformátumoknak is vannak közös esetei (érték + formátum → elvárt szöveg), mert a szerver és a böngésző ugyanazt kell mutassa.
- Az import és az export mintafájlokkal tesztelendő (`Tests/TableFixtures/import/`). Oda-vissza teszt:
  saját táblázat → `.xls` / `.xlsx` → visszaolvasás → ugyanaz az adat.
- Új függvény csak akkor kerülhet be, ha mindkét oldalon megvan, és a közös tesztek zöldek.

## 3. Adattárolás

A szövegfájlok mintáját követi: **a tartalom egy fájlban van**, nem a munkalap JSON-jában.
- **Fájl:** `<név>.tntable` (JSON) a lap mellékletei között. A munkalapon csak a `file` hivatkozás (`asset`, `filename`, `source`, `rev`) van.
- **Mentés:**
  1. A szerkesztő automatikusan menti (PUT, kb. 1 s késleltetéssel).
  2. A szerver mentéskor újraszámolja a képleteket (`TableEngine`), és a saját eredményét írja a fájlba.
  3. Utána `file.rev` nő, és a többi kliens ebből tudja, hogy újra kell töltenie.
- **A böngésző azonnal számol**, hogy gépelés közben is látszódjon az eredmény. A tárolt értéket mindig a szerver írja.
  Ha a kettő eltér, az a közös tesztek hibája.
- **Ütközés nincs**, mert a kijelölés zárol (egy dobozt egyszerre egy ember szerkeszt).
- **Az eredeti importált fájl** (`.csv`, később `.xlsx`) megmarad forrásként (`file.source`), így letölthető. A szerkesztés csak a `.tntable`-t módosítja.

### Fájlformátum

```json
{
  "format": "thinknodes-table", "version": 1,
  "id": "tbl-7f3a",
  "name": "Bevétel",
  "size": {"rows": 12, "cols": 5},
  "cols": {"A": {"w": 140}, "C": {"w": 60}},
  "rows": {"1": {"h": 28}},
  "header": {"rows": 1, "cols": 0},
  "grid": true,
  "styles": [
    {},
    {"b": 1, "fill": "#fff3c4", "border": {"bottom": {"w": 2, "color": "#333333"}}},
    {"i": 1, "u": 1, "color": "#b00020"},
    {"o": 1, "align": "right", "fmt": {"kind": "currency", "dec": 0, "symbol": "Ft"}, "border": {"top": {"w": 3, "style": "double"}}}
  ],
  "cells": {
    "A1": {"v": "Termék", "s": 1},
    "B2": {"v": 1200},
    "B3": {"v": 850.5},
    "B5": {"f": "SUM(B2:B4)", "v": 2050.5, "s": 3}
  }
}
```

- **Ritka tárolás:** csak a nem üres cellák szerepelnek.
- **`v` (érték):** szám, szöveg, logikai érték vagy hiba (`{"err": "#DIV/0!"}`). Képletes cellánál ez a szerver által számolt eredmény.
- **`f` (képlet):** a `=` jel nélkül tárolva.
- **`s` (stílus):** index a `styles` tömbbe, ahogy az xlsx is csinálja.
- **Stílusmezők:** `b` félkövér, `i` dőlt, `u` aláhúzott, `o` felülvonás, `color` betűszín, `fill` cellaszín, `align` igazítás (left / center / right),
  `fmt` számformátum, `border` cellakeret.
- **Cellakeret (`border`):** oldalanként (`top`, `right`, `bottom`, `left`) külön: `w` vastagság (1 vékony, 2 közepes, 3 vastag),
  `color` szín, `style` (`solid`, `dashed`, `dotted`, `double`). Ha két szomszédos cella közös oldalán eltér a keret,
  a vastagabb nyer, egyenlőnél a jobb oldali / alsó cella keretét a bal oldali / felső cella felülírja (ahogy az Excel rajzolja).
  A `grid` kapcsoló az alap, halvány rácsot kapcsolja; a cellakeret ettől függetlenül mindig látszik.
- **Számformátum (`fmt`):**

  | `kind` | Mezők | Példa (magyar) |
  |---|---|---|
  | `general` (alap) | – | `1234,5` |
  | `number` | `dec` tizedesjegyek, `group` ezreselválasztó | `1 234,50` |
  | `currency` | `dec`, `symbol`, `before` (a jel elöl) | `1 235 Ft`, `€ 12,00` |
  | `percent` | `dec` | `12,5%` |
  | `date` | `pattern` (`yyyy.MM.dd.`, `yyyy.MM.dd. HH:mm`, `HH:mm`) | `2026.11.24.` |
  | `text` | – | a beírt szöveg változatlanul, nem lesz szám |

  - A dátum a cellában számként tárolódik (napok 1899-12-30 óta, mint az Excelben), így számolni is lehet vele, és az import/export is egyszerű.
  - Beíráskor a felismert alak beállítja a formátumot: `12%` → `percent`, `2026.11.24.` → `date`, `1 200 Ft` → `currency`.
  - Az import a forrás formátumkódjából (`0.00`, `#,##0 "Ft"`, `0%`, `yyyy-mm-dd`) a legközelebbi `kind`-ot választja. Amit nem ért, az `general` lesz.
- **`id`, `name`:** állandó azonosító és megjelenített név. A későbbi táblázatközi hivatkozás ezekre épül (9. fejezet).
  A `name` alapból a munkalap neve (importkor), illetve a fájlnév.
- **Korlátok (javaslat):** legfeljebb 1000 sor × 100 oszlop, 50 000 nem üres cella, 5 MB. Az import e fölött levág, és szól.

## 4. Képletmotor (Swift és JS, azonos viselkedéssel)

**Nyelv (első változat):**
- Számok, szövegek `"…"`-ben, `+ - * /`, `^`, előjel, zárójelek, `&` (összefűzés).
- Hivatkozások: `A1`, `$A$1`, tartomány `A1:B5`, egész oszlop `B:B`.
- Függvények: `SUM`. Ha belefér, ugyanabban a körben, mert olcsók: `AVERAGE`, `MIN`, `MAX`, `COUNT`, `ROUND`, `IF`.
- Magyar Excel-kompatibilitás: a `SZUM`, `ÁTLAG`, `MIN`, `MAX`, `DARAB`, `KEREKÍTÉS`, `HA` nevek is működnek, az argumentumokat `,` és `;` is elválaszthatja.
  Beíráskor a tizedesvessző és a tizedespont is elfogadott.
- Hibák: `#REF!` (törölt vagy határon kívüli hivatkozás), `#DIV/0!`, `#VALUE!`, `#NAME?` (ismeretlen függvény), `#CIRC!` (körkörös hivatkozás).
- **Előkészítve:** a parser már most felismeri a másik táblázatra mutató hivatkozást (`'Bevétel'!B5`).
  Az első változatban ennek eredménye `#REF!` (9. fejezet).

**Újraszámolás („aktív doboz”):**
1. A képlet beíráskor AST-vé alakul, ebből kigyűjtjük a függőségeit.
2. Fordított függőségi gráf: cella → az őt használó képletek. A csúcsok kulcsa már most `(táblázat-id, cella)`,
   így a gráf később több táblázatra is kiterjeszthető.
3. Cella módosításakor csak a tőle függő cellák számolódnak újra, topologikus sorrendben. Kört a bejárás közben észlelünk,
   a körben lévő cellák `#CIRC!` értéket kapnak.
4. A böngészőben az új értékek azonnal kirajzolódnak. Mentéskor a szerver ugyanígy számol, és az ő eredménye kerül a fájlba.
5. Sor vagy oszlop beszúrásakor és törlésekor a képletek hivatkozásai eltolódnak, ahogy Excelben (a `$` rögzít).
   A törölt cellára mutató hivatkozásból `#REF!` lesz.
6. A motor a cellák értékét egy feloldón (`resolver`) keresztül kéri le. Az első változatban ez csak a saját táblázatot ismeri,
   később a többi táblázatot is.

**Megjelenítés:** a számok a cella formátumát (`fmt`) követik, alapból a magyar alakot (`1 234,5`). A szöveg balra,
a szám jobbra igazodik, ha a cella stílusa mást nem ír elő. A képlet eredménye megkapja a hivatkozott cella formátumát,
ha a saját cellájának nincs (pl. `SUM` pénznemes cellákon pénznem lesz), ahogy Excelben.

## 5. Megjelenés a vásznon

- A felépítés megegyezik a többi fájlos dobozéval: felül a fájlnév (elrejthető), középen a rács, alul a `comment`.
- A rács HTML-táblázat `foreignObject`-ben, mint a mostani CSV-nézet, és a dobozon belül görgethető.
  A meglévő `scrollbarPress` / `stopScroll` viselkedés marad: a rács bárhol megfogható és mozgatható, a görgetés csak a görgetősávokon működik.
- Oszlop- és sorfejléc (A, B, C… / 1, 2, 3…) csak szerkesztési módban látszik. A megtekintőben és az exportban csak az adat jelenik meg.
- A rögzített fejlécsor (`header.rows`) félkövér, és görgetéskor fent marad (`position: sticky`).
- A halvány alaprács a `grid` beállítással kapcsolható ki, a színe a témából jön. A cellakeretek (`border`) a saját vastagságukkal és színükkel
  rajzolódnak, a HTML-ben `border-collapse: collapse` mellett, így a 3. fejezet szabálya szerint nyer a vastagabb keret.
- Szerver: a `TableHTML` (ThinkTable) adja a megtekintő és az SVG-export HTML-jét.
- Nagy táblázatnál a vásznon legfeljebb az első 200 sor jelenik meg. Szerkesztési módban a teljes táblázat görgethető,
  és a láthatatlan sorok nem rajzolódnak ki (virtualizálás).

## 6. Szerkesztés

**Belépés:** Alt+dupla kattintás a dobozon, ugyanaz a mozdulat, ami a szövegszerkesztést indítja. Kilépés: Esc vagy kattintás a dobozon kívül.

**Szerkesztési módban:**
- A doboz tetején képletsor jelenik meg: a cella neve (pl. `B5`) és a nyers tartalma (`=SUM(B2:B4)`).
- Kijelölés: kattintás, Shift+kattintás, húzás (tartomány), kattintás az oszlop- vagy sorfejlécre (egész oszlop vagy sor).
- Mozgás: nyilak, Tab / Shift+Tab, Enter / Shift+Enter, Home / End, Ctrl+nyíl.
- Beírás: gépeléskor a cella tartalma lecserélődik, F2 vagy dupla kattintás a meglévőt szerkeszti, Delete törli, Esc elveti a változást.
- Képlet írásakor egy cellára kattintva vagy a nyilakkal a hivatkozás beszúródik, és a hivatkozott tartomány színes keretet kap.
- Formázás: Ctrl+B / I / U. A felülvonásnak és a színeknek nincs gyorsbillentyűje, ezek a panelen és a lebegő eszközsoron érhetők el.
- Vágólap:
  - **Másolás:** TSV és HTML formában is, így Excelbe és Numbersbe is beilleszthető.
  - **Beillesztés:** TSV vagy HTML-táblázat a kijelölt bal felső cellától. A beillesztett képletek relatív hivatkozásai az új helyhez igazodnak.
- Sor/oszlop: helyi menüből beszúrás, törlés, oszlopszélesség húzással.
- Visszavonás: szerkesztési módban saját visszavonási verem a cellaműveletekhez. Kilépés után a táblázat a munkalap visszavonásában egy lépésnek számít.

**Lebegő eszközsor** (a doboz fölött, szerkesztési módban): B, I, U, felülvonás, betűszín, cellaszín, igazítás (3 gomb),
számformátum (lenyíló + tizedesjegy −/+), keret, Σ (összegzés a kijelölés alá vagy mellé).

**Keret gomb:** lenyíló, mint az Excelben.
- Hová: minden rács, külső keret, csak alul / felül / balra / jobbra, belső vízszintes / függőleges, keret törlése.
- Milyen: vastagság (vékony, közepes, vastag), stílus (folytonos, szaggatott, pontozott, dupla), szín.
- A kijelölt tartományra hat. A „külső keret” csak a tartomány szélein lévő cellák külső oldalát állítja.

**Tulajdonságpanel:** Fájlnév (+ mutatás) → **Táblázat** (név, forrásfájl, fejlécsor rögzítése, alaprács, cellaformázás a kijelölt cellákra:
B / I / U / O, betűszín, cellaszín, igazítás, számformátum, keret; Letöltés: csv, xlsx, xls) → Megjegyzés → Megjelenés (háttér, kiemelés).

## 7. Létrehozás és import

### Rákérdezés feltöltéskor

Táblázatként is beolvasható fájl (első körben `.csv`, `.tsv`; a második körben `.xlsx`, `.xls`, `.ods`) feltöltésekor,
vászonra húzásakor vagy a közös könyvtárból beemelésekor egy kis párbeszéd jelenik meg:

- **Táblázat** (szerkeszthető, számol): `table` doboz, a fájl forrásként megmarad (`file.source`).
- **Fájl** (ahogy most): `.csv` / `.tsv` → csak olvasható `csv` szövegnézet; `.xlsx` / `.xls` / `.ods` → `document` doboz (letöltés).
- A „Megjegyzi erre a munkamenetre” jelölő több fájl egyszerre húzásakor ne kérdezzen fájlonként.
- A meglévő `csv` és `document` dobozok nem változnak. A helyi menüben („Megnyitás táblázatként”) később egyenként átalakíthatók: új `table` doboz jön létre mellettük.

### Új táblázat doboz forrásfájllal

Helyi menü → Objektum létrehozása → Táblázat. A párbeszédben:
- **Üres:** 5 oszlop × 10 sor, azonnal szerkesztési módban.
- **Forrásfájlból:** a lap mellékletei vagy a közös könyvtár közül választható fájl, vagy feltöltés a gépről (ugyanaz a fájlválasztó, mint a .web mappánál).
  Több munkalapos fájlnál munkalaponként egy doboz jön létre.

A forrásfájl később a panelen is megadható vagy cserélhető („Forrásfájl” → Újraolvasás).
Újraolvasáskor a program figyelmeztet, hogy a táblázatban végzett változtatások elvesznek.

### Forrásfájl figyelése (döntés)

A program figyeli, ha a forrásfájl megváltozik, és felajánlja az újraolvasást. A kézi „Újraolvasás” gomb is megmarad.
- **Változásnak számít:** új verzió feltöltése ugyanazzal a névvel, a közös könyvtárbeli fájl cseréje, vagy egy szövegfájlként
  (`csv` doboz) megnyitott forrás szerkesztése.
- **Felismerés:** a táblázat importkor eltárolja a forrás tartalmi lenyomatát (`file.sourceHash`, SHA-256), mert az időbélyeg nem elég megbízható.
  A szerver a forrás írásakor összeveti ezzel, és az eltérő táblázatoknak jelzést ad (`file.sourceChanged: true`).
- **Megjelenés:** a dobozon egy kis jelzés, a panelen pedig sáv: „A forrásfájl megváltozott” – Újraolvasás / Figyelmen kívül hagyás.
  A figyelmen kívül hagyás az új lenyomatot tárolja el, így ugyanarra a változásra nem kérdez újra.
- **Nem olvas újra magától,** mert a táblázatban végzett szerkesztések elvesznének. Ha a táblázat az import óta nem változott,
  a sáv ezt kiírja („nincs elvesző módosítás”), így a döntés könnyű.
- **Több munkalapos forrás:** az újraolvasás az összes belőle készült dobozra vonatkozik. A dobozok a munkalap nevével párosulnak.
  Az új munkalapból új doboz lesz, a megszűnt munkalap doboza megmarad, és jelzést kap.

### Első kör

| Forrás | Módja |
|---|---|
| `.csv`, `.tsv` | Szerver (`TableCSV`): elválasztó felismerése (`,` `;` tab), BOM, Windows-1250 tartalék kódolás. Nincs 200×30-as korlát, csak a 3. fejezet korlátai. A számként értelmezhető mezők (`1 234,5`, `1234.5`, `12%`, `2026.11.24.`) számok lesznek, a formátumuk is beáll. Az `=`-vel kezdődő mező szöveg marad: CSV-ből nem jön képlet. |
| Beillesztés a vászonra | Ha a vágólapon legalább 2×2-es táblázat van (TSV vagy HTML), `table` doboz jön létre. Különben szöveges doboz, ahogy most. HTML-ből a színek, a félkövér/dőlt és a keretek is átjönnek, ha vannak. |
| Export | Letöltés csv-ként (a megjelenített formátum nélkül, nyers értékek; képletnél az eredmény). |

### Második kör: `.xlsx`, `.ods`, `.xls`

**Több munkalapos fájl:** munkalaponként egy `table` doboz, egymás mellé rendezve. A táblázat neve (`name`) a munkalap neve.
Ha a munkalapok egymásra hivatkoznak, a táblázatközi hivatkozás (9. fejezet) elkészültéig ezek a képletek rögzített értékként jönnek át (lásd lent).

| Formátum | Javasolt megoldás |
|---|---|
| `.xlsx` | Saját Swift-olvasó (`TableImportXLSX`). A ZIP-et a már használt `unzip` bontja ki, a tartalmat `XMLParser` olvassa: `workbook.xml`, `sharedStrings.xml`, `sheetN.xml`, `styles.xml`. Átjön az érték, a képlet, a tárolt eredmény, a félkövér, dőlt, aláhúzott, a betű- és kitöltőszín, a keret (`<border>`: oldalanként stílus és szín), a számformátum, az oszlopszélesség. |
| `.ods` | Ugyanígy: ZIP + XML (`content.xml`, `styles.xml`). A keret a `fo:border-*` tulajdonságokból jön. |
| `.xls` | Saját Swift BIFF8-olvasó (`TableImportXLS`), lásd lent. |

Közös az importereknél: az eredmény egy köztes `TableDocument` munkalaponként, így a felismerés, a korlátok, a formátum-leképezés
és a dobozok elrendezése egy helyen van, a formátumonkénti kód csak az olvasást végzi.

**Keretek importja (mindhárom formátumnál):**

| Forrás | `w` | `style` |
|---|---|---|
| hairline, thin | 1 | `solid` |
| medium | 2 | `solid` |
| thick | 3 | `solid` |
| dashed, mediumDashed, dashDot… | 1 / 2 | `dashed` |
| dotted | 1 | `dotted` |
| double | 3 | `double` |

A keret színe az indexelt színpalettából vagy RGB-ből jön, az automatikus szín fekete. Az átlós keret nem jön át.

**Nem támogatott függvény:** a cella megtartja a fájlban tárolt eredményt, a képlet megjegyzésként megmarad (`"fx": "VLOOKUP(…)"`),
a cella sarkában pedig jelölés mutatja, hogy itt az érték rögzített. Ha később támogatjuk a függvényt, újra képlet lehet belőle.

### `.xls` import: saját Swift BIFF8-olvasó (döntés)

Egyszerűsített olvasó, külső program és C-könyvtár nélkül. Csak az Excel 97–2003 (BIFF8) formátum; a régebbi (BIFF5 és korábbi) fájlra hibaüzenet jön.

**Felépítés (`Sources/ThinkTable/BIFF/`):**
- `CompoundFile.swift`: az OLE-tároló (CFB) olvasása, a `Workbook` (régen `Book`) adatfolyam kiemelése. FAT- és miniFAT-lánc, korlátokkal és körfigyeléssel, mert sérült fájlnál végtelen ciklus is lehet.
- `BIFFReader.swift`: rekordok olvasása (`CONTINUE` rekordok összefűzése, különösen az `SST`-nél).
- `BIFFFormula.swift`: képletek visszafejtése (`Ptg` tokenek → képletszöveg).
- `TableImportXLS.swift`: összerakja a `TableDocument`-eket.

**Beolvasott rekordok:**

| Terület | Rekordok |
|---|---|
| Munkafüzet | `BOF`, `EOF`, `BOUNDSHEET8` (munkalapnevek), `SST` + `CONTINUE` (közös szövegek), `PALETTE` (egyéni színek), `DATEMODE` (1900 / 1904) |
| Stílus | `FONT` (félkövér, dőlt, aláhúzott, szín), `XF` (kitöltés, igazítás, keretek oldalanként stílussal és színnel, formátum), `FORMAT` (számformátum-kódok) |
| Cellák | `LABELSST`, `LABEL`, `NUMBER`, `RK`, `MULRK`, `BOOLERR`, `BLANK`, `MULBLANK` |
| Képlet | `FORMULA` (tárolt eredmény + `Ptg`), `STRING` (szöveges eredmény), `SHRFMLA` (megosztott képlet: a felső cella képlete eltolva) |
| Méret | `COLINFO` (oszlopszélesség), `ROW` (sormagasság) |

**Képletek (egyszerűsített):** csak a mi motorunk által ismert részhalmaz fejtődik vissza.
- Számok, szövegek, logikai értékek; műveletek `+ - * / ^ &`, összehasonlítás, előjel, zárójel.
- Cella- és tartományhivatkozás (`PtgRef`, `PtgArea`, a `$` jelzőkkel), megosztott képletnél a relatív eltolás.
- Függvények (`PtgFunc`, `PtgFuncVar`, `PtgAttr` SUM): `SUM`, `AVERAGE`, `MIN`, `MAX`, `COUNT`, `ROUND`, `IF`.
- Minden más (másik munkalapra mutató hivatkozás, név, tömbképlet, ismeretlen függvény): a cella a tárolt eredményt kapja, az `fx` megjegyzés pedig jelzi, hogy itt eredetileg képlet volt.
  Ha a forrásban másik munkalapra mutató hivatkozás volt, a táblázatközi hivatkozás (9. fejezet) elkészülte után újraimportálva képlet lehet belőle.

**Nem jön át:** egyesített cellák (csak a bal felső érték), feltételes formázás, megjegyzések, képek, diagramok, védelem, rejtett sorok és oszlopok.
Ezek egy összesítő üzenetben jelennek meg az import után („3 cellában a képlet rögzített értékként jött át…”).

**Titkosított `.xls`** (`FILEPASS` rekord): hibaüzenet, nem olvassuk be.

**Biztonság:** a rekordhosszakat, az indexeket és a láncokat mindig ellenőrizni kell, mert idegen bináris fájlt olvasunk.
A sérült vagy hamisított fájl hibát adhat, de nem okozhat összeomlást vagy túl nagy memóriafoglalást.
Ehhez kell egy fuzz-szerű teszt is: megcsonkított és véletlenszerűen elrontott mintafájlok.

### Export

| Formátum | Módja |
|---|---|
| `.csv` | Első kör (lásd fent). |
| `.xlsx` | Második kör, `TableExportXLSX`: `sharedStrings`, `styles` (betű, kitöltés, keret, számformátum), képletek és tárolt eredmények. A meglévő `ZipWriter` tömörítetlen ZIP-je érvényes xlsx-hez, ezt az Excel elfogadja. |
| `.xls` | Második kör, `TableExportXLS`: BIFF8-író (OLE-tároló + `Workbook` adatfolyam). A képletek `Ptg` tokenekké fordulnak; a motor minden függvénye kiírható, mert mindegyiknek van Excel-megfelelője. Színek: a BIFF8 56 színű palettát használ, ezért a saját színek a `PALETTE` rekordba kerülnek; ha 56-nál több kell, a legközelebbi színre kerekít. Keretek, számformátumok, oszlopszélesség is kiíródik. Felülvonás nincs az xls/xlsx-ben, ez elvész. |

Több munkalapos export: a vonallal összekötött táblázatok (9. fejezet) később egy munkafüzetbe exportálhatók, munkalaponként egy táblázattal,
és a táblázatközi hivatkozásból munkalapok közötti hivatkozás lesz.

## 8. Ütemezés

**Első kör**
1. **ThinkTable alapok:** adatmodell, képletmotor és számformátumok Swiftben és JS-ben, közös tesztesetek (elemzés, kiértékelés, függőségek, körök, hivatkozás-eltolás, formázott kiírás).
2. **Típus és megjelenítés:** regiszter, Swift modell és validálás, a mentéskori szerveres újraszámolás, `TableHTML`, `table-view.js` (cellakeretekkel), megtekintő.
3. **Szerkesztési mód:** kijelölés, billentyűzet, képletsor, formázás, számformátum, keret, eszközsor, panel, vágólap, automatikus mentés.
4. **Létrehozás és CSV:** új doboz párbeszéd (üres / forrásfájlból), rákérdezés feltöltéskor, CSV/TSV import, csv-export,
   forrásfájl figyelése és újraolvasása, Swift-tesztek mintafájlokkal.

**Második kör**
5. Közös köztes import-réteg, `.xlsx` és `.ods` import (keretekkel, számformátumokkal), több munkalap → több doboz.
6. `.xls` import (saját BIFF8-olvasó), sérült fájlos tesztekkel.
7. Export: `.xlsx`, majd `.xls` (BIFF8-író), oda-vissza tesztekkel.

**Harmadik kör**
8. Táblázatközi hivatkozás (9. fejezet), több táblázat exportja egy munkafüzetbe.
9. Később: további függvények, diagram a táblázatból, egyesített cellák.

## 9. Táblázatközi hivatkozás (előkészítés)

**Cél:** az egyik táblázat képlete a másik táblázat celláját használja (`'Bevétel'!B5`). Ha a forrás változik, a hivatkozó
táblázat is újraszámolódik, akár egy másik felhasználónál is.

**Működés (az összekötés elfogadva, a többi javaslat):**
- **Összekötés:** csak a vonallal összekötött táblázatok hivatkozhatnak egymásra. A függőség így a vásznon is látszik, és nem lesz rejtett kapcsolat.
- **Irány (döntés):** a vonal iránya nem számít, az összekötött táblázatok kölcsönösen hivatkozhatnak egymásra.
  Ha a hivatkozások kört alkotnak (A → B → A), a körben lévő cellák `#CIRC!` értéket kapnak.
- **Csak közvetlen kapcsolat:** a hivatkozott táblázatnak közvetlenül össze kell lennie kötve a hivatkozóval, egy vonallal vagy csomópontokon át.
  Ha A–B és B–C össze van kötve, attól A még nem hivatkozhat C-re.
- **Hivatkozás tárolása:** a képletben a táblázat állandó `id`-je áll (`{tbl-7f3a}!B5`), a felületen a neve (`'Bevétel'!B5`).
  Átnevezéskor így nem törik el. A forrás törlésekor vagy a vonal törlésekor `#REF!` lesz.
- **Hatókör:** először ugyanazon a munkalapon belül.
- **Újraszámolás a szerveren:** a munkalap betöltésekor és egy táblázat mentésekor a szerver felépíti a lap függőségi gráfját
  (csúcs: `(táblázat-id, cella)`). A megváltozott táblázattól függő táblázatokat újraszámolja és menti, a `file.rev`-jüket növeli.
  A többi kliens ebből frissül. Táblázatok közötti kört (A → B → A) is felismer, ilyenkor `#CIRC!`.
- **A böngésző** a látható függő táblázatokat azonnal újraszámolja, hogy gépelés közben is lássuk a hatást. A tárolt eredmény itt is a szerveré.
- **Zárolás:** a függő táblázat értéke akkor is frissül, ha valaki más éppen szerkeszti. Ilyenkor csak a `v` értékek változnak,
  a képletek nem, így a szerkesztését ez nem zavarja.

**Ami már az első körben elkészül, hogy később ne kelljen átírni:**
- `id` és `name` a fájlformátumban.
- A parser ismeri a `Név!A1` / `{id}!A1` formát; az első körben `#REF!` az eredménye.
- A függőségi gráf kulcsa `(táblázat-id, cella)`.
- A motor a cellákat feloldón (`resolver`) keresztül olvassa.
- A szerveren az újraszámolás a `ThinkTable` modulban van, nem a mentési végpontban, így később laponként is hívható.

## 10. Nyitott kérdések

Jelenleg nincs. A legutóbb lezártak (2026-11-24):
1. **A vonal iránya nem számít:** az összekötött táblázatok kölcsönösen hivatkozhatnak egymásra. A körkörös hivatkozás `#CIRC!` lesz (9. fejezet).
2. **A forrásfájl változását a program figyeli** (7. fejezet, „Forrásfájl figyelése”). A kézi „Újraolvasás” gomb is megmarad.

## 11. Megvalósítás állapota

### Első kör – kész (2026-11-24)

| Terület | Hol |
|---|---|
| Adatmodell, képletek, újraszámolás, számformátumok, CSV, HTML (Swift) | `Sources/ThinkTable/` (önálló target: `TableDocument`, `TableFormula`, `TableEngine`, `TableFormat`, `TableCSV`, `TableHTML`) |
| Ugyanez JavaScriptben | `Public/table/table-document.js`, `table-formula.js`, `table-engine.js`, `table-format.js` |
| Szerkesztési mód, vágólap, nézet, eszközsor | `Public/table/table-edit.js` (DOM nélküli vezérlő), `table-clipboard.js`, `table-view.js` |
| Fájlműveletek, párbeszédablakok | `Public/table/table-files.js` |
| Szerver | `Sources/ThinkNodes/TableFiles.swift`: mentéskor ellenőrzés + újraszámolás (`WorksheetStore.storeAttachment`), végpontok: `POST /api/table/…?from=` (forrásból / újraolvasás), `GET /api/table-source/…` (forrás figyelése), `GET /api/table-export/…?format=csv`; a megtekintő és az SVG a `TableHTML`-t rajzolja (`Rendering.swift` `fileTextHTML`) |
| Szerkesztő bekötése | `Public/editor.js`: olvasó nézet, Alt+dupla kattintás → cellaszerkesztés, helyi menü („Táblázat létrehozása”, „Cellák szerkesztése”, CSV-dobozon „Megnyitás táblázatként”), rákérdezés feltöltéskor, táblázatos szöveg beillesztése → táblázat doboz, Táblázat panel (név, fejlécsor, alaprács, eszközsor, forrásfájl, újraolvasás, figyelmen kívül hagyás, CSV-letöltés) |
| Típusregiszter | `Public/node-types.json`: `table` (`base: text`, `.tntable`) |
| Stílus | `Public/app.css` `.tn-*` |
| Tesztek | közös esetek: `Tests/TableFixtures/*.json`; Swift: `Tests/ThinkTableTests` (`swift test --filter ThinkTableTests`); JS: `node Tests/Editor/table-engine.mjs` (közös esetek + szerkesztésvezérlő) |

**Eltérések, döntések menet közben:**
- A `table` a `text` alkategóriája lett, így a betöltés, az automatikus mentés és a `file.rev` alapú újratöltés a szövegfájlokéval közös.
- A `.tntable` neve a lapon azonosító (`file-…`); a szerver a tényleges fájlnévből ismeri fel a táblázatot.
- CSV-exportban az `=`, `+`, `-`, `@` kezdetű szöveg elé `'` kerül (CSV-befecskendezés ellen).
- Egy cellára mutató hivatkozás függvényargumentumként tartományként viselkedik (Excel: `AVERAGE(A3)` szöveges cellánál `#DIV/0!`).
- A `ROUND` / számformátum kerekítése a feleket nullától elfelé viszi, saját kiírással (a printf és a JS `toFixed` az egzakt feleknél eltér).
- Forrásfájl a projekt másik lapjáról vagy a közös könyvtárból: előbb a saját lapra másolódik, onnan készül a táblázat.

**Böngészőben még nem ellenőrzött:** a szerkesztési mód kezelése (kijelölés egérrel, oszlopszélesség húzása, vágólap Excellel, párbeszédablakok). A tesztlap: `MassTest/TablaTeszt` (helyi adat).
