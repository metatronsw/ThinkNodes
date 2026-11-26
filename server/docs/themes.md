# ThinkNodes témák

**Új téma:** másold a `Public/themes/ThinkDefault.json` fájlt saját néven ugyanabba a könyvtárba. Adj új integer téma-ID-t, legalább egy palettát és egy vagy két támogatott módot. Az új JSON-t a Vapor induláskor olvassa be. A formátum gépi leírása a [theme.schema.json](theme.schema.json). A futó példák a [témakönyvtárban](../Public/themes) találhatók.

| Mező | Jelentés |
|---|---|
| `version`, `id`, `name` | Formátumverzió (1), stabil témaazonosító, megjelenített név. |
| `modes` | `["light","dark"]`, vagy egyetlen támogatott mód. Az első az export alapértelmezése kliensmód hiányában. Elhagyható: ilyenkor `light`, és ha bármelyik színnek van `dark` változata, `dark` is. |
| `palettes[]` | Minden paletta saját integer ID-t, nevet és 16–64 színt kap. Az ID-k a témán belül egyediek. |
| `colors[]` | Egyedi ID 0–63 között, fantázianév és legalább egy hatjegyű `light` vagy `dark` HEX. Egyetlen változat mindkét módban használható. |

A 0–15 ID minden palettában kötelező. Az első nyolc sorrendben a lap, tinta, felület, körvonal, kiemelés, majd három hangsúlyszín szerepét kapják. A 8–15 ID további nyolc választható színt ad. A 16–63 ID szabad. A név és a sorrend változhat. Új palettában hiányzó opcionális ID esetén a mező szerepszíne jelenik meg, az eredeti ID a dokumentumban marad.

## Grafika

A `graphics` opcionális. A `glow` (0–24 px) és a `selection` (0–7 szín-ID) a vászon kijelölését állítja. A `grid` lehet `dots`, `lines` vagy `drafting`. A `drafting` módban minden ötödik vonal erősebb mindkét irányban. A `glass` áttetsző dobozokat és üveghatású szerkesztőpaneleket kapcsol be. A `boxChamfer` pozitív értéke a lekerekített dobozok sarkait 45°-ban letöri (0–24 vászonegység). A `roundedWires` a Villám és a Zigzag vonalainak töréspontjait kerekíti. A `motionSpeed` a dobozanimációk sebességszorzója (0,1–5). A panelek mérete és stílusa közös, színük az oldal világos vagy sötét módjához igazodik.

Az esti (`dark`) szín bárhol elhagyható. Ilyenkor sötét módban a nappali szín látszik; ha egy palettának egyetlen esti színe sincs, a vászon sötét módban is teljesen nappali marad (a színek és a fényeffektek is).

A ThinkDefault négy palettája: Műhely és Botanika (21–21 szín), Radix (37 szín: mind a 31 Radix-színskála 9. fokozata, plusz a lap, tinta, felület, grafit és pasztell szerepszínek) és Catppuccin (26 szín: nappal a Latte, este a Mocha változat; [catppuccin/palette](https://github.com/catppuccin/palette), MIT-licenc). A színválasztó a fájl sorrendjében mutatja a színeket: elöl a semlegesek, utána színkör szerint.

A ThinkDefault paletták világos és sötét értékei a [Radix Colors](https://www.radix-ui.com/colors/docs/palette-composition/scales) 3.0.0 színskáláiból származnak.

## Vonalvastagság

A vonal vastagságát a téma adja: a vonal mérete (vékony 2, közepes 5, vastag 10,5 vászonegység) szorozva a `lineScale` szorzójával. A `lineScale` vonaltípusonként (`straight`, `sCurve`, `zigzag`, `lightning`, `arc`, `rope`) egy számot vagy megjelenésenkénti (`plain`, `thick`, `dashed`, `dotted`) szorzókat tartalmaz, 0,1 és 10 között. A hiányzó érték 1. A vastag megjelenés a szorzó után kétszeres.

```json
"lineScale": {
  "straight": {"plain": 0.9, "thick": 0.7, "dashed": 0.8, "dotted": 0.7},
  "rope": 1.1
}
```

## Dobozkeret

A `frame` a dobozok keretét állítja. A `width` a vastagság (0,5–16, alap: 1,6). A `color: "fill"` esetén a keret a doboz saját színét kapja, kitöltött dobozon is (alap: `auto`, a kitöltésből számolt sötétebb szín). A `fillOpacity` a kitöltött felület átlátszatlansága (áttetsző módban a fele) – alacsony értékkel a doboz színes keretű, halványan színezett belsejű lesz. A `halo` a keret körüli fényudvar átlátszatlansága: háromszoros vastagságú, áttetsző körvonal, szűrő nélkül. A `kind` a keret fajtája és helye: `outline` (alap) körvonal a doboz körül; `none` esetén a kitöltött doboz keret nélkül rajzolódik (a felület elválását a kitöltés és a vászon színkülönbsége adja), csak az üres háttérmódú doboz és a zárolt konténer kap körvonalat, a saját kijelölést pedig vékony kijelölés-körvonal jelzi. Későbbi bővítésre fenntartva: pl. `side` – a doboz oldalának színezése keret helyett. A kép és az előnézet saját keretét nem érinti.

```json
"frame": {"width": 4, "color": "fill", "fillOpacity": 0.14, "halo": 0.28}
```

## Szabadkézi rajz és papír

A `sketch` a dobozokat és a vonalakat szabadkézi (filc) rajzzá alakítja. A sarkos alakok egyetlen folytonos, kissé hajló vonalból állnak, amelynek a vége túlfut a kezdőponton; az ellipszis egyetlen, a bal oldalon pontosan össze nem érő vonal. A vonalak egy második, kissé elcsúsztatott, halványabb húzást kapnak. A `roughness` a remegés mértéke vászonegységben (0–5, alap 1,2), a `passes` a körvonal húzásainak száma (1–3, alap 2). A remegés a doboz azonosítójából számolódik, így minden újrarajzoláskor és az SVG-exportban is ugyanaz. A kattintható terület és a szöveg helye a szabályos alak marad. A keret vastagságát és színét, valamint a kitöltés átlátszatlanságát a `frame` adja. Sötét módban a rajz ugyanilyen, csak a színek mások. A közös algoritmus: `Public/sketch.js` és `Sources/ThinkCore/Sketch.swift`; a kettő egyezését a `Tests/Fixtures/sketch.json` ellenőrzi.

A `paper` papírfelületeket ad. A `grid: "sticky"` a táblázatot és a CSV-t cetlivé teszi (ragasztószalag, felpödrődő sarok, árnyék). A cetli színe a doboz színe fehérrel félig keverve; alapszínnél (2) a paletta 6-os színe. A `text: "notebook"` a szöveg- és kódfájlt füzetlappá teszi (sorvonalak, margóvonal, lyukak); a sorok magassága a betűméret 1,6-szorosa, a szöveg a vonalakon ül. A `sheet` a füzetlap, az `ink` a papíron álló szöveg, a `rule` a sorvonalak, a `margin` a margóvonal színe. A papír mindkét módban világos, ezért rajta a paletta színeinek nappali változata látszik.

```json
"sketch": {"roughness": 1.3, "passes": 1},
"paper": {"grid": "sticky", "text": "notebook", "sheet": "#fbfaf4", "ink": "#25314d", "rule": "#a9c8e8", "margin": "#e58a8f"}
```

## Minimalist

A leggyorsabb téma (id 7): nincs effekt, üveg, szabadkézi rajz, fényudvar (`glow: 0`, szűrő sem készül) és dobozkeret (`frame.kind: "none"`); egyenes vonalak, 6-os sarokkerekítés, kis csomópont. A világos és a sötét mód fényereje és kontrasztja hasonló: a vászon tört fehér, illetve grafit (egyik sem vakító vagy fekete), a szöveg kontrasztja mindkettőben kb. 9,3–10:1. Öt palettája (Kő, Fjord, Pasztell, Föld, Grafit) 21–21 színből áll, OKLCH-térben: 0 lap, 1 tinta, 2 felület (a vászonnál egy fokkal világosabb kártya), 3 vonal; 4–12 kilenc közép-tónusú szín (világosban egy fokkal mélyebb); 13–20 nyolc halvány (világos) / mély (sötét) kitöltésszín. A dobozfelület elválása a vászontól 1,24 (világos) / 1,34 (sötét), a szöveg a halvány kitöltéseken 8,6 / 6,1.

## Látványcsomag

Az `effects: "liquid"` gazdagabb megjelenést kapcsol be: áttetsző dobozfelület fénylő peremmel és csillogással, puha árnyék, lassan úszó háttérfények a paletta 4., 5. és 7. színéből, valamint rámutatás-, kattintás-, kijelölés- és pingeffektek. A statikus rész (felület, perem, árnyék, háttérfények) az SVG-exportban is megjelenik, a mozgás csak a böngészőben. A `boxRadius` a lekerekített doboz sarkának sugara (0–40, alap: 12). A csomag stílusai az `app.css` `[data-effects="liquid"]` szabályai, a doboz rétegeit az `editor.js` `liquid…` függvényei és a `Rendering.swift` adják. Csomag nélküli témában egyetlen plusz elem vagy szabály sem hat. A panelek és menük háttérelmosásához a `glass: true` is kell.

A dobozok mögötti tartalom valódi elmosása nem lehetséges: a Safari az SVG-n belül (elemen és `foreignObject`-ben is) figyelmen kívül hagyja a `backdrop-filter`-t. Valódi elmosást a HTML-panelek és menük kapnak.

A Liquid Glass téma öt palettája 21 színből áll: 0–3 lap, tinta, üveg, grafit; 4–7 és 11–15 élénk színek; 8 köd; 9–10 és 16–20 halvány felületszínek. A színek OKLCH-térben, azonos világosságon és telítettségen készültek, ezért egymással és a többi palettával is összeillenek.

A `box` a standard dobozalak, a `line` a standard vonaltípus. A támogatott értékek a sémában szerepelnek. Sokszögű dobozhoz a `contour` 3–32 konvex csúcspontot fogad, képernyőkoordináták szerint az óramutató járásával megegyező sorrendben. A középpont legyen a sokszög belsejében. Az x és y egysége a fél szélesség és a fél magasság. Az egyenes vonalhoz a `lineArc` 0 és 0,25 közötti arányt ad meg. A 0,1 érték a végpontok távolságának 10%-ával téríti ki a vonal közepét. A téma saját vonalához a `linePoints` 1–12 köztes töréspontot adhat meg. Az x a kezdőponttól a végpontig mért hányad, az y az arra merőleges eltolás a vonal hosszának arányában. A `junction` lehet ellipse, diamond vagy rectangle. A `junctionSize` az új csomópontok átmérője a vászon egységeiben.

## Téma törlése

A témafájl törlése után a szervert újra kell indítani (a témákat induláskor olvassa be). A törölt témát használó munkalapok az alaptémával (ThinkDefault, ennek híján a katalógus első témája) nyílnak meg; a színek paletta-ID-k, így az új palettán a megfelelő szerepszínt kapják. Ugyanígy a törölt paletta helyett a téma első palettája áll. Ez a betöltéskor, az importban és a mentéskor is érvényes (`Worksheet.repairAppearance`); a következő mentés már az új témát írja ki. A témára név szerint hivatkozó teszteket (`ThemeTests`) kézzel kell eltávolítani.

## Használat és ellenőrzés

A létrehozó a vászon tulajdonságpaneljének **Megjelenés** csoportjában választ témát és palettát. A fejléc ikonja minden oldalon Automatikus → Világos → Sötét sorrendben vált. A beállítás a böngészőben marad meg. Automatikus módban az operációs rendszer beállítása dönt. Az aktuális szerkesztési jogosultsággal rendelkező felhasználók a színnégyzet megnyitása után a kiválasztott palettáról színezhetnek.

A `"appearance":{"theme":3,"palette":1}` adja meg a munkalap témáját és palettáját. Ugyanabban a színmezőben egész paletta-ID vagy hatjegyű HEX-szín szerepelhet, például `"fill":2` vagy `"fill":"#3A587C"`. Az ID az aktuális témához, palettához és megjelenítési módhoz igazodik. A HEX-szín mentéskor és témaváltáskor is megmarad. A tulajdonságpanelen a paletta színei választhatók. Az SVG-export konkrét színeket ír ki. Közvetlen exportnál a `?mode=dark` vagy `?mode=light` megadja az oldal módját.

A demó útvonala `/ThemeDemo`. Az admin nevű létrehozó szerkesztheti a három lap megjelenését. Egy új témát világos és sötét környezetben, másik szerkesztővel, fájldobozon, csatlakozási pontokon és SVG-exportban is ellenőrizz.
