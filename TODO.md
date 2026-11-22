


[ **ÖTLET** ]
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



[ **KÍSÉRLETI** ]

SHIFT DRAG: 
- vonal húzáskor, vagy kijelölt vonal vastagítás legyen
- szín váltás ? 
- shift duplakatt: doboz, nyíl, forma váltás

SPACE INSERT: 
- kereső ablak nyílik, rendszer parancsokat lehet megadni, vagy a könyvtárból / közös könyvtárból dokumentumokat - szimbólumokat beilleszteni



[ **HIBÁK** ]

nyilak húzása belül - konténerből befelé (hibás)

admin oldalon az avatar képek egy sorban vannak és rálógnak a többi buttonra. csináld meg úgy hogy csak baloldalon legyen 1 aktuális látható, ha rákattintok akkor egy popup ablakban lehessen kiválasztani a többi közül az újat

canvas megtekintő / szerkesztő részen a bejelentkezett felhasználók neve mellett baloldalt van egy pont, ez már nem kell, csak az avatar ikon. 
tedd a felhasználókat baloldalt alulra, egy sorba, egymás mellé. jobboldalt a szélén legyen a legyen mindig az oldal létrehozója




[ **DESIGN** ]

megtekintő módban: 
a canvas felett baloldalra igazítva legyen kiírva a munkalap címe.

a létrehozókat tedd baloldalt a szöveg box alá
letöltés gombokat jobboldalra 
(cseréld fel)

további munkalapok: 
a cím itt is a box bal felső sarkában legyen, létrehozó bal oldalt alul


 doboz színek, effektek:
 - átlátszóság kapcsoló, szűntets meg, legyen helyette egy új aminek a neve: Free. Nincs látható keret, nincs háttér. Szöveg tördelésnél az elméleti keretet vegye figyelembe
 - új mód: Üres, nincs háttér, keret marad látható.
 - elmosott: marad a jelenlegi viselkedés
 
 ez a három mód csak külön alkalmazható
 kiemelés gomb ikon-szöveg nélkül
 szín választo jobboldalra igazítva
 


## KONTÉNER ÚJ működés

konténer tartalma mindig kitakarva legyen egy felete lévő másik doboztól ami nem a konténer része csak rálóg


A konténer kapjon egy Automatikus elrendezés beállítást. Bekapcsolásakor a konténer saját címe és szövege a tartalomterület felett jelenik meg, az alatta lévő gyermekdobozok pedig rácsban rendeződnek. Keskeny konténernél a rács egy oszlopra vált, és a szöveg sorokra törik.

A gyermekdobozok szélességét és magasságát az elérhető helyhez kell igazítani, a tartalmukat pedig a meglévő dobozrajzolás kezeli. Ha a gyermekek nem férnek el a konténer jelenlegi méretében, a rendszer növelheti a konténer belső tartalmi területét. Ennek látható következménye lehet, hogy a konténer automatikus módban nagyobb lesz.

A kézi pozicionálás megőrzéséhez az automatikus elrendezést külön kapcsolóval érdemes aktiválni, és kezdetben csak a közvetlen gyermekdobozokra alkalmazni. A konténerek egymásba ágyazásának és a konténeren belüli további konténereknek a viselkedését külön szabályként kell meghatározni.

## Fontos adatmodell-kérdés

A jelenlegi rendszer a gyermekdobozok vászon-koordinátáit használja, és a konténerbe kerülés parent kapcsolatként működik. Az automatikus rács megjelenítéskor számított pozíciókat adna a gyerekeknek. Ezeket nem célszerű minden rajzolási ciklusban elmenteni vagy a dokumentumba írni, mert az megnehezíti a közös szerkesztést, az undo-t és a kézi mozgatást.

Javaslat: a konténer tárolja az elrendezési beállításokat, a gyermekek eredeti pozíciói pedig maradjanak meg. A kiszámított pozíció csak megjelenítési réteg legyen; kézi mozgatáskor a felhasználó választhat vagy átválthat kézi elrendezésre. Így az automatikus újratördelés nem írja át észrevétlenül a canvas szerkezetét.

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

