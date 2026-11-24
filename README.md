# ThinkNodes

Közös ötletvászon Swift 6.0.3 és Vapor szerverrel, Vue 3 szerkesztővel és D3 Zoom nagyítással. A megtekintő nézet szerveroldali HTML-t és SVG-t használ. JavaScripttel a jelenlétet és a vásznat is élőben frissíti.

## Mappaszerkezet

| Mappa | Tartalom |
| --- | --- |
| `server/` | A szerver és a kliens forrása (`Sources/`, `Public/`, `Tests/`, `docs/`, `Patches/`), a `run.sh` és a `deploy/` szkriptek; build után itt a `thinknodes` bináris |
| `projects/` | Helyi projektadatok (Git-követésen kívül); élesben `/var/lib/thinknodes/Projects` |

## Szkriptek

Mindegyik önállóan futtatható, és a `--help` kiírja a kapcsolóit.

| Szkript | Feladat |
| --- | --- |
| `server/deploy/install.sh` | Ellenőrzi és telepíti a fejlesztéshez és futtatáshoz szükséges környezetet (Swift 6, rendszerkönyvtárak, Node.js, Python, Chromium, Vapor-csomagok). Csak a hiányzót telepíti; `--force`: mindent újra. |
| `server/deploy/build.sh` | `git pull`, majd build macOS-en vagy Fedorán. Ha a frissítés nem megy, vagy helyi változás van, felajánlja a GitHub-ág pontos másolatára állítást. A release bináris a `server/thinknodes` helyre kerül. `--debug`, `--no-pull`. |
| `server/deploy/daemon.sh` | Fedorán: `thinknodes` felhasználó, adatmappák, checkout a `/opt/ThinkNodes` alá, build, systemd szolgáltatás; végül kiírja a teendőket. |
| `server/run.sh` | A szerver indítása (helyben és élesben). `--update`: előtte `deploy/build.sh`; `--debug`: a debug bináris. A többi kapcsoló a `thinknodes` binárisé. |
| `server/test.sh` | Témakörönkénti tesztfuttatás: téma nélkül a commitolatlan módosításokból választja ki az érintett Swift- és JS-teszteket. `--all`: minden teszt; `--list`: csak kiírja, mit futtatna; témák (pl. `table`, `render`, `editor`): `--help`. Mindig debug buildet használ. |

Fejlesztés közben a debug build sokkal gyorsabb: egy Swift-fájl módosítása után kb. 10 s, a release build ehhez képest kb. 85 s. Helyben ezért elég a `server/test.sh` (ez elkészíti a debug binárist is) és a `server/run.sh --debug --port:8888`; release build csak élesítés előtt kell.

## Indítás

~~~sh
server/deploy/install.sh
server/deploy/build.sh --no-pull     # helyben, ha vannak még nem commitolt változások
server/run.sh --http --port:8888 --test
~~~

A `thinknodes` bináris kapcsolói (a `server/run.sh` ugyanezeket adja tovább; teljes lista: `server/thinknodes --help`):

| Kapcsoló | Jelentés |
| --- | --- |
| `--http` | HTTP HTTPS helyett |
| `--port:N` | Port; alapból 443, `--http` mellett 80 |
| `--host:CÍM` | Kötési cím; alapból `0.0.0.0`, IPv4 és IPv6 együtt: `::` |
| `--rate:MS` | A húzás közbeni előnézet két küldése közötti minimális idő (alapból 33 ms) |
| `--test` | Minden csatlakozó adminjogot kap (Tester1, Tester2…). Élesben tilos. |
| `--project:MAPPA` | Projektadatok mappája; alapból `../projects` a `server/` mappához képest |
| `--tls-dir:MAPPA` | A beépített LAN-tanúsítvány mappája (alapból `server/.thinknodes-tls`) |
| `--tls-cert:FÁJL`, `--tls-key:FÁJL` | Saját tanúsítvány és kulcs (PEM) |
| `--` | A többi argumentum változtatás nélkül a Vapor `serve` parancsához kerül |

HTTPS-nél a bináris maga készíti el a LAN-tanúsítványt: a `ca.crt` gyökértanúsítványt a klienseszközökön megbízhatóként kell telepíteni (a szerver indításkor kiírja az útvonalát). Adminfiók parancssorból: `server/run.sh user admin admin` (jelszót kér). Nyisd meg az `/admin` oldalt; az első helyi megnyitáskor itt is létrehozható az adminfiók.

Élesben (Fedora): `sudo server/deploy/install.sh`, majd `sudo server/deploy/daemon.sh`. Frissítés: a `daemon.sh` által kiírt `build.sh` parancs, majd `sudo systemctl restart thinknodes`.

## Munkalapok és fájlok

A főoldal kártyái projektmappákat nyitnak meg. Minden munkalap a saját mappájában, a mappával azonos nevű **.thnode** fájlban található. Az **Új projekt** projektmappát, az **Új munkalap** almappát hoz létre. A szerkesztőbe feltöltött **.thnode** szintén külön almappába kerül. A szerver indításkor és a lap megnyitásakor ellenőrzi a mappába másolt képeket és egyéb csatolmányokat. A támogatott fájlok előnézetet kapnak, a többiek letölthető fájldobozként jelennek meg.

Az első indításkor a szerver a régi, közös mappában tárolt munkalapokat saját almappába rendezi. Átviszi a lapbeállításokat, átmásolja a használt csatolmányokat, és az eredeti lapfájlokat a projekt **.trash/** mappájába menti.

| Útvonal | Adatfájl |
|---|---|
| /VisualDemo | projects/VisualDemo/VisualDemo.thnode |
| /VisualDemo/Jelmagyarazat | projects/VisualDemo/Jelmagyarazat/Jelmagyarazat.thnode |
| /Thinking | projects/Thinking/Thinking.thnode |
| /Thinking/Proba | projects/Thinking/Proba/Proba.thnode |

A munkalap JSON-formátumban tárolja a vásznat, a címét, a létrehozóját és a mentési revíziót. A projekt **.settings.json** fájljában vannak a tagság és a lapok láthatóságának beállításai. A rejtett lap közvetlen hivatkozással elérhető a jogosultaknak. A projekt főlapján beállított hozzáférést az összes allap örökli. A hozzáadott szerkesztők és az adminisztrátor kezelhetik a projektet. A vendégek nyilvános projektben szerkeszthetnek.

Helyben a **projects/.settings.json** tartalmazza az alkalmazás beállításait, a fiókokat és a bcrypt-jelszóhasheket. A beállításfájlokat és a munkalapokat a mellékletlista kihagyja. A munkalap saját letöltési gombja **.thnode** fájlt ad.

A fájldoboz alján a csomagikonra duplán kattintva lehet letölteni a fájlt. Új fájloknál a név alapból rejtett. A tulajdonságpanel **Megjelenés** részében kapcsolható be, a **Fájlnév** mezőben pedig a kiterjesztés előtti rész szerkeszthető. A jóváhagyott törlés a projekt **.trash/** mappájába helyezi a fájlt az eredeti projektbeli alkönyvtárral együtt.

A mentés atomi fájlcserét és revízióellenőrzést használ. Egy adatkönyvtárhoz egy futó szerverpéldány tartozik.

## Statikus prezentációk

Másold a teljes prezentációt a projektbe egy `NAME.web` mappába. Az alapértelmezett belépő az `index.html`. A prezentáció saját CSS-, JavaScript-, kép-, font- és egyéb fájljai a mappában maradnak. A prezentációhoz vezető útvonalban a `web` szegmens az URL-elválasztó.

| Fájl a projektben | ThinkNodes-útvonal |
|---|---|
| `demoproject/prezi.web/index.html` | `/demoproject/web/prezi/` |
| `demoproject/prezi.web/css/main.css` | `/demoproject/web/prezi/css/main.css` |
| `demoproject/anyagok/masik.web/index.html` | `/demoproject/anyagok/web/masik/` |

A szerkesztő vásznának helyi menüjében a **Prezentáció beszúrása** parancs hozzáadja a dobozt. A doboz dupla kattintásra új fülön nyitja meg a prezentációt. A doboz előnézete a mappába tett `preview.png`, ennek hiányában a `screen.png`. A doboz törlésekor a mappa a lemezen marad.

A megtekintő **Prezentációk** gombjánál projektjogosultsággal szűkíthető az olvasók köre és beállítható a prezentáció jelszava. Minden fájlra külön érvényes a projekt, az útvonalon lévő mappák és a prezentáció szabálya. Egy helyi beállítás csak szűkítheti az örökölt hozzáférést.

A böngésző elkülönített környezetben futtatja a prezentációt. A prezentáció nem fér hozzá a ThinkNodes sütijeihez, böngészőtárhelyéhez és bejelentkezett munkamenetéhez, nem küldhet űrlapot és nem ágyazható más oldalba. A mappán belüli relatív CSS-, kép-, font-, média- és klasszikus JavaScript-fájlok, valamint a külső HTTPS-források (például Tailwind CDN, Google Fonts) betöltődnek. Ha a mappában nincs `index.html`, de pontosan egy HTML-fájl van (például `code.html`), az lesz a belépő. A védett prezentációk relatív erőforrásai a megnyitáskor kapott, munkamenethez kötött ideiglenes útvonalon töltődnek be. HTTPS-en ehhez egy prezentációra korlátozott biztonságos süti is szükséges, HTTP-n (`--http`) az útvonal önmagában elég. A modulbetöltés és a ThinkNodes felé irányuló, programból indított hálózati kérések nem támogatottak; a prezentáción kívülre mutató relatív hivatkozások (`../`) 404-et adnak.

## Közös szerkesztés

A jelenlévők névsora a szerkesztőben a vászon jobb alsó sarkában, a megtekintőben a vászon alatt látszik. A kijelölés a szerkesztő böngészőfülhöz tartozik. Másik szerkesztő közben kábelt köthet a dobozhoz és le is választhat róla kábelt. Üres területre kattintás, az Escape vagy másik elem kiválasztása elengedi a kijelölést. Lapváltáskor és a fül bezárásakor is felszabadul a doboz. Megszakadt kapcsolat esetén a szerver időkorláttal oldja fel a zárolást.

A vászon módosításai automatikusan szinkronizálódnak. Húzáskor a saját doboz folyamatosan követi az egeret. A többi résztvevő egy WebSocket-kapcsolaton, alapból legfeljebb 100 milliszekundumonként kap pozíció-előnézetet. Az elengedés egy munkalapírást indít, az Escape megszakítja a húzást. A végleges hely WebSocket nélkül is megjelenik a többi résztvevőnél.

Az első szerkesztő csatlakozásakor a szerver visszaállítási pontot készít a munkalapról. A később csatlakozó szerkesztők ugyanezt használják. A **Mentés** és a **Ctrl+S** az aktuális közös állapotot rögzíti új visszaállítási pontként. A **Resign** megerősítés után ebből állítja vissza a vásznat minden résztvevőnél, az aktuális megosztási jogosultságokkal. A munkamenet az utolsó szerkesztő kilépéséig vagy kapcsolatának lejártáig tart. A következő munkamenet a lemezen lévő aktuális munkalapról indul.

## Dobozlinkek és allapok

A doboz **Link** mezőjében a relatív út kiindulópontja maga a munkalap. A belső lapot láncszem, a webcímet földgömb jelöli a doboz jobb alsó sarkában. A hivatkozás ugyanabban a böngészőfülben nyílik meg.

| Link a `/main/labor` munkalapon | Cél |
|---|---|
| `jegyzet` vagy `./jegyzet` | `/main/labor/jegyzet` |
| `..` vagy `/..` | `/main` |
| `../tervek` | `/main/tervek` |
| `/archiv/otletek` | `/archiv/otletek` |
| `https://example.com/` | A megadott weboldal |

Az **Új munkalap** a megtekintőből és a vászon helyi menüjéből is elérhető. Az új lap örökli a szülő megjelenését és a projekt hozzáférési szabályait. Megtekintéskor az allapok a vászon alatti **További munkalapok** részben jelennek meg. A cím melletti nyíl a szülőlapra visz.

## Vászon és útmutató

A főoldali **Útmutató** az eszközöket, a gyorsbillentyűket és az egérgesztusokat példákkal mutatja be. A megtekintő a mentett munkalapot rács nélküli SVG-ként, .thnode fájlként vagy szövegként tudja exportálni.

Az útmutató oldal a [server/Public/utmutato.html](server/Public/utmutato.html). Gyorsbillentyű vagy gesztus változásakor ezt kell frissíteni, a [központi táblázattal](server/docs/hotkeys.json) együtt. A példaábrák forrása a [HTML-sablon](server/docs/guide.template.html), az oldal elrendezése a [stíluslapon](server/Public/guide.css) található.

A `Patches/` két apró javítást tartalmaz a `swift-nio` és az `async-http-client` csomaghoz. A `deploy/build.sh` csak macOS-en, 15-nél régebbi SDK esetén teszi rá őket a letöltött csomagokra (Swift 6.0.3 + macOS 14 SDK).

A munkalapok a rövid kulcsú, 2-es verziójú JSON-formátumban készülnek. A **projects/** mappa tartalma helyi adatként a Git-követésen kívül marad.
