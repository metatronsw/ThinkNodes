# Hibák

Minden munkamenet elején át kell nézni, és a nyitott hibákkal foglalkozni kell (AGENTS.md).

## Nyitott

- **A Swift `JSONDecoder` egyes lebegőpontos literálokat 1 ulp pontatlansággal olvas (macOS 13 Foundation)** (2026-11-24, tizedes-audit)
  - Példa: `0.0020293361140076467` → `0.0020293361140076476`. A `.tntable` értékei a szerveren az utolsó bináris jegyben elcsúszhatnak (a kiírt 15 jegyre nincs hatással).
  - Teszt: `platformJSONDecoderDoublePrecision` (figyelmeztet). Teendő: ellenőrizni élesben (Fedora, swift-foundation); ha ott is pontatlan, saját számolvasó a `.tntable`-höz. Részletek: server/docs/EXCEL.md 12. fejezet.

- **Sötét kitöltésű szövegfájl- és táblázatdobozon a tartalom olvashatatlan** (2026-11-24, a táblázat tesztelésekor)
  - A `.node-note` szövegszíne rögzített sötét (`rgb(24, 35, 53)`), a doboz kitöltése viszont a palettából jön; a szerver által automatikusan felvett fájldobozok (`fill: "@2"`) sötét témában sötétek, így a tartalom nem látszik (pl. `MassTest/TablaTeszt`: `lista.csv`, `feltoltott.tntable`).
  - Dönteni kell: a fájl „lapja” mindig világos papír legyen (a hajtott sarkú lap mintájára), vagy a szövegszín kövesse a doboz kitöltését.

- **`Tests/Editor/gestures.mjs` elbukik** – már a TODO.md-ben is szerepel (`ownUnderlay`); a táblázat munka előtt is így volt (2026-11-24, ellenőrizve az eredeti `editor.js`-szel).
  - `markdownEditor` `adjust`: a teszt hamis DOM-jában a `getComputedStyle` / `el.style` hiányzik (`reading 'height'`).
  - 311. sor: `button("Mentés")` nem található (a Mentés gomb azóta átalakult).


## Javítva

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
