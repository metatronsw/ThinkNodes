# ThinkNodes

Közös ötletvászon Swift 6.0.3 és Vapor szerverrel, Vue 3 szerkesztővel és D3 Zoom nagyítással. A passzív nézet szerveroldali HTML-t és SVG-t használ.

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

A közvetlen URL első megnyitása automatikusan létrehozza a lapot. Nyilvános módban egy vendég alapból megtekintheti és megnyitással létrehozhatja a hiányzó lapot. A vendégek létrehozási joga külön kikapcsolható. A módosításhoz bejelentkezés, a munkalap törléséhez adminisztrátori szerepkör kell. A törölt munkalap a **Data/.trash/** mappába kerül. Az útvonal ismételt megnyitása üres munkalapot hozhat létre.

A mintalap közvetlen címe **/otletlabor/tervezes**. A mentés atomi fájlcserét és revízióellenőrzést használ. Egy adatkönyvtárhoz egy futó szerverpéldány tartozik.

## Vászon

- Bal gombbal húzd a dobozt a mozgatáshoz. Üres területen a bal gomb a nézetet mozgatja. A görgő nagyít, a **Közép** gomb a **(0, 0)** pontot középre állítja. Az X jobbra, az Y lefelé nő.
- Jobb kattintással nyílik meg a doboz vagy a kábel műveleti menüje. A dobozra kattintva az oldalsáv a formázott Markdown-szöveget mutatja. Dupla kattintás megnyitja a szerkesztőt. A címke, a megjegyzés, a forma, a méret és a szín szerkesztés közben frissül. Az **Auto size** alapértelmezetten bekapcsolt. A **Show Markdown** a dobozban is láthatóvá teszi a Markdown szövegét.
- A **Ctrl + bal gombos húzás** kábelt indít a dobozból. A **Kapcsolás** gomb ugyanezt a módot kapcsolja be módosítóbillentyű nélkül. A kábel a kiemelt célhoz illeszkedik, üres helyre engedve vászonkoordinátára kerül.
- A kábel menüjében a **Cél leválasztása** megtartja a végpont helyét, az **Új cél kijelölése** áthelyezi azt, a **Kapcsolat törlése** eltávolítja a kábelt.

A szerkesztő **SVG letöltése** gombja a teljes vásznat exportálja egy SVG-fájlba, a képernyőn éppen látható nagyítástól és a mentéstől függetlenül. A megtekintő oldalon az SVG, a JSON és a Markdown a mentett munkalapból készül. A Markdown tartalmazza a dobozok szövegét és a kapcsolatokat.
