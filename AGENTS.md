# Csak akkor módosíts ha engedélyt adtam rá, vagy külön utasítottam az első parancsban.

# Script futtatása tesztelés céljából mindig engedélyezett helyi mappákat érintő feladatban

# Vapor szerver indítása helyben: mindig a 8888-as porton történjen: run.sh --port:8888

# Vaport mindig csak egy szerver fusson egyszerre!

# Mindig szólj ha a vapor szerver kódja változott, indítsd ujra ha van futó szerver!

# A helyi fejlesztés és az éles működés külön kezelendő. A helyi `projects` mappa nem azonos az éles szerver adatkönyvtárával (jelenleg `/var/lib/thinknodes/Projects`). 

# Ha teszteléshez (pl. szerkesztő böngészős ellenőrzése) szükséges, a szerver tesztmódban indítható: `server/run.sh --port:8888 --test` 

# Minden munkamenet végén ír be a BUGS.md -be a nyitott hibákkat amik nem lettek megoldva vagy félre lettek rakva. Javított híbákat a DONE.md -be kell rakni

# Félretett feladatokat a TODO.md -be rakjad, témák szerint csoportosítva. Ha készen van töröld onnan, nem kell beírni hogy készen van.

# Mappaszerkezet: a gyökérben csak `server/` (minden kód, szkript, teszt, dokumentáció) és `projects/` (helyi adat) van. Gyökér mappában a nagy betűs .md fileok neked szólnak, szerkeszthetes és olvashatod őket. Amit nem olvashatsz és nem szerkeszthetsz: `note.md`

# Feladatok végeztével ha én azt mondom el van fogadva, akkor csinálj Git commitot, és mond el milyen commentet irtál hozzá. Írd be a CHANGES.md -be és ha a dokumentációt is kell változtatni, ird át a README.md -t 

# Git commit sose tartalmazzon push -t, azt manuálisan kell, neked nincs rá jogod, csak lezárt feladatoknál kell vagy külön kisérleti branch létrehozása előtt! 

# Külső szerverre csak külön utasításra, engedéllyel csatlakozhatsz. 

# File törlése minden esetben engedély köteles.






