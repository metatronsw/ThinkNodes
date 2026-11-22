# `.web` prezentációs mappák – megvalósítási terv

## Cél

Lehetővé tenni teljes, statikus HTML-prezentációk tárolását egy ThinkNodes projektben és Vaporon keresztüli kiszolgálását. Ezek a ThinkNodes-en belüli prezentációk nem külön domaineken működő, produkciós weboldalak. Egy projekt több, egymástól külön jogosultsággal kezelhető prezentációt tartalmazhat.

## Rögzített tárolási és URL-forma

Egy `NAME.web` könyvtár közvetlenül a projekt könyvtárában áll. Az URL-ben a `.web` kiterjesztés helyett a `web/NAME` útvonal jelenik meg:

| URL | Fájlrendszer |
| --- | --- |
| `/demoproject/web/prezi/index.html` | `Projects/demoproject/prezi.web/index.html` |
| `/demoproject/web/masik/index.html` | `Projects/demoproject/masik.web/index.html` |
| `/demoproject/web/prezi/css/main.css` | `Projects/demoproject/prezi.web/css/main.css` |

Az `index.html` az alapértelmezett belépési fájl. A prezentáció relatív hivatkozásai (CSS, JS, képek, almappák) az adott prezentáció könyvtárán belül maradnak. A projekt szabályai alatti könyvtárakban lévő web mappák támogatását is úgy kell kialakítani, hogy a teljes projektbeli relatív helyük egyértelmű legyen; például `Projects/demoproject/anyagok/prezi.web/` útvonala `/demoproject/anyagok/web/prezi/` lehet. A gyökérszintű projektpéldák az első implementáció kötelező esetei.

## Jogosultsági modell

Minden kiszolgált fájlkérésnél a Vapor a projektbeli hely alapján határozza meg az erőforrás dokumentum-hozzáférési láncát. A hozzáférés a meglévő szabályrendszerhez illeszkedjen:

1. A projekt hozzáférési szabályai érvényesek.
2. A projekt alatti könyvtárak örökölt szabályai érvényesek.
3. A konkrét `NAME.web` mappa saját, felülírható olvasási szabályokat kaphat a ThinkNodes már használt `.settings.json` mechanizmusával összhangban.
4. Egy gyermek szabálya szűkítheti az örökölt hozzáférést, de nem tágíthatja ki azt. A belépés nélküli publikus olvasást a meglévő `guestReadable` szemantikával kell összehangolni.
5. A meglévő bejelentkezés, szerepkörök, jelszavas feloldás és session-unlock működés maradjon következetes. Jelszóval védett web mappa feloldása után a böngésző a kért fájlt vagy `index.html`-t kapja meg; a feloldási folyamat ne szivárogtassa ki a fájl tartalmát.

A jogosultságot minden erőforráskérésnél ellenőrizni kell, nem csak az `index.html` betöltésekor. A CSS, kép vagy JavaScript URL közvetlen megnyitása ugyanazt a hozzáférés-ellenőrzést kapja.

## Vapor útvonal és kiszolgálás

- Vegyen fel dedikált route-ot a `/{projekt és esetleges alkönyvtárak}/web/{web-név}/{fájl útvonala...}` alakhoz. Ügyeljen az útvonalütközésekre a meglévő worksheet, API, edit és export route-okkal.
- A route a meglévő `WorksheetPath`, `WorksheetStore` és `DocumentAccess` konvenciókat használja, amennyire azok megfelelőek; a `.web` mappa keresését és jogosultságát célszerű a store-ba tenni, nem a route handlerben megkerülni a tárolási réteget.
- Ha fájlrész nincs megadva, szolgálja ki `index.html`-t. Ha a kért útvonal könyvtárra mutat, viselkedjen ugyanígy. Könyvtárlistázás ne legyen.
- Csak létező, normál fájl szolgálható ki. Ismeretlen fájlra 404-et adjon.
- A kiszolgálás a Vapor által olvasott streamen keresztül történjen. Ne tegyen projektadatot a `Public` könyvtárba és ne engedje megkerülni a hozzáférés-ellenőrzést a statikus `FileMiddleware`-rel.
- A megfelelő MIME-típusokat legalább HTML, CSS, JavaScript, JSON, SVG, PNG, JPEG, GIF, WebP, ICO, WOFF/WOFF2, TXT, MP4, WEBM és PDF esetén állítsa be. Ismeretlen típusnál biztonságos általános típust használjon.
- Az oldal és erőforrásai kapjanak `X-Content-Type-Options: nosniff`, megfelelő cache policy-t (jogosultságfüggő tartalomnál alapértelmezésként `no-store`), és átgondolt CSP-t. Ne adjon olyan fejlécet, amely aláássa az oldal tartalmi elkülönítését.

## Fájlrendszer-biztonság

- Az URL dekódolása után az útvonalat szegmensenként validálja. Elutasítandó a `..`, abszolút útvonal, üres/érvénytelen név, null byte, backslash-alapú útvonaltrükk és a kódolt elválasztóval való kilépési kísérlet.
- A végső, standardizált és symlink-feloldott fájlútvonalnak a kiválasztott `.web` gyökér alatt kell maradnia. A `.web` könyvtárig vezető komponensek és a webfán belüli fájlok symlinkjei ne vezessenek ki a megengedett gyökérből. Kiszolgálás előtt a fájltípus és a létezés ellenőrzendő.
- Rejtett ThinkNodes belső fájlok és `.settings.json` ne legyenek weben keresztül elérhetők, akkor sem, ha közvetlen URL-lel kérik őket.
- A `.web` névfeloldása csak a megengedett projektkönyvtárakban történjen; ne fogadjon a kliens által megadott tetszőleges fájlrendszerútvonalat.
- A projekt szabályainak megfelelő hozzáférés-ellenőrzés előzze meg az esetleges fájllétezési információk kiszivárgását, a meglévő alkalmazás konvencióit követve.

## Canvas-előnézet és szerkesztői élmény

- Egy `.web` mappa legyen beszúrható/megadható dobozként a canvasban, hasonlóan a meglévő fájl- és worksheet-dobozokhoz.
- A doboz tárolja a prezentáció projektbeli relatív nevét, ne abszolút fájlútvonalat. A szerver minden alkalommal ebből oldja fel az URL-t.
- A doboz előnézete mutassa a prezentáció nevét és lehetőség szerint az `index.html`-ből vagy külön `preview.png`-ből készített képet. Az automatikus HTML-renderelés iframe-ben kezdetben opcionális; ha elkészül, sandboxolt és jogosultságon át kiszolgált preview legyen.
- Dupla kattintás új böngészőfülön nyissa meg a teljes prezentációt a ThinkNodes URL alatt. A felugró ablak tiltásának kezelésére a kattintási művelet közvetlen felhasználói eseményhez kapcsolódjon.
- A canvas hivatkozhasson a dobozra stabil URL-lel, és a meglévő linkmásolási, kijelölési, mozgatási és törlési műveletekkel működjön együtt.
- Import első körben meglévő fájlok projektbe helyezését jelentse. ZIP-import csak külön döntés után készüljön; ha készül, kicsomagoláskor ugyanazokat az útvonal- és symlink-szabályokat kell érvényesíteni.

## Javasolt fejlesztési szakaszok

1. **Adatmodell és store API:** `.web` mappa feloldása, jogosultság-összesítés, biztonságos relatív fájlkeresés. Határozza meg a web mappák listázását és szerkesztői kezelését.
2. **Vapor kiszolgálás:** dedikált URL-route, index-fallback, jogosultság, MIME és válaszfejlécek.
3. **Canvas-integráció:** web doboz reprezentáció, preview megjelenítés, új fülön nyitás és linkmásolás.
4. **Jogosultságkezelő UX:** ha a meglévő beállítófelület nem tudja a `.web` szabályokat szerkeszteni, adjon célzott felületet a web mappa hozzáférési szabályainak módosítására.
5. **Dokumentáció és ellenőrzés:** használati útmutató, URL-példák, jogosultsági esetek és fájlútvonal-biztonság ellenőrzése.

## Elfogadási feltételek

- A megadott két példa URL a megfelelő fizikai `*.web` könyvtár `index.html` fájlját jeleníti meg.
- Egy projekten belül több, külön névvel rendelkező web mappa működik; a statikus almappák és relatív erőforrás-hivatkozások betöltődnek.
- Publikusan olvasható mappa kijelentkezve elérhető, zárt mappa csak a meglévő jogosultsági folyamat után. Közvetlen asset URL sem kerüli meg ezt.
- Projekt-, könyvtár- és webmappa-szabályok együtt érvényesülnek; az öröklés csak szűkíthető.
- A `../`, kódolt traversal, symlinkes kilépés, rejtett fájl és `.settings.json` nem szolgálható ki.
- A vászon doboz megnyitása új fülön a helyes prezentációt tölti be.
- A normál worksheet-route-ok, login/unlock folyamatok és meglévő statikus `Public` assetek viselkedése változatlan marad.

## Implementációs megjegyzés

A megvalósítás módosítani fogja a `Sources/ThinkNodes/Server.swift` fájlt. Szerverkód-változtatás után a Vapor szervert újra kell indítani.
