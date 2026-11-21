


+ svg -nél beágyazható legyen mentéskor a kép
+ A munkalapon automatikusan jelenjenek meg a képek és a file-ok amik a mappában vannak. 
+ svg üres háttér kezelése
+ markdown külön editorba is 
+ elkerülő úton haladó kábel, sosem keresztezi a dobozokat
+ project letöltése zip formtumba
+ sitemap , gráf alapon mutassa a linkeket 
+ javascript nélkül is működjön a statikus oldal megtekintés
+ Animációk az SVG -be, futó vonal 

konténer:
- jelezni kell vizuálisan mikor befoglal magába egy másik dobozt. Legyeni ilyenkor a konténer kerete pontozott és kapjon glow effektet.
? Konténert rátolva a kisebb dobozra, akkor is foglalja magába (ha teljesül a befoglalási méret szabály )



SHIFT DRAG: 
- vonal húzáskor, vagy kijelölt vonal vastagítás legyen
- szín váltás ? 
- shift duplakatt: doboz, nyíl, forma váltás

{ 
SPACE INSERT: 
- kereső ablak nyílik, rendszer parancsokat lehet megadni, vagy a könyvtárból / közös könyvtárból dokumentumokat - szimbólumokat beilleszteni
}





FILE KEZELÉS: 
- engedni hogy kívülről is elérhető legyen link alapján ? 

FILE BROWSER:
- a project mappából és azok almappáiból tud válogatni, drag & drop módszerrel, vagy file hozzá adása gomb-al


FILE TÖRLÉS: 
(kép, hang, zip, dokumentum esetén kérdezze meg)
- törlés a munkalapról (alap beállítás)
- törlés a mappából is


ÉRVÉNYTELEN URL:
ha a felhasználó nem létező útvonalat ad meg akkor most egy sima json üzenet van: 
{"error":true,"reason":"Érvénytelen munkalapútvonal."}

Ezt cseréld le egy statikus lapra, amin azt írja ilyen oldal nem létezik. 
linket a fő oldalra, és hogy jelentkezzen be  vagy regisztráljon, hozzon létre új oldalt




igazítsd úgy a grid-et, hogy az első pont a 0,0 origóba legyen

mikor be van csukva a property panel, dupla kattintásra akkor is tudni kell editálni a címet (ne nyiljon ki a property - csak jelenjen meg a szöveg kiemelés az objektum címén (vagy azon amit editálok) 

editáláskor a szöveg háttérszíne az objektum színe legyen sötétebb/világosabb verzióban attól függően melyik látszik jobban, a rectangle legyen lekerekített.

saját avatar választót töröld a canvas property -ból
az avatar választó helye az admin menüben van, az admin választja ki az usereknek

a canvas property menübe került a hand ikon, ami a pan lock, ezt tedd át a toolbar menübe

adj hozzá egy gombot, file beillesztése (a már meglévő projectben lévő file -ok közül tallózzon ) 
a file feltöltés és beillesztés gomb egy sorba egymás mellett legyen a canvas property alján

a canvas property becsukó/kinyitó gomb -nak adj új ikont, egy menü rendszer legyen

a jobboldali property ki/be csukónak is adj új ikont

jobb felül a mentés ikon legyen olyan mint a többi, ha disabled és ha lehet nyomni ( ne legyen kék ) 

admin gomb kerüljön át a jobboldal legszélére, utolsó előtti gomb legyen (a property bezáró legyen a legszélén jobboldalon ) 

nézd meg a .txt boxot, megjelenik rajta a görgető sáv, de nem lehet használni. 


---

nyilak húzása belül - konténerből befelé (hibás)
