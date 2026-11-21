


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







ÉRVÉNYTELEN URL:
ha a felhasználó nem létező útvonalat ad meg akkor most egy sima json üzenet van: 
{"error":true,"reason":"Érvénytelen munkalapútvonal."}

Ezt cseréld le egy statikus lapra, amin azt írja ilyen oldal nem létezik. 
linket a fő oldalra, és hogy jelentkezzen be  vagy regisztráljon, hozzon létre új oldalt



---

nyilak húzása belül - konténerből befelé (hibás)


FILE KEZELÉS: 
- töröld a file beillesztés gombot, csak file feltöltése legyen
- file törlése minden esetben a file mappából való törlése is, ezért kérdezzen meg. 
- a törölt file átkerül a project fő mappa .trash/ könyvtárába úgy, hogy ha a projecten belül másik subdirectory -ban volt, akkor másolja annak elérsi útját, hogy vissza állításkor a megfelelő mappába kerüljön majd vissza
- Minden file ami a munkalapon megjelenik, egységesen kapjon megjeleníthető filename -t a property panelen. A panelen NE lehessen átírni az extensiont, de a dobozon alul jelenítse meg teljes filename.extension formába
- HIBA: Nézd át az átnevezést, első átnevezéskor van hogy nem történik meg, és vissza ugrik az eredeti névre
- Ha külsőleg valaki berak valamit a project mappába, akkor azt induláskor/project betöltéskor ellenőrizni kell, és ha lehetséges be kell emelni a canvasra. Ha több van, egymás alá sorba. 

+ KONCEPCIÓ: Mindig, minden file jelenjen meg a canvas-on, csatolt file vagy munkalap. Ha nem támogatott típus - megjeleníthető, akkor egy alap doboz legyen, mint a .txt -nek, aminek csak a címét és a file nevet lehet változtatni. a csomag ikon + filename.extension jelenjen meg. Duplán rákattintva letölthető

+ KÉRDÉS: meg engedni hogy kívülről is elérhető legyen link alapján ? ez milyen kockázattal jár ? hogy valósítható meg, hogy működik a Vapor szerver ?

