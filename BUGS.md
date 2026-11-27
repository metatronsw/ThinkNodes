## Nyitott

- **Jobb gombos pásztázás és helyi menü (2026-11-27, `right-mouse-pan` ág): kézzel nézendő**
  - Megszűnt: kéz gomb (vászonmozgatás-zár, a `panLocked` beállítás szerveroldalon is), szóközös és bal gombos pásztázás. Új: jobb gomb + húzás pásztáz (objektum fölött is), mozgás nélküli jobb kattintás (küszöb: 5 px, `rightClickSlop`) felengedéskor nyitja a helyi menüt.
  - Valódi Chrome-ban (macOS, CDP) ellenőrizve: bal húzás és szóköz + húzás nem pásztáz, jobb húzás üres vásznon és dobozon pásztáz menü nélkül, jobb kattintás 3 px remegéssel menüt nyit. Safariban nincs kipróbálva.
  - A Windows-sorrend (a `contextmenu` a felengedés után jön) csak egységtesztben (gestures.mjs) van lefedve, valódi Windows-böngészőben nem.
  - Érintéses egyujjas pásztázás megmaradt (eddig a zár tiltotta, most mindig működik). Bal gombos húzás üres vásznon most semmit sem csinál (Alt + húzás a téglalapos kijelölés).
  - Ctrl + kattintás macOS-en továbbra is vonalhúzás, nem helyi menü; trackpaden a kétujjas kattintás + húzás pásztázása kézzel nézendő.

- **Érintőképernyő (mobil GPU): nyitott kérdések (2026-11-27, `right-mouse-pan` ág)**
  - Normál módban a két grafikus kártyás tartalomanimáció (`fx-shadow` átlátszóság + `will-change`, `wire-arrow` transzform) miatt a tableten ~40 kompozitált réteg van (LowPerformance módban 11, a vásznon belül egy sem). A felhasználó szerint most jó; ha mégis lassú / villog: érintőképernyőn alapból LowPerformance, vagy nem kompozitált animációk (PERF.md, asztali mérés is kell).
  - A vászonréteg 7680 × 3984 eszközpixel a tableten (overscan 1 → 3×3 képernyő); mobilon kisebb overscan megfontolandó (mérni).
  - iPaden / Safariban nincs kipróbálva.

- **Eszköztár: „Rács és megjelenítés” csoport, LowPerformance mód, S / G / L (2026-11-27, `right-mouse-pan` ág): kézzel nézendő**
  - A rácsra igazítás, a saját (pont)rács és a LowPerformance mód (az animációk leállítása + a díszítő háttér kikapcsolása együtt) egy felfelé nyíló csoportban; a lista a vászon területére kerül (Teleport), mert az eszköztár görgethető sávja levágta / elcsúsztatta. Billentyűk: S, G, L (váltókapcsolók, gépelés közben nem). A korábbi külön beállítás (tnMotionOff / tnPlainBackground) egyszer átvándorol LowPerformance-ra; a bench-idle.js (`?bench=`) a két részt továbbra is külön kapcsolja.
  - „Mind” csoport (2026-11-27): a gomb bal kattintásra a teljes vásznat mutatja, jobb kattintásra / nyomva tartva kinyílik: Mind, 100% (új `zoom-actual` ikon), teljes képernyő. Billentyűk: H teljes vászon, Ctrl+H 100%, Ctrl+F teljes képernyő ki / be – **Windowson a Ctrl+F a böngésző keresőjét, a Ctrl+H az előzményeket írja felül**, Macen szabad (⌘F / ⌘Y). A mobilra korlátozó teljes képernyő-szabály visszavonva; a megtekintő teljes képernyő gombja a régi.
  - Minden csoportgomb jobb kattintásra nyílik (közös `groupTrigger`: eszköztár-csoportok, gyors eszközök lenyílói; a lézer és az egérmutató gombja eddig is). Chrome-ban ellenőrizve; a teljes képernyő a vezérelt Chrome-ban csak CDP-engedéllyel kapcsolható, ott működik.
  - Chrome-ban ellenőrizve (kapcsolás nyitott listában, kívülre kattintás, S/G/L, átvándorlás). Kézzel nézendő: Safariban, keskeny (mobil) eszköztárnál a lista helye; a billentyűk nem jeleznek vissza látható módon, ha a csoport zárva van.

- **Filctoll, rajzeszköz-választó, egyszeri eszköz (D) (2026-11-27, `right-mouse-pan` ág): kézzel nézendő**
  - Közös motor a lézerrel (Public/laser.js, eszközleírások). Filc: nem halványul; 3 mp-en belül kezdett vonás az előző rajzhoz adódik, később az új vonás mindenkinél törli az előzőt (`clear`); pontkorlát rajzonként 1500 (lézer: vonásonként 48). A szerver továbbítja a `kind` / `clear` mezőt (Collaboration.swift).
  - Két Chrome-mal ellenőrizve: választó (jobb kattintás), hozzáadás 3 mp-en belül és törlés utána mindkét oldalon, D egyszeri rajz (fényes keret, egy vonás után visszaáll), nyugalomban 0 képkockakérés, pásztázás / nagyítás követése, A kilépése után B-nél eltűnik. A lézer p1000-en továbbra is ~60 fps.
  - Kézzel nézendő: a hosszú nyomás (0,45 mp) a gombon valódi egérrel és érintéssel; Safariban az egész (a leképezés közös, ott ellenőrizve); a megtekintőben (passive-frame) a filc.
  - Rajzmód (2026-11-27): a rajz canvasa fogja el az egeret, a dobozok nem kapnak egéreseményt (rámutatás, tooltip, kijelölés), a kurzort a canvas adja. A szerkesztő a canvast a vászon részének tekinti: jobb gombos pásztázás, görgős nagyítás, jobb kattintásra a vászon helyi menüje (dobozé nem); a megosztott egérmutató is küld. Chrome-ban ellenőrizve; mérve: p1000-en a váltás stílusszámítása 34–37 → 0,8 ms, rajzmódban a rámutatás 16 → 0 ms. Kézzel nézendő: Safariban, és a megtekintőben (a passive-frame saját kattintásai rajzmódban nem érhetők el).
  - Esc rajzmódban vagy vonás közben (2026-11-27): a saját rajz (folyó vonás, filcrajz, lézer) törlődik, a többieknél a filcrajz is (`clear` üzenet pontok nélkül); kikapcsolt eszköznél nem töröl. Két Chrome-mal ellenőrizve. A többieknél a lézer halványuló vonala nem törlődik azonnal, hanem 2,2 mp alatt elfogy. Élesített egyszeri rajznál (D) az Esc a visszavonás mellett a saját rajzot is törli.
  - A filc vonalképe a lézertől eltér (lágy szegély + mag, mindkét vége lekerekített, nincs fehér csillanás és elvékonyodás): a tartós rajzhoz ez illik; ha a lézerrel azonos kell, a `tools.marker.layers` / `taper` állítandó.

- **Lézer pointer: kurzor és új vonalrajz (2026-11-27, `right-mouse-pan` ág): nyitott és kézzel nézendő**
  - Kurzor: fekete-fehér varázspálca (`Public/laser-cursor.svg`). A vászon CSS-ből kapja, a mutatott doboz / vonal a laser.js-ből inline (leszármazott-szabály p1000-en a váltást 50 → 100–200 ms-os képkockára rontotta). Chrome-ban mérve (LiquidGlass, p1000): váltás, rámutatás, pásztázás, üresjárat az alapszinten. Safariban nincs mérve; a megtekintőben (passive-frame) nincs kipróbálva. Bekapcsolt lézerrel a dobozok rámutatási kurzora (pointer, copy stb.) helyett is a pálca látszik.
  - Vonalrajz: hibrid mintavétel (12 px / 40–100 ms), 100 ms-os csomagküldés, Catmull-Rom görbe, elvékonyodó vég, 2,2 mp élettartam, max. 48 pont. Ugyanazon a húzáson: 146 → 65–70 pont, 50–80 → 27–36 üzenet, a bájtok −55%. A lézer saját JS-e képkockánként ~0,2 ms. Két böngészővel (a fogadó oldal ütemezett csóvája) nincs kipróbálva.
  - Sarkok és interpoláció (2026-11-27): centripetális Catmull-Rom görbe, és a mintavétel megtartja a fordulópontot, ha a mozgás 3 px-nél jobban eltér két pont egyenesétől. Chrome-ban: a hullám sima, a valódi sarkok élesek; ugyanazon a pályán 70 → 89 pont (az eredeti 146 helyett), 60 fps (p1000 is).
  - Zoom és lézer (2026-11-27): ok megtalálva – Safari 18.6 `getScreenCTM`-je nem tartalmazza a vászon burkolójának CSS-transzformját (görgős nagyítás / pásztázás előnézete, editor.js previewView), ezért zoom közben a rajz elcsúszott, a közben kezdett vonal első pontja rossz helyre (a szél felé) esett. A laser.js most a vászon valódi téglalapjából számol korrekciót (Chrome-ban egységmátrix). Safariban szimulált előnézettel (CSS-transzform a burkolón) és WebDriver-egérrel ellenőrizve; **kézzel nézendő:** valódi görgővel és trackpaddel Safariban. A bennragadt rajz elleni lezárások is megmaradtak.
  - A megosztott egérmutató (mouse.js) is a közös `Public/screen-matrix.js` leképezést használja: Safariban és Chrome-ban szimulált előnézettel ellenőrizve, a küldött pozíció a mutató helye. **Kézzel nézendő:** valódi görgős / trackpades zoom két böngészővel (a fogadó oldalon a mutató helye).
  - Rajz canvason (2026-11-27): a vonal a látható terület méretű `<canvas>`-ra kerül (laser.js), a munkalap képernyő-mátrixával. Chrome, p1000 (animációk ki): rajzolás 38 → 60 fps, elhalványulás 44–53 → 60 fps; pásztázás, váltás, rámutatás az alapszinten. Pásztázás közben a vonal a tartalommal együtt mozog (képernyőképpel ellenőrizve). Safariban nincs mérve; a megtekintőben a canvas betöltődik, rajzolás ott nincs kipróbálva. A jelenlévők egérmutatói ([data-mouse-layer]) még a vászon-SVG-ben vannak, ugyanazzal a festési költséggel.

- **Szerver Fedora 45-ön (2026-11-27): nyitott tételek**
  - A szerver Swift 6.3.3-mal fut (swift.org, `/opt/swift-6.3.3`), a fejlesztőgép 6.0.3-mal: a két fordító eltérhet (a 6.3.3 két Linux-hibát mutatott meg, ezek javítva). Ha a Mac is 6.3.3-ra áll, újra egyezik.
  - A szerveren a szokásos frissítés (`build.sh`, `THINKNODES_SWIFT` nélkül) végigment (2026-11-27): a swift.env alapján a 6.3.3-at veszi fel; a `server/Package.resolved` a 6.3.3 miatt helyben módosul (a build.sh pull előtt eldobja).
  - Az új Fedora-telepítés teljes folyamata (`git clone` → `install.sh` → `daemon.sh`) tiszta gépen nincs végigpróbálva; a lépései külön-külön a szerveren futottak.
  - Újraindításkor a naplóban: `Could not stop HTTP server: Abort.500: Server stop took too long` (a leállás ~10 mp-ig vár, valószínűleg a nyitott hosszú lekérdezések miatt), és indításkor `Failed to set thread priority for worker thread … errno=13` (a szolgáltatás nem rootként fut). Mindkettő ártalmatlannak tűnik, a szolgáltatás újraindul.
  - A régi `thinknodes.service.d/chromium.conf` drop-in megmaradt (a daemon.sh a unitba is beírja a Chromium útját); ártalmatlan.

- **WhiteBoard textúrák és füzetlap (2026-11-26): nyitott és kézzel nézendő**
  - Chrome-ban (képernyőkép három nagyításon, a sorvonalak mérése) és Safari 18.6-ban (a sorvonalak mérése, képernyőkép) ellenőrizve. Nincs mérve: a vászontextúra kétszintes kitöltésének költsége mozdulat közben sok dobozos lapon (p300), főleg Safariban.
  - A textúra sűrűsége és erőssége szemre állítandó: a csempe 192 vászonegység (a képernyőn 192–384 px között, szintenként áttűnve), erősség: világos vászon 0,45, sötét karton 0,2, papír 0,4. A képek kontrasztja a beágyazás előtt meg lett emelve (papír ×8, karton ×8 enyhe simítással).
  - A füzetvonal az alapvonalhoz képest a betűtípus mértékeiből becsült (k ≈ 0,36: rendszerbetű, egyenközű): Chrome-ban a vonal teteje kb. 2 px-lel, Safariban 2,5–3,5 px-lel az alapvonal alatt. A Safari „legkisebb betűméret” beállítása (itt 14 px) miatt a sorköz a tényleges betűméretből számol; a 14 px-nél kisebb címsor (h4–h6 nagyon kicsi dobozbetűnél) sávja így is eltérhet.
  - A füzetlapon a kép és a táblázat (ha a markdown ad ilyet) magassága nem a sormagasság többszöröse: utána a sorok elcsúszhatnak.
  - Kézzel nézendő: kijelölt füzetlap / cetli kerete (a textúra a keret belső felét fedi), a kódfájl doboza mostantól a szokásos szabadkézi doboz (sorvonal nélkül, sötét módban sötét).
  - Az önálló SVG-export (/export/svg) a szerverre mutató címeket beágyazza (elemenként legfeljebb 20 MB, összesen 100 MB; ami ezen túl van, hivatkozás marad). Nagy fájlokkal (videó, nagy PDF) az SVG mérete megnő; a letöltés ideje nincs mérve. Az előnézeti képek és a megtekintő nem ágyaz be. Helyi fájlként megnyitva a fájldoboz feliratai (pl. a fájlnév) a böngésző alapbetűjével látszanak: az önálló SVG-ben az app.css általános szabályai nincsenek benne (régi állapot).

- **Kapcsolatvesztés (2026-11-26): kézzel nézendő**
  - Safariban csak a kapcsolat nélküli szakasz mérve (nincs ismétlődő DOM-írás); a szerver visszatérése utáni viselkedés (nincs újratöltés) csak Chrome-ban.
  - Valódi hálózatvesztés (Wi-Fi ki, alvás utáni ébredés) és élesben a fordított proxy (502-es válaszok) mögötti viselkedés nincs kipróbálva.
  - A kapcsolat nélkül még be nem töltött fájltartalmak (szövegfájl, táblázat, kép) offline nem töltődnek be; a már betöltöttek látszanak.

- **Minimalist téma (2026-11-26): kézzel nézendő**
  - Safariban nincs megnézve; Chrome-ban világos és sötét módban képernyőképpel ellenőrizve.
  - A „Kiemelés” beállítású dobozok árnyéka a témától független (tömör, eltolt árnyék); ha a Minimalistban zavaró, a téma kikapcsolhatná vagy halványíthatná.
  - A Pasztell paletta közép-tónusú színei világos módban gyengébben válnak el a vászontól (2,3:1), a többi palettáé 3,3–3,6:1.

- **Üresjárati terhelés és akadások javítása (2026-11-26): maradék és kézzel nézendő tételek** (részletek: server/docs/PERF.md „Üresjárat”)
  - Maradék üresjárati terhelés a Liquid Glass lapon 9 futó animációval: Chrome ~17–21%, Safari ~25% WebContent + 5% WindowServer („Animációk ki”: ~0%). Ha ez is sok: kevesebb lépés/mp (12-vel Chrome ~13%, Safari ~10% volt), vagy csak a látható animációk futtatása.
  - Saját kijelölésnél a kijelölés fénye (Liquid Glass „lélegzés”) végtelen animáció: amíg valami ki van jelölve, folyamatos képkockák (döntés: maradhat, csak szerkesztői).
  - Chrome-ban az első kijelölésnél egy 67 ms-os képkocka maradt (a tulajdonságpanel első megnyitása); a késés már 8 ms.
  - Egy mérésnél (Chrome, meleg kör, 55–58 mp) 1,4 és 1,6 mp-es fagyás volt; a következő 5 kör hibátlan, nem reprodukálható. Megfigyelendő.
  - Firefox nincs a gépen: a CSS-animációk (offset-path a futó pöttyön) és az új kapcsolók ott nincsenek kipróbálva.
  - Kézzel nézendő Chrome-ban és Safariban: az „Animációk leállítása” és a „Díszítő háttér kikapcsolása” gomb, a dobozanimációk látványa a letöltött SVG-hez mérten, a kúpos vastag vonal új lüktetése (a hegye is kicsit vastagodik).
  - A mérőeszközök a `Public/`-ban is hagytak fájlt: `bench-idle.js` (a szerkesztő csak `?bench=` címre tölti be), `bench-anim.svg`, `bench-dot.html` (próbaoldalak); élesben is kiszolgálódnak. Törlésük / áthelyezésük döntésre vár.

- **Megtekintő (megszűnik): ismert eltérések a szerkesztőtől** (2026-11-26)
  - A megtekintőben az animációk SMIL-esek maradtak (Safariban ~44–48% üresjáratban); a szerkesztő CSS-animációi ott nem működnének, mert a CSP (`style-src 'self'`) az elemenkénti stílust tiltja.
  - Minden betöltéskor ~122 CSP-hiba („Applying inline style violates…”): a szerver által írt `style` attribútumokat a böngésző eldobja, amit kell, a `viewer.js` állítja be utólag.

- **Főoldali .webp előnézetek: nyitott / kézzel nézendő** (2026-11-26)
  - A librsvg a dobozokba ágyazott HTML-t (táblázat, szövegfájl, .md tartalma) nem rajzolja ki: a háttérképen ezek a dobozok üresek. Ha zavaró, a szerver a raszteres változathoz egyszerű helyettesítő vonalakat rajzolhat a szöveg helyére.
  - Élesben (Fedora) a `librsvg2-tools` és `libwebp-tools` csomag kell (az install.sh telepíti); a meglévő szerveren kézzel: `dnf install librsvg2-tools libwebp-tools`, utána szerver-újraindítás. Nélkülük a régi SVG-előnézet megy.
  - Ha egy lap képe nem készíthető el (pl. sérült egyedi előnézeti kép), arra a lapra SVG jön, de a kártya már elmosás nélkül mutatja.
  - Ellenőrizve 2026-11-26: a lap törlésekor a teljes mappa (a gyorsítótárral) a lomtárba kerül, ott nem marad régi nevű fájl; az átnevezés javítva (DONE.md).
  - Kézzel nézendő: a rámutatás-effekt világos módban és érintőképernyőn; Safariban, hogy a kivilágosodás kivétele után a többi kártya már nem villan fel (a vezérelt Safariban a villanás képernyőképen nem mérhető).
  - A sötét módú, megerősített kiemelkedés-árnyék képernyőképen nincs megnézve (a vezérelt Safari mérése időtúllépéssel megszakadt); a CSS kint van.
  - Ötlet: a „További munkalapok” kártyái és a linkes dobozok képe is kaphatna `.webp` változatot (most a teljes SVG-t töltik).

- **Táblázat-szerkesztés, „Tartalom a dobozhoz”, kurzorcsoport: kézzel nézendő / nyitott** (2026-11-26)
  - A skálázott táblázat szerkesztőjében a valódi egérkattintást a vezérelt Safariban nem lehetett végigpróbálni (az ablak közben elvesztette a fókuszt); a cellaválasztás kódja JS-eseménnyel és a találatvizsgálattal (a kattintott pont alatt a jó cella áll) ellenőrizve. Kézzel nézendő: kattintás, húzásos kijelölés, oszlopszélesség húzása, sor / oszlop kijelölése skálázott táblázatban, nagyított vásznon is.
  - Skálázott szerkesztésnél a fejlécsávok és a képletsor is a táblázattal együtt kicsinyül, és a doboz belső margóján (részben a dobozon belül) állnak; nagy kicsinyítésnél a képletsor nehezen olvasható.
  - „Tartalom a dobozhoz”: 200 sornál hosszabb táblázatnál és CSV-nél az olvasó nézet az első 200 sort skálázza, a szerkesztő az összeset.
  - CSV-n (2026-11-26 óta): illesztve a CSV a szerkesztés táblázatnézetével jelenik meg (alaprács, félkövér első sor, rögzített oszlopszélesség), nem a sima CSV-nézettel; a táblázat korlátainál (1000 sor × 100 oszlop) nagyobb CSV a sima nézetben marad. Csak fej nélküli Chromiumban próbálva, Safariban kézzel nézendő (kattintás, dupla kattintásos szerkesztés skálázva).
  - Ebben a Safariban a legkisebb betűméret 14 px (Beállítások / Haladó): a 13 px-es doboz- és táblázatszöveg ezért nagyobbnak látszik a beállítottnál. Ez nem hiba, de a méretek mérésekor számít.
  - A kurzorcsoport hosszú nyomása és jobb kattintása kézzel nézendő (a vezérelt ablakban az eszköztár a mozgatható tartományon kívül esett, JS-eseménnyel működött); érintőképernyőn a hosszú nyomás.

- **Egységes gombok, vonalak, Liquid Glass (2026-11-26): kézzel nézendő**
  - Automatizált Safariban ellenőrizve (lásd CHANGES.md). Kézzel nézendő: a rámutatás kiemelése érintőképernyőn, a fejléc gombjai mindegyik témában, a megtekintő eszköztára, a kép rámutatása Liquid Glass témán (próbaképes doboz nem volt a próbalapon), a csevegőablak világos Liquid Glass módban, a felugró Megjelenés panel kis ablakban.
  - A vonal animációja minden húzás alatt szünetel (a nem érintett vonalaké is); nagy lapon a húzás elején és végén az animált vonalak újrarajzolódnak.

- **Igazítás, sarokfogó, vászonszín, színválasztó, .md szerkesztő: nyitott és kézzel nézendő tételek** (2026-11-26)
  - Vászonszínű doboz textúrás vásznon: az alatta álló elemek maszkolással takarva (2026-11-26, felhasználói döntés). Nincs mérve Safariban: sok vászonszínű doboz / sok átfedő elem költsége (maszkos csoportok), a fájldoboz (foreignObject) maszk alatt. A takarás a doboz alakját követi, a WhiteBoard szabadkézi körvonalát nem (a szabályos alak). Vászonszínű fájl- és grafikondoboz textúrás vásznon a vászon színét kapja (nem a textúrát).
  - Csoportos húzás közben a rács kivágása és a takarás a húzás eltolásával követi a dobozt; a pásztázás / nagyítás közbeni követés Safariban szemmel nézendő.
  - A .md szerkesztőben a címsor nyersen, alapméretben látszik (megjelenítéskor nagyobb), ezért a címsor alatti sorok szerkesztésbe lépve a címsor magasságkülönbségével feljebb kerülnek; a sorok közti távolság egyezik. Kézzel nézendő: holt billentyűs ékezet a nyilak után, nagyított vászon, füzetlapos (WhiteBoard) .md doboz.
  - Kézzel nézendő: a sarokfogó érintéssel, ellipszis / rombusz alakú dobozon (a fogó a befoglaló téglalap sarkán áll), a rendszer színválasztójának élő húzása (minden mozdulat ment), a színválasztó a tulajdonságpanelen (ott a lista még eltolja a gombokat).

- **Közös munka (színek, avatarok, kurzorcímke, ping nyila): kézzel nézendő és döntésre váró tételek** (2026-11-26)
  - Kézzel nézendő két valódi böngészővel / eszközzel: a kurzorcímke olvashatósága világos és sötét vásznon, a ping nyila az ablak sarkaiban és teljes képernyőn, a nyíl fölötti megállás és a kattintás, a megtekintő oldal görgetett állapotban. Az automatizált Safari ablaka nincs fókuszban, ezért ott a saját résztvevő mindig „nem aktív”.
  - A kurzorcímke választása böngészőnként tárolódik (localStorage), nem a fiókhoz; ha fiókszintű kell, a `UserPreferences`-be tehető.
  - A ping hangja: nincs némító kapcsoló; ha zavaró, a kurzorcímke mellé tehető egy hang ki/be gomb. A hang csak az oldalon tett első kattintás / billentyű után szól (böngészőszabály).
  - Kézzel nézendő két valódi böngészővel: lézer pointer érintéssel (a d3 érintéses nagyítás lézer közben nincs letiltva), előadás teljes képernyőn azonos és eltérő felbontással, a keret rajzolása / méretezése, csevegés és napló a megtekintő oldalon.
  - Előadás: a megtekintő oldal (nincs nagyítás) nem követ; nagyon nagy lapon a folyamatos követés teljesítménye mérendő.
  - A sötét palettaszínek (pl. `#027864`, `#6550b9`) neve sötét módban a jelenlévők között halványabban olvasható.

- **WhiteBoard: nyitott és kézzel nézendő tételek** (2026-11-25)
  - Füzetlapon a markdown lista elemei között egy üres sor van (a sorvonalak tartása miatt).
  - Kézzel nézendő: szabadkézi doboz kijelölése és átméretezése (a rajz méretváltáskor újraszámolódik), zárolt konténer, megtekintő és SVG-export a füzetlappal (beágyazott CSS, `lh` nélkül, `--rule` változóval), a cetli táblázatszerkesztése.

- **Liquid Glass: kézzel nézendő és nyitott tételek** (2026-11-25)
  - Automatizált Safariban rendben (képernyőkép és mérés): világos / sötét mód, kijelölés fényudvara, ping, üvegpanel, megtekintő. Kézzel nézendő: a kattintásgyűrű és a rámutatás áttűnései szemre, más felhasználó kijelölésének glow-ja két böngészővel, a gyors eszközök és a helyi menü üveghatása, a többi négy paletta, mobil.
  - A fejléc gombjai nem kapnak üveghatást (a szerkesztő munkaterületén kívül vannak).

- **A 2026-11-25-i vonal- és gyorseszköz-változások: kézzel, Safariban nézendő** (2026-11-25; a tesztek 2026-11-26-án hozzáigazítva, mind átmegy)
  - Kézzel nézendő Safariban: a futó pötty (szerkesztő, megjelenítő, export), a három vonalméret régi munkalapokon, a fájlnév helyben szerkesztése (ékezetek, Enter, Esc), a gyors eszközök az ablak négy sarkában.

- **Gyors eszközök (próba): ismert hiányok** (2026-11-25)
  - Ahol egy feliratos gombnak nincs saját ikonja (pl. táblázat egyes gombjai), az alapértelmezett fájl-ikon látszik, több gomb egyforma lehet.
  - Háttér nélküli gombok tarka tartalom fölött nehezebben olvashatók.
  - Az új „Szerkesztés” gomb és a lenyíló lista zárása (kívül kattintás, Esc) 2026-11-26-án csak fej nélküli Chromiumban próbálva (a Safari távoli automatizálása ki volt kapcsolva): Safariban kézzel nézendő.

- **Doboz szövegének szerkesztése a dobozon: kézzel nézendő / nyitott tételek** (2026-11-25)
  - Automatizált Safariban rendben: belépés, tördelés egyezése, gépelés, Enter, kattintás, visszavonás, Esc. Kézzel nézendő: holt billentyűs ékezetek, húzásos kijelölés, nagyított / kicsinyített vászon, körbefuttatott konténerszöveg szerkesztése, amikor a szöveg valóban kikerül egy gyermekdobozt.
  - Ismert eltérések szerkesztés közben: a markdown jelölés nyersen látszik (címsor nem nagyobb, így formázott szövegnél a tördelés eltér); a sorkizárt szöveg balra zárt; AutoSize doboznál a záró üres sor is helyet kér (Enter után a betű kisebb lehet, amíg a sor üres).
  - A panel Text mezője a doboznál marad (döntés: 2026-11-25).

- **Szöveg- és kódfájl szerkesztése a dobozon: kézzel, Safariban nézendő tételek** (2026-11-25)
  - Automatizált Safariban, valódi egérmozgással rendben: gépelés, törlés, visszavonás, kattintás, dupla kattintás, húzásos kijelölés görgetve is, nyílbillentyűk. Kézzel nézendő (a vezérelt böngészőben nem próbálható): holt billentyűs / összetett bevitel, a jobb gombos menü, érintéses kijelölés, Shift+nyíl kijelölés közben a doboz görgetése.

- **Éles kirajzolás nagyítva: Safariban nincs mérve** (2026-11-24)
  - 100% fölött a nyugalmi réteg megszűnik (`restLayer`), hogy a táblázat / CSV / szövegfájl éles legyen. Safariban ellenőrizendő az élesség, és hogy a pásztázás / nagyítás indulásakor mekkora a megakadás (a réteg visszakapcsolása; PERF.md szerint 40–70 ms lehet).

- **A 2026-11-24-i vászon-, táblázat- és CSV-módosítások Safariban nincsenek kipróbálva** (2026-11-24)
  - Chromiumban ellenőrizve. Safariban külön nézendő: CSV cellaszerkesztés (ugyanaz a szerkesztő, mint a táblázaté; a fejlécsávok táblázaton Safariban ellenőrizve), a „méretre igazítás” gomb mérése (a saját görgetősáv tartója mellett), a 800%-os nagyítás, a zoom-kijelző helye.

- **Közös görgetés: a táblázat szerkesztő- és olvasó nézetének görgetési helyzete nem pontosan fedi egymást** (2026-11-24)
  - Cellaszerkesztés közben a rács görgetési értéke megy át változatlanul az olvasó nézetekbe; a fejlécsor és a belső térköz miatt a többieknél néhány képponttal (CSV-nél, ahol a sormagasság eltér, többel) máshol állhat a tartalom.

- **Teljesítmény: nagyítás végén 80–190 ms-os képkocka; táblázatszerkesztés görgetése ~50 fps** (2026-11-24)
  - Este enyhítve: görgős nagyításnál a rögzítés 0,3 mp nyugalmat vár, így mozdulatonként egyszer fut le (nem kattanásonként). Maga a rögzítő képkocka költsége nem változott.
  - A mérések szerint ez a két terület nem javult eleget; részletek és a kipróbált megoldások: `server/docs/PERF.md` („Ami nem javult vagy nyitva maradt”).
  - A `contain: strict` gyorsította a táblázatgörgetést (42 → 54 fps), de Safariban a rétegződő elem foreignObject-ben nem kattintható, ezért kikerült.

- **Megjelenítő (viewer): a Safaris saját görgetősáv nincs kipróbálva** (2026-11-24)
  - A `viewer.js` is megkapta az `attachScrollbars` hívást a fájldobozokra, de csak a szerkesztőben ellenőriztem.

- **A Swift `JSONDecoder` egyes lebegőpontos literálokat 1 ulp pontatlansággal olvas (macOS 13 Foundation)** (2026-11-24, tizedes-audit)
  - Példa: `0.0020293361140076467` → `0.0020293361140076476`. A `.tntable` értékei a szerveren az utolsó bináris jegyben elcsúszhatnak (a kiírt 15 jegyre nincs hatással).
  - Teszt: `platformJSONDecoderDoublePrecision` (figyelmeztet). Teendő: ellenőrizni élesben (Fedora, swift-foundation); ha ott is pontatlan, saját számolvasó a `.tntable`-höz. Részletek: server/docs/EXCEL.md 12. fejezet.

- **A CSV olvasó nézet legfeljebb 1000 sort / 60 oszlopot mutat (2026-11-26-ig 200 / 30)** (2026-11-24)
  - Az ezen kívüli cellára eső társ-kijelölés nem jelenik meg az olvasó nézetben. A fájlnak csak az első 200 000 karaktere kerül a nézetbe (`filePreviewLimit`), így széles soroknál 1000 sor előtt is vége lehet.
  - Nincs mérve: egy 1000 × 60-as CSV kirajzolásának és görgetésének ideje (Safari, megtekintő és szerkesztő).

- **Olvasható szövegszín a dobozon (2026-11-26): kézzel nézendő / ismert korlátok**
  - Fej nélküli Chromiumban ellenőrizve (szerkesztő és megtekintő egyezik, világos és sötét mód). Safariban kézzel nézendő, a többi témában és palettán is.
  - A felületet a kitöltés és a vászon színéből számolja: konténerbe tett, átlátszó kitöltésű dobozon (Liquid Glass, áttetsző mód) a konténer színe nem számít, és a vászon textúrája / háttérfényei sem.
  - Csak a sima doboz szövegére hat (kitöltött, áttetsző vagy vászonszínű háttérnél); az üres és szabad háttérmódú doboz, a fájldobozok, a vonalcímkék és a dobozon kívüli megjegyzés szövege változatlan.

- **Táblázatszerkesztő új fejlécsávjai: Chromiumban és CSV-n nincs kipróbálva** (2026-11-25)
  - A ragadó fejlécek helyett külön fejlécsávok vannak (lásd DONE.md). Automatizált Safari 18.6-ban táblázaton ellenőrizve (megjelenés, oszlopszélesség húzása); Chromiumban, CSV-szerkesztésnél, egyedi sormagasságnál és a „méretre igazítás” gombbal még nézendő. A görgetés sebessége az új szerkezettel nincs mérve (2026-11-25-én a `perf.py` nem futott le: az automatizált Safari időzítői álltak).
  - Ha a megnyitott cella a rács legfelső sorába esne, a fejlécsáv alá kerülhet (a korábbi ragadó fejlécnél is így volt).

- **Szűkített d3-csomag: a pásztázás kézzel ellenőrizendő** (2026-11-25)
  - Automatizált Safariban a nagyítás működik, és a teljes d3-mal azonos eredményt ad; az automatizált húzás (üres vászonról és szóközzel) egyik csomaggal sem mozdította a nézetet, így a pásztázás, az érintéses nagyítás és a „Mind” gomb szemmel nézendő.

- **Külön ablakos szövegszerkesztő és csomag-párbeszéd: a kinézet nincs szemmel ellenőrizve** (2026-11-25)
  - Automatizált Safariban a szövegszerkesztő oldal betölt és működik (a mező mérete, állapotsor, mentés gomb), a darabolt feltöltés a böngészőből végigment; képernyőkép nem készült (a kijelző aludt). A folyamatjelző és a „Folytatás” gomb megjelenése kézzel nézendő.
