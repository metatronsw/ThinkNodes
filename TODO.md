


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




FILE TÖRLÉS:
- törlés a munkalapról (alap beállítás)
- törlés a mappából is

FILE BROWSER:
- a project mappából és azok almappáiból tud válogatni, drag & drop módszerrel, vagy file hozzá adása gomb-al


SPACE INSERT: 
- kereső ablak nyílik, rendszer parancsokat lehet megadni, vagy a könyvtárból / közös könyvtárból dokumentumokat - szimbólumokat beilleszteni
-




doboz link szöveget vedd nagyobra
locked konténer keret vastagsága legyen duplája
canvas property: töröld a sorkizárás gombot

CURSOR HIBA:
- vizsgáld felül az egér cursor viselkedését, bizonyos esetekben nem tudja kikötni elsőre a dobozba bekötött vonal véget
- nézd át a rendszert, tegyél optimalizálási javaslatot

ha végeztél akkor egyszerűsítsd: 
- alapból üres canvas felett normál cursor
- drag közben váltson csak hand -re 
- alt lenyomásakor váltson cursort (rád bízom mire, de sorold fel a lehetőségeket) 
- objektum felett ha nincs még szelektálva akkor csak a hand-pointing ikon legyen, ha már mozgatom akkor váltson a 4 nyil ikonra


# Fejléc megszűntetése: 

editor módban: 
- teljesen töröld a fejlécet, nincs rá szükség
- Admin gomb a ThinkNodes ikon és path elé kerüljön balolralra (csak akkor ha admin van bejelentkezve)
- visszavonás, újra,  resign, gomboj a property panel becsukó nyil gombbal egy sorba kerüljenek át, csak ikon kell
- bezárás gomb a canvas becsukó gomb mellé kerüljön át egy sorba, csak ikon kell, legyen más ikon, egyértelműbb
- ha egy munkalap nem a legfelsőbb mappában van, akkor középen felül egy felfele mutató talpas szárú ikon jelenjen meg (mint most) 
- ha egy munkalap nem a fő munka lap (nem egyezik a neve a mappával) tehát mellék lap, akkor egy ballra mutató talpas ikon legyen ott fent középen, amit megnyomva a mappa fő lapra ugrik

megtekintő módban: 
- azonos az editor mód új elrendezésével, itt is törölni kell a kék fejléc sávot
- a munkalap nézeten belül van a jobb felső sarokban a ceruza ikon: ezt helyezd a munkalap fölé középre



