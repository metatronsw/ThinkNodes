# Mindig szólj ha a vapor szerver kódja változott és újra kell indítani

# Ne kérdezz feleslegesen script indítás engedély kérés miatt

# ha azt mondom ez a funkció kísérleti, akkor előtte csinálj meg mindent ami normális feladat, utána csinálj git commit -ot mielőtt elkezdenéd a kísérletit

# A helyi fejlesztés és az éles működés külön kezelendő. A helyi `Projects` mappa nem azonos az éles szerver adatkönyvtárával (jelenleg `/var/lib/thinknodes/Projects`). Minden feladatnál tisztázd vagy állapítsd meg, melyik környezetre vonatkozik; a helyi fájlmódosítás nem jelenik meg automatikusan élesben. Éles szerverhez ne csatlakozz és ott ne módosíts adatot, hacsak a felhasználó ezt kifejezetten nem kéri.




# Vapor szerver indítása helyben: mindig a 8888-as porton, hogy a http://mtrn.local:8888 címről elérhető legyen (HTTPS esetén https://mtrn.local:8888). Kötés `::` címre (IPv4 + IPv6, a mtrn.local helyben csak IPv6-ra oldódik fel), pl.: `THINKNODES_DATA=Projects THINKNODES_SECURE_COOKIES=0 .build/debug/ThinkNodes serve --hostname :: --port 8888`, vagy `THINKNODES_HOST=:: ./run.sh --local --port:8888` (HTTPS-hez: `THINKNODES_HOST=:: ./run.sh --port:8888`). Egy adatkönyvtárhoz egyszerre csak egy szerverpéldány fusson, ezért HTTP és HTTPS közül egyszerre csak az egyik.

# Ha teszteléshez (pl. szerkesztő böngészős ellenőrzése) szükséges, a szerver tesztmódban indítható: `THINKNODES_HOST=:: ./run.sh --local --test --port:8888` (launch.json: `thinknodes-test`). Ilyenkor minden csatlakozó admin jogot kap; ez helyben rendben van, mert a helyi hálózaton más soha nincs. Élesben tilos.
