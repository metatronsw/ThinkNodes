# Típusrendszer átépítése – haladási napló

Terv: `docs/node-types.md`. Kiinduló commit: `668d2b1`. Ha a munka megszakad: olvasd el ezt a fájlt,
nézd meg a `git status`/`git diff`-et, és a első nem kipipált lépéstől folytasd.
A végén: tesztek, szerver újraindítása (`thinknodes-test` launch config, 8888-as port), a felhasználó átnézi.

## Adatformátum (schemaVersion 3)

Objektum (`nodes[]`), JSON-kulcsok:

| Kulcs | Jelentés |
|---|---|
| `id`, `pos`, `w`, `h`, `parent`, `locked`, `elevated` | mint eddig |
| `type` | `box`, `text`, `code`, `csv`, `image`, `document`, `audio`, `junction` (alkategória: `code`, `csv` → `base: text`) |
| `text` | box: markdown szöveg; junction: címke; fájltípusok: megjegyzés (markdown) |
| `fontSz`, `textCol`, `bold`, `italic`, `underline`, `align`, `vAlign`, `justified`, `fitText` | szövegstílus (box teljes; fájltípusoknál a megjegyzés igazítása `align`) |
| `hideText` | box: összecsukás (csak az első sor); fájltípus: megjegyzés elrejtése |
| `shape`, `fill`, `backgroundMode`, `animation` | box megjelenés (fájltípusnál `fill`, `backgroundMode`) |
| `file` | `{asset, filename, ext, showFilename, alphaEnabled, alphaBackground, rev}` |
| `link` | `{kind: "url" \| "sheet" \| "web", target}` |
| `angle` | junction címke elforgatása fokban |
| `container` | box: konténer (egyszer belehúztak valamit; kiürülve is az marad, mint régen a `kind: container`) |

Megszűnik: `title`, `kind`, `file.type`, `file.webPath`, `file.hideTitle`, `textStyle`, `titleOutside`,
`backgroundEnabled`, `backgroundBlur`. A régi (schemaVersion 2) munkalapot a szerver nem tölti be.

Szövegfájl (`text`/`code`/`csv`) tartalma csak a fájlban van; a szerkesztő automatikusan menti (PUT), utána
`file.rev`-et növel, a többiek ebből tudják, hogy újra kell tölteni.

Típusregiszter: `Public/node-types.json` (szerver: `NodeTypes.swift`, kliens: `Public/node-types.js`).

## Lépések

- [x] 1. Típusregiszter (JSON + Swift + JS betöltő)
- [x] 2. Swift modell: `Idea` új mezők, validálás, schemaVersion 3, régi migrációs kód törlése
- [x] 3. Szerver: import / fájltípus-felismerés (szöveg tartalom alapján, hangformátumok, dokumentum)
- [x] 4. Szerver renderelés: box szöveg (markdown címsorszintek, listajel, B/I/U ráadás), fájl fejléc + megjegyzés,
      link jel alul középen, link fajták (web előnézet, munkalap előnézet), junction elforgatás, code/csv
- [x] 5. Szerkesztő: modell, létrehozás, beillesztés (szöveg → box, URL → linkes box, drag&drop URL), import
- [x] 6. Szerkesztő renderelés (a szerverrel egyezően)
- [x] 7. Tulajdonságpanel képességekből; többes kijelölés közös képességekkel; link hozzáadás/törlés; canvas panel előnézet
- [x] 8. Megtekintő (viewer.js), egyéb kliens modulok
- [x] 9. Tesztek frissítése (Swift, gestures.mjs)
- [x] 10. Helyi Projects adatok törlése / újralétrehozása, szerver újraindítása, böngészős ellenőrzés

## Napló

- Szerver kész és lefordul (1–4.): `NodeTypes.swift`, `Model.swift` (Idea: type/link/angle; schemaVersion 3; régi migráció törölve;
  reconcile a regiszter szerint osztályoz), `Rendering.swift` (box szöveg: `ideaDrawing`/`nodeSVG`; fájlok: `fileBox`, `fileTextHTML`, `parseCSV`;
  link: `linkMarker`, `target()`), `CanvasMarkdown.swift` (blokk: `level`, `indent`), `Server.swift` (`fileTexts` a megtekintőnek és az SVG-exportnak).
  A box szöveg alapmérete `fontSz` (16). Fájlobjektum CSS-osztályai: `node-file node-<root>`, `node-file-name`, `node-body`, `node-comment align-*`,
  `node-document`, `node-code`, `node-csv`, `node-plain`, `node-link-caption`. Kliens még NINCS átírva.
- Kliens kész (5–8.): `node-types.js`, `geometry.js` (`labelLayout`, `linkCaption`), `canvas-files.js` (`importFile` a regiszter szerint,
  `nodeName`, `fileNameParts(file, image)`), `editor.js` (`renderNode`, `renderFileBox`, `renderLinkMarker`, `linkDestination`, `nodePanels`,
  `edgePanels`, `markdownEditor`, `addLink`/`removeLink`, `fileTexts` + `editFileText` automatikus mentés), `viewer.js` (kattintásra nyíló link),
  `audio-player.js` (idő, egyszerre egy), `app.css` (új fájlobjektum-osztályok a végén), `icons.svg` (heading, list, code, more, rotate).
  Következő: 9. tesztek (Swift `Tests/ThinkNodesTests`, `Tests/Editor/gestures.mjs`), 10. helyi Projects adatok + szerver.
- Tesztek (9.): Swift 40/40, `gestures.mjs` zöld (új: URL-beillesztés → linkes doboz, link törlése, típusfelismerés, címsorszintek).
  A `container` jelző visszakerült (a konténer kiürülve is konténer marad, ahogy a terv kérte).
  Ismert dokumentum-kiterjesztés (pdf, docx, zip…) mindig `document`, tartalomtól függetlenül.
- Adat (10.): a helyi Projects munkalapjai kiürítve, schemaVersion 3; a régiek mentése: `Projects/.trash/schema2-backup/`.
  `asd` és `weblap` bemutató objektumokat kapott minden típusból. Szerver: `thinknodes-test` (8888).
- KÉSZ. Következik: a felhasználó átnézi, utána módosítások.
