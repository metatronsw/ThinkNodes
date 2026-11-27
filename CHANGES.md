# Változások

## 2026-11-27 – Telepítő szkriptek szétválasztva: update.sh frissít, build.sh csak fordít, daemon.sh cserél

- **update.sh (új):** csak `git pull` (fast-forward), a visszaállítás-ajánlattal; a régi build.sh-ból. A `daemon.sh` és a `run.sh --update` hívja.
- **build.sh:** csak fordít, a helyi fájlokból; a bináris a `.build/release/thinknodes`-ben (`--debug`: `.build/debug/thinknodes`) marad. A `--no-pull` megszűnt.
- **daemon.sh:** telepítés és frissítés: `update.sh`, `build.sh`, és csak sikeres build után a szolgáltatás leállítása, az új bináris áthelyezése a `server/thinknodes` helyre, indítás; sikertelen buildnél a futó szolgáltatás érintetlen. Ha a frissítéssel maga is változott, az új változattal folytatja. Új kapcsoló: `--no-pull`. A saját Swift-keresése és zárfájl-törlése kikerült (a build.sh-ban van).
- **as-owner.sh (új):** a root → checkout-tulajdonos átadás (runuser) egy helyen; az `update.sh` és a `build.sh` használja.
- **run.sh:** helyben a `.build/release/thinknodes`-t indítja; `--binary:PATH` kapcsoló (a systemd-unit így indítja a `server/thinknodes`-t); `--update`: `update.sh` + `build.sh`.
- `test.sh` a `--no-pull` nélkül hívja a build.sh-t; README, PERF.md, BUGS frissítve. macOS-en kipróbálva; Linuxon (root, systemd-csere) még nem.

## 2026-11-27 – build.sh root-ként: zárfájlok törlése, fordítás a checkout tulajdonosaként

- **build.sh:** Linuxon root-ként indítva törli a SwiftPM `/tmp`-beli zárfájljait (`…_.build*.lock`; a `thinknodes` felhasználó által hagyottakat a Fedora `fs.protected_regular` védelme miatt a root nem nyithatja meg: „invalid access to /tmp/_opt_ThinkNodes_server_.build.lock”). Ha a checkout nem a rooté, a tulajdonosnak adja vissza a fájlokat, és `runuser`-rel a tulajdonos nevében fut tovább (frissítés és fordítás), így a `.build`-be nem kerül root tulajdonú fájl. README frissítve.

## 2026-11-27 – A jobb oldali tulajdonságpanel megszűnt; tömör gombok; ikonos vászonmenü (`right-mouse-pan` ág)

- **Tulajdonságpanel:** a panel és a jobb felső nyitó / záró gombja törölve; minden funkciója a gyors eszközökben (jobb kattintás). A csak a panelen lévő mezők mezőgombok lettek (`FieldButton`: a gombon az érték / ikon, kattintásra lebegő réteg a mezővel; mentés a mező elhagyásakor, választásnál azonnal): betűméret, kép keretvastagsága, csomópont elforgatása és átmérője, grafikon típusa / kategóriái / értékoszlopai (+ fejlécsor kapcsoló), link célja, weboldal neve, táblázat neve; a táblázat CSV-letöltése gomb. A „Szerkesztés” művelet törölve; dupla kattintás: szerkesztés a vásznon. Chrome-ban típusonként összevetve: a régi panel minden kezelőeleme elérhető. `quick-tools.json` frissítve.
- **Tömör gombok:** a fejléc, az eszköztár, a lenyíló listák, a gyors eszközök, a vászonmenü és a lebegő mezők gombjai minden témában és állapotban tömörek (letiltva csak a tartalom halványul).
- **Vászonmenü:** csak ikonok (súgó és akadálymentes név a felirat); a Középre állítás és az Új munkalap saját ikont kapott.
- Útmutató és `docs/hotkeys.json` frissítve. A `Tests/Editor/gestures.mjs` panelre épülő részei még nincsenek hozzáigazítva (BUGS.md).

## 2026-11-27 – Érintőképernyő: csípés előnézettel, első ujj visszatartása, kevesebb réteg; H / Ctrl+H (`right-mouse-pan` ág)

- **Csípés (két ujj):** mozdulat közben csak a réteg CSS-transzformja változik (mint a görgetésnél), a nézet 400 ms nyugalom után rögzül; az ujjak helye a vászon nem mozgó tárolójához (`.canvas-area`) mérve (a mozgó jelenethez mérve kettős kép, megforduló irány volt). Csípési küszöb: a nagyítás a kezdeti távolság 15%-ánál (legalább 30 px) nagyobb változásra indul, ugrás nélkül.
- **Egy ujj** már nem pásztáz. Az első ujj lenyomása legfeljebb 150 ms-ig visszatartva: második ujjra elvész (nincs kijelölés, panelváltás), elmozdulásra, lejáratra vagy koppintásra lefut.
- **Rétegek mobil GPU-n:** érintőképernyőn csak a kijelölt doboz jegyzete görgethető; a húzáspajzs és az üres lézercanvas nyugalomban nem fest (a tableten 49 → 40 réteg, a végtelen méretű réteg megszűnt).
- **Billentyűk:** H teljes vászon, Ctrl+H 100% (a Shift+1 és a Z helyett).
- Honor tableten (Android 14, Chrome 157) mérve (csípés: 40 mozdulatra 42 → 3 újrarajzolás, 41 → 56 fps; pásztázás 0 px eltérés), a felhasználó kézzel is jóváhagyta. Útmutató, `docs/hotkeys.json`, tesztek frissítve.

## 2026-11-27 – Filctoll, rajzmód, egyszeri eszköz (D), eszköztár-csoportok, LowPerformance mód (`right-mouse-pan` ág)

- **Filctoll:** a lézerrel közös motoron (`Public/laser.js`, eszközleírások). Nem halványul; 3 mp-en belül kezdett vonás az előző rajzhoz adódik, később az új vonás mindenkinél törli az előzőt. Nem mentődik; a rajzoló kilépésekor a többieknél eltűnik. Pontkorlát: lézer vonásonként 48, filc rajzonként 1500 pont. Saját kurzor (`marker-cursor.svg`). A szerver a `kind` / `clear` mezőt is továbbítja (`Collaboration.swift`).
- **Rajzeszköz csoportgomb:** kattintásra be / ki, jobb kattintásra vagy nyomva tartva lézer / filc választó.
- **Egyszeri eszköz (`Public/one-shot.js`):** globális, billentyűvel élesíthető, egy használat után visszaálló működés. D: egy vonás a választott rajzeszközzel (a gomb csak fényes keretet kap).
- **Rajzmód:** a rajz canvasa fogja el az egeret, a dobozok nem reagálnak (rámutatás, tooltip, kijelölés); a pásztázás, nagyítás, a vászon helyi menüje és a mutatómegosztás működik. p1000-en a váltás stílusszámítása 34–37 → 0,8 ms. Esc rajzmódban vagy vonás közben: a saját rajz törlése mindenkinél.
- **Eszköztár:** „Rács és megjelenítés” csoport (rácsra igazítás S, saját rács G, LowPerformance mód L) és „Mind” csoport (teljes vászon Shift+1, 100% Z – új `zoom-actual` ikon –, teljes képernyő Ctrl+F). Minden csoportgomb jobb kattintásra nyílik (`groupTrigger`), a listák a vászon területére kerülnek (Teleport). A LowPerformance mód az animációk leállítását és a díszítő háttér kikapcsolását vonja össze (a régi külön beállítás egyszer átvándorol; `bench-idle.js` külön kapcsolhatja).
- Útmutató és `docs/hotkeys.json` frissítve; TODO: a később belépő nem látja a meglévő filcrajzot.

## 2026-11-27 – Jobb gombos pásztázás, helyi menü felengedéskor, új lézer pointer (`right-mouse-pan` ág)

- **Pásztázás és helyi menü:** megszűnt a kéz gomb (vászonmozgatás-zár, a `panLocked` beállítás szerveroldalon is), a szóközös és a bal gombos pásztázás. Jobb gomb + húzás pásztáz (objektum fölött is); mozgás nélküli jobb kattintás (küszöb 5 px, `rightClickSlop`) felengedéskor nyitja a helyi menüt, macOS- és Windows-eseménysorrenddel is. Útmutató és `docs/hotkeys.json` frissítve; a Chrome-os mérőszkriptek jobb gombbal pásztáznak.
- **Lézer kurzor:** fekete-fehér varázspálca (`Public/laser-cursor.svg`); a vászon CSS-ből, a mutatott doboz / vonal inline kapja (leszármazott-szabály p1000-en a váltást 50 → 100–200 ms-ra rontotta).
- **Lézer rajz:** hibrid mintavétel (12 px, 40–100 ms, fordulópont-megőrzés 3 px tűréssel), 100 ms-os csomagküldés, centripetális Catmull-Rom görbe, elvékonyodó vég, 2,2 mp élettartam, max. 48 pont. Ugyanazon a húzáson 146 → 89 pont, az üzenetek ~fele.
- **Lézer canvason:** a rajz a látható terület méretű `<canvas>`-on (a vászon-SVG-ben képkockánként festést és rétegezést okozott): p1000-en rajzolás 38 → 60 fps. Részletek: `server/docs/PERF.md`.
- **Safari zoom-hiba:** a Safari `getScreenCTM`-je nem tartalmazza a vászon burkolójának CSS-transzformját (görgős nagyítás / pásztázás előnézete), ezért a lézer elcsúszott, a közben kezdett vonal rossz helyről indult, és a megosztott egérmutató is rossz helyet küldött. Közös javítás: `Public/screen-matrix.js` (a vászon valódi téglalapjából számolt korrekció). A bennragadt rajzot (elveszett felengedés) a lézer lezárja.

## 2026-11-27 – Szerver Fedora 45-ön: swift.org Swift 6.3.3, Swift-verziók a swift.env-ben, Linux-javítások

- **Miért nem a 6.0.3:** a swift.org 6.0.3-as toolchainjének clangja (LLVM 17) a Fedora 45 C++ fejléceit (GCC 16) nem fordítja (a swift-crypto BoringSSL-je C++); a Fedora `swift-lang` 6.3.2 pedig assertionnel épült, és egy függőségen összeomlott. A szerver ezért a swift.org hivatalos 6.3.3-át használja (`fedora41` építés, `/opt/swift-6.3.3`), a fejlesztőgép marad 6.0.3.
- **`server/deploy/swift.env`:** egy helyen a verziók (`SWIFT_LINUX`, `SWIFT_LINUX_PLATFORM`, `SWIFT_MACOS`, `SWIFT_RELEASE_KEY`); az `install.sh`, a `build.sh` és a `daemon.sh` ebből dolgozik.
- **`install.sh`:** a swift.env szerinti toolchain letöltése és aláírás-ellenőrzése, utána **C++-fejléc-próba** a toolchain clangjával (`<memory>`, `<string>`, `<system_error>`): ha nem fordul, kiírja, hogy a `swift.env`-ben újabb verzió kell. A szerveren kipróbálva: 6.0.3 → hiba, 6.3.3 → rendben.
- **Linux-javítások a kódban:** `ProjectPackage.swift` – a szabad hely a fájlrendszerből (`attributesOfFileSystem`, `systemFreeSize`; a `volumeAvailableCapacityForImportantUsage` csak Apple-en van); `LinkPreview.swift` – az `addrinfo` mezőnként (a mezősorrend macOS-en és glibc-n eltér). `run.sh`: a futó szerverek keresése `${…##*/}`-val (a `basename` a `-bash` folyamatnevet kapcsolónak vette).
- **`build.sh`:** a frissítést csak a követett fájlok helyi változása akasztja meg; a nem követett fájlok (pl. a régi mappaszerkezet gyökérben maradt `.build/`-je) nem (`git status --untracked-files=no`), csak ha a fast-forwardot ténylegesen megakasztják.
- A szerveren: Swift 6.3.3 telepítve, build 32 szálon, új systemd unit (`server/run.sh --project:/var/lib/thinknodes/Projects --tls-dir:/var/lib/thinknodes/tls`); a szolgáltatás fut, HTTPS 200.

## 2026-11-27 – Szerver: ugyanaz a Swift (6.0.3), mint a fejlesztőgépen

- A Fedora `swift-lang` 6.3.2 (6.3.2-7.fc45) fordítója a tiszta buildben a `swift-service-context` függőségen összeomlott (LLVM-ellenőrzés: `createUniquePath: Model must contain at least one '%'`, IRGen; egyszálú fordítással is).
- **`server/deploy/install.sh`:** Linuxon a swift.org hivatalos Swift 6.0.3 csomagját (fedora39 / fedora39-aarch64 építés) telepíti a `/opt/swift-6.0.3` mappába, a swift.org kulcsaival ellenőrzött aláírással (`gnupg2` a rendszercsomagok között); a dnf `swift-lang` nem kell, telepítve maradhat. macOS-en továbbra is swiftly.
- **`server/deploy/build.sh`, `daemon.sh`:** magától csak a Swift 6.0.3-at veszik fel (`~/X-Code/RunTime/Swift/6.0.3`, `/opt/swift-6.0.3`, swiftly, PATH); más a `THINKNODES_SWIFT`-tel adható meg. A `build.sh` megjegyzi, melyik fordító építette a `.build`-et (`.build/.swift-version`), és váltáskor a lefordított részeket törli (a letöltött csomagforrások maradnak).
- macOS + Swift 6.0.3 alatt kipróbálva (első futáskor teljes újrafordítás a jelző miatt); Fedorán a szerveren ellenőrizendő (BUGS.md).
- Javítás (a szerveren az `install.sh` szó nélkül megállt): a swift.org kulcsainak importja a régi, lejárt kulcsok miatt hibakóddal térhet vissza, és a kimenete el volt nyelve, így a `set -e` üzenet nélkül kilépett. Most az import hibakódja nem állítja meg (a döntő az aláírás ellenőrzése, hiba esetén a `gpg` kimenete kiíródik), és a szkript minden váratlan kilépésnél kiírja a sort és a parancsot (`set -E`, `trap … ERR`). A rendszercsomag-ellenőrzés a helyettesítő csomagokat is elfogadja (`rpm -q --whatprovides`, pl. `zlib-devel` → `zlib-ng-compat-devel`).
- Az aláírás-ellenőrzés a Swift 6.x release kulcsának rögzített ujjlenyomatával (`52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`, https://swift.org/keys/active/): a `swift.org/keys/all-keys.asc` cím már nem kulcsot ad. A kulcs a swift.org `release-key-swift-6.x.asc` fájljából, ha onnan nem jön meg, a keyserver.ubuntu.com-ról; csak az ezzel az ujjlenyomattal érvényesen aláírt csomag települ.

## 2026-11-27 – daemon.sh: elárvult SwiftPM zárfájl

- A root-ként futtatott `install.sh` a `/tmp`-ben hagyta a SwiftPM zárfájljait (`/tmp/_opt_ThinkNodes_server_.build*.lock`: a build, a `Package.resolved`, a munkaterület-állapot és a manifest-gyorsítótár zárja), a `thinknodes` felhasználóként futó build ezért „invalid access” hibával leállt (a `Package.resolved`-ot „corrupted”-nek jelezte). A `server/deploy/daemon.sh` a fordítás előtt mindet törli, az `install.sh` root-ként futtatva maga után is (az előtag a `.build` útvonalából képezve).

## 2026-11-26 – Szerverfrissítés Fedorán Swift 6.3.2-vel: csomagfeloldás a build előtt

- **Ok:** az async-http-client 1.33.1 a Swift 6.2+ alatt más csomagleírást használ, és a `swift-configuration` csomagot is kéri; a 6.0.3-mal készült `server/Package.resolved`-ban ez nincs, a build pedig tiltotta a feloldást („out-of-date resolved file”). Egy korábbi feloldás a szerveren helyben módosította a `Package.resolved`-ot, ami a `git pull`-t is megakasztotta.
- **`server/deploy/build.sh`:** a fordítás előtt `swift package resolve` (a rögzített verziók maradnak, a hiányzók bekerülnek), pull előtt a `Package.resolved` helyi változása kérdés nélkül elvetve (generált fájl). **`server/deploy/install.sh`:** a csomagok előzetes feloldása is engedi a hiányzó csomagokat.
- macOS + Swift 6.0.3 alatt kipróbálva (a fájl nem változik); Fedora + Swift 6.3.2 a szerveren ellenőrizendő (BUGS.md).

## 2026-11-26 – WhiteBoard: textúrák külön fájlban, nagyításkor nem ugranak; füzetvonalak Safariban; önálló SVG-export

- **Textúrák külön fájlban:** a képek kikerültek a téma JSON-jából (base64 helyett): `Public/themes/WhiteBoard.paper.webp`, `WhiteBoard.cardboard.webp`, a JSON-ban csak a fájlnév (`graphics.textures.images`). A szerkesztő a `/themes/…` címről tölti (gyorsítótárazható), a szerver a betöltéskor beolvassa őket az SVG-exporthoz; hiányzó fájlnál a téma nem töltődik be. A képek kontrasztja meg lett emelve (az eredetiek szinte egyszínűek voltak).
- **Nagyításkor nincs ugrás:** a vászon textúrája vászonegységben áll, a tartalommal együtt mozog és nagyul; részletességi szintekkel (2^n, két szomszédos szint áttűnve, mint a Blender rácsa), így a szemcse a képernyőn 192–384 px között marad. A rajzolt rácsvásznon két mintás kitöltés, SVG-minta nélkül. A szabadkézi doboz nem kap külön textúrát (a vászoné átlátszik), a papír a lap saját koordinátáiban. Halványabb: világos 0,45, sötét karton 0,2, papír 0,4.
- **Füzetvonalak Safariban:** a Safari „legkisebb betűméret” beállítása a 13 px-es betűt 14-re emelte, és a px-es sormagasságot arányosan növelte, a vonalak és margók nem; a sorok fokozatosan elcsúsztak. Most egység nélküli sormagasság (1.6) és a tényleges betűméretből számolt sorköz (`--pitch`); a szöveg alapvonala kb. 2 px-lel a vonal fölött (Chrome és Safari 18.6, mérve). A tábla filcnyomai (háttérfények) megszűntek.
- **Önálló SVG-export** (`/export/svg`): a képek, a hang, a fájldobozok letöltése (`download` névvel), a használt ikonok és a textúrák a fájlba ágyazva, belső kéréssel a letöltő munkamenetével (Server.swift `selfContainedSVG`; elemenként 20 MB, összesen 100 MB). Teszt: `svgExportIsSelfContained`. PERF.md 3. szabály kiegészítve.
- Megjegyzés: a `9fb0caa` commit már tartalmazta a nagyításkori ugrás javítását, a Safari-vonalakat és a filcnyomok megszüntetését, de az üzenete egy korábbi állapotot ír le; ez a bejegyzés pótolja. Dokumentáció: server/docs/themes.md „Textúrák”, theme.schema.json; nyitott tételek: BUGS.md, a könyvtárra bontott témák: TODO.md.

## 2026-11-26 – .web oldal: `../` hivatkozás a projektmappán belül

- A .web oldal eddig csak a saját mappájából tölthetett be fájlt (a `../kepek/x.png` 404 lett); a közös könyvtár abszolút címmel (`/common/...`) eddig is működött.
- Minden kiszolgált HTML oldal tükrözött `<base>`-t kap: `{.web cím}_tn-assets/{bérlet | public}/{mappa}/{név}.web/…`. A jelölő utáni rész a projekt gyökeréhez képesti útvonal, így a böngésző által feloldott `../` a projekten belül a lemez szerinti fájlra mutat; a projekt gyökere fölé lépő cím 404 (`WebPresentationRequest.candidates`, `outside`).
- Jog: a projekt fájljaira a projekt olvasási joga és jelszava vonatkozik (publikus .web zárt projektben a vendég csak a .web saját fájljait látja). Rejtett (`.`), `.thnode`, HTML fájl, mappa és szimbolikus link nem szolgálható ki. Bejelentkezett nézőnek publikus .web-nél is bérlet jár, hogy a homokozóból elérje a projekt fájljait.
- Teszt: `presentationParentReferencesStayInsideProject`; valódi Chrome-ban (CDP, homokozóval) ellenőrizve. Próbalap: `projects/test-container/parent-proba.web`. Leírás: server/docs/node-types.md „.web mappa”.

## 2026-11-26 – WhiteBoard: pontos füzetvonalak, ismétlődő textúrák; VectorStudio téma törölve

- **Füzetvonalak:** a címsor sávja a sormagasság egész többszöröse, az alapvonala a vonalra esik; a markdown kódblokk térköze csak oldalt, a vízszintes vonal egy sor, így az utánuk következő sorok sem csúsznak el (Chrome-ban mérve: az alapvonal kb. 2 px-lel a vonal fölött a dokumentum végéig). A füzetlap markdownja a doboz betűméretével íródik; a kódfájl (`type: "code"`) már nem füzetlap.
- **Textúrák:** a téma ismétlődő webp textúrákat adhat a vászonnak és a dobozoknak (`graphics.textures`; csempe 256 képernyőképpont, a nagyítástól független); a „Díszítő háttér kikapcsolása” ezeket is elrejti. A tábla filcnyomai megszűntek. Részletek: server/docs/themes.md „Textúrák”, séma: server/docs/theme.schema.json.
- A **VectorStudio** téma törölve; a tesztek a LiquidGlass témát használják. Nyitott, kézzel nézendő tételek: BUGS.md.

## 2026-11-26 – Kapcsolatvesztés: nincs villogás, nincs újratöltés; tartós munkamenetek

- **Ok:** a munkamenetek memóriában voltak, ezért a szerver újraindulása után új CSRF-token (tesztmódban új „TesterN” név) járt, és a nyitott szerkesztő és megtekintő a visszatéréskor teljesen újratöltötte magát (villanás, újraépülés); többszöri leállás–indulásnál ez villogásként látszott. Kapcsolat nélkül a megtekintő másodpercenként újraírta a „Kapcsolat megszakadt” jelzést, és mindkét lap másodpercenként próbálkozott.
- **Tartós munkamenetek** (`Sources/ThinkNodes/FileSessions.swift`): az adatmappa `.sessions.json` fájljában (0600), összevont írással, a 30 napja nem használtak törlésével. Újraindítás után senki nem lép ki, a token sem változik. Teszt: `sessionsSurviveServerRestart`.
- **Újratöltés helyett tokenátvétel:** ha mégis új a token, de a felhasználó és a jogosultság ugyanaz, a szerkesztő és a megtekintő átveszi (`live.setToken`, `chat.setToken`); újratöltés csak jogosultság-változáskor.
- **Fokozatos újrapróbálkozás** kapcsolat nélkül (1, 2, 4, 5 mp; `collaboration.js`, `page-updates.js`); a megtekintő a jelzést csak egyszer írja ki.
- Ellenőrzés (Chrome, szerver leállítva, majd újraindítva): kapcsolat nélkül a lapok állnak és működnek; visszatéréskor nincs újratöltés, képbetöltés vagy vászoncsere, a lapok újracsatlakoznak. Mérőeszköz: `Tests/Perf/chrome-offline.mjs`, `safari-offline.py`. PERF.md: 9. szabály.

## 2026-11-26 – Minimalist téma; keret nélküli dobozok a témából

- **Új téma: Minimalist** (`Public/themes/Minimalist.json`, id 7): a leggyorsabb – nincs effekt, üveg, szabadkézi rajz, fényudvar, dobozkeret; egyenes vonalak, kis sarokkerekítés. Öt paletta (Kő, Fjord, Pasztell, Föld, Grafit) 21–21 színnel, OKLCH-ban; a világos és a sötét mód fényereje, kontrasztja hasonló (szöveg kb. 9,3 / 10:1).
- **`graphics.frame.kind`** (`outline` alap, `none`): a téma elhagyhatja a kitöltött dobozok keretét (editor.js `shape`, Rendering.swift `boxSurface`); az üres doboz és a zárolt konténer körvonala marad, a saját kijelölést ilyenkor a vékony kijelölés-körvonal jelzi. Későbbi bővítésre fenntartva (pl. `side`: az oldal színezése).
- **`glow: 0`**: nem készül fényudvar-szűrő (eddig üres szűrő jött létre).
- Teszt: `minimalistThemeDrawsNoFrame`. Mérés (Chrome, a Liquid Glass lap tartalma, 9 tartalom-animációval): üresjárat Minimalist 18%, Liquid Glass 21%; animációk nélkül mindkettő ~0%. Próbalap: `projects/Minimalist`.

## 2026-11-26 – Szerver: napló-zaj megszüntetése a hosszú lekérdezéseknél

- A jelenlét (`/api/presence`) és a lapváltozás (`/api/page-changes`) hosszú lekérdezése a várt „lejárt” esetben (a kliens elhagyta a lapot, a csatorna lejárt) csendes 410-es választ ad dobás nélkül; korábban minden lapbezárás egy „Abort.410: Gone” figyelmeztetést írt a naplóba. A kliens viselkedése nem változott (jelenlét: újracsatlakozás, lapváltozás: az oldal újratöltése).
- A PERF.md elejére kötelező irányelvek kerültek (szabályok, mérési módszer, mérőeszközök és elavulásuk).

## 2026-11-26 – Szerkesztő: üresjárati terhelés és akadások javítva; „Animációk leállítása”, „Díszítő háttér kikapcsolása”

- **Animációk a szerkesztőben CSS-ből** (app.css „Tartalom-animációk”): doboz (pulzálás, villogás, ringás, ugrálás) és vonal (szaggatott minta, vastag lüktetés, kúpos vastag vonal, futó pötty `offset-path`-szal, lüktető nyílhegy). 20 lépés/mp (`steps()`, minden szakasz 50 ms többszöröse), a közös idővonal nullpontjához igazítva (`editor.js queueMotionAlign`). A téma sebességszorzóját a szerkesztő nem alkalmazza (az eltérő ütem kétszer annyi képkockát kért).
- **Letölthető SVG:** SMIL marad (önállóan működik), ugyanazokkal a mértékekkel; a kúpos vastag vonal a szerkesztővel azonosan a kitöltés köré rajzolt, vastagodó körvonallal lüktet (a `d`-animáció kikerült).
- **Háttérfények állók** (Liquid Glass): a végtelen animáció Chrome-ban üresjáratban ~17% CPU-t vitt, a mozgás nem is látszott.
- **Ping hangja:** előre generált `Public/ping.wav` `<audio>` elemmel (a Web Audio-környezet létrehozása az első lenyomáskor 250–290 ms-ig blokkolt).
- **Pásztázás vége:** a nézet 400 ms nyugalom után rögzül (`perfOptions.panCommit`), egymás utáni húzások között nincs teljes újrarajzolás.
- **Vezérlősáv:** „Animációk leállítása” (`data-still`) és „Díszítő háttér kikapcsolása” (`data-plain`; fények, filcnyomok, később textúrák); localStorage `tnMotionOff`, `tnPlainBackground`. Útmutató, hotkeys.json, README frissítve.
- **Mérőeszközök** (Tests/Perf): valódi Chrome (CDP) és Safari (WebDriver) üresjárati, pásztázási és első-kattintás mérések; leírás: server/docs/PERF.md „Üresjárat”.
- Eredmény (Liquid Glass, üresjárat): Chrome 94–98% → 17–21%, Safari 71% → 25% WebContent. Minden teszt átmegy; release build; a helyi tesztszerver (8888) az új builddel fut.

## 2026-11-26 – „Tartalom a dobozhoz” CSV-dobozon is

- A CSV panelén (és a gyors eszközökben) is ott a „Tartalom a dobozhoz” kapcsoló: a teljes táblázat arányosan, torzítás nélkül a doboz méretéhez skálázódik, mint a táblázatdoboznál. Illesztve a CSV a szerkesztés táblázatnézetével jelenik meg (a szerkesztő ugyanazt a dokumentumot használja, így szerkesztésbe lépve semmi nem ugrik); dupla kattintással a skálázott rétegben szerkeszthető.
- Szerver: `Rendering.swift csvGridDocument` (az `editor.js csvDocument` párja: szöveges cellák, alaprács, egy fejlécsor, az oszlopszélesség az első 300 sor leghosszabb mezője) és `csvEditorRows` (a `table-csv.js parseCSVRows` pontos párja; a TableCSV.rows a záró üres sorokat elhagyja, ami más skálát adna). Szerkesztő: `fitDocument`, `fittedTable` (CSV-re is).
- A táblázat korlátainál (1000 sor × 100 oszlop) nagyobb CSV a sima olvasó nézetben marad. Teszt: `contentFitCSVUsesTheEditorTable`. Verzió: `editor.js?v=103`.

## 2026-11-26 – Olvasható szövegszín a dobozon, nagyobb CSV-nézet, régi gyorsítótár-fájlok törölve

- **Szövegszín:** ha a doboz szövegének kontrasztja a felülettel 3 alatt van (WCAG-arány), kirajzoláskor a téma tintájának jobban olvasható (nappali vagy esti) változatát kapja. A felület a kitöltés a vászon fölött, a téma átlátszatlanságával (Liquid Glass 64 / 40 %, üveg 66 %, áttetsző 75 %, szabadkézi téma halvány tónusa); a tárolt szövegszín nem változik. Szerver: `Rendering.swift labelInk` (`Idea.labelInk`, nem tárolt mező; `Worksheet.painted` tölti), szerkesztő: `editor.js boxInk`; csak a sima doboz szövegére (kitöltött, áttetsző és vászonszínű háttérnél). Teszt: `unreadableBoxTextGetsThemeInk`.
- **CSV olvasó nézet:** legfeljebb 1000 sor × 60 oszlop (eddig 200 × 30), a szerveren és a szerkesztőben egyformán (`csvPreviewRows`, `csvPreviewColumns`).
- **Takarítás (engedéllyel):** a 12 régi `.preview-v12*.svg` és az üres `projects/a/.chat.jsonl` törölve.
- Ellenőrzés: minden Swift- és JS-teszt átmegy; release build (`deploy/build.sh --no-pull`), a szerkesztő és a megtekintő szövegszíne fej nélküli Chromiumban egyezik (világos és sötét mód); a helyi `a` lap CSV-je 417 sort mutat. Verzió: `editor.js?v=102`; a helyi tesztszerver (8888) az új builddel fut.

## 2026-11-26 – BUGS.md átnézése: előnézet átnevezéskor, gyors eszközök lenyíló listája és Szerkesztés gombja

- **Lap átnevezése:** az előnézet gyorsítótára (`.<lap>.preview[-dark].svg` / `.webp`) az új névvel megy tovább, a régi nevű nem marad a mappában; a módosítás ideje megmarad, így érvényes marad (`Model.swift moveDocument`). Teszt: `uploadedWorksheetsUseTheirOwnFolder`.
- **Gyors eszközök, lenyíló lista:** a listán kívüli kattintás és az Esc bezárja (az Esc ilyenkor csak a listát zárja, a gyors eszközöket nem).
- **Gyors eszközök, Szerkesztés:** új `properties` gomb (tulajdonságpanel ikon) dobozon, csomóponton és vonalon, a Törlés előtt; megnyitja és ki is nyitja a tulajdonságpanelt (`quick-tools.json`, `editor.js renderQuickTools`).
- Döntések: csökkentett mozgásnál a ping animációja marad; az új doboz nem kap automatikusan eltérő színt (ötlet a TODO.md-ben).
- Ellenőrzés: minden érintett Swift- és JS-teszt átmegy; a gyors eszközök fej nélküli Chromiumban kipróbálva (Safariban a távoli automatizálás ki volt kapcsolva). Verzió: `editor.js?v=101`. Helyesbítés: a szerver a release binárist futtatja, ez akkor nem készült újra, így az átnevezés javítása csak a következő buildben (lásd fent) került a futó szerverre.
