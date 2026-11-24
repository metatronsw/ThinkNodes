# Google-bejelentkezés beállítása az éles szerveren

Ez a leírás a Fedora szerverre telepített ThinkNodes szolgáltatásra vonatkozik (`server/deploy/daemon.sh`).
A Google-bejelentkezés nem kötelező: amíg nincs beállítva, a belépőoldalon csak a felhasználónév és a jelszó látszik.

Állapot: a kód tesztekkel ellenőrzött, de valódi Google OAuth-klienssel még nem futott. Az első éles belépés a tényleges próba; ha nem megy, a „Hibakeresés” fejezet segít.

## Mit ad, és mit nem

- A belépőoldalon megjelenik a „Belépés Google-fiókkal” gomb. A jelszavas belépés változatlanul megmarad.
- A Google csak azonosít: megmondja a szervernek, hogy a böngésző előtt ülő személy melyik e-mail-cím tulajdonosa. Hogy ki mit láthat és szerkeszthet, azt továbbra is a ThinkNodes-fiók szerepköre és a projektek jogosultságai döntik el.
- A Google-től nem jön létre új fiók. Belépni csak azzal a Google-fiókkal lehet, amelynek az e-mail-címét az adminisztrátor előre hozzárendelte egy ThinkNodes-felhasználóhoz.
- A szerver a Google-től csak az e-mail-címet kéri (`openid email`), nevet, profilképet, naptárat, fájlokat nem. A címen kívül semmit nem tárol a Google-fiókról.

## Előfeltételek

1. **Nyilvános domainnév.** A Google visszatérési címnek csak `https://` kezdetű, valódi végződésű (`.hu`, `.com`…) domainnevet fogad el. IP-címet (`https://192.168.0.10/…`) és `.local` nevet nem. A névnek nem kell az internetről elérhetőnek lennie: a Google maga soha nem csatlakozik a szerverhez, csak a felhasználó böngészőjét irányítja vissza, ezért belső hálózati címre mutató DNS-név is megfelel.
2. **HTTPS.** A szolgáltatás alapból HTTPS-en fut a 443-as porton, ez megfelel. A beépített LAN-tanúsítvánnyal is működik (a Google nem ellenőrzi a szerver tanúsítványát), de a böngészőknek ugyanúgy meg kell bízniuk benne, mint eddig.
3. **Google-fiók a Google Cloud Console-hoz** (bármelyik, ingyenes; nem kell fizetős szolgáltatás).
4. **A Google-bejelentkezést tartalmazó ThinkNodes-verzió** a szerveren (lásd „Telepítés”).

## 1. OAuth-kliens létrehozása a Google-nál

A Google időnként átnevezi a menüket; a lényeg a három dolog: hozzájárulási képernyő, „Web application” típusú kliens, visszatérési cím.

1. Nyisd meg: <https://console.cloud.google.com/>, és hozz létre egy projektet (pl. „ThinkNodes”), vagy válassz egy meglévőt.
2. **Hozzájárulási képernyő** („APIs & Services → OAuth consent screen”, újabb felületen „Google Auth Platform → Branding / Audience”):
   - Alkalmazásnév (ezt látják a felhasználók a Google oldalán, pl. „ThinkNodes”) és egy kapcsolattartó e-mail-cím.
   - Felhasználói kör: **External** (bármilyen Google-fiók), vagy **Internal**, ha Google Workspace-szervezeted van, és csak a szervezet tagjai lépnek be.
   - Hatókörök (scopes): elég az alapértelmezett `openid` és `email`. Ezek nem érzékeny hatókörök, a Google ellenőrzési eljárása nem kell hozzájuk.
   - External esetén a közzétételi állapot kezdetben **Testing**: ekkor csak a „Test users” listára felvett Google-fiókok tudnak belépni (legfeljebb 100). Ha ennél többen lesznek, vagy nem akarod a listát karbantartani, állítsd **In production** állapotra.
3. **Kliens** („APIs & Services → Credentials → Create credentials → OAuth client ID”, újabb felületen „Clients → Create client”):
   - Application type: **Web application**.
   - **Authorized redirect URIs**: pontosan az a cím, amelyen a felhasználók a szervert elérik, a `/login/google/callback` útvonallal:

     ```
     https://thinknodes.pelda.hu/login/google/callback
     ```

     Karakterre egyeznie kell: `https`, ugyanaz a gazdanév, a végén nincs `/`. Ha a szerver nem a 443-as porton fut, a port is része (`https://thinknodes.pelda.hu:8443/login/google/callback`). Ha több címen is elérhető a szerver, mindegyiket fel kell venni.
   - Az „Authorized JavaScript origins” mezőt hagyd üresen, nincs rá szükség.
4. A létrehozás után a Google megmutatja a **Client ID**-t (`…apps.googleusercontent.com` végű) és a **Client secret**-et. A titkot újabban csak létrehozáskor lehet teljes egészében kimásolni; ha elveszett, új titkot kell készíteni a kliens oldalán.

## 2. Telepítés a szerveren

A `daemon.sh` új verziója kell hozzá, mert az írja be a szolgáltatásba a beállítófájl beolvasását, és az hozza létre a fájlt. A szkript újrafuttatása biztonságos: a meglévő adatokhoz, fiókokhoz és a már kitöltött beállítófájlhoz nem nyúl.

```sh
cd /opt/ThinkNodes
sudo runuser -u thinknodes -- git pull     # előbb a friss daemon.sh kell a lemezre
sudo server/deploy/daemon.sh               # fordít, újraírja és újraindítja a szolgáltatást
```

Ha a `git pull` kimarad, a régi `daemon.sh` fut le: az ugyan letölti és lefordítja az új kódot, de a szolgáltatást még a régi módon írja meg. Ilyenkor elég a `daemon.sh`-t még egyszer lefuttatni.

A `daemon.sh` a végén kiírja a Google-bejelentkezés állapotát (`Google sign-in: off` vagy `on`).

Figyelem: a `daemon.sh` minden futáskor újraírja a `/etc/systemd/system/thinknodes.service` fájlt. Ha abban kézzel módosítottál valamit (pl. saját tanúsítvány: `--tls-cert:`, `--tls-key:`), azt a futtatás után újra be kell írni.

## 3. A kliensadatok megadása

A beállítófájl: `/var/lib/thinknodes/thinknodes.env`. A `daemon.sh` hozza létre, csak a `thinknodes` felhasználó (és a root) olvashatja.

```sh
sudo nano /var/lib/thinknodes/thinknodes.env
```

Vedd ki a `#` jelet a két sor elől, és írd be az értékeket:

```
THINKNODES_GOOGLE_CLIENT_ID=1234567890-abcdefg.apps.googleusercontent.com
THINKNODES_GOOGLE_CLIENT_SECRET=GOCSPX-…
```

Szabályok: soronként egy `NÉV=érték`, idézőjel és az `=` körüli szóköz nélkül. Mindkét érték kell; ha bármelyik hiányzik vagy üres, a Google-bejelentkezés kikapcsolva marad.

Utána:

```sh
sudo systemctl restart thinknodes
sudo journalctl -u thinknodes -n 30 --no-pager | grep -i google
```

Ha be van kapcsolva, a naplóban ez áll: `Google sign-in: enabled (callback path /login/google/callback)`.

Az újraindítás minden bejelentkezett felhasználót kiléptet (a munkamenetek a szerver memóriájában vannak), a nem mentett szerkesztések miatt érdemes csendes időpontban végezni.

### Ha a szerver proxy mögött van

A szerver a visszatérési címet abból a gazdanévből képezi, amelyet a böngésző kérése tartalmaz (`https://GAZDANÉV/login/google/callback`). Ha a felhasználók más címet látnak, mint a szerver (fordított proxy, porttovábbítás más portra), add meg kézzel a beállítófájlban, pontosan úgy, ahogy a Google-nál szerepel:

```
THINKNODES_GOOGLE_REDIRECT=https://thinknodes.pelda.hu/login/google/callback
```

## 4. Google-fiókok hozzárendelése a felhasználókhoz

1. Lépj be adminisztrátorként (jelszóval), és nyisd meg a Beállítások oldalt: `/admin`.
2. A „Felhasználók” résznél minden sorban megjelent a **Google-fiók** mező. Írd be a felhasználó Google-fiókjának e-mail-címét, majd „Mentés”.
3. Új felhasználónál („Új felhasználó”) a jelszó elhagyható, ha Google-fiókot adsz meg. Az ilyen fiókba csak Google-lal lehet belépni, amíg később jelszót nem kap.

Tudnivalók:

- Egy e-mail-cím csak egy felhasználóhoz tartozhat. A cím kis- és nagybetűi nem számítanak.
- A cím a Google-fiók elsődleges címe legyen (amit a Google a fiókválasztóban mutat), nem egy alias.
- A mező kiürítése és mentése leválasztja a Google-fiókot. Az ezzel a fiókkal bejelentkezett munkamenetek azonnal megszűnnek; a jelszavas belépés megmarad.
- A Google-fiók mező csak akkor látszik az adminoldalon, ha a Google-bejelentkezés be van kapcsolva.
- A hozzárendelés a projektadatok között, a `/var/lib/thinknodes/Projects/.settings.json` fájlban tárolódik (a felhasználó `google` mezője), így a mentésekkel együtt mozog.

## 5. Kipróbálás

1. Jelentkezz ki, nyisd meg a `/login` oldalt: a jelszavas űrlap alatt ott a „Belépés Google-fiókkal” gomb.
2. A gomb a Google fiókválasztójára visz. Válaszd azt a fiókot, amelyet az előbb hozzárendeltél.
3. A Google visszairányít, és be vagy lépve; ha egy védett oldalról indultál, oda jutsz vissza.

Érdemes egy nem hozzárendelt Google-fiókkal is megpróbálni: a belépőoldalon ezt kell látni: „A(z) … Google-fiókhoz nem tartozik ThinkNodes-fiók.”

## Hogyan működik

Szabványos OpenID Connect „authorization code” folyamat, PKCE-vel:

1. **Indítás** (`GET /login/google`): a szerver három véletlen értéket készít (state, nonce, PKCE-ellenőrző), eltárolja a böngésző munkamenetében, és átirányít a Google-hoz a kliensazonosítóval és a visszatérési címmel.
2. **Azonosítás a Google-nál**: a felhasználó a Google oldalán választ fiókot és adja meg a jelszavát. A ThinkNodes a Google-jelszót soha nem látja.
3. **Visszatérés** (`GET /login/google/callback`): a Google egy egyszer használható kóddal küldi vissza a böngészőt. A szerver ellenőrzi, hogy a state ugyanaz-e, amit ő adott ki ennek a böngészőnek (így más nem tud idegen belépést ráerőltetni a felhasználóra).
4. **Kódbeváltás**: a szerver közvetlenül, HTTPS-en a Google-hoz fordul (`oauth2.googleapis.com/token`), és a kódot a klienstitokkal és a PKCE-ellenőrzővel egy azonosító tokenre váltja. Ehhez a szervernek ki kell látnia az internetre.
5. **Ellenőrzés**: a tokenben a szerver megnézi, hogy a Google adta-e ki, ennek a kliensnek szól-e, nem járt-e le, a nonce egyezik-e, és hogy a Google igazoltnak jelzi-e az e-mail-címet.
6. **Fiók keresése**: ha a cím hozzá van rendelve egy felhasználóhoz, új munkamenet indul az ő nevében, ugyanolyan, mint jelszavas belépés után. Ha nincs, a belépés elutasítva.

A munkamenet a Google-tól függetlenül él tovább: ha a felhasználó kilép a Google-ból, a ThinkNodes-ban bent marad a szerver újraindításáig vagy a kijelentkezésig. A hozzáférés visszavonása ezért a ThinkNodes adminoldalán történik (Google-fiók leválasztása, szerepkör módosítása vagy a felhasználó törlése), ez azonnal hat.

## Hibakeresés

A szerver naplója: `sudo journalctl -u thinknodes -f`. A sikertelen Google-belépések `Google sign-in failed: …` sorral szerepelnek benne.

| Jelenség | Ok és teendő |
| --- | --- |
| Nincs „Belépés Google-fiókkal” gomb | A két változó valamelyike hiányzik, üres, vagy a sor elején ott maradt a `#`; a szolgáltatás nem lett újraindítva; vagy a régi `daemon.sh` telepítette a szolgáltatást (nincs benne `EnvironmentFile`). Ellenőrzés: `systemctl cat thinknodes \| grep EnvironmentFile`. |
| A Google oldalán: `Error 400: redirect_uri_mismatch` | A visszatérési cím nem egyezik karakterre a Google-nál felvettel. A hibaoldal részletei megmutatják, milyen címet küldött a szerver; azt kell felvenni, vagy a `THINKNODES_GOOGLE_REDIRECT` értékét javítani. A Google-nál a módosítás néhány perc alatt lép életbe. |
| A Google oldalán: `Error 401: invalid_client` | Hibás vagy elírt Client ID. |
| A Google oldalán: `Error 403: access_denied`, „az alkalmazás tesztelés alatt áll” | A hozzájárulási képernyő Testing állapotú, és a fiók nincs a tesztfelhasználók között. Vedd fel, vagy állítsd In production állapotra. |
| „A Google-bejelentkezés nem sikerült. Próbáld újra.” | A kódbeváltás vagy a token ellenőrzése hibázott; a pontos ok a naplóban van. `Google token endpoint: HTTP 401` = hibás Client secret; `HTTP 400` = a visszatérési cím vagy a kód nem stimmel; hálózati hiba = a szerver nem éri el a `oauth2.googleapis.com` címet (tűzfal, DNS); `expired` = a szerver órája rossz (`timedatectl`). |
| „A Google-bejelentkezés lejárt vagy megszakadt.” | A belépés indítása és a visszatérés között elveszett a munkamenet: közben újraindult a szerver, a böngésző tiltja a sütiket, vagy a felhasználó más címen indította a belépést, mint ahová a Google visszaküldte (pl. IP-címen nyitotta meg, a visszatérés domainnévre megy). Mindig a Google-nál felvett címen kell megnyitni a szervert. |
| „A(z) … Google-fiókhoz nem tartozik ThinkNodes-fiók.” | A cím nincs hozzárendelve senkihez az adminoldalon, vagy elírás van benne. |

## Biztonság

- A klienstitok csak a `thinknodes.env` fájlban legyen (jogosultság `0600`, tulajdonos `thinknodes`). Ne kerüljön a gitbe, a projektadatok közé vagy mentésbe olvasható formában. Ha kiszivárog, a Google-nál készíts új titkot, és töröld a régit.
- A titok önmagában nem ad hozzáférést a ThinkNodes-adatokhoz: belépni csak hozzárendelt Google-fiókkal lehet, a Google saját azonosítása után.
- Aki hozzáfér egy hozzárendelt Google-fiókhoz, be tud lépni a hozzá tartozó ThinkNodes-fiókba. Adminisztrátori fiókhoz csak kétlépcsős azonosítással védett Google-fiókot érdemes rendelni.
- Kikapcsolás: tedd vissza a `#` jelet a két sor elé, és indítsd újra a szolgáltatást. A hozzárendelt címek megmaradnak, a Google-lal belépett munkamenetek az újraindítással megszűnnek.
