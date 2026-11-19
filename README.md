# ThinkNodes

Közös ötletvászon Swift 6.0.3 és Vapor szerverrel, Vue 3 szerkesztővel és D3 Zoom nagyítással. A megtekintő nézet szerveroldali HTML-t és SVG-t használ. JavaScripttel a jelenlétet és a vásznat is élőben frissíti.

## Indítás

Futtasd a projekt könyvtárából.

~~~sh
./build.sh --skip-update -j 2
./run.sh
~~~

Nyisd meg a [http://127.0.0.1:8080/admin](http://127.0.0.1:8080/admin) oldalt. Az első helyi megnyitáskor itt hozható létre az adminfiók. Az adminoldalon állítható a hozzáférés és kezelhetők a felhasználók. Adminfiókot parancssorból is létrehozhatsz a **./run.sh user admin admin** paranccsal, amely jelszót kér.

A build először a **~/X-Code/Swift/6.0.3/usr/bin/swift** binárist keresi. A **THINKNODES_SWIFT** változóval megadható másik útvonal. Az első teljes build letölti a rögzített Vue- és D3-verziót a **Public/vendor/** könyvtárba. Utána a böngésző helyben tölti be őket. A **./build.sh --server-only** csak a szervert építi. A **THINKNODES_DATA**, **THINKNODES_HOST**, **THINKNODES_PORT** és **THINKNODES_CONFIGURATION** változók felülírják az alapértékeket. HTTPS mögött állítsd a **THINKNODES_SECURE_COOKIES=1** változót.

## Munkalapok és fájlok

| URL | Adatfájl |
|---|---|
| **/munkalap1** | **Data/munkalap1.json** |
| **/mégnincsilyen** | **Data/mégnincsilyen.json** |
| **/gondolatok/otletek1** | **Data/gondolatok/otletek1.json** |

Egy munkalap egy JSON-fájl. Ebben van a munkalap címe, megjegyzése és Markdown-szövege, valamint a revízió, a dobozok és a kapcsolatok. A **Data/.settings.json** és **Data/.users.json** a szerver beállításait és a fiókokat tárolja. Utóbbiban a jelszavak helyett bcrypt-hashek vannak.

A közvetlen URL első megnyitása bejelentkezés után automatikusan létrehozza a privát lapot a bejelentkezett felhasználó nevére. A munkalapot a tulajdonos, a kijelölt szerkesztők és az adminisztrátorok szerkeszthetik. A tulajdonos és az admin állíthatja a nyilvánosságot és a szerkesztőket a Munkalap panelen. A nyilvános lap vendégként megtekinthető és letölthető, ha az adminoldalon a teljes oldal olvasásához nincs előírva a belépés. Régebbi, tulajdonos nélküli laphoz az admin rendelhet tulajdonost. A munkalap törléséhez adminisztrátori szerepkör kell. A törölt munkalap a **Data/.trash/** mappába kerül. Az útvonal ismételt megnyitása üres munkalapot hozhat létre.

A mintalap közvetlen címe **/otletlabor/tervezes**. A mentés atomi fájlcserét és revízióellenőrzést használ. Egy adatkönyvtárhoz egy futó szerverpéldány tartozik.

## Közös szerkesztés

A jobb felső névsor mutatja, kik vannak a munkalapon. A név melletti szín a kijelölt doboz körüli keret színe is. A kijelölés a szerkesztő böngészőfülhöz tartozik. Másik szerkesztő közben kábelt köthet a dobozhoz és le is választhat róla kábelt. Üres területre kattintás, az Escape vagy másik elem kiválasztása elengedi a kijelölést. Lapváltáskor és a fül bezárásakor is felszabadul a doboz. Megszakadt kapcsolat esetén a szerver időkorláttal oldja fel a zárolást.

A szerkesztő automatikusan ment. A szöveg, a formázás, a doboz húzása és a kábel csatlakoztatása megjelenik a többi megnyitott nézetben. Külön dobozok egyidejű szerkesztésekor mindkét felhasználó módosításai bekerülnek a munkalapba.

## Dobozlinkek és allapok

A doboz **Link** mezőjében a relatív út kiindulópontja maga a munkalap. A belső lapot láncszem, a webcímet földgömb jelöli a doboz jobb alsó sarkában. A hivatkozás ugyanabban a böngészőfülben nyílik meg.

| Link a `/main/labor` munkalapon | Cél |
|---|---|
| `jegyzet` vagy `./jegyzet` | `/main/labor/jegyzet` |
| `..` vagy `/..` | `/main` |
| `../tervek` | `/main/tervek` |
| `/archiv/otletek` | `/archiv/otletek` |
| `https://example.com/` | A megadott weboldal |

Az új allap első bejelentkezett megnyitáskor jön létre. Az allap szerkesztőit és nyilvánosságát a saját **Munkalap** paneljén állíthatod be.

## Vászon

- Bal gombbal húzd a dobozt a mozgatáshoz. Üres területen a bal gomb a nézetet mozgatja. A görgő nagyít, a **Közép** gomb a **(0, 0)** pontot középre állítja. Az X jobbra, az Y lefelé nő.
- Jobb kattintással nyílik meg a doboz vagy a kábel műveleti menüje. A dobozra kattintva a nyitott oldalsáv a formázott Markdown-szöveget mutatja. A **Ctrl + dupla kattintás** megnyitja a doboz szerkesztőjét. A sima dupla kattintás a doboz linkjét követi vagy megnyitja a jegyzetét. A címke, a megjegyzés, a forma, a méret és a szín szerkesztés közben frissül. Az **Auto size** alapértelmezetten bekapcsolt. A **Show Markdown** a dobozban is láthatóvá teszi a Markdown szövegét.
- A **Ctrl + bal gombos húzás** kábelt indít a dobozból. A kábel a kiemelt célhoz illeszkedik, üres helyre engedve vászonkoordinátára kerül.
- Dupla kattintás a vonalra megnyitja a címke, a szín, a vastagság, a nyílirányok és a vonaltípus beállításait. Mindkét végpont leválasztható és húzható, majd dobozhoz kapcsolható. A doboz törlésekor a hozzá tartozó kábelek végpontjai a helyükön maradnak.
- A csatlakoztatott végpontot **Ctrl + húzással** lehet leemelni. A húzás közben a Ctrl elengedhető. Két kábel szabad végének összeillesztése névvel és színnel ellátható csomópontot hoz létre. A csomópont az utolsó kábel lecsatlakoztatásáig marad a lapon.
- Az **Alt** megjeleníti a méretező sarkokat. Automatikus méretezéskor a sarok húzása arányosan változtatja a betűméreteket, és megadja a doboz új minimális méretét. Kézi méretezéskor a betűméretek rögzítettek.
- A **Konténer** gomb az átfedő, azonos szinten lévő dobozokat a konténerhez rendeli. Behúzáskor a mozgatott elem területének több mint fele kell, hogy a célkonténerben legyen. Egymásba ágyazott céloknál a legbelső alkalmas konténer fogadja az elemet. A **Lock** a tartalom önálló mozgatását rögzíti. A **Konténer feloldása** egy szinttel kijjebb helyezi a közvetlen tagokat a vásznon elfoglalt helyük megőrzésével.
- A **Munkalap** panelen állítható a pontrács színe és térköze. A bal alsó rácsgomb állapotát a munkalap menti, és az SVG-export is követi.
- A cím és a Markdown egymástól függetlenül a doboz kilenc pozíciójához igazítható. A megjegyzés külön vízszintes igazítást kap. A színmintára kattintva megnyílik a helyi paletta, az RGB-csúszkák és a rendszer színválasztója. A HEX-mező közvetlenül szerkeszthető.

A szerkesztő **SVG letöltése** gombja a teljes vásznat exportálja egy SVG-fájlba, a képernyőn éppen látható nagyítástól és a mentéstől függetlenül. A megtekintő oldalon az SVG, a JSON és a Markdown a mentett munkalapból készül. A Markdown tartalmazza a dobozok szövegét és a kapcsolatokat.

A szerver az 1-es és a 2-es verziójú munkalapokat olvassa. Mentéskor a konténerek, csomópontok és formázások a 2-es verziójú munkalap-JSON-ba kerülnek.
