# ThinkNodes munkalaptémák – kivitelezési terv

## Adatformátum

A Public/themes/<témanév>.json egy témát ír le. Az integer téma-ID globálisan egyedi, a paletta-ID a témán belül egyedi. A fantázianév és a fájlnév átnevezhető. A paletta szín-ID-ja stabil azonosító, a JSON-beli sorrend csak a választó sorrendje. Egy minimális ThinkDefault témadefiníció például:

```json
{
  "version": 1,
  "id": 1,
  "name": "ThinkDefault",
  "modes": ["light", "dark"],
  "palettes": [{
    "id": 1,
    "name": "Műhely",
    "colors": [
      {"id": 0, "name": "Papír", "light": "#F5F8FC", "dark": "#171E28"},
      {"id": 1, "name": "Tinta", "light": "#202D41", "dark": "#E4ECF7"},
      {"id": 2, "name": "Porcelán", "light": "#FFFFFF", "dark": "#263240"},
      {"id": 3, "name": "Grafit", "light": "#536780", "dark": "#A8B8CC"},
      {"id": 4, "name": "Kobalt", "light": "#304CCC", "dark": "#92ABFF"},
      {"id": 5, "name": "Moha", "light": "#317154", "dark": "#86CDA6"},
      {"id": 6, "name": "Borostyán", "light": "#925C19", "dark": "#F0BB77"},
      {"id": 7, "name": "Korall", "light": "#A64554", "dark": "#F296A4"}
    ]
  }]
}
```

A nyolc közös ID szerepe rendre háttér, szöveg, felület, körvonal, kiemelés és három további hangsúlyszín. A többi hely opcionális, összesen 8–64 szín lehet. Legalább egy HEX-érték kell színenként. Ha csak az egyik van meg, mindkét mód azt használja. Többszörös ID, két hiányzó változat vagy hibás HEX esetén a témabetöltő megnevezi a fájlt és a mezőt. Hibás téma mellett a többi érvényes téma használható marad.

A munkalap például `"appearance":{"theme":1,"palette":1,"mode":"auto"}` beállítást tárol. A színmezőkben, a szövegstílusokban és a végpontoknál is integer azonosító szerepel. Palettaváltás változatlanul hagyja ezeket. Ha egy opcionális ID hiányzik a célpalettából, a renderer az adott mező szerepe szerinti alapszínt használja (például feliratnál Tintát). Visszaváltáskor visszatér az eredeti szín. A régi projekteket nem írjuk át.

## Mód, jogosultság és felület

- Az oldal saját light/dark/auto választást tárol. Auto esetén a böngésző rendszerbeállítását követi, annak változásaira is reagál.
- A munkalap közös téma-, paletta- és módbeállítását csak a munkalap létrehozója módosíthatja. Ezt a Vapor szerver minden mentési útvonalon ellenőrzi, az élő együttműködés, import és visszaállítás útvonalait is beleértve. Más szerkesztő a saját munkáját mentheti és választhat objektumszínt. Egy időközben beérkező mentés nem állíthatja vissza véletlenül egy korábbi témára a lapot.
- A canvas property panelen a létrehozó kiválasztja a témát, azon belül a palettát, majd a módot. A többiek látják az aktuális választást. Explicit light/dark esetén mindenki ugyanazt látja. Auto esetén a közös szabály minden kliensen annak saját oldalmódját követi. Egymódú témánál mindig az egyetlen támogatott mód érvényesül.
- A property panelen a lekerekített színminta kattintásra megnyitja az aktív paletta rácsát. A négyzeteken az aktuális mód színe látszik. A kijelölést pipa, a fantázianevet súgó és akadálymentes címke jelzi. A választó billentyűzettel is kezelhető. Az RGB-csúszkákat és a szabad színbevitelt ez a választó váltja fel.

## Grafikai megvalósítás

A téma opcionális, deklaratív beállításai adják a munkalapra korlátozott CSS-változókat, a panel felületét, keretét és lekerekítését, a kijelölés szín-ID-ját és a glow erősségét. A vonalak, csomópontok és dobozok alakját közös geometrialeírásból rajzolja a szerkesztő és a Swift-renderelő. A kapcsolat végpontjait és a kattintható területet ugyanebből az alakból számítjuk. Az animációknál a téma a meglévő effektusok időzítését és paramétereit állíthatja. A munkalap témája a weboldal navigációját és adminfelületét nem színezi át.

Ugyanazok a feloldási szabályok érvényesek az editorban, a megtekintőben, az előnézetben és az SVG-exportban. Auto módú exportnál a böngésző átadja az éppen megjelenített módot. Közvetlen export-URL esetén, ha sem kérésből, sem rögzített módból nem állapítható meg a kliens megjelenése, a téma első támogatott módját használjuk. A letöltött SVG a színeket konkrét HEX formában tartalmazza, önállóan megnyitható.

## Három szállítandó téma

| Téma | Világos / esti háttér | Világos / esti kiemelés | Karakter |
|---|---|---|---|
| ThinkDefault | #F5F8FC / #171E28 | #304CCC / #92ABFF | A jelenlegi világos megjelenés és hozzá tervezett esti párja. |
| VectorStudio | #FAF9F6 / #191821 | #6543C8 / #B9A3FF | Precíz ívek, tiszta kontúrok, kevés hangsúlyszín. Inspiráció: https://vectorizer.ai/ |
| Blueprint | #EFF4F5 / #102A40 | #186487 / #88D5EE | Rajzlap és éjszakai tervrajz, finom raszter, vékony szerkesztővonalak, derékszögű panelek, minimális glow. |

## Kivitelezés és átvétel

1. Témakatalógus, verziózott JSON-séma, validálás, integer tárolás és mód-/színfeloldás.
2. Létrehozói jogosultság, közös állapot mentése és élő szinkronizálása.
3. Canvas property vezérlők, palettaválasztók, három kész téma, az oldal külön módválasztója.
4. Megtekintő, előnézet és önálló SVG-export bekötése.
5. Új demóprojekt három összehasonlítható munkalappal. Legalább egy téma két választható palettát kap. A demó dobozokat, feliratokat, csomópontokat, nyilakat és szöveges fájlt is bemutat.
6. Rövid témakészítési útmutató, géppel ellenőrizhető séma és másolható működő példa. Átvételkor két eltérő jogosultságú munkamenetben ellenőrizzük a módosítást és a szinkront, továbbá a világos/sötét/auto öröklést, az egymódú témát, a 8 és 64 színes palettát, a hiányzó változatot/ID-t, a mentés–újranyitást és az SVG színegyezését.
