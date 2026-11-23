

[ **HIBÁK** ]


 
 
 
 [ **TELJESÍTMÉNY – MEGBESZÉLENDŐ** ]

+ **KÉSZ (2026-11-23): kliensre, közös tesztekkel (PLAN.md C5).** Markdown a dobozokban (gépelés közbeni késés): a szerkesztő minden leütés után a szervertől kéri a doboz szövegének markdown-feldolgozását (`/api/text/canvas`, cmark-gfm), ez ~100 ms késést és leütésenként egy kérést jelent. A tördelés már most is kliensoldali (geometry.js `labelLayout`), a szerver csak a megtekintőhöz, előnézetekhez és exporthoz tördel (Rendering.swift, pontosan egyező szabályokkal). Kérdés: kerüljön-e a markdown-feldolgozás is a kliensre (pl. commonmark.js, ugyanazon CommonMark-specifikáció referencia-megvalósítása), és a szerver csak az előnézetekhez/megtekintőhöz dolgozzon? Ha igen: közös tesztkészlet (bemenet → elvárt blokkok) fusson a Swift- és a JS-oldalon is, hogy a kettő ne térjen el. Részletek: PLAN.md C5.

 [ **DESIGN** ]









[ **KÍSÉRLETI** ]

SHIFT DRAG: 
- vonal húzáskor, vagy kijelölt vonal vastagítás legyen
- szín váltás ? 
- shift duplakatt: doboz, nyíl, forma váltás

SPACE INSERT: 
- kereső ablak nyílik, rendszer parancsokat lehet megadni, vagy a könyvtárból / közös könyvtárból dokumentumokat - szimbólumokat beilleszteni





[ **FILE KEZELÉS** ]
+ Nagy szövegfájl szerkesztése külső szerkesztőben (docs/node-types.md, text típus). A mérethatárt is meg kell adni.
+ .thnode import: most új almunkalapot hoz létre, de nem keletkezik doboz a vásznon. Az új típusrendszerben (docs/node-types.md) a `sheet` típushoz kell kötni.




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