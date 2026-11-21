# ThinkNodes

Közös ötletvászon Swift 6.0.3 és Vapor szerverrel, Vue 3 szerkesztővel és D3 Zoom nagyítással. A megtekintő nézet szerveroldali HTML-t és SVG-t használ. JavaScripttel a jelenlétet és a vásznat is élőben frissíti.

## Indítás

Futtasd a projekt könyvtárából.

~~~sh
./build.sh --skip-update -j 2
./run.sh
~~~

Nyisd meg a [https://localhost/admin](https://localhost/admin) oldalt. Az első helyi megnyitáskor itt hozható létre az adminfiók. Az adminoldalon állítható a hozzáférés és kezelhetők a felhasználók. Adminfiókot parancssorból is létrehozhatsz a **./run.sh user admin admin** paranccsal, amely jelszót kér.

A build először a **~/X-Code/Swift/6.0.3/usr/bin/swift** binárist keresi. A **THINKNODES_SWIFT** változóval megadható másik útvonal. Az első teljes build letölti a rögzített Vue- és D3-verziót a **Public/vendor/** könyvtárba. Utána a böngésző helyben tölti be őket. A **./build.sh --server-only** csak a szervert építi. A **THINKNODES_DATA**, **THINKNODES_HOST**, **THINKNODES_PORT** és **THINKNODES_CONFIGURATION** változók felülírják az alapértékeket. HTTPS mögött állítsd a **THINKNODES_SECURE_COOKIES=1** változót.

### Fedora Linux build

A release binárist Fedora Linuxon építsd, Swift 6 toolchainnel. A fordításhoz szükséges alapcsomagok: **clang**, **gcc-c++**, **git**, **pkgconf-pkg-config**, **curl**, **openssl** és **ca-certificates**. Telepítés:

~~~sh
sudo dnf install clang gcc-c++ git pkgconf-pkg-config curl openssl ca-certificates
~~~

A Swift 6 Linux toolchain külön telepítendő; a `swift --version` paranccsal ellenőrizd, hogy elérhető-e. Ezután a teljes alkalmazás buildje:

~~~sh
./build-fedora.sh
~~~

A szerver buildje böngészős függőségek letöltése nélkül:

~~~sh
./build-fedora.sh --server-only
~~~

A bináris a **.build/release/ThinkNodes** útvonalon készül. A buildszkript kiírja annak dinamikus könyvtárfüggőségeit is. A futtató Fedora rendszeren a Swift compiler nem kell, de a bináris által jelzett megosztott könyvtáraknak rendelkezésre kell állniuk; azonos vagy újabb Fedora kiadáson építs, mint a célrendszer. A futtatáshoz a bináris mellett a projekt **Public/** és **Projects/** állományai, valamint a TLS-beállítások szükségesek. A futó szolgáltatást korlátozott jogosultságú külön felhasználóként érdemes elindítani.

#### Indítás systemd szolgáltatásként

A `deploy/thinknodes.service` unit a `/opt/ThinkNodes` telepítési útvonalat és a `thinknodes` szolgáltatásfelhasználót használja. A launcher GitHubról frissíti a checkoutot, ezért ennek a felhasználónak írnia kell az alkalmazásmappát; a projektek és a TLS-kulcsok külön, a `/var/lib/thinknodes` alatt tárolódnak. A frissítés utáni buildhez Swift toolchain is kell a szerveren.

~~~sh
sudo useradd --system --home-dir /var/lib/thinknodes --create-home --shell /sbin/nologin thinknodes
sudo chown -R thinknodes:thinknodes /opt/ThinkNodes
sudo install -m 0644 /opt/ThinkNodes/deploy/thinknodes.service /etc/systemd/system/thinknodes.service
sudo systemctl daemon-reload
sudo systemctl enable --now thinknodes
sudo systemctl status thinknodes
~~~

A napló követése: `sudo journalctl -u thinknodes -f`. Leállítás: `sudo systemctl stop thinknodes`. A unit a 443-as porthoz szükséges jogosultságot rootként futás nélkül adja meg.

### HTTPS a belső hálózaton

Indítás a szervergépen:

~~~sh
./run.sh
~~~

A **./run.sh** alapértelmezésben a release binárist indítja, és szükség esetén release módban fordít. Debug indításhoz használd a **./run.sh --debug** parancsot.


Macen LAN-os teszthez a **./run.sh --local** debug binárist indít HTTP-n, alapból a 80-as porton. Így a böngészőben elég az **http://** előtag és a Mac címe. A szkript ezen a porton csak a szerver indításához kér adminisztrátori jogosultságot. Sudo nélküli futtatáshoz használd a **./run.sh --local --port:8080** parancsot.

A szerver alapból minden IPv4-hálózati interfészen a **443**-as porton figyel. A másik eszköz böngészőjében nyisd meg az indításkor kiírt, közös hálózathoz tartozó HTTPS-címet. A szervergépen a **https://localhost/admin** címen végezhető el az első adminisztrátori beállítás. A közös szerkesztés ugyanazon a porton használja a titkosított WebSocket-kapcsolatot.

A szkript OpenSSL-lel helyi hitelesítőt hoz létre a **.thinknodes-tls/** könyvtárban. Az eléréshez használt eszközökön egyszer telepítsd a **ca.crt** fájlt megbízható gyökértanúsítványként. A **.key** fájlok a szerveren maradjanak. Az indításkor kiadott szervertanúsítvány a felismert LAN-címekre is érvényes. IP-címváltozás után indítsd újra a szervert.

Saját PEM-tanúsítványlánc és hozzá tartozó, jelszó nélküli privát kulcs is használható:

~~~sh
THINKNODES_TLS_CERT=/utvonal/fullchain.pem THINKNODES_TLS_KEY=/utvonal/server.key ./run.sh
~~~

A **THINKNODES_HOST** és a **THINKNODES_PORT** mindkét módban felülírja a kötési címet és a portot. A **THINKNODES_TLS_DIR** a helyben előállított tanúsítványok könyvtárát adja meg. A **./run.sh --http** alapból minden IPv4-interfészen figyel a **80**-as porton, és kiírja a helyi és hálózati HTTP-címeket. A böngészőben ehhez elég az **http://** előtag és a szerver címe. Csak a szervert futtató gépről való eléréshez indítsd így: **THINKNODES_HOST=127.0.0.1 ./run.sh --http**. A **--port:8000** mindkét módban felülírja a portot, a **--rate:100** pedig milliszekundumban adja meg a húzás közbeni előnézet két küldése közötti minimális időt. Az alapérték **33 ms**.

A szerkesztőben és a megtekintőben a bejelentkezett felhasználó a vászon bal alsó gombjával kapcsolhatja be saját mutatója megosztását. Az újonnan megnyitott lapon a megosztás ki van kapcsolva.

A `./run.sh --test` indításkor minden új böngésző-munkamenet automatikusan adminisztrátori jogot kap, Tester1, Tester2 és további neveken. A tesztfelhasználó a fejléc **Bejelentkezés** gombjával saját fiókra válthat.

## Munkalapok és fájlok

A főoldalon minden kártya egy projektmappát nyit meg. A mappával azonos nevű **.thnode** a fő munkalap. A többi **.thnode** melléklap, a további fájlok a **Mappa tartalma** alatt tölthetők le. A JSON-adatfájlok is mellékletek. Minden almappának saját főlapja és beállításfájlja van.

| Útvonal | Adatfájl |
|---|---|
| /VisualDemo | Projects/VisualDemo/VisualDemo.thnode |
| /VisualDemo/Jelmagyarazat | Projects/VisualDemo/Jelmagyarazat.thnode |
| /Thinking | Projects/Thinking/Thinking.thnode |
| /Thinking/Proba | Projects/Thinking/Proba.thnode |

A munkalap JSON-formátumban tárolja a vásznat, a címét, a létrehozóját és a mentési revíziót. A projekt **.settings.json** fájljában vannak a tagság és a lapok láthatóságának beállításai. A rejtett lap közvetlen hivatkozással elérhető a jogosultaknak. Az új almappa átveszi a szülő aktuális jogosultságait. A hozzáféréshez minden szülőmappán is át kell jutni. A nyilvános mód olvasást enged, szerkeszteni a jogosult tagok tudnak. A rendszergazda kezeli az összes projektet.

A **Projects/.settings.json** tartalmazza az alkalmazás beállításait, a fiókokat és a bcrypt-jelszóhasheket. A beállításfájlokat és a munkalapokat a mellékletlista kihagyja. A munkalap saját letöltési gombja **.thnode** fájlt ad.

A mentés atomi fájlcserét és revízióellenőrzést használ. Egy adatkönyvtárhoz egy futó szerverpéldány tartozik.

## Közös szerkesztés

A vászon bal alsó sarkában, csatlakozási sorrendben megjelenő névsor mutatja, kik vannak a munkalapon. A név melletti szín a kijelölt doboz körüli keret színe is. A kijelölés a szerkesztő böngészőfülhöz tartozik. Másik szerkesztő közben kábelt köthet a dobozhoz és le is választhat róla kábelt. Üres területre kattintás, az Escape vagy másik elem kiválasztása elengedi a kijelölést. Lapváltáskor és a fül bezárásakor is felszabadul a doboz. Megszakadt kapcsolat esetén a szerver időkorláttal oldja fel a zárolást.

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

A vászon jobb kattintásos menüjében az **Új munkalap** létrehozza az allapot és a rá mutató dobozt. Az allap örökli a szülő háttérszínét, egyedi rácsközét, mappájának hozzáférési szabályait. Létrehozás után a szülőlapon rögtön szerkeszthető az új doboz címe, és a doboz hivatkozása megnyitja az allapot. A munkalapkártyán a létrehozó és a látható közvetlen allapok száma szerepel. Megtekintéskor az allapok mentett SVG-előnézete a vászon alatt található. A fejléc útvonala kattintható, a felfelé mutató nyíl a szülőlapra visz.

## Vászon és útmutató

A főoldali **Útmutató** az eszközöket, a gyorsbillentyűket és az egérgesztusokat példákkal mutatja be. A megtekintő a mentett munkalapot rács nélküli SVG-ként, .thnode fájlként vagy szövegként tudja exportálni.

Gyorsbillentyű vagy gesztus változásakor frissítsd a [központi táblázatot](docs/hotkeys.json). A [HTML-sablonban](docs/guide.template.html) találhatók a példaábrák, az oldal elrendezése pedig a [stíluslapon](Public/guide.css).

```sh
python3 tools/generate-guide.py
python3 tools/generate-guide.py --check
```

Az első parancs elkészíti a kiszolgált `Public/utmutato.html` fájlt. A második ellenőrzi, hogy a verziózott HTML egyezik-e a forrásokkal.

A munkalapok a rövid kulcsú, 2-es verziójú JSON-formátumban készülnek. A **Projects/** mappa tartalma helyi adatként a Git-követésen kívül marad.
