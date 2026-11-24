# Változások

## 2026-11-24 – Swift-modulok: ThinkCore és ThinkNodes

- A `ThinkNodes` futtatható modul kettévált. Új `ThinkCore` könyvtár: Model, Rendering, Theme, WebPresentation, ProjectPackage, TableFiles, NodeTypes, WorksheetFile, WorksheetLink, CanvasMarkdown, PageUpdates. A `ThinkNodes`-ban marad: Server, Collaboration, LinkPreview, Launch, LANCertificate.
- A szerver által használt mag-deklarációk `package` láthatóságot kaptak (a többi `internal` maradt). Explicit `package init` a memberwise inicializáló pontos másaként: `Worksheet`, `User`, `UserPreferences`, `SiteSettings`; továbbá `PageUpdates.init()`, `WebPresentationSessions.init(requireCookie:)`. Az `encodeQuery` a `Server.swift`-ből a `Rendering.swift`-be került. Más tartalmi változás nincs (a `package ` nélküli összevetés szerint).
- Tesztek: `@testable import ThinkCore` is; a `test.sh` útvonal-hozzárendelése mindkét modulra illeszkedik. 67 Swift teszt rendben.
- Release build egy módosítás után: szerverréteg 85 → 25 s, mag 85 → 65 s, változás nélkül 34 → 9 s. A debug build változatlan (9–13 s).

## 2026-11-24 – Témakörönkénti tesztfuttatás, gyorsabb típusellenőrzés

- Új `server/test.sh`: a commitolatlan módosításokból (vagy `--since REF`, illetve megadott témák alapján) csak az érintett Swift- és JS-teszteket futtatja; `--all`, `--swift`, `--js`, `--list`. Mindig debug build, ugyanazokkal a cache-útvonalakkal, mint a `deploy/build.sh`; a Vapor kérésnaplóját elrejti.
- A `Tests/ThinkNodesTests/WorksheetTests.swift` (1408 sor, 39 teszt) témák szerint szétbontva: `WorksheetTests`, `RenderingTests`, `CollaborationTests`, `AccessTests`, `AttachmentTests`, a közös HTTP-segédfüggvények a `HTTPTestSupport.swift`-ben. A tesztek tartalma változatlan.
- Lassú típusellenőrzésű kifejezések átírva (viselkedés változatlan): `VisualTheme.valid` (egy ~20 tagú `&&`-lánc → lépésenkénti `guard`), vegyes típusú tömb-összefűzések (`WebPresentationReference`, `CanvasFile.validSource` / `commonURL` / `sheet(from:)`), `CommonLibrary.list`, `number()`. A ThinkNodes modul típusellenőrzése 14,0 → 8,3 s (debug buildben érvényesül; a release build ideje, kb. 85 s, nem változott: ott az optimalizálás a meghatározó).
- Mérések: egy téma tesztje módosítás nélkül kb. 16 s (ebből kb. 7 s a SwiftPM üres buildje, kb. 7 s a tesztfolyamat indítása), az összes teszt kb. 20 s; Swift-fájl módosítása után a debug build kb. 10 s.
- README: `test.sh` és a debug binárissal történő helyi fejlesztés leírása.

## 2026-11-24 – Futtatókörnyezet áthelyezve a ~/X-Code/RunTime alá

- A Swift 6.0.3, a Node.js és a headless Chromium a `~/X-Code/RunTime/{Swift,NodeJS,Chromium}` alá került; az elérési utak frissítve:
  `server/deploy/build.sh`, `server/deploy/install.sh` (Swift, NodeJS `env.sh`), `server/Sources/ThinkNodes/WebPresentation.swift` (Chromium).
- A `~/X-Code/RunTime/NodeJS/env.sh` (a repón kívül) is az új helyre mutat.
- A `server/.build` a projekt korábbi helyére (`~/Work/ThinkNodes`) fordított, használhatatlan modul-cache-t tartalmazott; félretéve `server/.build.old-path` néven (törölhető), a build újra elkészült.
- Ellenőrzés: 67 Swift teszt rendben; JS: canvas-markdown, table-engine, table-fuzz rendben, `gestures.mjs` a BUGS.md-ben már nyilvántartott hibával bukik.
