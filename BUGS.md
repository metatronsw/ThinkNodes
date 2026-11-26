# Hibák

Minden munkamenet elején át kell nézni, és a nyitott hibákkal foglalkozni kell (AGENTS.md).

## Nyitott

- **Főoldali .webp előnézetek: nyitott / kézzel nézendő** (2026-11-26)
  - A librsvg a dobozokba ágyazott HTML-t (táblázat, szövegfájl, .md tartalma) nem rajzolja ki: a háttérképen ezek a dobozok üresek. Ha zavaró, a szerver a raszteres változathoz egyszerű helyettesítő vonalakat rajzolhat a szöveg helyére.
  - Élesben (Fedora) a `librsvg2-tools` és `libwebp-tools` csomag kell (az install.sh telepíti); a meglévő szerveren kézzel: `dnf install librsvg2-tools libwebp-tools`, utána szerver-újraindítás. Nélkülük a régi SVG-előnézet megy.
  - Ha egy lap képe nem készíthető el (pl. sérült egyedi előnézeti kép), arra a lapra SVG jön, de a kártya már elmosás nélkül mutatja.
  - A lap átnevezésekor / törlésekor a `.preview*.webp` (mint eddig az SVG-gyorsítótár) a régi néven a mappában marad.
  - Kézzel nézendő: a rámutatás-effekt világos módban és érintőképernyőn.

- **Táblázat-szerkesztés, „Tartalom a dobozhoz”, kurzorcsoport: kézzel nézendő / nyitott** (2026-11-26)
  - A skálázott táblázat szerkesztőjében a valódi egérkattintást a vezérelt Safariban nem lehetett végigpróbálni (az ablak közben elvesztette a fókuszt); a cellaválasztás kódja JS-eseménnyel és a találatvizsgálattal (a kattintott pont alatt a jó cella áll) ellenőrizve. Kézzel nézendő: kattintás, húzásos kijelölés, oszlopszélesség húzása, sor / oszlop kijelölése skálázott táblázatban, nagyított vásznon is.
  - Skálázott szerkesztésnél a fejlécsávok és a képletsor is a táblázattal együtt kicsinyül, és a doboz belső margóján (részben a dobozon belül) állnak; nagy kicsinyítésnél a képletsor nehezen olvasható.
  - A „Tartalom a dobozhoz” csak táblázatdobozon van (CSV-n nincs); 200 sornál hosszabb táblázatnál az olvasó nézet az első 200 sort skálázza, a szerkesztő az összeset.
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
  - A chat-próba a helyi `projects/a` mappában üres `.chat.jsonl` fájlt hagyott; törlése engedélyre vár.
  - A sötét palettaszínek (pl. `#027864`, `#6550b9`) neve sötét módban a jelenlévők között halványabban olvasható.

- **WhiteBoard: nyitott és kézzel nézendő tételek** (2026-11-25)
  - Füzetlapon a markdown lista elemei között egy üres sor van (a sorvonalak tartása miatt); a nagy címsor egy sorvonalnyi magasságba szorul.
  - Kézzel nézendő: szabadkézi doboz kijelölése és átméretezése (a rajz méretváltáskor újraszámolódik), zárolt konténer, megtekintő és SVG-export a füzetlappal (beágyazott CSS, `lh` nélkül, `--rule` változóval), a cetli táblázatszerkesztése.

- **Liquid Glass: kézzel nézendő és nyitott tételek** (2026-11-25)
  - Automatizált Safariban rendben (képernyőkép és mérés): világos / sötét mód, kijelölés fényudvara, ping, üvegpanel, megtekintő. Kézzel nézendő: a kattintásgyűrű és a rámutatás áttűnései szemre, más felhasználó kijelölésének glow-ja két böngészővel, a gyors eszközök és a helyi menü üveghatása, a többi négy paletta, mobil.
  - A fejléc gombjai nem kapnak üveghatást (a szerkesztő munkaterületén kívül vannak).
  - Élénk kitöltésen a doboz szövegszíne nem igazodik magától: világos módban a halványabb élénk színeken (pl. zöld) a világos szöveg nehezen olvasható.
  - Csökkentett mozgás beállításnál (`prefers-reduced-motion`) a kattintásgyűrű és a ping animációja megmarad.

- **A 2026-11-25-i vonal- és gyorseszköz-változások: kézzel, Safariban nézendő** (2026-11-25; a tesztek 2026-11-26-án hozzáigazítva, mind átmegy)
  - Kézzel nézendő Safariban: a futó pötty (szerkesztő, megjelenítő, export), a három vonalméret régi munkalapokon, a fájlnév helyben szerkesztése (ékezetek, Enter, Esc), a gyors eszközök az ablak négy sarkában.

- **Gyors eszközök (próba): ismert hiányok** (2026-11-25)
  - A hagyományos menü „Szerkesztés” parancsa (panel megnyitása) nem került a gombok közé.
  - Ahol egy feliratos gombnak nincs saját ikonja (pl. táblázat egyes gombjai), az alapértelmezett fájl-ikon látszik, több gomb egyforma lehet.
  - A kinyitott lista csak a saját gombjára vagy választásra zárul; máshová kattintva nyitva marad, amíg a gyors eszközök látszanak.
  - Háttér nélküli gombok tarka tartalom fölött nehezebben olvashatók.

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

- **A CSV olvasó nézet legfeljebb 200 sort / 30 oszlopot mutat; a megtekintőben a cellakijelölés nem látszik** (2026-11-24)
  - Az ezen kívüli cellára eső társ-kijelölés nem jelenik meg az olvasó nézetben. (Az üres sorok miatti elcsúszás javítva.)

- **Táblázatszerkesztő új fejlécsávjai: Chromiumban és CSV-n nincs kipróbálva** (2026-11-25)
  - A ragadó fejlécek helyett külön fejlécsávok vannak (lásd DONE.md). Automatizált Safari 18.6-ban táblázaton ellenőrizve (megjelenés, oszlopszélesség húzása); Chromiumban, CSV-szerkesztésnél, egyedi sormagasságnál és a „méretre igazítás” gombbal még nézendő. A görgetés sebessége az új szerkezettel nincs mérve (2026-11-25-én a `perf.py` nem futott le: az automatizált Safari időzítői álltak).
  - Ha a megnyitott cella a rács legfelső sorába esne, a fejlécsáv alá kerülhet (a korábbi ragadó fejlécnél is így volt).

- **Szűkített d3-csomag: a pásztázás kézzel ellenőrizendő** (2026-11-25)
  - Automatizált Safariban a nagyítás működik, és a teljes d3-mal azonos eredményt ad; az automatizált húzás (üres vászonról és szóközzel) egyik csomaggal sem mozdította a nézetet, így a pásztázás, az érintéses nagyítás és a „Mind” gomb szemmel nézendő.

- **Külön ablakos szövegszerkesztő és csomag-párbeszéd: a kinézet nincs szemmel ellenőrizve** (2026-11-25)
  - Automatizált Safariban a szövegszerkesztő oldal betölt és működik (a mező mérete, állapotsor, mentés gomb), a darabolt feltöltés a böngészőből végigment; képernyőkép nem készült (a kijelző aludt). A folyamatjelző és a „Folytatás” gomb megjelenése kézzel nézendő.

- **Az új doboz ugyanolyan színű, mint a konténer, amibe kerül** (2026-11-25)
  - Az új doboz mindig a 2-es színt kapja; ha a konténer is 2-es színű (alapértelmezett doboz), a belehelyezett doboz csak a keretéről látszik, amíg más színt nem kap (`projects/b`). Döntés kell: kapjon-e az új / belehúzott doboz automatikusan eltérő színt.
