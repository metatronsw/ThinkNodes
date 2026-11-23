# Hibák

Minden munkamenet elején át kell nézni, és a nyitott hibákkal foglalkozni kell (AGENTS.md).

## Nyitott

- **A munkalap minden presence-kérésnél teljes lemezolvasással töltődik be** (2026-11-23, teljesítmény)
  - A `Collaboration.presence` minden `poll`/`select`/`ping` műveletnél `store.load`-ot hív (beállítások, házirend-lánc, munkalapfájl dekódolása és validálása, mappa listázása), a két globális zár alatt. N résztvevőnél egy mentés N teljes betöltést indít sorban.
  - Az optimalizálási tervben szerepel (memóriabeli munkalap-gyorsítótár); megbeszélendő.

## Javítva

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
