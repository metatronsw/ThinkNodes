
# project migráció

+ Kész (docs/migration.md „Megvalósítás”): ZIP-export (projekt / részfa / lap, .version, külső fájlok, titkosítás), import főoldalon és allapként.
+ Hátra: ThinkNodes-csomag ZIP behúzása a vászonra (most .web-ként próbálja, különben mellékletként tölti fel) → ismerje fel és ajánlja fel az importot.

+ Projektcsomag mérethatára: most a .web ZIP max. 100 MiB, a .thnode max. 12 MiB, a teljes projekt (képek, .web, .version) ennél jóval nagyobb lehet. Dönteni kell a felső határról (és a kibontott méret/fájlszám korlátjáról); ha több száz MB vagy GB is előfordulhat, streamelt feltöltés és letöltés kell (nem `body.collect` memóriába), plusz folyamatjelző a kliensen.


# instance 
- lehessen létrehozni instanced klónokat dobozokról, ha az egyik változtatva van a másik is kövesse a változást.
- kell egy ID minden doboznak (vonal,csomópont egyedi lesz, annak nem kell) vagy már most is van ? 
- 


# SHIFT DRAG: 
Ez egy kísérleti módosító funkció lenne, a property panel kiváltására, hogy minnél kevesebb funkció - szerkesztés miatt kelljen kinyitni. Minden doboz, objektum, és elem kaphatna ilyen extra módosítót. Ha rendelkezik vele, akkor  SHIFT + lenyomott balegérgomb hatására 

+ Nyilat az adott pontra illeszteni dobozon belül!


+ vonal húzáskor, vagy kijelölt vonal vastagítás legyen
- szín váltás ? 
- shift duplakatt: doboz, nyíl, forma váltás

SPACE INSERT: 
- kereső ablak nyílik, rendszer parancsokat lehet megadni, vagy a könyvtárból / közös könyvtárból dokumentumokat - szimbólumokat beilleszteni





[ **FILE KEZELÉS** ]
+ Nagy szövegfájl szerkesztése külső szerkesztőben (docs/node-types.md, text típus). A mérethatárt is meg kell adni.
+ .thnode import: most új almunkalapot hoz létre, de nem keletkezik doboz a vásznon. Az új típusrendszerben (docs/node-types.md) a `sheet` típushoz kell kötni.

Közös fájlok / .web / lomtár – hátralévő (2026-11-23):
+ Kipróbálni két szerkesztővel: törlés („lomtárba, a többi doboz törlődik / üres lesz”) és .web átnevezés, miközben a másik lapot valaki szerkeszti (kijelölt dobozt kihagy, és szól).
+ A pillangó ikon (`webPublic`) csak az aktuális lap dobozain frissül; a többi lapon ugyanarra a fájlra / .web-re mutató doboz régi állapotot mutathat. Megoldás: a szerver adja a publikus állapotot megjelenítéskor, ne a doboz tükrözze.
+ Fájl átnevezése után a többi lapon a dobozon a régi fájlnév látszik (a hivatkozás működik).
+ Másik lapról másolt-beillesztett fájldoboz most új példányt tölt fel; közös hivatkozás legyen helyette (editor.js, beillesztés `sourcePath !== path` ága).
+ Visszavonás (undo) fájldoboz eltávolításakor nem nézi a többi lap használatát; a lomtárba tett (release) fájl undo-val nem jön vissza.
+ Közös könyvtárbeli szövegfájl tartalma a megtekintő oldalon nem jelenik meg (csak a szerkesztőben).
+ A törölt projektek a gyökér `.trash` mappájába kerülnek; ezek kezelése (lista, visszaállítás, ürítés) nincs meg.
+ `common` nevű projektet tiltani kell (a /common/ címet a közös könyvtár foglalja).
+ JS teszt hiba: Tests/Editor/gestures.mjs `ownUnderlay` (a 7e6f36e kijelölés-átírás óta).



[ **KONTÉNER ÚJ működés** ]

konténer tartalma mindig kitakarva legyen egy felete lévő másik doboztól ami nem a konténer része csak rálóg


A konténer kapjon egy Automatikus elrendezés beállítást. Bekapcsolásakor a konténer saját címe és szövege a tartalomterület felett jelenik meg, az alatta lévő gyermekdobozok pedig rácsban rendeződnek. Keskeny konténernél a rács egy oszlopra vált, és a szöveg sorokra törik.

A gyermekdobozok szélességét és magasságát az elérhető helyhez kell igazítani, a tartalmukat pedig a meglévő dobozrajzolás kezeli. Ha a gyermekek nem férnek el a konténer jelenlegi méretében, a rendszer növelheti a konténer belső tartalmi területét. Ennek látható következménye lehet, hogy a konténer automatikus módban nagyobb lesz.

A kézi pozicionálás megőrzéséhez az automatikus elrendezést külön kapcsolóval érdemes aktiválni, és kezdetben csak a közvetlen gyermekdobozokra alkalmazni. A konténerek egymásba ágyazásának és a konténeren belüli további konténereknek a viselkedését külön szabályként kell meghatározni.

## Fontos adatmodell-kérdés

A jelenlegi rendszer a gyermekdobozok vászon-koordinátáit használja, és a konténerbe kerülés parent kapcsolatként működik. Az automatikus rács megjelenítéskor számított pozíciókat adna a gyerekeknek. Ezeket nem célszerű minden rajzolási ciklusban elmenteni vagy a dokumentumba írni, mert az megnehezíti a közös szerkesztést, az undo-t és a kézi mozgatást.

Javaslat: a konténer tárolja az elrendezési beállításokat, a gyermekek eredeti pozíciói pedig maradjanak meg. A kiszámított pozíció csak megjelenítési réteg legyen; kézi mozgatáskor a felhasználó választhat vagy átválthat kézi elrendezésre. Így az automatikus újratördelés nem írja át észrevétlenül a canvas szerkezetét.

## Vászonszerkesztő teljesítménye (docs/PERF.md)

+ Puffer (`overscan`) automatikus méretezése a képernyő és a memória alapján.
+ Nagyítás végi újrafestés gyorsítása; táblázatszerkesztés görgetése és cellakijelölése.
+ Alt / Ctrl lenyomásakor ne változzon a vászon gyökerének osztálya (teljes stílusszámítás).
+ Mérőszkript: csomópont- és konténerhúzás, táblázat 1000 dobozos lapon, Chromium-mérés.

## Teljesítmény és erőforrásigény

Ez várhatóan könnyű számítás, nem folyamatosan nagy terhelésű funkció. A rács kiszámítása alapvetően a közvetlen gyermekek számával arányos (O(n)), a szöveg tördelése pedig a szöveg hosszától függ.

Az elrendezést csak akkor kell újraszámolni, amikor a releváns adatok változnak: gyermek hozzáadása vagy eltávolítása, szöveg- vagy méretmódosítás, konténerméret-változás, illetve ablakméret miatti újrarajzolás. Nem szükséges animációs képkockánként futtatni. A szerkesztőben a számítás kis, korlátos dokumentumokon történhet; szerveroldalon pedig csak akkor kell, ha ugyanazt az automatikus elrendezést a statikus előnézetnek is meg kell jelenítenie.

A legnagyobb költség inkább a viselkedés és szerkesztési élmény megtervezése: például hogy egy gyermek tartalmának növekedése átrendezze-e a többi elemet, vagy hogy a konténer magassága automatikusan nőjön-e.

## Javasolt első változat

Első körben egy kapcsolható Rács elrendezés módot terveznék, amely:

- a konténer saját címét és szövegét felül, olvashatóan mutatja;
- a közvetlen gyermekeket alatta, egy vagy több oszlopban rendezi;
- szűk helyen egy oszlopra vált;
- sorokra tördeli a gyermekek szövegét;
- változáskor újraszámol, nem folyamatosan;
- kikapcsolható, hogy a jelenlegi kézi konténerhasználat megmaradjon.

Ez reális és takarékos megoldás. A megvalósítás előtt tisztázandó tervezési pont, hogy az automatikus mód változtathatja-e a konténer külső méretét, vagy csak annak meglévő méretein belül rendezheti a tartalmát.


[ **ÖTLETEK A JÖVŐBEN** ]
+ lézer rajz
+ szabadkézi rajz
+ svg -nél beágyazható legyen mentéskor a kép
+ A munkalapon automatikusan jelenjenek meg a képek és a file-ok amik a mappában vannak. 
+ svg üres háttér kezelése
+ markdown külön editorba is 
+ elkerülő úton haladó kábel, sosem keresztezi a dobozokat
+ project letöltése zip formtumba
+ sitemap , gráf alapon mutassa a linkeket 
+ javascript nélkül is működjön a statikus oldal megtekintés
+ Animációk az SVG -be, futó vonal 
+ chat a felhasználók között


# Google-bejelentkezés

+ Kész: belépés Google-fiókkal az admin által hozzárendelt e-mail-cím alapján (README „Google-bejelentkezés”).
+ Hátra: kipróbálás valódi Google OAuth-klienssel (Cloud Console: kliens létrehozása, visszatérési cím felvétele), helyben `http://localhost:8888`-on és élesben.
+ Kész: hozzáférés-kérés admin jóváhagyással, jelvény a fejléc Admin gombján (AdminMessages), README és server/deploy/GOOGLE.md.
+ Hátra: a kérelmező értesítése a döntésről (most nincs; a szerver nem küld e-mailt).
+ Lehetőség: további adminisztrátori jelzések (AdminMessage.Kind), pl. lemezhely, hibás mentés.
+ Lehetőség: a felhasználó maga kösse össze / válassza le a Google-fiókját (most csak az admin teheti); a Google `sub` azonosítójának rögzítése az e-mail-cím mellé.
