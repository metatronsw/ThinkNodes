# ThinkNodes fejlesztési terv

Első lépésként a meglévő Vapor-nézet kapjon teljes értékű, JavaScript nélküli olvasási módot. Erre épülhet a közös Swift modell, majd az iPhone-on, iPaden és Macen helyben szerkeszthető natív kliens. A szerverkapcsolat az offline projektek megosztását és az élő együttműködést adja hozzá.

## Mi vihető át Vaporba?

| Funkció | Jelenlegi megvalósítás | Javasolt hely |
| --- | --- | --- |
| Projektlista, allapok, előnézet, export, jogosultságok | A Vapor már HTML-t, SVG-t és JSON-t ad a tárolt munkalapokból | A webes és natív felület ugyanazokat a hozzáférési szabályokat használja. A natív kliens kapjon JSON-projektlistát. |
| Kijelölés, jegyzet, elemkeresés | A passzív kijelölést a `viewer.js` rajzolja. A `?note=<id>` már szerveroldali jegyzetnézet. | A Vapor rajzolja a kért elem kiemelését és részleteit. A keresés működhet GET-űrlappal. |
| Projekt- és lapműveletek | A `cards.js` a meglévő Vapor végpontokat hívja | Az átnevezéshez, létrehozáshoz és egyéb kezelési műveletekhez használhatók szerveroldali HTML-űrlapok. Sikeres POST után átirányítás, hiba esetén szerveroldali üzenet. Ez az olvasási módhoz opcionális. |
| Validálás, kábelek és konténerek szabályai, revízióütközés | A szerver validál és revíziót ellenőriz. A webes kliens saját módosítási, undo és összefésülési logikát futtat. | A tiszta dokumentumszabályok kerüljenek közös Swift modulba. A Vapor maradjon a szerveroldali jogosultság és az elfogadott revízió végső ellenőrzője. |
| Nagyítás, húzás, hit testing, ideiglenes kijelölés, helyi undo | A webes editor kezeli | Maradjanak kliensoldalon, a natív alkalmazásban Swiftben. A szerver a végleges módosítást kapja. Az élő mozgás, kurzor és jelenlét külön, átmeneti adat. |

A kiindulópontok a [Vapor útvonalak](Sources/ThinkNodes/Server.swift), az [SVG-renderelő](Sources/ThinkNodes/Rendering.swift), a [munkalapmodell és tároló](Sources/ThinkNodes/Model.swift), a [passzív kliens](Public/viewer.js) és a [webes összefésülés](Public/collaboration.js).

## Passzív nézet JavaScript nélkül

1. A főoldali projektkártyák, az allapok és az SVG már közvetlenül megjeleníthetők. Az elemlistához és a vászonhoz adjunk valódi hivatkozásokat. Például a `/projekt/lap?node=box-1#vaszon` megnyitásakor a Vapor a laphoz tartozó azonosítót ellenőrzi, SVG-keretet rajzol, és HTML-ben megmutatja a címet, a formázott jegyzetet és az elem célhivatkozását. Vonalakhoz legyen `?edge=<id>`. A régi `?note=<id>` linkek maradjanak használhatók.
2. Az SVG-elemen külön vezérlő nyissa meg a célhivatkozást, hogy a kijelölés és a navigáció egyaránt elérhető legyen egyszerű kattintással és billentyűzettel. A vászon alatti HTML-elemlista ugyanazt a kijelölést biztosítsa. A törölt elemre mutató linknél maradjon látható a munkalap, rövid állapotüzenettel.
3. A néző saját kijelölése az URL-ben maradjon, így újratölthető és megosztható. A többi szerkesztő kijelöléséből a Vapor az oldal lekérésekor rajzolhat pillanatképet a [jelenléti állapotból](Sources/ThinkNodes/Collaboration.swift). Ehhez olvasási művelet kell, amely nem foglal dobozt és nem hoz létre jelenléti munkamenetet. A „Frissítés” link őrizze meg a néző kijelölését. Az élő követéshez a meglévő JavaScriptes nézet marad használható.
4. Ellenőrzés kikapcsolt JavaScripttel, vendégként és bejelentkezve: projektlista → allap → doboz vagy kábel kijelölése → jegyzet vagy célhivatkozás. Külön ellenőrizendő a jelszavas lap feloldása és a billentyűzetes navigáció.

## Natív iOS, iPadOS és macOS kliens

- **Közös Swift csomag.** A `Worksheet`, `Idea` és a kapcsolatok tiszta `Codable` modellje, a JSON-migráció, a gráfszabályok és a geometria kerüljenek egy Vapor-független SwiftPM targetbe. A Vapor a HTTP-integrációt és a szervertárolót tartja meg. A régi JSON-formátumokat közös tesztadatokkal ellenőrizzük.
- **Natív vászon.** Közös SwiftUI-képernyők és `Canvas` a dobozokhoz, kábelekhez és kijelölési keretekhez. A találatvizsgálat világkoordinátákban történjen. Külön natív elemlista és hozzáférhetőségi vezérlők kellenek, mert a Canvas rajzelemei önmagukban nem interaktívak. UIKit/AppKit az iPades érintés és a Mac egér-, trackpad- és billentyűzetkezeléséhez, ahol szükséges. A jegyzetet Swiftből formázzuk. Az alkalmazás Swiftben fusson, WebView és JavaScript nélkül. [Apple Canvas dokumentáció](https://developer.apple.com/documentation/swiftui/canvas)
- **Helyi tárolás.** SQLite-tranzakcióban együtt mentsük a munkalap állapotát és a feltöltésre váró műveletet. A csatolmányok helyi fájlok legyenek, az adatbázisban a hivatkozásukkal. Már az első indításkor lehessen helyi projektet létrehozni, szerkeszteni, újranyitni és exportálni. Szerverfiók a szinkronhoz kell.

## Offline → szinkron → online

1. **Első feltöltés.** A felhasználó kiválasztja a célszervert és bejelentkezik. Új helyi projekthez a kliens manifestet, munkalapokat és csatolmányokat küld. A Vapor ideiglenes tárolóban validálja a teljes csomagot, majd egy lépésben teszi elérhetővé. A feltöltési azonosítóval ismételhető a kérés duplikálás nélkül. Új projekt alapból privát legyen. Útvonalütközésnél felhasználói döntés kell az új névről vagy egy meglévő projekt összekapcsolásáról.
2. **Korábban összekapcsolt projekt.** Projekt és lap kapjon az átnevezést túlélő azonosítót. Kapcsolódáskor a kliens először lekéri a szerver revízióit és a törléseket, majd a helyi változásokat az utolsó közös revízióból kiindulva küldi. A jelenlegi `If-Match` alap megtartható a laponkénti írásra. Külön mezők módosításai automatikusan egyesíthetők. Azonos mező, törlés és szerkesztés, illetve érvénytelen gráf esetén a kliens őrizze meg a helyi változatot és kérjen döntést. A törölt lap maradjon törlésként nyilvántartva, hogy egy régi offline másolat ne töltse fel újra.
3. **Megszakítás és átállás.** Csak a Vapor által visszaigazolt művelet kerül ki a várólistából. Az átvitelt újraindítható blokkokra kell bontani. Élő módba akkor váltson a lap, amikor az alaprevízió egyezik, az addigi helyi műveletek visszaigazolása megérkezett, és az élő kapcsolat felállt. Az átállás alatt keletkező helyi szerkesztés is kerüljön a várólistába. Hálózatvesztés után a helyi szerkesztés folytatható.
4. **Élő mód.** Első körben a natív kliens használhatja a meglévő munkalap- és jelenléti protokollt. A natív hitelesítés és az import kapjon dokumentált, verziózott API-t. A mozgáselőnézethez a `URLSessionWebSocketTask` használható. Az iOS-háttérszinkron legyen késleltethető, az app előtérbe kerülésekor folytatható. Az állapotjelző külön mutassa a helyi mentést, a szinkronizálást, a feloldandó konfliktust és az élő kapcsolatot. [Apple WebSocket dokumentáció](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask) · [Apple Background Tasks dokumentáció](https://developer.apple.com/documentation/backgroundtasks)

## Sorrend és elfogadási feltételek

1. **Vapor olvasási mód.** JavaScript nélkül megnyílik a munkalap, a kijelölés és a jegyzet.
2. **Natív offline kliens.** Repülő módban létrehozható és szerkeszthető a projekt. Az app újraindítása után a módosítások és a csatolmányok megvannak.
3. **Projektimport és szinkron.** Két eszközön tesztelendő az első feltöltés, a félbeszakadt feltöltés, az átnevezés, a törlés és az eltérő offline szerkesztések összefésülése.
4. **Élő együttműködés.** Egy natív és egy webes kliens ugyanazt a lapot szerkeszti. Kapcsolatvesztés és újracsatlakozás után a mentett adatok egyeznek.
