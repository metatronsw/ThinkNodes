# Változások

## 2026-11-24 – Táblázat / CSV: a többi résztvevő látja a cellakijelölést

- Amíg valaki egy táblázat- vagy CSV-doboz celláit szerkeszti, a többi szerkesztő az olvasó nézetben látja a kijelölt tartományt (az illető színével árnyalva), az aktív cellát (keret) és azt, hogy éppen szerkesztés alatt áll-e (szaggatott keret). A gépelt szöveg nem megy át, az érték a szokásos mentéssel érkezik.
- Új, rövid életű üzenet az élő csatornán (`cells`, `Collaboration.swift` `CellMark`; kliens: `live.cells`, `peerCells`, `peerMark`). Csak az küldheti, aki a dobozt fogja; a később csatlakozók megkapják az aktuális állapotot; kilépéskor, a doboz elengedésekor és a kapcsolat bontásakor törlődik. Legfeljebb 80 ms-onként megy ki.
- Nem része: a megtekintő (csak a szerkesztőben látszik), és a görgetési helyzet követése (külön tétel a TODO.md-ben) – a kijelölt cella a másik félnél lehet a látható részen kívül.
- Ellenőrizve két böngészőlappal (Chromium, mérő-adatmappa): szerkesztett cella, tartomány, törlés kilépéskor. A szerver kódja változott (újrafordítva, újraindítva). Tesztek: az érintett Swift tesztek és a három JS teszt rendben; `gestures.mjs` változatlanul bukik.

## 2026-11-24 – Táblázat / CSV: a kattintott cella nyílik meg, nincs villanás, gyorsabb frissítés

- Dupla kattintásra az a cella nyílik meg szerkesztésre, amelyik fölött kattintottak, és a képernyőn a helyén marad (`clickedCell`, `gridOffset`). A cellát a doboz vászonbeli helyéből és a táblázat elrendezéséből számoljuk, nem találatvizsgálatból. A panelről vagy menüből indított szerkesztés az olvasó nézet görgetési helyzetét veszi át; kilépéskor az olvasó nézet ott folytatódik, ahol a szerkesztő állt.
- Dupla kattintásnál a tulajdonságpanel fájlnév-mezője már nem veszi el a fókuszt a megnyitott cellától.
- Más résztvevő mentése után a doboz nem villan üresre („…”): az új fájlváltozat betöltéséig a régi tartalom marad látható, a görgetési helyzettel együtt (`lastFileTexts`; szövegfájlra is érvényes).
- Cellaszerkesztésnél a mentés késleltetése 1,5 mp helyett 0,25 mp. Két böngészőlappal mérve a másik résztvevőnél kb. 0,6 mp-en belül megjelent az új érték, üres állapot nélkül.
- Ellenőrizve Chromiumban a mérő-adatmappán; Safariban nem. Csak kliensoldali változás (a szerver kódja nem változott).

## 2026-11-24 – Vászon nézetkorlátok, közvetlenül szerkeszthető CSV, táblázat- és dobozjavítások, főoldal

A felhasználói lista „-” jelű tételei; a „+” jelűek megbeszélésre várnak (TODO.md „Megbeszélendő”).

**Vászon (szerkesztő)**
- Legnagyobb nagyítás 800% (eddig 400%). A legkisebb nagyítás a kompozíciótól függ: a teljes tartalom ekkor a képernyő negyedét tölti ki (oldalanként a felét); a 100% mindig elérhető.
- Pásztázni bármelyik irányba addig lehet, amíg a legszélső objektum éppen eltűnik a képernyő szélén (egér, görgő, érintés, szóköz+húzás; `constrainView`, `contentBox` az `editor.js`-ben).
- Betöltéskor és a „Mind” gombnál a kompozíció (az objektumok határoló dobozának) közepe kerül a képernyő közepére, mint a megtekintőben – eddig a vászon origója.
- A nagyítás értéke a vászon alján, középen jelenik meg (külön komponens, nem rajzolja újra a szerkesztő gyökerét).
- Görgethető tartalom (szövegfájl, CSV, táblázat) egérgörgővel csak a kijelölt dobozban görög; nem kijelölt doboz fölött a görgő a vásznat nagyítja.

**Táblázat**
- A táblázat szélessége rögzített (az oszlopszélességek összege): a félkövér betű már nem szélesíti az oszlopot (szerkesztő és szerver: `TableHTML`).
- Felülvonás helyett áthúzás (a fájlbeli `o` kulcs maradt; a régi felülvont cellák áthúzva jelennek meg). Az igazítás gombjai a szövegeknél megszokott ikonokat kapták, az Alaprács ikonja valódi rács (`table-grid`).
- Táblázat nem kaphat elmosott hátteret. Szerkesztés közben nem jelenik meg a rejtett Text buboréksúgója.
- Új háttérmód: „Vászonszín” (`backgroundMode: "canvas"`) táblázatra, CSV-re és képre (átlátszó kép, SVG): a doboz a munkalap háttérszínét mutatja, a vászon rácsa nem látszik át. Szerver: `BoxBackgroundMode.canvas`, `Rendering.swift`.
- Új gomb a panelen (táblázat és CSV): a doboz átméretezése a tartalom tényleges méretére (`fitBoxToContent`; legfeljebb 4096 × 4096).
- Megtekintő: a szövegfájl-, CSV- és táblázatdoboz tartalma kilógott a dobozból, és a táblázat cellaformázása sem érvényesült, mert az oldal tartalombiztonsági szabálya (`style-src 'self'`) nem engedi a szerver által beírt `style` attribútumot. A `viewer.js` most szkriptből állítja be ezeket.

**Önálló CSV**
- A CSV cellái közvetlenül a vásznon szerkeszthetők (dupla kattintás; kijelölés, törlés, átírás, beillesztés), formázás és képletek nélkül (`TableEditor` `plain` mód). Mentéskor az eredeti elválasztó, a sorvégek és a soronkénti mezőszám megmarad; korlát 1000 sor × 100 oszlop.
- A tulajdonságpanelen megszűnt a CSV tartalmának szövegszerkesztője (a Text megjegyzés maradt).

**Dobozok**
- Külső vizuális tartalom (kép, SVG, weboldal- és munkalap-előnézet) egységesen 5 px lekerekítést kap (szerkesztő, megtekintő, szerver).
- A buboréksúgó követi a szöveg igazítását (bal / közép / jobb); a megtekintőben a sablon `data-align` mezőjéből.

**Főoldal**
- Az Új projekt / Projekt importálása külön szekcióban áll, vonallal elválasztva a projektektől.
- Vendégeknek (nincs bejelentkezve, vagy vendég szerepkör) tájékoztató: létrehozáshoz és szerkesztéshez be kell jelentkezni, és csak a publikus projektek láthatók.

**Ellenőrzés:** Chromiumban, tesztmódban, a mérő-adatmappán (`server/.build/perf-data`): nagyítási és pásztázási korlát, kezdő nézet, görgetési szabály, táblázat (félkövér, áthúzás, méretre igazítás), CSV szerkesztése és a mentett fájl, vászonszín (szerkesztő és megtekintő), megtekintőbeli kilógás, főoldal, súgóigazítás; a vendégtájékoztató tesztmód nélküli szerveren. Safariban nem ellenőriztem. Tesztek: 72 Swift teszt, `table-engine`, `table-fuzz`, `canvas-markdown` rendben; a `gestures.mjs` ugyanott bukik, ahol eddig (BUGS.md). A szerver kódja változott (újrafordítva, újraindítva).

## 2026-11-24 – Teljesítményjavítás a vászonszerkesztőn (a `perf` ág beolvasztva a `main`-be)

- Négy egymásra épülő változat (A–D), mind beolvasztva az alapbeállításokkal (a mérésben leggyorsabb kombináció), kapcsolható kísérleti beállításokkal (`localStorage.tnPerf`); mérések, okok, eredménytáblák: `server/docs/PERF.md`.
- Fő eredmények Safari 18.6-ban, release szerveren (300 / 1000 doboz): kijelölés késése 108 → 26 ms / 312 → 28 ms; gyors pásztázás 49 → 60 fps / 21 → 51 fps; lassú nagyítás 17 → 53 fps / 11 → 44 fps; csoport húzása 17 → 48 fps / 8 → 25 fps; másik felhasználó húzása közben 36 → 60 fps.
- Nem javult eleget: a nagyítás végi újrafestés (80–190 ms) és a táblázat szerkesztési módjának görgetése (~50 fps).
- Új mérőeszközök: `server/Tests/Perf/` (adatgenerátor, Safari-mérő, képkocka-rögzítő, második felhasználó); új indítási beállítás: `thinknodes-perf`.
- Tesztek: `table-engine`, `canvas-markdown` rendben; a `gestures.mjs` egy állítása a kurzor-pajzshoz igazodott, a teszt ugyanott bukik, ahol eddig. Swift-kód nem változott.

## 2026-11-24 – Más által fogott fájldoboz nem görgethető

- Ha egy szövegfájl-, CSV- vagy táblázatdobozt másik felhasználó fog, a tartalma nem görgethető: sem a natív, sem a Safaris saját görgetősáv nem húzható (`Public/app.css`, `.node.occupied`). A görgő eddig is csak a saját kijelölt dobozon görgetett.
- Két böngészőlappal ellenőrizve (Chromium); Safariban nem próbáltam ki külön.

## 2026-11-24 – Safari: saját görgetősáv a fájldobozokon, kattintható táblázatszerkesztő

- Ok: Safariban (WebKit) az SVG-transzform alatti foreignObject-ben a natív görgetősáv nem húzható, és a sávra nyomott egér mozgását a lap sem kapja meg. Ezért WebKitben a szövegfájl-, CSV- és táblázatdoboz (megjelenítés és cellaszerkesztés) natív sávja rejtve van, helyette az elem mellett saját sávok állnak: a hüvelyk húzható, a sínre kattintva odaugrik (`Public/scrollbar-drag.js`; bekötve: `editor.js`, `table/table-view.js`, `viewer.js`; stílus: `app.css` `.tn-sb*`). Más böngészőben nincs változás.
- A táblázatszerkesztő gyökere (`.tn-table-editor`) és a billentyűzet-nyelő már nem pozicionált: Safariban emiatt a szerkesztőben semmi nem volt kattintható. A rács új tartót kapott (`.tn-table-scroll-host`).
- A korábbi két kísérlet (sáv felismerése vászonkoordinátából, védelem a `pressNode`-ban) bent maradt, a többi böngészőben ez dönti el, hogy a doboz húzása vagy a görgetés indul.
- Ellenőrizve automatizált Safari 18.6-ban és Chromiumban; JS tesztek (`table-engine`, `canvas-markdown`) rendben. Nyitva maradt: BUGS.md (oszlopszélesség-fogó Safariban, megjelenítő).

## 2026-11-24 – Hozzáférés-kérés Google-fiókkal, adminisztrátori jelzések, meghívási szabály

- **Hozzáférés-kérés.** Ismeretlen, a Google által igazolt címmel belépett látogató a `/login/request` oldalon kérelmet adhat be (kért felhasználónév). Az admin a Beállítások oldal „Hozzáférési kérelmek” paneljén jóváhagyja (felhasználónév, szerepkör; meglévő, Google-fiók nélküli felhasználó nevével a cím ahhoz kapcsolódik) vagy elutasítja; az elutasítás feloldható. Alapból kikapcsolva; az adminoldalon kapcsolható és e-mail-domainekre szűkíthető. Korlátok: címenként egy kérelem, legfeljebb 50 függő, 30 nap után lejár. Tárolás a `.settings.json`-ban (`googleAccess`, `accessRequests`, `rejectedGoogle`). Útvonalak: `GET/POST /login/request`, `POST /admin/requests`.
- **Adminisztrátori jelzések** (`AdminMessage`, `WorksheetStore.adminMessages()`): közös lista az adminokra váró teendőkről, későbbi fajtákkal bővíthető. A fejléc Admin gombján jelvény mutatja a darabszámot (minden oldalon), az adminoldal tetején „Teendők” panel. Most a függő hozzáférés-kérelmeket jelzi.
- **Új szabály: projektbe csak a létrehozója és az admin hívhat meg szerkesztőt** (és távolíthat el). Eddig bármelyik meghívott szerkesztő is megtehette. Új `DocumentAccess.invitable`; a `grant`/`revoke` művelet, az `/api/worksheet-users` és a „Szerkesztők kezelése” gomb/menüpont (`Public/cards.js`, `data-invite`) ezt követi. Fiók-szerepkört továbbra is csak admin ad; meghívni csak szerkesztő szerepkörű fiókot lehet.
- Javítás: szűk képernyőn a Google-fiók mezős felhasználósor nem váltott egyoszlopos elrendezésre (`app.css`).
- Tesztek: `unknownGoogleAccountCanRequestAccess`, a `projectPoliciesFollowDirectory` és a `worksheetRoundTrip` kiegészítve; 72 Swift teszt rendben. Böngészőben ellenőrizve (tesztmód, mintakérelmek): jelvény, „Teendők”, kérelmek panelje. Nem ellenőrzött böngészőben: a kérelem oldala és a „Szerkesztők kezelése” menüpont elrejtése (a `cards.js` módosítása); valódi Google-klienssel továbbra sem futott.
- Dokumentáció: `server/deploy/GOOGLE.md` („Hozzáférés-kérés”), README („Szerepkörök és meghívás”).

## 2026-11-24 – Google-bejelentkezés: éles beállítási útmutató, daemon.sh

- Új `server/deploy/GOOGLE.md`: a Google-bejelentkezés beállítása a Fedora szerveren (OAuth-kliens létrehozása, visszatérési cím, `thinknodes.env`, fiókok hozzárendelése, működés, hibakeresés, biztonság).
- `server/deploy/daemon.sh`: létrehozza a `/var/lib/thinknodes/thinknodes.env` beállítófájlt kommentezett mintasorokkal (`0600`, `thinknodes`), ha még nincs; a meglévőt nem írja felül. A végén kiírja a beállítófájl helyét és a Google-bejelentkezés állapotát. Csak szintaxisellenőrzés futott (`bash -n`), Fedorán nem próbáltam ki.
- Helyben a Google-bejelentkezés nem lesz használva; a helyi teszthez készített `server/.google.env` törölve.
- TODO.md: hozzáférés-kérés Google-fiókkal (javaslat).

## 2026-11-24 – Google-bejelentkezés

- Új `server/Sources/ThinkNodes/GoogleSignIn.swift`: OpenID Connect „authorization code” folyamat PKCE-vel, state és nonce ellenőrzéssel. Útvonalak: `GET /login/google` (átirányítás a Google-hoz), `GET /login/google/callback` (kódbeváltás, ID token ellenőrzése: kibocsátó, címzett, lejárat, nonce, igazolt e-mail).
- Bekapcsolás környezeti változókkal: `THINKNODES_GOOGLE_CLIENT_ID`, `THINKNODES_GOOGLE_CLIENT_SECRET` (és szükség esetén `THINKNODES_GOOGLE_REDIRECT`); nélkülük nincs gomb és nincs útvonal. Tesztmódban kikapcsolva. Indításkor a szerver kiírja, ha be van kapcsolva.
- A Google csak azonosít: a `User` új `google` mezője (e-mail-cím a `.settings.json`-ban) köti a Google-fiókot a ThinkNodes-fiókhoz, az admin a Beállítások oldalon állítja. Új fiók nem jön létre a Google-től; egy cím egy felhasználóhoz tartozhat. Jelszó nélküli új fiók Google-fiókkal létrehozható (véletlen jelszó-hash-t kap).
- A Google-lal indult munkamenet megszűnik, ha a hozzárendelést törlik vagy megváltoztatják.
- `deploy/daemon.sh`: a szolgáltatás beolvassa a `/var/lib/thinknodes/thinknodes.env` fájlt, ha létezik (a `daemon.sh` újrafuttatása kell hozzá).
- Teszt: `googleSignInOpensTheLinkedAccount` (71 Swift teszt rendben). Böngészőben ellenőrizve: gomb a belépőoldalon, átirányítás a Google-hoz, Google-fiók mező az adminoldalon. Valódi Google OAuth-klienssel nem próbáltam ki (nincs hozzá kliensazonosító), lásd TODO.md.
- README: „Google-bejelentkezés” fejezet.

## 2026-11-24 – Görgetősáv húzása fájldobozban (Safari 18)

- A szövegfájl-, CSV- és táblázatdoboz görgetősávjának felismerése a doboz vászonbeli helyéből és az egér vászonkoordinátájából számol, nem a DOM-ból (`Public/editor.js` `scrollbarPress`); Safariban a foreignObject-beli elemek mérete/helye megbízhatatlan, ezért ott a doboz húzása kapta el a görgetősávot.
- Chromiumban ellenőrizve (a görgetősáv-sávban a lenyomás nem indít dobozhúzást, a tartalmon igen); Safari 18-ban megerősítésre vár (BUGS.md). JS tesztek: `table-engine`, `canvas-markdown` rendben; a `gestures.mjs` a régi, ismert okból bukik.

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
