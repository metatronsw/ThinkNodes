
# project migráció
+ Hátra: a darabolt feltöltés kipróbálása valódi, több GB-os csomaggal és megszakított hálózattal (eddig tesztek és kis csomag); a `.web` ZIP (100 MiB) és a `.thnode` (12 MiB) feltöltése továbbra is egyben megy.


# FILE KEZELÉS
Közös fájlok / .web / lomtár – hátralévő (2026-11-23):
+ Kipróbálni két szerkesztővel: törlés („lomtárba, a többi doboz törlődik / üres lesz”) és .web átnevezés, miközben a másik lapot valaki szerkeszti (kijelölt dobozt kihagy, és szól).
+ Visszavonás lomtárba tétel után: a fájl visszaáll (2026-11-24), de a többi lapon a törölt / üres dobozzá alakított dobozok nem állnak vissza. Ehhez a lomtárba tételkor fel kellene jegyezni a többi lap érintett dobozait.
+ A pillangó ikon és az átnevezett fájlnév a többi lapon a következő betöltéskor frissül (a szerver olvasáskor adja); nyitott szerkesztőben azonnali frissítéshez értesítés kellene a többi lapnak.
+ Törölt projekt visszaállítása más néven (most csak az eredeti néven, ha szabad).
+ .web élő ablak a dobozban (előnézet helyett futó oldal, átméretezés = ablakméretezés): tanulmány kész (server/docs/web-elo-ablak-tanulmany.md, 2026-11-26); a 9. pont kérdései döntésre várnak, utána Safari-prototípus és mérés.


# Kódszínezés (server/Sources/ThinkHighlight) és dobozon szerkesztés

- Ismert egyszerűsítések: JS-ben a `)` / `]` / `}` utáni `/` mindig osztás, az objektumkulcsok és a JSX nem kapnak külön színt; Swiftben a `/…/` reguláris kifejezés nincs felismerve; HTML-ben a `style="…"` attribútum és az eseménykezelők tartalma sima szöveg.
- További nyelvek igény szerint (`.ts`, `.py`, `.xml` / `.svg` – az utóbbi a HTML elemzővel).
- Szerkesztés közben minden leütés a teljes szöveget újraszínezi és újraépíti a doboz tartalmát; nagyobb (100 KB körüli) fájlnál mérendő, kell-e csak az érintett sorokat frissíteni.
- A kódszerkesztőben nincs Shift+Tab (behúzás csökkentése) és több sor együttes behúzása.
- A `.md` doboz szerkesztéskor nyers szövegre vált (más betű, más magasság): ez a formázott megjelenítésből adódik.
- A letölthető SVG-ben a fájldobozok tartalma egyébként formázatlan (nincs belső térköz, a doboz betűmérete, a túlnyúló szöveg levágása; a `.txt` / `.md` doboz is ilyen): az exportba a fájldobozok alapstílusát is be kellene ágyazni.
- Nincs ellenőrizve: az előnézeti rajz (`/api/preview`) képként (`<img>`) megjelenítve is színes-e – a válasz `style-src 'self'` szabálya a beágyazott stílust tilthatja.
- A közös könyvtár (`@common`) kódfájljai a szerkesztőben színezetlenek (statikus címről töltődnek); a megtekintőben színesek.
- Dobozon szerkesztés kiterjesztése más dobozokra (sima doboz szövege, megjegyzés); a külön ablakos nagyfájl-szerkesztő színezés nélküli.
- Szemmel nézendő Safariban: a szövegmező háttere és betűje szerkesztés közben, a kurzor és a görgetés nagyított vásznon, mentetlen szöveg rövid színezetlen állapota bezárás után.

# Google-bejelentkezés

+ Hátra: kipróbálás valódi Google OAuth-klienssel (Cloud Console: kliens létrehozása, visszatérési cím felvétele), helyben `http://localhost:8888`-on és élesben.
+ Döntés (2026-11-25): a kérelmező nem kap levelet a döntésről; visszatéréskor látja az állapotot.
+ Lehetőség: további adminisztrátori jelzések (AdminMessage.Kind), pl. lemezhely, hibás mentés.
+ Lehetőség: a felhasználó maga kösse össze / válassza le a Google-fiókját (most csak az admin teheti); a Google `sub` azonosítójának rögzítése az e-mail-cím mellé.

# Teljesítmény (server/docs/PERF.md „Betöltés és szerver – 2026-11-25”)

+ Szerver: HTTP/2 élesben, előre tömörített statikus fájlok, megtekintő oldal gyorsítótára, `usageLocked` és `reconcile` ritkítása.
+ Kliens: `modulepreload`, `commonmark.js` halasztott betöltése. (A szűkített d3-csomag kész: 2026-11-25.)
+ Mérés: a táblázatszerkesztő görgetése az új fejlécsávokkal (Safari, `perf.py --only table`); a `perf.py` `tabla` lapos futása javítandó (a keresett `n00005` doboz nincs meg).

# Grafikon (Public/chart.js)
- SVG-exportban és az előnézeti képen a grafikon doboza üres (a rajz a böngészőben készül). Megoldás lehet: a szerkesztő mentéskor a kész SVG-t is eltárolja.
- Az „egy grafikon – egy táblázat” szabályt csak a szerkesztő tartja be; a szerver több adatvonalnál az utolsót veszi forrásnak (kézzel írt vagy importált lapnál fordulhat elő).
- További lehetőségek: halmozott oszlop, vízszintes sáv, területdiagram, tengelycím, saját színek, sorok helyett oszlopok mint sorozatok, dátumtengely.
- A grafikon buboréksúgója a böngésző saját `<title>` súgója; a szerkesztő közös buboréksúgójára (tooltip.js) érdemes átállni.
- A helyi próbalap (`projects/a/grafikon`) törölhető, ha már nem kell.

# Struktúra-konténer (Public/structure-boxes.js)
- Swift-forrás: `struct` és tárolt `let` / `var` tulajdonságok (számított változó nem) elemzője a `formats` jegyzékbe; a `.swift` kiterjesztés a `geometry.js` `structureSourcePattern` és a `Model.swift` `isStructureSource` listájába. Struct → konténer, tulajdonság → doboz (név: típus), struct típusú tulajdonság → beágyazott konténer (a típus definíciója szerint).
- Újragenerálás visszavonása: a visszavont generálás után a forrás ujjlenyomata eltér, ezért a figyelő azonnal újraépíti (a forrásfájl szerkesztése nincs a visszavonási lépésekben).
- Gépelés közben minden újragenerálás külön visszavonási lépés és mentés; lehetőség: összevonás a gépelés végéig.
- Két szerkesztő egyszerre generálhat (azonos eredménnyel); lehetőség: csak a forrást szerkesztő kliens generáljon.
- A dobozméret becsült szövegszélességből számol (nem a szerkesztő mérőjéből): szélsőséges betűtípusnál a szöveg kilóghat vagy sok hely marad.
- Újragenerálás után a megnőtt konténer rátakarhat a mellette / alatta lévő dobozokra (a bal felső sarka marad, jobbra-lefelé nő); lehetőség: a szomszédok eltolása vagy jelzés.
- A konténer 4096 képpontos legnagyobb méretén túl a tartalom kilóg (nagy forrásnál); lehetőség: kisebb betű / tömörebb elrendezés.

# Konténer – szöveg körbefuttatása

- Automatikus teszt a körbefuttatásra (JS–Swift egyezés: `textSlot`, körbefuttatott `labelLayout`).
- A sor a doboz mellett a legszélesebb szabad szakaszt használja; egy rövid sorvég így a doboz túloldalára kerülhet. Lehetőség: a megkezdett bekezdés maradjon ugyanazon az oldalon.
- Csak a közvetlen gyermekeket kerüli ki, a befoglaló téglalapjuk szerint (nem téglalap alakú gyermeknél is).
- A szövegszerkesztő mező a vásznon (gépelés közben) nem követi a körbefuttatást.
- A régi `autoLayout` kulcs olvasása (`Model.swift` `FormerKey`) törölhető, ha már egyik szerveren sincs ilyen lap.
- Sebesség, további lehetőségek (2026-11-25):
  - csak az érintett bekezdések újratördelése és külön `<text>` bekezdésenként (kisebb csere);
  - a `dx` lista rövidítése (az utolsó szóköz utáni nullák elhagyása).
- Keskeny konténerben a doboz melletti szűk helyre (40 képponttól) is kerül szöveg, szavanként egy sorban; lehetőség: nagyobb legkisebb szélesség, alatta a szöveg a doboz alatt folytatódjon.
- Nyilak konténerben: a konténerből a saját belső dobozára húzott (beágyazott) vonal a konténer szélétől a dobozig tart; ha a doboz a szél közelében van, a vonal nagyon rövid. Lehetőség: más kiindulópont (pl. a konténer címsora vagy közepe felől).
- Nagy csoport (150+ doboz és 200+ vonal) húzása lassú (Safari: 14 képkocka/mp): minden kijelölt doboz és vonal képkockánként újrarajzolódik, a végpontfogantyúkkal együtt. Lehetőség: a csoport együtt mozgatása egy közös transzformációval.
- Konténer ráhúzása kint lévő csomópontra: a konténer a dobozokat befogja, a csomópontokat nem.
- A régebbi munkamenet-mentés maradéka az `editor.js`-ben (`checkpointState`, `checkpointRevision`, `checkpointBusy`, `receiveCheckpoint`): a hívója (`sessionAction`) törölve, az állapotot már semmi nem állítja.
- Modulverziók (`?v=`) kézi léptetése négy fájlban: automatizálható (a szerver adja a verziót).
- `perf.py`: a téglalap-kijelölő lépés Alt nélkül fut (`ALT = ""`), így alapból nem kijelölést mér.
- A `gestures.mjs`-ből kimaradt a „csomópont tartalmas konténerre ejtve a tartalma lesz” eset (Safariban kézi szkripttel ellenőrizve); pótolandó.


# HÁTTEREK ÉS MEGJELENÍTÉS

+ Könyvtárra bontott témák: `Public/themes/<Név>/theme.json`, mellette a téma képei és hangjai (most a képek `Public/themes/<Téma>.<név>.webp` néven a JSON mellett állnak). Utána témánkénti hang (pl. `sounds.ping`). Érinti: betöltő (Theme.swift `Themes.catalog`), editor.js `textureURL`, a témák áthelyezése, tesztek (gestures.mjs, test.sh), themes.md / séma.
+ A megtekintő megszűnik: a vendégeknek és a csak olvasási joggal rendelkezőknek a szerkesztő csak olvasható módja kell (exportok, előadás követése, csevegés, napló, élő kijelölések). Utána a viewer.js, a passivePage és a megtekintő-specifikus szerveroldali rajzolás törölhető.


# ÚJ DOBOZ SZÍNE

+ Megbeszélendő: az új doboz színe az utoljára létrehozott doboz színe legyen (most mindig a 2-es szín, így alapértelmezett konténerben csak a keretéről látszik). Az automatikus eltérő szín elvetve (2026-11-26).


# GYORS ESZKÖZÖK / TULAJDONSÁGPANEL

+ A „kinyíló rész semmit nem tol el” szabály bevezetése a tulajdonságpanelen is: a színválasztó listája ott még eltolja a többi gombot (a gyors eszközökben már rögzített réteg: `ColorPicker floating`, `placePopup`).
+ A többi típus (fájldobozok, kép, vonal, csomópont) saját elrendezése a `quick-tools.json`-ban (most a „*” automatikus sorai adják).


# RAJZESZKÖZÖK (lézer, filctoll – Public/laser.js)
- A később belépő nem látja a már meglévő filcrajzot (a szerver csak továbbít, nem tárol). Ha kell: a szobában a résztvevőnkénti utolsó filcrajz tárolása a pontkorlátig, és átadása belépéskor (mint az előadás kerete).
