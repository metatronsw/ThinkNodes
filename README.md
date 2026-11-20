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

A főoldalon a felső szintű projektek szerepelnek. A paklit a projektmappában közvetlenül található JSON-fájlok száma határozza meg. Az új projekt nyilvános módban indul. Minden bejelentkezett szerkesztő módosíthatja, belső módban pedig külön hozzáférés adható.

A jobb kattintásos projektmenüben beállítható a láthatóság, a jelszár, a szerkesztési zár és a hozzáférés. A mappára adott jog és a mappaszintű zár az alatta lévő munkalapokra is érvényes. A jelszó csak hashként kerül az adatkönyvtár közös `.document-policies.json` fájljába. A munkalaphoz tartozó képek és dokumentumok a megtekintő **Mappa tartalma** szekciójában jelennek meg. Egy csatolt fájlhoz külön hozzáférés is adható.


A helyi **/demo** bemutató többszintű projekt külön kutatási, tervezési, megvalósítási és mérési munkalapokkal. A főoldali kártyák a munkalap háttérszínét használják, az elcsúsztatott lapok az allapokat jelzik. Jobb kattintással megnyitható a kártyamenü. Egy rejtett projekt kártyáját az adminisztrátor látja a főoldalon. A közvetlen hivatkozásra a munkalap meglévő olvasási és szerkesztési jogosultságai érvényesek.

| URL | Adatfájl |
|---|---|
| **/munkalap1** | **Projects/munkalap1.json** |
| **/mégnincsilyen** | **Projects/mégnincsilyen.json** |
| **/gondolatok/otletek1** | **Projects/gondolatok/otletek1.json** |

Egy munkalap egy JSON-fájl. A tárolt és letöltött JSON rövid kulcsokat használ, például `pos`, `align`, `textCol`, `w`, `h` és `vAlign`. A munkalap API ugyanezeket a rövid kulcsokat használja. Ebben van a munkalap címe és formázott Text mezője, valamint a revízió, a dobozok és a kapcsolatok. A **Projects/.settings.json** és **Projects/.users.json** a szerver beállításait és a fiókokat tárolja. Utóbbiban a jelszavak helyett bcrypt-hashek vannak.

Önálló munkalapnál a közvetlen URL első megnyitása bejelentkezés után automatikusan létrehozza a privát lapot a bejelentkezett felhasználó nevére. A munkalapot a tulajdonos, a kijelölt szerkesztők és az adminisztrátorok szerkeszthetik. A tulajdonos és az admin állíthatja a nyilvánosságot és a szerkesztőket a Munkalap panelen. A nyilvános lap vendégként megtekinthető és letölthető, ha az adminoldalon a teljes oldal olvasásához nincs előírva a belépés. Régebbi, tulajdonos nélküli laphoz az admin rendelhet tulajdonost. A munkalap törléséhez adminisztrátori szerepkör kell. A törölt munkalap a **Projects/.trash/** mappába kerül. Az útvonal ismételt megnyitása üres munkalapot hozhat létre.

A mentés atomi fájlcserét és revízióellenőrzést használ. Egy adatkönyvtárhoz egy futó szerverpéldány tartozik.

## Közös szerkesztés

A vászon bal felső sarkában, csatlakozási sorrendben megjelenő névsor mutatja, kik vannak a munkalapon. A név melletti szín a kijelölt doboz körüli keret színe is. A kijelölés a szerkesztő böngészőfülhöz tartozik. Másik szerkesztő közben kábelt köthet a dobozhoz és le is választhat róla kábelt. Üres területre kattintás, az Escape vagy másik elem kiválasztása elengedi a kijelölést. Lapváltáskor és a fül bezárásakor is felszabadul a doboz. Megszakadt kapcsolat esetén a szerver időkorláttal oldja fel a zárolást.

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

A vászon jobb kattintásos menüjében az **Új munkalap** létrehozza az allapot és a rá mutató dobozt. Az allap a szülő háttérszínét, rácsbeállításait, tulajdonosát, szerkesztőit és nyilvánosságát örökli. Ezek később a saját **Munkalap** paneljén módosíthatók. A munkalapkártyán a létrehozó és a látható közvetlen allapok száma szerepel. Megtekintéskor az allapok mentett SVG-előnézete a vászon alatt található. A fejléc útvonala kattintható, a felfelé mutató nyíl a szülőlapra visz.

## Vászon

- Bal gombbal húzd a dobozt a mozgatáshoz. Üres területen a bal gomb a nézetet mozgatja. A görgő nagyít, a **Közép** gomb a **(0, 0)** pontot középre állítja. Az X jobbra, az Y lefelé nő.
- Jobb kattintással nyílik meg a doboz vagy a kábel műveleti menüje. A kijelölés megnyitja az oldalsávot, a kijelölés megszüntetése a munkalap tulajdonságait mutatja. A jobb felső nyíllal kézzel bezárt panel a következő kijelöléskor is zárva marad. Szerkesztésben az objektumra duplán kattintva a tulajdonságpanelen a teljes címke kijelölődik, és gépeléssel átírható. A link szerkesztésben az ikonra, megtekintésben a dobozra duplán kattintva követhető. A külső hivatkozások külön böngészőablakban vagy lapon nyílnak meg. Az objektum menüjében a **Link** és a **Link feloldása** kezeli a hivatkozást. A **Ping** a résztvevők vásznán egy rövid, táguló kerettel emeli ki a dobozt. A cím, a Text mező, a forma, a méret és a szín szerkesztés közben frissül. A **Hide text** alapból ki van kapcsolva. Bekapcsolásakor a szöveg helyén ••• jelenik meg. A doboz fölé vitt egérrel olvasható a formázott szöveg.
- Az **Enter** megnyitja a munkalap gyorskeresőjét. Enterrel vagy Esc-kel bezárható. Az **Esc** a vásznon először megszünteti a kijelölést, kijelölés nélkül bezárja a panelt. A **Delete** és a **Backspace** törli a kijelölt objektumot. Ctrl-lal együtt a csomópont kábelei, konténernél a tartalmazott objektumok és a hozzájuk vagy a konténerhez kötött kábelek is törlődnek.
- Egy adott kezdőobjektumtól egy adott célobjektumig egy kábel csatlakozhat. Két szabad vég összeillesztésekor zöld kör jelzi a leendő csomópont helyét.
- A **Ctrl + bal gombos húzás** kábelt indít egy dobozból vagy a vászon üres pontjáról. A kábel a kiemelt célhoz illeszkedik, üres helyre engedve vászonkoordinátára kerül.
- Ctrl + kattintás a vonal belsejére csomópontot szúr be, és két kábelszakaszra osztja a vonalat. Az új pont ugyanazzal a húzással a helyére vihető. A kijelölt vonal alatt a felhasználó színével folytonos vonal jelenik meg. Dupla kattintással nyílnak meg a vonal beállításai. Külön gombsoron választható a geometria (Egyenes, S-forma, Villám, Íves, Kötél) és a megjelenés (Sima, Vastag, Szaggatott, Pontozott). A nyilak, az alapszélesség és a szín külön állíthatók. Mindkét végpont leválasztható és húzható, majd dobozhoz kapcsolható. A doboz törlésekor a hozzá tartozó kábelek végpontjai a helyükön maradnak.
- A végpontot a teljes nyílhegy megfogásával lehet húzni. Nyílhegy nélküli végponton azonos méretű láthatatlan téglalap szolgál fogófelületként. Két kábel szabad végének összeillesztése címke nélküli csomópontot hoz létre. A címke, az átmérő és a szín a csomópont paneljén módosítható. Ha már csak egy kábel maradna a csomóponton, a csomópont eltűnik, és a kábel vége ugyanazon a helyen szabaddá válik.
- Az **Alt** megjeleníti a méretező sarkokat. A sarkot húzva a doboz mérete változik. A cím és a Text betűmérete külön állítható. Alt+húzás a dobozon a kapcsolataival együtt másolja a dobozt. Alt+dupla kattintás a teljes Text mezőt kijelöli.
- A **Konténer** gomb az átfedő, azonos szinten lévő dobozokat a konténerhez rendeli. Behúzáskor a mozgatott elem területének több mint fele kell, hogy a célkonténerben legyen. Egymásba ágyazott céloknál a legbelső alkalmas konténer fogadja az elemet. A **Lock** a tartalom önálló mozgatását rögzíti. A **Konténer feloldása** egy szinttel kijjebb helyezi a közvetlen tagokat a vásznon elfoglalt helyük megőrzésével.
- A pontrács melletti **Rácsra igazítás** a mozgatott objektum közepét a legközelebbi rácspontra illeszti. Alapértelmezésben ki van kapcsolva. A **Munkalap** panelen állítható a pontrács láthatósága, színe és térköze. A vászon alján lévő Pontrács gomb az adott böngészőfülön felülbírálja a munkalap alapbeállítását. Az exportált SVG rács nélkül készül.
- A **Dobozon kívül** kapcsoló a címet a doboz mellé helyezi. A Text a dobozon belül marad. Ilyenkor nyolc külső igazítás választható. A cím és a Text egymástól függetlenül a doboz kilenc pozíciójához igazítható. A cím és a szöveg helyét Ctrl+Alt+húzással is beállíthatod. A színmintára kattintva megnyílik a helyi paletta, az RGB-csúszkák és a rendszer színválasztója.

A Munkalap panel **SVG letöltése** gombja a teljes vásznat exportálja egy SVG-fájlba, a képernyőn éppen látható nagyítástól és a mentéstől függetlenül. A megtekintő oldalon az SVG, a JSON és a Text export a mentett munkalapból készül. A Text export tartalmazza a dobozok szövegét és a kapcsolatokat.

A munkalapok a rövid kulcsú, 2-es verziójú JSON-formátumban készülnek. A **Projects/** mappa tartalma helyi adatként a Git-követésen kívül marad.
