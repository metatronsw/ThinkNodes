# Változások

## 2026-11-24 – Szövegfájl- és táblázatdoboz: palettát követő színek, keret nélküli módosító

- A szövegfájl-, kódfájl- és táblázatdoboz tartalma a szerkesztőben is a doboz szövegszínét használja (alapból a paletta 1-es színe), a háttér a doboz kitöltése (paletta 2), így világos és sötét módban is olvasható (`Public/editor.js` `renderFileBox`; a megjelenítő eddig is így működött).
- Új „Keret: be/ki” kapcsoló ezeken a dobozokon a Megjelenés panelen (`frame: false`), bármelyik háttérmóddal (Free = átlátszó, Üres, Elmosott, Áttetsző) kombinálható; a szerver oldali rajzolás is követi (`Rendering.swift` `boxSurface`). A táblázat Megjelenés paneljén Szövegszín választó.
- A táblázat szerkesztési módja (képletsor, oszlop- és sorfejléc, kijelölés, cellabevitel) rögzített fehér helyett a doboz hátteréből és szövegszínéből kevert színeket használ (`Public/app.css`, `--tn-paper`). A cellákra kézzel beállított színek változatlanok.
- Teszt: `textFileBoxFrameCanBeSwitchedOffInEveryBackgroundMode`; a Swift tesztek rendben (70). Böngészőben nem ellenőriztem: a helyi `projects` mappa üres volt, a JS tesztek pedig nem futottak (a `node` nincs a PATH-on). Doksi: `server/docs/node-types.md`.

## 2026-11-24 – Figyelmeztetés nem létező adatmappánál

- Ha a `--project:` mappa nem létezik, a szerver (és a `user` parancs) indításkor kiírja, hogy új, üres adatmappát hoz létre, és felsorolja a mellette lévő valódi ThinkNodes-adatmappákat (amelyekben van `.settings.json`), pl. elírásnál `ThinkProject` → `ThinkProjects`. Ez okozta a korábbi „nem lehet belépni” esetet is.
- Kipróbálva elírt és létező mappával (`user` paranccsal, szerver indítása nélkül); Swift tesztek rendben.

## 2026-11-24 – Debug build jelzése a nyitóoldalon

- Debug buildben a nyitóoldal jobb alsó sarkában figyelmeztető jelvény: „Debug build” és az adatmappa valós útvonala (szimbolikus linkek feloldva). Release buildben a jelvény nem kerül az oldalba (`#if DEBUG`, `Server.swift` `debugBadge`; stílus: `Public/app.css` `.debug-badge`).
- Teszt: `debugBuildShowsBadgeWithRealDataFolder`; böngészőben ellenőrizve (debug: látszik, release: nincs).
- `.claude/launch.json`: új `thinknodes-debug-test` konfiguráció (`run.sh --debug … --test`).

## 2026-11-24 – run.sh: futó példányok listája, foglalt port és adatmappa ellenőrzése

- A `server/run.sh` indítás előtt kilistázza a gépen futó ThinkNodes-szervereket (PID, felhasználó, port, adatmappa; a systemd `thinknodes.service` jelölve). A `ps -eo` minden felhasználó folyamatát látja, így a `thinknodes` felhasználóként futó daemon is megjelenik.
- Nem indul, ha a port foglalt (ThinkNodes vagy más program; utóbbinál `lsof`-fal kiírja, mi foglalja), vagy ha egy másik példány ugyanazt az adatmappát használja. Javasol szabad portot.
- Javítás: a relatív `--project:`, `--tls-dir:`, `--tls-cert:`, `--tls-key:` útvonalak eddig a `server/` mappához képest értelmeződtek (a `run.sh` `cd`-je miatt), most a hívó mappájához képest, ahogy a súgó írja; a `~/` is kibontva.
- Kipróbálva: két példány (8888 + 8889), azonos port, azonos adatmappa, idegen program a porton, relatív `--project:`, `user` parancs.

## 2026-11-24 – Adatmappa kiírása, figyelmeztetés fiók nélküli adatmappánál

- Ok (a `--project:~/Project/ThinkProject` „nem működött”): a kapcsoló jó volt, de az új, üres adatmappában nincs `.settings.json`, így felhasználói fiók sincs, a belépés ezért nem sikerült.
- Indításkor a szerver kiírja az adatmappát (`Data folder: …`); ha nincs egyetlen fiók sem (és nem tesztmód), kiírja, hogyan hozható létre az első admin (`./run.sh user NAME admin --project:…` vagy helyi böngészőből `/admin`). A `user` parancs is kiírja, melyik adatmappába mentett.
- A login oldal fiók nélküli adatmappánál figyelmeztet (helyi gépről linkkel az `/admin` oldalra). Teszt: `loginPageWarnsWhenTheDataFolderHasNoAccounts`.

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
