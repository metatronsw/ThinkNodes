# ThinkNodes témák

**Új téma:** másold a `Public/themes/ThinkDefault.json` fájlt saját néven ugyanabba a könyvtárba. Adj új integer téma-ID-t, legalább egy palettát és egy vagy két támogatott módot. Az új JSON-t a Vapor induláskor olvassa be. A formátum gépi leírása a [theme.schema.json](theme.schema.json). A futó példák a [témakönyvtárban](../Public/themes) találhatók.

| Mező | Jelentés |
|---|---|
| `version`, `id`, `name` | Formátumverzió (1), stabil témaazonosító, megjelenített név. |
| `modes` | `["light","dark"]`, vagy egyetlen támogatott mód. Az első az export alapértelmezése kliensmód hiányában. |
| `palettes[]` | Minden paletta saját integer ID-t, nevet és 8–64 színt kap. Az ID-k a témán belül egyediek. |
| `colors[]` | Egyedi ID 0–63 között, fantázianév és legalább egy hatjegyű `light` vagy `dark` HEX. Egyetlen változat mindkét módban használható. |

A 0–7 ID minden palettában kötelező. Sorrendben a lap, tinta, felület, körvonal, kiemelés, majd három hangsúlyszín szerepét kapják. A 8–63 ID szabad. A név és a sorrend változhat. Új palettában hiányzó opcionális ID esetén a mező szerepszíne jelenik meg, az eredeti ID a dokumentumban marad.

## Grafika

A `graphics` opcionális. `panelRadius` (0–32 px), `glow` (0–24 px) és `selection` (0–7 szín-ID) a munkalap felületét állítja. A `grid` lehet `dots` vagy `lines`. A `motionSpeed` a dobozanimációk sebességszorzója (0,1–5). A külön `css` objektum a panelek stílusát írja le. A `surface` palettaszín-ID, a `borderWidth`, `padding` és `shadow` pixelérték. A `font` lehet `system`, `mono` vagy `serif`. Ezek csak a munkalap paneljeire érvényesek.

A `box` a standard dobozalak, a `line` a standard vonaltípus. A támogatott értékek a sémában szerepelnek. Sokszögű dobozhoz a `contour` 3–32 konvex csúcspontot fogad, képernyőkoordináták szerint az óramutató járásával megegyező sorrendben. A középpont legyen a sokszög belsejében. Az x és y egysége a fél szélesség és a fél magasság. A VectorStudio témában működő példa látható. A téma saját vonalához a `linePoints` 1–12 köztes töréspontot adhat meg. Az x a kezdőponttól a végpontig mért hányad, az y az arra merőleges eltolás a vonal hosszának arányában. A `junction` lehet ellipse, diamond vagy rectangle. A `junctionSize` az új csomópontok átmérője a vászon egységeiben.

## Használat és ellenőrzés

A létrehozó a vászon tulajdonságpaneljének **Megjelenés** csoportjában választ. Az oldal saját választója a főoldal fejlécében van. Az öröklés sorrendje: munkalap → oldal → operációs rendszer. Az aktuális szerkesztési jogosultsággal rendelkező felhasználók a színnégyzet megnyitása után a kiválasztott palettáról színezhetnek.

A munkalap azonosítókat tárol, például `"appearance":{"theme":3,"palette":1,"mode":"auto"}` és `"fill":2`. Az SVG-export konkrét színeket ír ki. Automatikus módú lap közvetlen exportjánál a `?mode=dark` vagy `?mode=light` megadja az oldal módját. Fix munkalapmód elsőbbséget élvez.

A demó útvonala `/ThemeDemo`. Az admin nevű létrehozó szerkesztheti a három lap megjelenését. Egy új témát világos és sötét környezetben, másik szerkesztővel, fájldobozon, csatlakozási pontokon és SVG-exportban is ellenőrizz.
