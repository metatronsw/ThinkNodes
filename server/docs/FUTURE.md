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

# Felmérések: WebAssembly, WebGL és natív kliens (2026-11-25)

Kiindulás: a `docs/PERF.md` mérései (Safari 18.6, `p300` / `p1000`). A cél a lehető legjobb teljesítmény. Kód nem változott,
ez csak felmérés.

## WebAssembly kliens

**Megvalósítható, a szerver lényegében változatlan marad.** A kliens statikus fájlokból áll, JSON-API-n és WebSocketen
beszél, a Vapor ismeri az `application/wasm` típust. Legfeljebb a `.wasm` kerüljön a tömörített típusok közé.

**Önmagában nem gyorsítana.** A megmaradt akadások a böngésző rajzolásában vannak, nem a JavaScriptben: nagyítás végi
újrafestés (80–190 ms), Alt/Ctrl stílusszámítás (~30 ms), foreignObject-réteg újrafestése, SVG-szűrők, animált vonalak. A
táblázat húzásának szkriptideje már 6 ms. A WASM a DOM-ot csak JS-en át éri el, így egy WASM-ból vezérelt SVG-vászon nem
lenne gyorsabb.

Ahol előnyt adna:
- **Számításigényes, tiszta logika Web Workerben:** táblázat képletmotorja nagy táblán, CSV-feldolgozás, nagy fájlok
  kódszínezése, vonalútvonalak és találatvizsgálat sok ezer elemnél. Előbb mérni kell, most egyik sem szűk keresztmetszet.
- **Egy forrás:** a `ThinkTable` és a `ThinkHighlight` most Swiftben és JS-ben is meg van írva (`table/*`, `highlight/*`).
  WASM-ra fordítva a JS-másolat megszűnhet. Ez karbantartási, nem sebességbeli nyereség.
- **Saját renderelő** (WebGL) logikája futhat WASM-ban – lásd alább.

Kivitelezés: Swift 6.x (swift.org) + WebAssembly SDK; a helyi Xcode 5.9.2-es fordítója nem tud WASM-ot. A modulok
Foundationt használnak (9 fájlból 8), így a `.wasm` több MB lehet; Embedded Swifttel kicsi, de Foundation nélkül. Alternatíva
egy-egy forró ponthoz: Rust / C. A WASM a Workerben fut, ugyanazt a felületet adja, mint a mostani JS, és ha nem töltődik be,
a JS dolgozik tovább.

## WebGL vászon

Az `editor.js` (6048 sor) felosztása és sorsa WebGL-nél:

| Rész | Sor | WebGL-nél |
|---|---|---|
| Rajzolás (`renderNode`, `renderEdge`, `renderCanvas`, rétegkomponensek) | ~580 | teljesen új |
| Rajzoló segédek (`shape`, `wireDrawing`, `animatedWire`, árnyék, liquid) | ~230 | új, a logika átvehető |
| Nézet, nagyítás, rács (d3-zoom, rétegtrükkök) | ~350 | nagyrészt új |
| Mozdulatok, kijelölés, húzás | ~665 | átalakítás: saját találatvizsgálat |
| Szöveg-, kód-, táblázat-, fájl- és grafikondobozok | ~1110 | átalakítás: DOM-rétegként maradnak |
| Állapot, közös szerkesztés, mentés, visszavonás | ~670 | marad |
| Objektumműveletek | ~620 | marad |
| Menük, billentyűk, verziók | ~450 | marad |
| Gyors eszközök, inspector, keresés, fejléc | ~1080 | marad |
| UI-segédek | ~300 | marad |

A `geometry.js` (936 sor) szinte teljesen újrahasznosítható: tiszta számítás, a szövegszélességet betűtáblából becsli.
A `containers.js`, `collaboration.js`, `editor-history.js` és a táblázatmotor marad; a `glow.js`, `ping.js`, `justify.js`
helyett új megoldás kell.

Nehéz pontok, a legnehezebbtől:
1. **Szöveg:** markdown-formázás, sorkizárás, címsorok, ékezetek, emoji, tetszőleges betűtípus. Út: dobozonként Canvas2D-vel
   raszterizált textúra nagyítási szintenként (egyszerűbb), vagy SDF/MSDF betűatlasz (mindig éles, bonyolult).
2. **HTML-tartalmú dobozok** (táblázat, CSV, szöveg- és kódfájl, markdown-megjegyzés, d3-grafikon, hang, szerkesztők): DOM-réteg
   a vászon fölött a kamerával transzformálva – a Safari foreignObject-hibái megszűnnek. Gond a rétegsorrend (a DOM mindig
   felül van): nyugalomban saját Canvas2D-rajzolóval textúra, csak a szerkesztett doboz élő DOM; a grafikonok Canvas2D-re.
3. **Találatvizsgálat:** most 30 elemenkénti eseménykezelő és `getTotalLength` / `getPointAtLength`. Helyette térbeli index
   (quadtree / R-fa) és geometriai találat (`shapeDistance`, `edgeInRectangle` már megvan).
4. **Vonalak:** vastagított vonal illesztéssel és kerek véggel, szaggatás, nyilak, elvékonyodó ív, címkehézag, adatvonal-dugó.
5. **Effektek és animációk:** glow, liquid glass, neon fényudvar, árnyék, dobozanimációk, pulzálás, futó pötty, ping – shaderek
   és saját animációs ciklus; itt nyer a legtöbbet. A `[data-effects="liquid"]` CSS-szabályokat shader-paraméterekre kell fordítani.
6. **Akadálymentesség:** 81 `tabindex` / `role` / `aria-*` hely; rejtett, párhuzamos DOM-lista kell.
7. **Megtekintő:** a `viewer.js` és a `Rendering.swift` (1733 sor) SVG-t rajzol. Vagy a megtekintő is WebGL-t kap (az SVG csak
   exportra marad), vagy két rajzoló kinézetét kell kézzel egyformán tartani.

Utak:
- **A) Teljes WebGL** (DOM csak szerkesztéshez): legnagyobb gyorsulás, kb. 4–7 ezer sor új kód.
- **B) Hibrid (javasolt kezdés):** WebGL a rácsra, felületekre, vonalakra, kijelölésre, effektekre, képekre; szöveg
  Canvas2D-textúra; tartalmas dobozok nyugalomban textúra, szerkesztéskor DOM. Lépésenként bevezethető, az SVG-rajzoló közben
  tartalék.
- **PixiJS** (WebGL/WebGPU, alakzatbontás, szöveg, szűrők): sokkal kevesebb saját kód, ~150–200 KB függőség.

A Vue a panelekhez, menükhöz, inspectorhoz marad. Első lépés: egy próba, amely csak dobozokat, vonalakat és rácsot rajzol, és
mérés a `p1000` lapon (most: csoport húzása 24,8 fps, gyors nagyítás 23,9 fps), mielőtt a szöveg és a rétegsorrend jön.

Becslés: kb. 3–5 hónap.

## Natív iOS / iPadOS / macOS kliens – felmérés a mostani kódhoz

A fenti „Natív iOS, iPadOS és macOS kliens” irányterv kiegészítése.

**Ami Swiftben már megvan:**

| Rész | Állapot |
|---|---|
| `ThinkTable`, `ThinkHighlight` | Vapor-független, azonnal használható |
| Modell (`Idea`, `Connection`, `Worksheet`, `Point`, enumok; `Model.swift`) | `Codable`, de a fájl a Vaporra épül (`Content`, `Abort`, benne a tároló is) – ki kell emelni |
| Markdown-tördelés (`CanvasMarkdown.swift`, swift-cmark) | megvan, a JS-tördelés párja |
| Vonalgeometria, nyíl, elvékonyodó ív (`Rendering.swift`) | részben, SVG-szövegbe ágyazva; a matematika átvehető |

**Ami a JS-szerkesztőből portolandó:** `geometry.js` (936 sor), `containers.js` (98), objektumműveletek (~620),
mozdulatok és találatvizsgálat (~665), mentés / összefésülés / visszavonás (~950: `editor.js`, `collaboration.js`,
`editor-history.js`), tartalmas dobozok és táblázatszerkesztés (~1900, natívan sok része egyszerűbb), inspector, gyors
eszközök, menük, keresés, verziók (~1500, SwiftUI-ban), rajzolás (~800, új). Becslés: 10–15 ezer sor Swift (a webkliens
13,4 ezer sor JS + 1,2 ezer CSS).

**Szerveroldali módosítás (kicsi):**
- Módosítás nélkül működik: `GET`/`PUT /api/worksheet` (`If-Match`), `/api/browse`, `/api/presence` (long poll),
  `/api/motion` (`URLSessionWebSocketTask`), verziók, csatolmányok, előnézeti képek, jelszavas `POST /login` (süti).
- Kell: `GET /api/session` JSON-ben (CSRF, felhasználó, szerep, beállítások) – most csak HTML-be ágyazva jön (`data-csrf`,
  `data-role`, `data-themes`, `data-preferences`).
- Google-bejelentkezés: az `ASWebAuthenticationSession` saját sütitárat használ, ezért átadó lépés kell (visszairányítás az app
  sémájára egyszer használható tokennel, amelyet az app munkamenetre cserél).
- LAN-tanúsítvány: az iOS (ATS) elutasítja a saját aláírásút – tanúsítványrögzítés az appban (`URLSessionDelegate`) vagy
  telepített profil; szerveroldali módosítás nélkül.
- Témák: statikus JSON (`Public/themes/*.json`), letölthető; a témalistához jól jönne egy kis végpont.
- Az offline mód és szinkron (lent, 2–3. lépés) jelentős szerveroldali munka; egy első, csak online változathoz nem kell.

**Rajzolás:** javasolt Core Animation rétegfa (`UIView` / `NSView`, saját kamera). Pásztázás és nagyítás egy
rétegtranszform; dobozonként és vonalanként csak a változott réteg rajzolódik újra; glow és árnyék rétegtulajdonság
(`shadowPath`); animációk `CABasicAnimation` / `CAKeyframeAnimation`, ProMotionnel 120 Hz; nagyítás végén a szövegrétegek
`contentsScale`-je újraállítandó. A SwiftUI `Canvas` egyszerűbb, de minden változásra az egész jelenetet újrarajzolja (1000+
objektumnál szöveggel szűk lehet). Metal csak akkor, ha a rétegfa nem elég.

Natívan egyszerűbb, mint WebGL-ben: szöveg (Core Text / TextKit 2), markdown (swift-cmark → `AttributedString`), kódfájl
(`ThinkHighlight` + TextKit), táblázat (saját rácsrajzoló, modell: `ThinkTable`), grafikon (Swift Charts), hang (AVFoundation),
képek. Nincs rétegsorrend-gond, minden egy rétegfában van. Nehéz: saját találatvizsgálat, akadálymentesség
(`accessibilityElements`), az iPad érintés / Pencil és a Mac egér / trackpad / gyorsbillentyűk (`docs/hotkeys.json`) eltérő
bemenete; iPhone-on valószínűleg csak megtekintés.

**Három rajzoló kockázata:** ma a JS-szerkesztő és a `Rendering.swift` rajzol, a natív app lenne a harmadik. Javaslat: közös
`ThinkModel` Swift-modul (modell, migráció, típusregiszter, szabályok, geometria, szövegelrendezés, összefésülés), amelyet a
szerver és az app is használ; később WASM-ra fordítva a webkliens logikáját is adhatja.

**Munkabecslés** (egy tapasztalt fejlesztő, durva nagyságrend):

| Szakasz | Tartalom | Idő |
|---|---|---|
| 0. Közös mag | modell kiemelése a Vaporból, `geometry.js` portolása, tesztek közös tesztadatokon | 3–5 hét |
| 1. Megtekintő app | bejelentkezés, projektlista, minden típus kirajzolása, pásztázás, nagyítás, élő frissítés | 4–6 hét |
| 2. Alapszerkesztés | kijelölés, mozgatás, átméretezés, létrehozás, vonalak, szöveg, visszavonás, mentés és összefésülés | 6–8 hét |
| 3. Teljes szerkesztő | inspector, gyors eszközök, témák és effektek, táblázat, fájlok, grafikon, verziók | 6–10 hét |
| 4. Élő együttműködés | jelenlét, mozgás WebSocketen, mások kurzora és cellakijelölése | 2–3 hét |
| 5. Offline és szinkron (opcionális) | lent, szerveroldali munkával | 6–10 hét |

Online MVP (0–4.): kb. 5–7 hónap.

**Fejlesztőgép:** macOS 13.7.8, Xcode 15.2 (Swift 5.9.2), Intel. A `Package.swift` `swift-tools-version: 6.0`-t az Xcode 15
nem nyitja meg (a közös modulnak 5.9-es manifest kell, vagy újabb Xcode). Az Xcode 16 legalább macOS 14.5-öt kér; az App
Store-ba feltöltéshez 2026 tavasza óta (ellenőrizendő) az Xcode 26 SDK kell, az macOS 15.6-ot. Ellenőrizni, hogy a gép
frissíthető-e; saját eszközre Xcode 15-tel is lehet fejleszteni.

## Összevetés

| | WebGL-hibrid | Natív Swift |
|---|---|---|
| Teljesítmény | nagy javulás | a legnagyobb (Core Animation / Metal, 120 Hz) |
| Szöveg, HTML-tartalom | a legnehezebb rész | natívan megoldott |
| Platformok | minden böngésző | csak Apple |
| Szerveroldali módosítás | nincs | kicsi (munkamenet-végpont, Google-átadás) |
| Fenntartás | egy kliens marad | két kliens, közös maggal enyhítve |
| Munka | ~3–5 hónap | ~5–7 hónap (MVP) |

Ha a cél a teljesítmény saját Apple-eszközökön, és a web maradhat a mostani optimalizált SVG, a natív app a jobb befektetés.
Ha mindenkinek, böngészőben kell gyorsabbnak lennie, a WebGL.
