# Hibák

Minden munkamenet elején át kell nézni, és a nyitott hibákkal foglalkozni kell (AGENTS.md).

## Nyitott

## Javítva

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
