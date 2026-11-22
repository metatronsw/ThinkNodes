# ThinkNodes témák

**Új téma:** másold a `Public/themes/ThinkDefault.json` fájlt saját néven ugyanabba a könyvtárba. Adj új integer téma-ID-t, legalább egy palettát és egy vagy két támogatott módot. Az új JSON-t a Vapor induláskor olvassa be. A formátum gépi leírása a [theme.schema.json](theme.schema.json). A futó példák a [témakönyvtárban](../Public/themes) találhatók.

| Mező | Jelentés |
|---|---|
| `version`, `id`, `name` | Formátumverzió (1), stabil témaazonosító, megjelenített név. |
| `modes` | `["light","dark"]`, vagy egyetlen támogatott mód. Az első az export alapértelmezése kliensmód hiányában. |
| `palettes[]` | Minden paletta saját integer ID-t, nevet és 16–64 színt kap. Az ID-k a témán belül egyediek. |
| `colors[]` | Egyedi ID 0–63 között, fantázianév és legalább egy hatjegyű `light` vagy `dark` HEX. Egyetlen változat mindkét módban használható. |

A 0–15 ID minden palettában kötelező. Az első nyolc sorrendben a lap, tinta, felület, körvonal, kiemelés, majd három hangsúlyszín szerepét kapják. A 8–15 ID további nyolc választható színt ad. A 16–63 ID szabad. A név és a sorrend változhat. Új palettában hiányzó opcionális ID esetén a mező szerepszíne jelenik meg, az eredeti ID a dokumentumban marad.

## Grafika

A `graphics` opcionális. A `glow` (0–24 px) és a `selection` (0–7 szín-ID) a vászon kijelölését állítja. A `grid` lehet `dots`, `lines` vagy `drafting`. A `drafting` módban minden ötödik vonal erősebb mindkét irányban. A `glass` áttetsző dobozokat és üveghatású szerkesztőpaneleket kapcsol be. A `boxChamfer` pozitív értéke a lekerekített dobozok sarkait 45°-ban letöri (0–24 vászonegység). A `roundedWires` a Villám és a Zigzag vonalainak töréspontjait kerekíti. A `motionSpeed` a dobozanimációk sebességszorzója (0,1–5). A panelek mérete és stílusa közös, színük az oldal világos vagy sötét módjához igazodik.

A ThinkDefault paletták világos és sötét értékei a [Radix Colors](https://www.radix-ui.com/colors/docs/palette-composition/scales) 3.0.0 színskáláiból származnak.

A `box` a standard dobozalak, a `line` a standard vonaltípus. A támogatott értékek a sémában szerepelnek. Sokszögű dobozhoz a `contour` 3–32 konvex csúcspontot fogad, képernyőkoordináták szerint az óramutató járásával megegyező sorrendben. A középpont legyen a sokszög belsejében. Az x és y egysége a fél szélesség és a fél magasság. Az egyenes vonalhoz a `lineArc` 0 és 0,25 közötti arányt ad meg. A 0,1 érték a végpontok távolságának 10%-ával téríti ki a vonal közepét. A téma saját vonalához a `linePoints` 1–12 köztes töréspontot adhat meg. Az x a kezdőponttól a végpontig mért hányad, az y az arra merőleges eltolás a vonal hosszának arányában. A `junction` lehet ellipse, diamond vagy rectangle. A `junctionSize` az új csomópontok átmérője a vászon egységeiben.

## Használat és ellenőrzés

A létrehozó a vászon tulajdonságpaneljének **Megjelenés** csoportjában választ témát és palettát. A fejléc ikonja minden oldalon Automatikus → Világos → Sötét sorrendben vált. A beállítás a böngészőben marad meg. Automatikus módban az operációs rendszer beállítása dönt. Az aktuális szerkesztési jogosultsággal rendelkező felhasználók a színnégyzet megnyitása után a kiválasztott palettáról színezhetnek.

A `"appearance":{"theme":3,"palette":1}` adja meg a munkalap témáját és palettáját. Ugyanabban a színmezőben egész paletta-ID vagy hatjegyű HEX-szín szerepelhet, például `"fill":2` vagy `"fill":"#3A587C"`. Az ID az aktuális témához, palettához és megjelenítési módhoz igazodik. A HEX-szín mentéskor és témaváltáskor is megmarad. A tulajdonságpanelen a paletta színei választhatók. Az SVG-export konkrét színeket ír ki. Közvetlen exportnál a `?mode=dark` vagy `?mode=light` megadja az oldal módját.

A demó útvonala `/ThemeDemo`. Az admin nevű létrehozó szerkesztheti a három lap megjelenését. Egy új témát világos és sötét környezetben, másik szerkesztővel, fájldobozon, csatlakozási pontokon és SVG-exportban is ellenőrizz.
