

készíts egy tervet és próba verziót arra az esetre ha a kliens drag & drop a canvas területére egy dokumentumot vagy képet. Különböztessünk meg kategóriákat: 
- kép: jelenítse meg ha kompatibilis, átméretezhető, markdown text is adható hozzá
- dokumentum: txt, md, json,  jelenítse meg formázott módon
- hang: mp3 . lejátszható play icon, bele tekerhetőség 



képek és json kód beemelése
paste text / markdown


svg -nél beágyazható legyen mentéskor 
A munkalapon automatikusan jelenjenek meg a képek és a file-ok amik a mappában vannak. 

svg üres háttér kezelése

+ markdown külön editorba is 

+ elkerülő úton haladó kábel, sosem keresztezi a dobozokat



+ project letöltése zip formtumba

+ sitemap , gráf alapon mutassa a linkeket 

+ javascript nélkül is működjön a statikus oldal megtekintés


+ Animációk az SVG -be, futó vonal 


## --------------- --------------- ---------------


doboz keret szín legyen automatikus
töröld a keret szín beállítást és a .json file ból is 
a text háttér colort is töröld, nincs rá szükség
ne foglalkozz a régi projectekkel, írd át úgy a rendszert hogy ha betöltéskor olyan property-t vagy key -t talál a .json -ban ami nem értelmezhető, akkor csak eldobja, új mentéskor már nem rakja bele. Ha hiányzik egy property akkor se áljon le a rendszer, töltse be hiányosan és pótolja default értékkel

text tool tip akkor is jelenjen meg a box mellett onmouse ha nincs text hide, viszont nem fér ki a szöveg a boxban! 


grid kapcsoló a al alsó sarokban ne legyen globális, csak kliens oldali felülbírálás

letöltéskor a grid-et NE rakja bele az svg -be .. ne csak hide legyen, hanem törölje a file ból, bele se rakja!

gépelés közben folyamatosan villognak-frissülnek megtekintő oldalon a letöltés és bejelentkezés gombok.

link a dobozon: írd ki az ikon mellé (úgy hogy a szöveg jobbra legyen igazítva, az ikon jobboldalon a legszélén legyen) a Link tartalmát is. (tehát hogy /subdir vagy https://google.com
onMouseOver esetén pedig legyen aláhúzva és szöveg

property panel : tedd az előnézet és szerkesztés gombot lelgalulra jobboldalra. (baloldalt marad egy sorba a törlés) 

fejléc resign és mentés gomb cseréljen helyet.
fejléc: megtekintés gombot nevezd át : bezárás -ra
fejléc: kijelentkezés gombon csak az ikon legyen, felirat nem

project nézet: 
töröld a projectek megjelenítésénél a kártyáról az ikont
tedd be háttérnek elmosottan a project fő munkalapját. (csak a statikus svg-t használd, nem kell live view)
legyen a tipográfia szebb, jobban tagolva az ikonok, cím, és írd ki hány lapot tartalmaz összesen


vonal rendszer:

vonal felirat mindig középen legyen, akkor is ha változik a vonal hossza, próbáld meg igazítani a speciális vonal típusoknál is, hogy párhuzamos legyen a közepével

villám vonal legyen agresszívebb, közelebb legyenek a töréspontok, kevésbé távolodjanak el a középponti tengelyől

a vonal kijelölése egyezzen a vonal stílussal, legyen része a nyílvég is. kijelölt állapotban is megállapítható legyen hogy ez milyen vonal : szaggatott vagy pöttyös.

kijelölt doboz kijelölés kerete kapjon egy glow effektet
a glow effektnek adj egy lassú pulzáló smil aminációt ami örök loop



munkalap beállítások:
szerkesztők között ne sorolja fel a tulajdonost



