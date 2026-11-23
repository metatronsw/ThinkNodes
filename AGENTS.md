# Mindig szólj ha a vapor szerver kódja változott és újra kell indítani

# Ne kérdezz feleslegesen script indítás engedély kérés miatt

# A helyi fejlesztés és az éles működés külön kezelendő. A helyi `Projects` mappa nem azonos az éles szerver adatkönyvtárával (jelenleg `/var/lib/thinknodes/Projects`). Minden feladatnál tisztázd vagy állapítsd meg, melyik környezetre vonatkozik; a helyi fájlmódosítás nem jelenik meg automatikusan élesben. Éles szerverhez ne csatlakozz és ott ne módosíts adatot, hacsak a felhasználó ezt kifejezetten nem kéri.


# Vapor szerver indítása helyben: mindig a 8888-as porton, 

# Ha teszteléshez (pl. szerkesztő böngészős ellenőrzése) szükséges, a szerver tesztmódban indítható: `THINKNODES_HOST=:: ./run.sh --local --test --port:8888` (launch.json: `thinknodes-test`). Ilyenkor minden csatlakozó admin jogot kap; ez helyben rendben van, mert a helyi hálózaton más soha nincs. Élesben tilos.

# Minden munkamenet elején nézd át a BUGS.md-t, és foglalkozz a nyitott hibákkal, mielőtt új feladatba kezdesz. A javított hibát vidd át a „Javítva” részbe.
