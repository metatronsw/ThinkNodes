# Változások

## 2026-11-25 – Kódszínezés a letölthető SVG-ben

- Az önálló SVG-be (letöltés: `/export/svg/…`, és a lap előnézeti rajza) beágyazódnak a kódszínezés színszabályai és a kód alapformája (egyenközű betű, tördelés), ha a lapon van színezhető kódfájl (`codeStyle`, `Rendering.swift`). A megtekintő oldalon nincs beágyazás, ott az `app.css` adja.
- A szabályok egy helyen: `CodeHighlight.colourRules` (ThinkHighlight); teszt őrzi, hogy szó szerint egyeznek az `app.css` `.hl-*` szabályaival (`highlightColourRulesMatchTheStylesheet`), és hogy az export tartalmazza őket (`standaloneSVGEmbedsCodeColours`).
- Safariban kipróbálva: a `projects/test-container` letöltött SVG-je önállóan megnyitva színes (`demo.json`, `demo.css`).
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Kódszínezés (JSON, CSS) és dobozon szerkesztés

- **Kódszínezés:** a `.json` és a `.css` kódfájl doboza színezve jelenik meg a szerkesztőben és a megtekintőben. Saját, könnyű elemző (nem nyelvtani elemzés): megjegyzés, szöveg, szám, kulcsszó, kulcs / tulajdonságnév, szelektor, függvény, írásjel. A tévedés legfeljebb rossz szín, a fájl tartalmához a színező nem nyúl.
- **Külön modul:** `server/Sources/ThinkHighlight` (önálló SwiftPM cél, csak a Foundationtől függ; teszt: `Tests/ThinkHighlightTests`). Új nyelv: egy fájl a modulban (`CodeLanguage`) és egy sor a `CodeHighlight.languages` listában. Most: `JSONLanguage.swift`, `CSSLanguage.swift`.
- **A szerver színez, a kliens megjelenít:** a kész HTML a fájl tartalma szerint gyorsítótárazva (`highlightedCode`, `Rendering.swift`), így csak változáskor készül újra. A szerkesztő a doboz fájljához a `GET /api/attachment/<lap>?name=…&highlight=<kiterjesztés>` címről kéri (204: nincs hozzá nyelv). A fájl első 100 000 bájtja kap színt (`colouredLimit`), a többi sima szöveg.
- **Színek:** hat szín a doboz szövegszínéhez keverve (`.hl-*`, `app.css`), így világos és sötét háttéren is olvasható, témától függetlenül.
- **Tördelés:** a kódfájl sorai tördelődnek (eddig vízszintesen görgettek); sorszám nincs.
- **Dobozon szerkesztés (új fogalom):** a szövegfájl (`.txt`, `.md`, kód) a vásznon, a doboz helyén szerkeszthető. Dupla kattintás nyitja (Alt-tal a tulajdonságpanel), Esc vagy a doboz elengedése zárja. Közben sima szöveg látszik; a formázott / színezett nézet bezáráskor, a mentés után tér vissza. Kódfájlban a Tab két szóközt ír, az Enter megtartja a sor behúzását.
- **Panel:** a szövegfájlok szövegmezője megszűnt; helyette „Szerkesztés a dobozon” gomb. Marad a betűméret, a szövegszín, a mentés állapota (kódnál a NAGYBETŰS kapcsoló nincs). Nagy fájlnál (256 KB fölött) változatlanul a külön ablakos szerkesztés.
- **Mentés:** a doboz elengedése előtt a függő fájlmentés lefut (`saveFileText`, `selectNode`), így a `file.rev` akkor is lép, ha a szerkesztést máshová kattintva hagyják el – a többi résztvevő ebből tölti újra a fájlt. (A táblázat / CSV cellaszerkesztésére is érvényes.)
- Tesztek: `test.sh highlight` (5 teszt: JSON, CSS, HTML-védés, hibás bemenet, nagy fájl); `test.sh --swift render`, `--js editor` rendben.
- Safariban kipróbálva (`projects/test-container`): behúzott `demo.json` és `demo.css` színes, a sorok tördelődnek; dupla kattintásra szövegmező nyílik fókusszal, gépelés után Esc-re a doboz mentve, újraszínezve jelenik meg. A megtekintő oldalon a színezett szakaszok megvannak.
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Egységes konténer-fogalom: konténer az, amiben éppen van objektum

- **Szabály:** konténer az a doboz, amiben éppen van másik objektum (van, aminek ő a szülője). Eddig kétféle fogalom élt: a tárolt `container` jelző (a doboz kiürülve is konténer maradt) – ezt használta a rétegsorrend, a csomópont ejtése, a befogás, a panel és a szövegkörbefuttatás – és a „van benne doboz” – ezt a nyíl rárugrása. Most mindenhol az utóbbi érvényes.
- **Mi változik a gyakorlatban (csak kiürült konténernél):** a kiürült konténer újra sima doboz. A ráejtett csomópont feloldódik benne (nem a tartalma lesz); a rétegsorrendben a mérete szerint áll, nem a konténerek között legalul; mozgatva nem fog be más dobozt; a panelről eltűnnek a konténergombok (tartalom rögzítése, szövegkörbefuttatás). Ha újra dobozt ejtesz rá, megint konténer.
- **Tárolt jelző:** a `container` mező megmarad a fájlban, de a kód nem belőle dolgozik; a szerkesztő minden módosításkor a tényleges állapothoz igazítja (`syncContainerFlags`), a módosítással egy visszavonási lépésben. A szerver a rajzoláskor és az ellenőrzéskor a szülő–gyermek kapcsolatból indul ki: a szülőnek doboznak kell lennie (a jelző már nem feltétel), és megszűnt az a szabály, hogy `textFlow: true` csak konténeren állhat.
- Helye: `editor.js` (`containerIDs`, `syncContainerFlags`; az `occupiedContainers` megszűnt), `editor-history.js`, `collaboration.js` (a szülő érvényessége), `Model.swift` (`validate`), `Rendering.swift` (`containers`, `flowing`).
- Tesztek: a `gestures.mjs` érintett részei az új szabályhoz igazítva (kiürült konténer nem fog be dobozt; újra konténer lesz, ha dobozt ejtenek rá; üres dobozra ejtett csomópont feloldódik). `test.sh --all` rendben (86 Swift-teszt, minden JS-teszt).
- Safariban kipróbálva: tartalmas konténerben mozgatott és oda behúzott csomópont a konténer tartalma marad / lesz; a jelzős, de üres konténerre ejtett csomópont feloldódik benne, és a konténer jelzője a mentett fájlból eltűnik.
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Takarítás a konténer- és vonalátalakítás után (a működés nem változik)

- **Nem használt szűrők és CSS:** törölve az `ownSurface` és `ownWire` fényudvar-fajta (`glow.js`), a `--glow-own-surface` és `--glow-own-frame` CSS-változó (`editor.js`), és a mozgás közbeni szűrőkikapcsoló szabályból a három elavult elem (`app.css`). A doboz felülete és a vonal saját kijelölése már korábban szűrő nélküli lett.
- **Nem használt kód:** törölve a `viewer.js` felesleges importjai (`arrowLength`, `arrowTransform`), az `editor.js` felesleges importjai (`plainFirstLine`, `shapeOutline`) és a sehonnan nem hívott `sessionAction` (a korábbi munkamenet-mentés / visszaállítás függvénye), a `geometry.js` nem használt exportjai (`canvasBounds`, `edgeStyles`, `shapeOutline`), a `glow.js` `glowURL` függvénye és a szerveroldali rajz `nodeLayers` változója (a régi vonalréteg-számításhoz kellett). Megjegyzés: a `sessionAction` törlése után a `checkpointState` / `checkpointRevision` / `checkpointBusy` állapot még megvan (a szerver üzeneteit fogadja), de már semmi nem állítja – ez a régebbi mentési rendszer maradéka, nem ebben a körben került elő.
- **`home` mező:** törölve a modellből (`Model.swift`) és a szerkesztő visszaállító kódja (`restoreHomes`). Az első, rácsba rendező változat tárolta ide a gyermekdoboz kézi helyét; az a változat csak 2026-11-25-én, helyben élt. Előtte ellenőrizve: egyik helyi lap (`a`, `a/grafikon`, `test-container`) sem tartalmaz `home` mezőt. Ha egy fájlban mégis maradt, a szerver figyelmen kívül hagyja és a következő mentéskor elhagyja.
- **`autoLayout` → `textFlow`:** a konténer szövegkörbefuttatásának kapcsolója a fájlban és a kódban mostantól `textFlow` (alapból be, `false` kapcsolja ki). A szerver a régi `autoLayout` kulcsot olvasáskor még elfogadja, mentéskor az új néven írja ki; teszt: `formerAutoLayoutKeyLoadsAsTextFlow`. Érintett helyi lapok (`a`, `test-container`) a következő mentéskor írődnak át. Mivel a régi név már a távoli ágon is szerepelt, az éles szerveren lévő lapokat is a szerver olvasási szabálya kezeli.
- **Nyílhegy-rövidítés egy helyen:** a „vonal a nyílhegy talpáig tart” számítás a szerkesztőben és a megtekintőben külön volt megírva; most közös függvény (`geometry.js wireHeads`), mindkettő azt hívja. A szerveroldali párja (`Rendering.swift head`) marad. A megtekintőben három felesleges változó is megszűnt.
- **Körbefuttatás egyezés-teszt:** tíz közös eset (`Tests/Fixtures/text-flow.json`: doboz nélkül, egy / két dobozzal, sorkizártan, három igazítással, keskeny konténerben, kikapcsolva, túl hosszú szöveggel). A szerkesztő tördelését a `Tests/Editor/text-flow.mjs`, a szerverét a `textFlowMatchesSharedFixtures` teszt veti össze ugyanazzal az elvárt sorlistával (szöveg, hely, igazítás); a két oldal mind a tíz eseten egyezik. A `test.sh` `editor` és `render` témája is futtatja.
- **Vonalak egyezés-tesztje:** tizenkét közös eset (`Tests/Fixtures/wires.json`: nyíllal és anélkül, vastag vonal, két nyílhegy rövid vonalon, oda-vissza párok vékony / ferde / 12-es / vegyes vastagságú / ellipszis–doboz változatban, S-görbe, kötél, konténer és belső doboza). A szerkesztő útvonalát a `Tests/Editor/wires.mjs`, a szerverét a `wirePathsMatchSharedFixtures` teszt veti össze; mind a tizenkét eseten egyezik. Ez fedi az oda-vissza eltolást, a vastagságfüggő távolságot és a nyílhegy talpáig érő vonalat. (A vonalak rétegét a `wiresRenderAboveEveryBoxExceptElevatedOnes` ellenőrzi.)
- Lezárás: teljes tesztkör (`test.sh --all`) rendben, 86 Swift-teszt és minden JS-teszt. A kijelölt csomópont Safari-ellenőrzése nem sikerült (BUGS.md); a konténer-fogalom egységesítése döntésre vár (TODO.md). Szerverkód változott (`Model.swift`, `Rendering.swift`): release build, a helyi szerver újraindítva.
- **Csomópont világosítása törölve:** a kijelölt csomópont felületének CSS `brightness(1.3)` szabálya (`app.css`) megszűnt (döntés: a Safari SVG-n nem rajzolja ki, képen nem volt ellenőrizhető). A kijelölt csomópontot továbbra is a körvonala jelzi.

## 2026-11-25 – Másik konténerbe áthúzott doboz húzás közben is látszik

- **Hiba:** ha egy dobozt az egyik konténerből a másikba húztál, a doboz az egér elengedéséig eltűnt. Ok: húzás közben a doboz még a régi konténeréhez tartozik, és a konténer a tartalmával egy tömb a rajzolási sorrendben – a később rajzolt másik konténer ezért eltakarta.
- **Javítás:** az éppen húzott doboz (a tartalmával együtt), illetve a húzott csoport húzás közben minden nem kiemelt doboz fölé kerül; elengedéskor a végleges helyére áll a sorrendben (`containers.js layerOrder` `lifted`, `editor.js liftedNodes`).
- Ellenőrzés: Safari, két konténeres próbalap, húzás közben megállítva: a sorrend `nagy konténer, kis konténer, m, áthúzott doboz` (előtte a doboz a kis konténer előtt állt), a képernyőképen a doboz látszik; elengedve a kis konténer tartalma lett. `test.sh editor` rendben. Csak kliensoldali változás. Más szerkesztő húzásánál (távoli mozgás) nem vonatkozik.

## 2026-11-25 – Vonalak rétege: minden vonal minden doboz fölött

- **Egyetlen szabály:** minden vonal minden doboz fölött fut – konténer, a konténer tartalma és a sima dobozok fölött is. Kivétel a **Kiemelt** objektum: az a vonalak fölött van.
- **data-connection:** a táblázatot (vagy CSV-t) és grafikont összekötő különleges vonal (eddigi nevén adatvonal) neve mostantól data-connection; ez mindig minden objektum mögött van (változatlan).
- Megszűnt a korábbi, végpontoktól és konténerektől függő rétegszámítás („a vonal a végpontjai alatt, az őket tartalmazó konténerek fölött”; konténer és belső doboza közti vonal külön esete; szabad végű vonal konténerből). Következmény: a vonal láthatóan átmegy az útjába eső dobozokon, és a vonal eleje / vége a doboz szélén a doboz fölé rajzolódik.
- Szerkesztő és szerver párban (`editor.js wireLayers`, `Rendering.swift`). Tesztek az új szabályhoz igazítva: `wiresRenderAboveEveryBoxExceptElevatedOnes` (Kiemelt dobozzal bővítve), `containerStylesAndJunctionsSurviveRoundTrip`, `gestures.mjs` két elvárása. `test.sh render editor worksheet` rendben.
- Ellenőrzés: Safari, próbalap beágyazott konténerekkel és egy Kiemelt dobozzal: a szerkesztőben és a megtekintőben minden vonal az összes doboz után, a Kiemelt előtt rajzolódik.
- Visszalépési pont, ha nem válik be: az ezt megelőző commit (`ecc4d94`).
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Csomópont konténerben; sok kijelölt vonal gyorsabb

- **Csomópont ejtése:** dobozra ejtve változatlanul feloldódik a dobozban (a vonalai a dobozhoz kötődnek). Konténerre ejtve nem oldódik fel: a konténer tartalma lesz, megmarad a vonalaival, és a konténeren belül szabadon mozgatható (a konténer szövege nem kerüli ki). Konténeren belüli dobozra ejtve abban a dobozban oldódik fel. Eddig a konténer is „doboznak” számított, ezért a konténeren belüli csomópont az első mozdításra feloldódott a konténerben, és csomópontot nem lehetett a konténerbe húzni. (`editor.js junctionDropTarget`; csoportos mozgatásra és vonal kettévágására ugyanez a szabály.)
- **Sok kijelölt vonal (Alt + téglalap):** a saját kijelölésű vonal eddig vonalanként SVG-szűrőt (fényudvar) kapott a teljes befoglaló téglalapjára; sok vonalnál ez lassú volt, és a Safari a túl nagy szűrős vonalakat időnként nem rajzolta ki. Most szűrő helyett a vonal alá rajzolt szélesebb, áttetsző sáv jelzi a kijelölést (`wire-own-halo`); más felhasználó kijelölése változatlan. Safari, 300 dobozos mérőlap, 162 doboz + 209 vonal kijelölve: kijelölés húzása közben a leghosszabb akadás 247 → 83 ms, nagyításnál 295 → 143 ms, csoport húzása 9 → 14 képkocka/mp (leghosszabb akadás 1,1 → 0,19 mp).
- Tesztek: a `gestures.mjs` két elvárása az új csomópont-szabályhoz igazítva (konténerre ejtve gyermek lesz, egyenként és csoportban húzva). `test.sh editor` rendben. Safariban kipróbálva: csomópont mozgatása konténeren belül, behúzás konténerbe, ejtés belső dobozra, kihúzás.
- Csak kliensoldali változás.

## 2026-11-25 – Vastag vonal nem lóg túl a nyílhegyen (megtekintő, export)

- **Ok:** a szerveroldali rajzban (megtekintő, SVG-export, előnézeti kép) a vonal a nyílhegy csúcsáig futott, a nyílhegy csak rá volt téve; vastag vonalnál a vonal vége (lekerekített véggel) kilógott a nyílhegy mellett és a csúcsán túl. A szerkesztő eddig is a nyílhegy talpánál fejezte be a vonalat.
- **Javítás:** a szerver is a nyílhegy talpáig rajzolja a vonalat, a nyíljelölő a vonal végéről indul (`Rendering.swift`; a szerkesztő `wireDrawing` / `wireArrow` párja). Két nyílhegy rövid, egyenes vonalon – mint a szerkesztőben – legfeljebb a fél hosszig ér. A megtekintő a dobozok élő mozgatásakor ugyanígy frissíti a vonalat (`viewer.js`).
- Tesztek: két meglévő teszt elvárt útvonala a rövidebb vonalhoz igazítva (`experimentalAnchorsLoadAsAutomaticConnections`, `themeProjectRoundTrip`). `test.sh render worksheet editor` rendben.
- Ellenőrzés: Safari képernyőkép a megtekintőről 12 / 24 / 32-es vonalakkal minden vonaltípusból (egyenes, S-görbe, ív, kötél, villám), egy- és kétnyilas, hosszú és rövid változatban; a szerkesztővel egyezik. A villám típus vastag vonallal és sűrű töréssel továbbra is zsúfolt (a szerkesztőben is).
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Oda-vissza kötés: a távolság a vonalvastagsághoz igazodik

- Az oda-vissza kötés két vonala közti távolság eddig fix 12 képpont volt, így két vastag (pl. 12-es) vonal összeért. Most a két középvonal távolsága: az egyik nyílhegy fél szélessége + a másik vonal fél vastagsága + 4 képpont (a két irány közül a nagyobb), de legalább 12. Két 2-es vonalnál 12 (változatlan), két 12-esnél 27, két 24-esnél 45, 2-es és 12-es párnál 22 képpont. Így sem a vonalak, sem a nyílhegyek nem érnek a másik vonalhoz.
- A vastagság változtatásakor a pár mindkét vonala újraszámolódik. Szerkesztő, megtekintő és szerver párban (`geometry.js pairShift`, `wireRoutes`, `reverseWidth`; `Rendering.swift`).
- Ellenőrzés: Safari képernyőkép a szerkesztőről és a megtekintőről 12-es, 24-es és vegyes (2 + 12) párral. `test.sh render editor` rendben. Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Oda-vissza kötés: a két vonal egymás mellett fut

- Ha két doboz között mindkét irányban van vonal (A → B és B → A), a két vonal nem fedi egymást: mindkettő a saját haladási irányához képest jobbra tolódik 6 képponttal, így párhuzamosan, 12 képpontra egymástól futnak, és a csatlakozási pontjaik is egymás mellé kerülnek. Egyirányú kötés változatlan. Azonos irányú második vonal továbbra sem húzható.
- Megvalósítás: a páros vonal geometriája a két doboz eltolt helyéből számolódik (`geometry.js edgeGeometry`, `pairGap`; `wireRoutes` / `hasReverse` ismeri fel a párt), a szerkesztőben, a megtekintőben és a szerveroldali rajzban (`Rendering.swift`) egyformán. Konténer és a saját belső doboza közti (beágyazott) vonalra és az adatvonalra nem vonatkozik.
- Korlát: ferdén érkező vonalnál az eltolt végpont néhány képponttal a doboz szélén belülre / kívülre eshet (a vonal a doboz alatt fut, így a belülre eső rész nem látszik; kívül legfeljebb pár képpontos rés lehet).
- Sebesség: a párok felismerése csak vonal felvételekor / törlésekor / átkötésekor számol (a lap vonalainak száma szerint), mozgatáskor vonalanként egy halmazkeresés. Safari, 300 dobozos mérőlap (`perf.py --sheet p300`): dobozmozgatás 59,4, csoportmozgatás 59,9, gyors pásztázás 60 képkocka/mp – a korábbi méréssel azonos.
- Ellenőrzés: Safari képernyőkép a szerkesztőről és a megtekintőről (vízszintes, függőleges, ferde pár, ellipszis–doboz pár). Külön automatikus teszt nincs. `test.sh render editor` rendben. Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Nyilak konténerben: rárugrás csak a szélnél, látható előnézet, vonal a konténerek fölött

- **Rárugrás:** az a doboz, amiben van másik doboz (konténer tartalommal), a nyíl végét csak a széle körüli sávban (kb. 18 képernyőpont befelé, 8 kifelé) vonzza magához; a belsejében a nyíl szabadon áll, vagy a benne lévő dobozokra ugrik. Így a belső dobozból kifelé húzott nyíl nem ragad azonnal a konténerre, és a kívülről a konténer belsejébe húzott nyíl is eléri a belső dobozt (`editor.js snap`). Üres konténer és a sima doboz változatlanul a teljes felületén cél.
- **Húzott nyíl láthatósága:** az előnézeti vonal világos szegélyt kapott; a kék vonal a sötétkék konténeren belül húzva szinte nem látszott.
- **Vonal két konténer dobozai között:** a vonalat a második konténer eltakarta (a mai rétegsorrend-váltás mellékhatása: a konténer és a tartalma egy tömb). A vonal most a végpontjai alatt, de minden őket tartalmazó konténer fölött fut; szabad végű vonal konténerből a konténer fölött. Szerkesztő és szerver párban (`editor.js wireLayers`, `Rendering.swift`).
- Teszt: `wiresBetweenBoxesInDifferentContainersRenderAboveBothContainers`; `test.sh render editor` rendben. Safariban (WebDriver, a test-container másolatán) kipróbálva: Ctrl-húzás belső dobozból a másik konténer belső dobozára – közben nincs rárugrás a konténerekre, a kész vonal látszik mindkét konténer fölött; konténerből a belső dobozra húzva a vonal létrejön.
- Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Címsor nem sorkizárt; alulra igazítás körbefuttatásnál; test-container próbaprojekt

- **Címsor:** címsor sosem sorkizárt. Sorkizárt szövegű dobozban a címsor a vízszintes igazítást követi (bal / közép / jobb a 9 gombból), a törzsszöveg marad sorkizárt. Szerkesztő és szerver párban (`geometry.js labelLayout`, `Rendering.swift ideaDrawing`).
- **Alulra igazítás konténerben:** körbefuttatott szövegnél az „alul” (és a „közép”) eddig visszaesett felülre, ha a lejjebb kezdett szöveg új akadályba ütközött és kilógott volna. Most ilyenkor csak annyival kezdődik feljebb, amennyivel kilógna, így a szöveg az alsó szélhez (középnél a közép közelébe) kerül.
- **Projektek (helyi adat):** a `projects/b` törölve (a felhasználó kérésére); új `projects/test-container`: öt konténer (teljes markdown sorkizárva és belső konténerrel; középre; alulra-jobbra sorkizárva; keskeny; körbefuttatás kikapcsolva), egy sima doboz ugyanazzal a szöveggel és egy rálógó doboz. A szöveg minden támogatott markdown-elemet tartalmaz: három címsorszint, félkövér, dőlt, félkövér-dőlt, soron belüli kód, link, felsorolás három szinten, számozott lista, idézet, kódblokk, vízszintes vonal, soron belüli sortörés.
- Ellenőrzés: Safari képernyőképen a próbalap (szerkesztő): körbefuttatás, alulra igazítás, jobbra álló címsor sorkizárt szöveg fölött. `test.sh render editor markdown` rendben. Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Körbefuttatás: ritkább újratördelés húzás közben, nagyobb térköz a doboz két oldalán

- **Ritkább újratördelés:** húzás közben a konténer szövege csak akkor tördelődik újra, ha a belső doboz legalább 12 képpontot mozdult (a doboz helye ilyenkor 12-es lépésekre kerekítve számít); elengedéskor a pontos hellyel. A legfeljebb 6 képpontos eltérés a doboz körüli térközön belül marad. A konténer húzásakor a szöveg egyáltalán nem számolódik újra.
- **Térköz:** a szöveg a belső doboz bal és jobb oldalától 18 képpontra áll (eddig 8); fent és lent marad 8. Szerkesztő, megtekintő és export egyformán (`geometry.js labelLayout`, `Rendering.swift ideaDrawing`).
- Mérés (Safari, a `projects/b` másolata, a belső doboz gyors húzása): sorkizárással 42 → 45 képkocka/mp, anélkül 55 → 57; lassabb húzásnál a nyereség nagyobb, mert több képkocka marad újratördelés nélkül. A sorkizárás pontossága változatlan (0,05 képponton belül).
- Megjegyzés: mióta a sorkizárás Safariban ténylegesen működik, a sorkizárt doboz több soros címsora is kitöltődik (a szavak közé kerül a hely).
- `test.sh render editor markdown` rendben. Szerverkód változott (`Rendering.swift`): release build, a helyi szerver újraindítva.

## 2026-11-25 – Körbefuttatott konténerszöveg: a belső doboz húzása gyorsabb

- **Mérés (Safari, a `projects/b` lap másolata, 777 × 790-es konténer 1400 betűs szöveggel, benne egy doboz húzása):** előtte 14 képkocka/mp, egyes képkockák 230–320 ms; körbefuttatás nélkül 60 képkocka/mp. A saját számítás közben elhanyagolható (a körbefuttatás 0,4–1,5 ms, a rajzoló függvények összesen ~20 ms a teljes húzásra).
- **Ok:** amikor a doboz mozgása miatt a sorok átrendeződnek, a Vue soronként írta át a szöveget: egy képkockában 200–290 DOM-módosítás, 60–90 `tspan` törlése és beszúrása. A Safari minden beszúrt / törölt elem után újraépíti a teljes `<text>` elrendezését. (Egy sor szövegének vagy az összes sor helyének módosítása önmagában 2 ms.)
- **1. javítás – a szöveg egy lépésben cserélődik:** a doboz `<text>` eleme a sorok tartalmából képzett kulcsot kap; ha a tördelés változik, az új szöveg a dokumentumon kívül épül fel, és egyszer kerül be. Ha csak a sorok helye változik, a kulcs marad, és csak az x / y frissül. Eredmény: sorkizárás nélkül 14 → 55 képkocka/mp.
- **2. javítás – sorkizárás rajzolás előtt:** a sorkizárt sor eltolásai (`dx`) már a virtuális DOM-ban a sorra kerülnek, nem kirajzolás utáni méréssel és visszaírással. A sor hossza húzás közben vászon-szövegmérésből jön (0,3–4 képponttal eltérhet a Safari SVG-szövegétől); nyugalomban és a mozdulat végén a böngésző pontos mérése igazítja be, és a pontos hosszt megjegyzi (utána a jobb szél 0,05 képponton belül pontos). Eredmény sorkizárással: 14 → 42 képkocka/mp (95. percentilis 235 → 35 ms).
- Kipróbálva, de elvetve: a `<text>` kivétele a dokumentumból a `dx`-írások idejére (nem gyorsított).
- Helye: `Public/editor.js` (`renderNode`: a `<text>` kulcsa, `justified`), `Public/justify.js` (`justifyShifts`, `justifyRows`). `test.sh editor markdown` rendben. Csak kliensoldali változás; a helyi szerver újraindítva.

## 2026-11-25 – Sorkizárás Safariban, igazítás a körbefuttatott konténerben, kijelölt doboz háttere

- **Sorkizárás:** a kapcsoló Safariban hatástalan volt, mert a Safari SVG-szövegen nem alkalmazza a `word-spacing`-et. A sor most betűnkénti `dx` listát kap (a szóköz utáni betű tolódik), ez Safariban is működik. Kikapcsoláskor az eltolás lekerül a sorról (`Public/justify.js`; szerkesztő és megtekintő).
- **Igazítás körbefuttatásnál:** a függőleges igazítás (közép / alul) a körbefuttatott konténerszövegre is hat: a szöveg kezdőpontját néhány lépésben közelítjük, mert a sorok helye a magasságtól függ. A vízszintes igazítás a sor szabad helyén belül érvényes; sorkizárt szöveg balra zárt marad. Szerkesztő és szerver párban (`geometry.js labelLayout`, `Rendering.swift ideaDrawing`).
- **Belső doboz húzása:** a sorkizárás mérése kötegelve fut (előbb minden írás, aztán minden mérés: egy elrendezés soronkénti helyett), és az azonos tartalmú sor hosszát megjegyzi. Maga a körbefuttatás számítása 0,4–1,5 ms (Node.js, a `projects/a` és `b` konténerein mérve).
- **Kijelölt doboz háttere:** a saját kijelölés a doboz felületére SVG-szűrőt (fényudvar + világosítás) tett; nagy vagy a képernyőről kilógó dobozon a Safari a szűrős felületet nem rajzolta ki, a konténer háttere eltűnt (képernyőképpel reprodukálva). A felületen és a kereten már nincs szűrő: a világosítást szűrő nélküli fedőréteg adja (`.selection-own-tint`), a kijelölést a vastag keret jelzi; a fényudvar a dobozon megszűnt.
- Ellenőrzés: Safari képernyőképen a sorkizárás és az alsó igazítás látszik. **Nincs ellenőrizve böngészőben:** a kijelölt konténer új megjelenése és a belső doboz húzásának sebessége (a gép képernyője a próba alatt zárolva volt, egérműveletet nem lehetett küldeni). `test.sh render editor markdown` rendben. Szerverkód változott: release build, a helyi szerver újraindítva.

## 2026-11-25 – Konténer: a szövegkörbefuttatás alapból be van kapcsolva

- Minden konténer saját szövege kikerüli a benne lévő dobozokat, külön bekapcsolás nélkül. A konténer paneljén a rács ikonnal („Szöveg körbefuttatása a tartalom körül”) kikapcsolható (`autoLayout: false`).
- Következmény: a meglévő lapokon is, ahol egy konténernek szövege és gyermekdoboza is van, a szöveg mostantól felülről folyik és kikerüli a dobozokat (szerkesztő, megtekintő, export). Gyermek nélküli konténer változatlan.
- `test.sh render editor worksheet` rendben. A szerver kódja változott (`Rendering.swift`): release build készült, a helyi szerver újraindítva.

## 2026-11-25 – Sorkizárt szövegű doboz mozgatása gyorsabb

- **Ok:** a sorkizárás (`Public/justify.js`) a doboz minden újrarajzolásakor – húzás közben képkockánként – újramérte a sorok szélességét (`getComputedTextLength`, kényszerített elrendezés). A `projects/b` lap másolatán a 22 soros, sorkizárt konténer húzása Safariban 30 fps volt (60 képkocka alatt 732 mérés, kb. 1,5 mp).
- **Javítás:** a sor csak akkor mér újra, ha a tartalma, a kért szélessége vagy a betűje változott (soronkénti kulcs; betűkészlet betöltésekor érvénytelenedik). Ugyanaz a húzás most 54 fps, mérés nélkül.
- Mérés: automatizált Safari, `Tests/Perf/perf.py` rögzítője, release szerver. `test.sh editor` rendben. Csak kliensoldali változás.

## 2026-11-25 – Konténer: a saját szöveg kikerüli a benne lévő dobozokat

- **Mit csinál:** a konténer tulajdonságpaneljén (Doboz csoport, rács ikon) „Szöveg körbefuttatása a tartalom körül”. Bekapcsolva a konténer saját szövege felülről folyik, és soronként kikerüli a közvetlen gyermekdobozokat: a sor a doboz mellett, a legszélesebb szabad helyen folytatódik, vagy ha ott túl kevés a hely, a doboz alatt. A gyermekdobozok ott maradnak, ahová kézzel kerültek; a helyük és méretük nem változik.
- **Élő:** gyermek húzásakor a konténer szövege azonnal újratördelődik. A megtekintő és az SVG-export ugyanígy tördel (a két oldal kódja párban áll).
- **Korlátok:** a függőleges igazítás körbefuttatásnál nem hat (a szöveg felül kezdődik); a dobozok körül 8 képpont térköz van; ami nem fér ki, az a szokott módon „…”-tal rövidül (a konténer nem nő).
- **Az első változat megszűnt:** a rácsba rendezés (a gyermekek áthelyezése) félreértés volt, kikerült. Ahol az a változat már áthelyezett dobozokat, ott a szerkesztő a lap következő módosításakor visszateszi őket a kézi helyükre (`home` mező, utána törlődik).
- Adatmodell: a konténeren `autoLayout` (a név az első változatból maradt). Helye: `Public/geometry.js` (`textSlot`, `wrapRuns`, `labelLayout`), `Public/editor.js` (`flowObstacles`), `Sources/ThinkCore/CanvasMarkdown.swift` (`wrapMarkdown`, `TextSlot`), `Sources/ThinkCore/Rendering.swift` (`textSlot`, `ideaDrawing`).
- Kipróbálva Safariban (WebDriver, ideiglenes próbalap): szerkesztő, gyermek áthúzása, megtekintő. `test.sh render editor markdown worksheet` rendben. Külön automatikus teszt a körbefuttatásra nincs. A szerver kódja változott: release build készült, a helyi szerver újraindítva.

## 2026-11-25 – Konténer: a rálógó doboz a konténer tartalmát is kitakarja

- **Rétegsorrend:** a konténer és a teljes tartalma (beágyazott konténerekkel együtt) egy tömbként kerül a rajzolási sorrendbe. Ami a konténer fölött van és nem a része, az a tartalmát is kitakarja. Eddig a konténer kisebb gyermekdobozai „átütöttek” a rálógó, náluk nagyobb idegen dobozon.
- Testvérek között a szabály változatlan: előbb a konténerek, aztán a nagyobb doboz van alul. A kiemelt rétegben továbbra is csak a méret számít.
- Helye: `Public/containers.js` (`layerOrder`, a szerkesztő ezt használja), `Sources/ThinkCore/Rendering.swift` (megtekintő, SVG-export). Teszt: `boxesAboveAContainerAlsoCoverItsContents`; `test.sh render editor` rendben.
- Böngészőben (Safari) nincs külön kipróbálva. A szerver kódja változott (`Rendering.swift`): futó szervert újra kell indítani.

## 2026-11-25 – Grafikon önálló objektumként (D3), adatvonal, táblázat-igazítás

- **Grafikon (`chart` típus):** önálló objektum, saját fájl nélkül: oszlop-, vonal-, kör- és pontdiagram. Az adatát a vonallal bekötött táblázat (`.tntable`) vagy CSV adja; bekötött táblázat nélkül üres. A táblázat csak táblázat marad (a korábbi, ágon belüli „megjelenítés: grafikon” mód megszűnt). A grafikon törlése a táblázatot nem érinti; a táblázat törlése után a grafikon megmarad üresen.
- **Létrehozás:** a táblázat / CSV paneljén és helyi menüjében „Grafikon létrehozása”: új grafikon a táblázat mellett, bekötve. Az „Önálló táblázat (másolat)” gomb megszűnt.
- **Adatvonal:** a táblázat és a grafikon közti vonal automatikusan adatvonal (nem választható, nem tárolt tulajdonság: a két végpont típusa adja). Nyíl helyett mindkét végén félkorong áll, a lapos oldala a doboz oldalára simul; a nyílkapcsolók ezen a vonalon nem látszanak. Egy grafikonba egy táblázat köthető: újabb bekötésekor a korábbi adatvonal megszűnik, az oszlopkiosztás automatikusra áll. Más dobozból akárhány közönséges vonal mutathat a grafikonra.
- **Adatvonal helye:** mindig minden objektum mögött van (legalsó réteg), és a két doboz egymás felé eső oldalának közepéhez csatlakozik.
- **Hajtott lapsarok megszűnt:** a szövegfájl-, CSV- és táblázatdobozok jobb felső sarkából lekerült a hajtott sarok jele (szerkesztő, megtekintő, export).
- **Grafikon panel:** típus, forrás neve, kategóriaoszlop, értékoszlopok (legfeljebb 8; pont: 3, kör: 1), fejlécsor. Automatikus kiosztás: az első szöveges oszlop a kategória, a számoszlopok a sorozatok. A CSV számai magyar és angol írásmóddal is felismerődnek. Kördiagramon a nyolc fölötti szeletek „Egyéb” néven összevonódnak.
- **Megtekintő:** ugyanaz a modul (`Public/chart.js`) rajzol a bekötött táblázat fájljából. Szkript nélküli kimenetben (SVG-export, előnézeti kép) a grafikon doboza üres.
- **D3:** külön csomag a rajzoláshoz: `Public/lib/d3-chart.js` (d3-scale + d3-shape, 39 KB), a tárolóban; csak akkor töltődik le, ha a lapon van grafikon. Újraépítés: `deploy/d3-slim.sh` (mindkét csomagot építi).
- **Táblázat és CSV doboza:** a sarka 5 px-es lekerekítésű (a grafikoné a szokásos); a jobb oldalon megszűnt a görgetősávnak fenntartott sáv, így a tartalomhoz igazított dobozban nincs fölösleges margó.
- **Közös fájl változásszámlálója:** ha egy lapon több doboz mutat ugyanarra a fájlra, a mentés a legnagyobb számláló fölé lép (`latestRev`); a grafikon a forrás legfrissebb változatát olvassa.
- **Tesztek:** `chart.mjs` (JS: számfelismerés, kiosztás, a négy típus SVG-je, adatvonal és félkorong), `chartIsAStandaloneObjectFedByTheConnectedTable` (Swift).
- Helyi próbalap: `projects/a/grafikon` (kézzel létrehozva a teszthez).
- Szerverkód változott: újrafordítva és újraindítva.

## 2026-11-25 – Csomag: darabolt, folytatható feltöltés és közvetlen letöltés; nagy szövegfájl külön ablakban

- **Csomag-mérethatár:** 200 MiB helyett 4 GiB (a ZIP64 nélküli ZIP formátum határa; a saját export tömörítés nélküli), kibontva 8 GiB, 20 000 fájl. Induláskor szabadhely-ellenőrzés.
- **Feltöltés darabokban:** 8 MiB-os darabok, folyamatjelző a párbeszédablakban. Megszakadt kapcsolatnál a kliens magától újrapróbál (egyre hosszabb szünetekkel), utána „Folytatás” gomb; a kapcsolat visszatértekor magától folytat. A szerver csak a saját folytatási pontjától fogad el adatot, így darab nem kerülhet be kétszer és nem maradhat ki. Az oldal újratöltése vagy a szerver újraindítása után ugyanazt a fájlt kiválasztva onnan folytatódik (24 óráig). Részletek: `server/docs/migration.md`.
- **Letöltés:** a csomag a szerveren várja a letöltést (egy óráig, csak a készítőjének); a böngésző közvetlenül lemezre tölti, a saját letöltéskezelőjével folytathatóan – korábban az egész csomag a lap memóriájába töltődött.
- **Nagy szövegfájl (256 KB fölött):** az oldalsávon szövegmező helyett „Szerkesztés külön ablakban” gomb; a külön ablak a teljes fájlt szerkeszti, automatikus mentéssel és ütközésvédelemmel (ha közben más mentett, nem írja felül). A fájl eredeti sorvégei megmaradnak.
- **Döntések:** a megtekintő görgetése marad; a hozzáférés-kérelmező nem kap levelet; projektek között a beillesztett fájl másolat marad.
- **Tesztek:** `packageUploadsInChunksAndResumes`, `textFileEditorSavesAndDetectsConflicts` (Swift), `package-upload.mjs` (JS: hálózati hiba, elveszett válasz, folytatás, lejárat). Élő próba a helyi szerveren: letöltés részleges kéréssel, feltöltés két darabban megszakítással, rossz folytatási pontra 409. Automatizált Safariban a szövegszerkesztő oldal és a böngészőből indított darabolt feltöltés működik; képernyőkép nem készült (a kijelző aludt).
- Nincs kipróbálva: több GB-os csomag, valódi hálózati megszakadás, a párbeszédablak és a szövegszerkesztő kinézete.
- Szerverkód változott: újrafordítva és újraindítva.

## 2026-11-25 – Szűkített d3-csomag

- A szerkesztő a teljes d3 (280 KB, tömörítve 93 KB) helyett csak a használt részt kapja: `zoom`, `zoomIdentity`, `select`, `pointer` és a függőségeik – `server/Public/lib/d3-zoom.js`, 55 KB (tömörítve 18,6 KB). A fájl a tárolóban van, a saját szerver adja ki; a `deploy/build.sh` a d3-at már nem tölti le.
- Újraépítés (csak verzióváltáskor vagy új d3-függvény használatakor): `server/deploy/d3-slim.sh` – az npm-ről letölti a `d3-zoom` 3.0.0 és `d3-selection` 3.0.0 modult és az esbuildet egy ideiglenes mappába, és egy fájllá fűzi őket.
- Ellenőrizve: minden teszt zöld; automatizált Safariban a szerkesztő betölt, a görgős nagyítás működik, és ugyanaz a próba a teljes d3-mal pontosan ugyanazt az eredményt adta. A pásztázást az automatizált húzás egyik csomaggal sem mozdította (a tesztkörnyezet sajátja), ezt kézzel érdemes megnézni.
- A régi `server/Public/vendor/d3.js` törölve (engedéllyel; nem volt a tárolóban, a szerver már nem használta).
- Szerverkód változott (a szkript hivatkozása): újrafordítva és újraindítva.

## 2026-11-25 – Gyorsabb tesztek, válasz-tömörítés, táblázat-gyorsítótár a megtekintőben

- **Tesztelők:** a `gestures.mjs` gyorsított idővel fut (az időzítések és az óra nyolcszoros sebességgel; `TEST_SPEED=1` a valós idő): 11 mp → 2,9 mp, hat egymás utáni futás hibátlan. A `test.sh` a JS-teszteket a háttérben, párhuzamosan futtatja, miközben a Swift fordít.
- **Válasz-tömörítés (gzip) a szöveges típusokra:** `editor.js` 280 → 80 KB, `d3.js` 280 → 93 KB, `app.css` 73 → 18 KB; a megtekintő oldala a helyi `a` lapon 159 → 20 KB, a mérő `tabla` lapon 433 → 66 KB. A feltételes kérés (304) változatlanul működik, a kicsomagolt tartalom bájtra egyezik.
- **Megtekintő / előnézet:** a táblázat dobozok kész HTML-je a fájl tartalma szerint gyorsítótárazva (`RenderedTables`), a cellaérték dekódolása a leggyakoribb típussal kezd. A helyi `a` lap megtekintője 87–100 ms → 17 ms (a mintavétel szerint az idő ~70%-a a `.tntable` újradekódolása volt minden kérésnél).
- **Hiba javítva:** két lap azonos nevű szövegfájlja egy lapon ugyanazt a tartalmat mutatta a megtekintőben és az exportban (a tartalom kulcsa csak a fájlnév volt; most a forrással együtt egyedi, `CanvasFile.textKey`).
- Ellenőrzött, hibát nem találtam: útvonal-kijátszás a `/common`, a mellékletek, az előnézet és a tallózó címein (403 / 404); a linkelőnézet helyi és belső címre csak helyőrző képet ad.
- Nem sikerült mérni: a táblázatszerkesztő görgetése az új fejlécsávokkal (az automatizált Safari időzítői leálltak, valószínűleg takarásban volt az ablak).
- Szerverkód változott: újrafordítva és újraindítva. További gyorsítási lehetőségek: `server/docs/PERF.md` („Betöltés és szerver – 2026-11-25”).

## 2026-11-24 – TODO- és BUGS-tételek (`todo-bugs-2026-11-24` ág)

- **Tesztek:** a `Tests/Editor/gestures.mjs` újra átmegy; a szerkesztő mostani működéséhez igazítva (részletek: DONE.md).
- **Törölt projektek lomtára:** az adminoldalon („Törölt projektek”) a gyökér `.trash` mappájának projektjei visszaállíthatók az eredeti néven, vagy – a „Végleg” négyzet bejelölése után – véglegesen törölhetők; „Lomtár ürítése” mindet törli (`/admin/trash`, `deletedProjects`, `restoreProject`, `purgeDeletedProjects`).
- **`common` projektnév foglalt** (`WorksheetPath.reserved`).
- **Közös fájlok:** az átnevezett fájlnév és a publikus (pillangó) állapot minden lapon a tulajdonos mappából jön olvasáskor; a közös könyvtár szövegfájljai a megtekintőben is megjelennek; a lomtárba tett közös fájl visszavonáskor visszaáll.
- **Szerkesztő:** ugyanannak a projektnek másik lapjáról másolt fájldoboz beillesztéskor közös hivatkozás lesz (nem új feltöltés); a vászonra húzott `.thnode` az új allapra mutató laplinkes dobozt kap; a behúzott ThinkNodes-csomag ZIP-nél a szerkesztő felajánlja az importot allapként (`isPackageZip`, `package.js`).
- **CSV olvasó nézet:** a társak cellakijelölése és a dupla kattintással megnyitott cella üres sorokat tartalmazó fájlban is a jó sorra esik.
- **Táblázatszerkesztő (Safari):** a ragadó fejlécek helyett külön fejlécsávok (oszlopbetűk, sorszámok), amelyek a rács görgetését követik – Safariban a ragadó fejléc görgetés után nem látszott és nem volt kattintható; az oszlopszélesség-fogó így működik. A szerkesztő megnyitásakor a vászon nem ugrik el (a Safari a fókusz miatt elgörgette a vászonterületet). Automatizált Safariban ellenőrizve.
- Szerverkód változott: újrafordítva és újraindítva.

## 2026-11-24 – Safari-mérés: görgős nagyítás és táblázathúzás gyorsítása; puffer- és memóriamérés

Mérés: automatizált Safari 18.6, release szerver, mérő-adatmappa (`p300`: 376 doboz). Részletek: `server/docs/PERF.md` („2026-11-24 esti mérés”).

- **A mai rács- és élesítés-változtatás nem lassít:** a rajzolt / CSS-rács és az élesítés be / ki minden nagyítási és pásztázási forgatókönyvben azonos eredményt adott.
- **Az akadás oka a nézet rögzítése** (teljes újrarajzolás az új méretarányon, kis nagyításnál 30–130 ms-os képkocka), ami a görgetés minden 150 ms-os szünetében lefutott – egérgörgőnél kattanásonként.
- **Javítás:** görgős nagyításnál a rögzítés további 0,3 mp nyugalmat vár (`wheelCommitDelay`, `perfOptions.wheelCommit`); a kattanások egy mozdulattá olvadnak össze, kattintás előtt azonnal rögzül (`flushView`). Egérgörgős nagyítás kis nagyításnál: 51,8 → 59,5 fps, 18 → 1 lassú képkocka; gyors nagyítás: 46 → 59,4 fps; szakaszos nagyítás 100% fölött: 8 → 1 képkocka 50 ms fölött. Ára: a nagyítás után kb. 0,45 mp-ig a kép a korábbi felbontásban, nagyítva látszik.
- **Puffer (`overscan`) és memória:** 0,5 / 1 / 2 / 3 értékkel a nagyítás és a pásztázás sebessége nem változott; a lap folyamatának memóriája a mérési zajon belül azonos (163–165 MB betöltve), a grafikus folyamaté nem változott (288 MB). Nagyobb puffer tehát nem segít: nem a puffer fogy el, hanem az új méretarány kirajzolása drága. Az alap marad 1.
- **Táblázat húzása:** 39,5 → 59,5 fps, a leghosszabb képkocka 382 → 47 ms. Két ok volt: (1) a doboz minden képkockában újraépítette és összehasonlította a táblázat teljes fáját (295 ms szkript 64 képkockára → 6 ms; `cachedGrid`); (2) a saját kijelölés glow-szűrője a nagy felületen kijelöléskor és a húzás végén 200–300 ms-os megakadást okozott – szövegfájl-, CSV- és táblázatdobozon a saját kijelölés mostantól csak vastag keret, glow nélkül.
- A szerver újrafordítva és újraindítva (verziószámok). JS tesztek rendben, `gestures.mjs` változatlanul bukik.

## 2026-11-24 – Háttérrács vászonelemre rajzolva (Safari: ugráló rács nagyítás közben)

- Megfigyelés: Safariban a rács nagyítás közben mindenhol ugrált, kis nagyításnál jobban, nagynál kevésbé. Automatizált Safariban mérve a rács és a vászonréteg beállított értékei képkockánként egyeztek, a képkockaidő egyenletes volt – tehát nem a számolás és nem a rétegváltás az ok.
- Valószínű ok: a rács csempézett CSS-háttér volt (a teljesítményjavítás óta), és a böngésző a csempe méretét egész képpontra kerekíti. Tört rácsköznél a kerekítés csempénként összeadódik: sok csempénél (kis nagyítás) nagy, kevésnél kicsi az elcsúszás, és nagyítási lépésenként változik.
- Javítás: a rács `<canvas>` elemre rajzolódik (`drawGrid`, `perfOptions.grid = "draw"`, alap): minden pont és vonal a saját, pontos helyére kerül; sok pontnál egyetlen mintakitöltés, amelynek a léptéke tört is lehet. A korábbi mód visszakapcsolható: `{"grid":"css"}`.
- Ellenőrizve: automatizált Safari 18.6-ban a rács megjelenik (12% és 62%), Chromiumban is. Az ugrálás megszűnését szemmel nem tudtam megerősíteni. A szerver újrafordítva és újraindítva (verziószámok).

## 2026-11-24 – Safari: nagyítás közben ugrált a rács (az élesítés késleltetve)

- Feltételezett ok: az „éles kirajzolás nagyítva” javítás a nézet minden rögzítésekor ki-, a következő mozdulatnál visszakapcsolta az előre raszterizált réteget. Nagyítás közben a nézet többször is rögzül (görgőszünet, a kirajzolt réteg széle), a réteg váltása pedig Safariban megakadás.
- Javítás: a réteg a mozdulat alatt és közvetlenül utána megmarad; az élesítés csak 0,6 mp nyugalom után kapcsol be (`restLayer`, `sharpTimer`). A táblázat / CSV / szöveg így a nagyítás után 0,6 mp-cel lesz éles.
- Chromiumban ellenőrizve a rétegállapot (mozdulat közben és után megmarad, nyugalomban élesít, új mozdulatnál visszaáll). Safariban nem tudtam megnézni; ha ott továbbra is ugrál, a `localStorage.tnPerf = '{"sharp":false}'` kapcsolóval eldönthető, hogy ez-e az ok. Csak kliensoldali változás.

## 2026-11-24 – Táblázat / CSV: cellaszerkesztés közben nincs lekerekített keret

- Cellaszerkesztés közben a doboz nem kapja meg a saját kijelölés vastag, lekerekített, világító keretét (`syncUi`, `editor.js`); a többi résztvevő továbbra is látja, hogy a doboz foglalt.
- A szerkesztett cella kerete a cellán belül, szögletesen áll (az általános fókuszkeret 3 px-re kijjebb, lekerekítve rajzolódott); a szerkesztő gyökerének fókuszkerete megszűnt (`app.css`).
- Ellenőrizve Chromiumban. A szerver újrafordítva és újraindítva (csak a stíluslap és a szkript verziószáma változott benne).

## 2026-11-24 – Táblázat / CSV: az Enter szerkesztést indít

- Kijelölt cellán az Enter szerkesztést indít (mint az F2), nem lép a következő sorra. Szerkesztés közben az Enter elfogadja a beírást, és a cella kijelölve marad; továbblépni a nyilakkal vagy Tabbal lehet (`table-edit.js`, `keydown`).
- Ellenőrizve a vezérlő közvetlen próbájával (Node) és a táblázat-tesztekkel; böngészőben nem próbáltam külön. Csak kliensoldali változás.

## 2026-11-24 – Éles táblázat, CSV és szövegfájl nagyítva (800%-ig)

- Ok: a vászon előre raszterizált rétege (`will-change: transform`, a pásztázás gyors indulásához) a görgethető HTML-tartalmat a 100%-os felbontásában tartotta, ezért belenagyítva életlen volt. Cellaszerkesztés közben a nyugalmi transzform eddig is kikapcsolt, ezért volt ott éles.
- Javítás: nyugalomban, 100% fölötti nagyításnál a réteg nem marad külön réteg (`restLayer`, `editor.js`); a következő mozdulat elején visszakapja. Ára: 100% fölött a pásztázás / nagyítás indulásakor egy rövid megakadás lehet (docs/PERF.md 2. pont). Kikapcsolható: `localStorage.tnPerf = '{"sharp":false}'`.
- Ellenőrizve Chromiumban 470%-on (előtte–utána összevetve), pásztázás utána is működik. Safariban nem mértem, sem az élességet, sem a megakadás mértékét. Csak kliensoldali változás.

## 2026-11-24 – Közös görgetési helyzet minden görgethető fájltartalomra

- Aki egy szövegfájl-, CSV- vagy táblázatdobozt kijelölve görget (olvasó nézetben vagy cellaszerkesztés közben), annak a görgetési helyzetét a többi szerkesztő és a megtekintő élőben követi (új `scroll` üzenet az élő csatornán, legfeljebb 50 ms-onként; a szerver csak a dobozt fogó résztvevőtől fogadja el).
- A görgetés végén (0,4 mp nyugalom után) a helyzet a dobozhoz mentődik (`scroll: {x, y}`, `Model.swift`), így a később érkezők és a megtekintő is ugyanott látják a tartalmat (a megtekintő a `data-scroll-x/y` mezőből állítja be). A görgetés nem kerül a visszavonási előzménybe.
- A dobozt nem fogó résztvevő saját görgetése (pl. a görgetősáv húzásával) helyi marad, és a következő közös változás felülírja.
- Ellenőrizve két böngészőlappal (Chromium, mérő-adatmappa): élő követés szerkesztőben és megtekintőben, mentés, visszatöltés. A szerver kódja változott (újrafordítva, újraindítva). 72 Swift teszt és a három JS teszt rendben; `gestures.mjs` változatlanul bukik. Safariban nem ellenőriztem.

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
