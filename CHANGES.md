# Változások

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
