# Projektmigráció: ZIP-export és -import

Tervezési leírás. Itt rögzítjük a döntéseket, mielőtt a kód elkészül.

## Cél

- Projekt, laprészfa vagy egyetlen lap letöltése ZIP-ben, és feltöltése egy másik (vagy ugyanarra a) szerverre.
- Fő felhasználás: a helyi szerverről élesre, illetve két különböző szerver között.
- Felhasználói fiók **soha** nem kerül a csomagba. Teljes szervermentés (fiókokkal) nem része ennek a tervnek.
- Importálás mindig **új példányt** hoz létre; meglévő projekt felülírása / frissítése későbbi feladat.

## Csomagformátum

### Nyitott ZIP (nincs manifest)

A csomag maga a mappa, ahogy a szerveren van. Két forma elfogadott:

```
X/X.thnode          ← gyökérlap (a legfelső mappa és a vele azonos nevű .thnode)
X/.settings.json
X/<médiafájlok>, X/<név>.web/…
X/<allap>/<allap>.thnode, …
```

vagy ugyanez mappa nélkül (`X.thnode` a ZIP gyökerében). Így a kézzel becsomagolt projektmappa is importálható
(pl. Finder „Tömörítés”, vagy `zip -r` a szerver adatmappájában lévő `X` mappáról).

- A gyökérlap felismerése: pontosan egy legfelső mappa, benne a vele azonos nevű `.thnode`; vagy pontosan egy `.thnode` a ZIP gyökerében.
- Sémaverzió: laponként a `.thnode` `schemaVersion` mezője. Külön csomagverzió nincs.
- Épség: a ZIP fájlonkénti CRC-je elég.

### Titkosított csomag

```
thinknodes-encrypted.json   ← nyitott fejléc
content.bin                 ← titkosítva: pontosan a fenti nyitott ZIP
```

- Fejléc: csomagformátum-verzió, kulcsszármaztatás (memóriaigényes, lassú KDF, pl. scrypt) paraméterei és sója, titkosító eljárás (AES-256-GCM, nagy fájlnál darabolva).
- Csak ThinkNodes nyitja ki; cserébe a jelszó offline nehezen próbálgatható, és a formátumverzió jelszó nélkül is ellenőrizhető.

## Mi kerül a csomagba

| Benne van | Nincs benne |
|---|---|
| `.thnode` lapok (a teljes részfa) | Felhasználói fiókok, `.settings.json` (az adatmappa gyökerében) (hashek, `preferences`) |
| Lapmappák médiafájljai, dokumentumai | **Bármilyen jelszó-hash** (a `.settings.json`-ból törölve) |
| `.settings.json` mappánként: `mediaFiles`, `archivedFiles`, `publicFiles`, `hidden`, `frozen`, `guestReadable`, `owner`, `editors`, lapbeállítások (`worksheets`) | Előnézeti gyorsítótár: `.*.preview-v*.svg`, `.*.tn-preview.webp` |
| `.web` mappák a saját `.settings.json`-jukkal | `.trash`, `.tn-upload-*`, `.link-previews`, `.DS_Store`, `__MACOSX` |
| `.version` (mentett állapotok) – **csak ha kérik**, alapból nem | `@common` fájlok (a szerverhez tartoznak) |

## Exportálás

**Ki:** szerkesztő (a projekt tagja) vagy admin. Csak az kerül bele, amit az exportáló olvasni tud (jelszavas projektnél feloldva).

**Honnan:** a főoldal projektkártyájának menüjéből és a szerkesztő export menüjéből.

**Mit:**
1. teljes projekt;
2. egy lap az összes allapjával;
3. egy lap egyedül (a saját fájljaival, allapok nélkül).

**Beállítások az export párbeszédben:**
- *Mentett állapotok (`.version`)* – jelölőnégyzet, alapból ki.
- *Csomagon kívüli fájlok* – „bemásolás a hivatkozó lap mappájába” vagy „hivatkozás marad, figyelmeztetés”.
- *Titkosítás* – lásd lent.

### Jelszó és titkosítás

Jelszót csak a projekt kaphat; az allapok és a `.web` prezentációk a projekt jelszavát öröklik.

- **Jelszavas projekt (vagy annak allapja):** a titkosítás kötelező, külön **csomagjelszóval**.
  - Legalább 12 karakter.
  - Nem egyezhet a projekt jelszavával (a szerver a projekt hash-ével ellenőrzi).
  - Ha a csomagot feltörik, a tartalom kiszivárog, de a szerveren lévő projekt jelszava nem.
- **Nem jelszavas projekt:** a titkosítás választható, alapból nincs (nyitott ZIP).

## Importálás

**Ki:** szerkesztő vagy admin. Projekten belül szerkesztési jog kell az aktuális laphoz.

**Hova:**
- **Főoldal → új projekt.** Foglalt név esetén `-2`, `-3` … utótag (vagy átnevezés a párbeszédben).
  Felajánljuk új projektjelszó megadását (nem kötelező; a csomagból nem jön jelszó).
- **Projekten belül → az aktuális lap alá allapként.** A vásznon létrejön hozzá egy laplinkes doboz a látható terület
  közepén, kijelölve. Az allap a befogadó projekt jelszavát örökli; a projektszintű `guestReadable`, `owner`, `editors` nem érvényes.

A mostani egylapos `.thnode` import megmarad.

### Menete (két lépés)

1. **Feltöltés és elemzés.** A szerver rejtett ideiglenes mappába bontja (titkosítottnál előbb a csomagjelszót kéri),
   ellenőriz, és jelentést ad: gyökérnév, lapok száma, sémaproblémák, párosítandó szerkesztők, nem található hivatkozások.
2. **Jóváhagyás.** A felhasználó beállítja a párosítást / nevet / jelszót, a szerver egy lépésben a helyére mozgatja.
   Az ideiglenes mappa lejár és törlődik, ha nem hagyják jóvá.

### Felhasználók

- **Tulajdonos (`owner`):** az importáló.
- **Létrehozó (`creator`)** minden lapon: az importáló.
- **Szerkesztők (`editors`):** párosító ablak. Azonos nevű, szerkesztő szerepkörű felhasználó előre kiválasztva, de jóvá kell hagyni;
  másik felhasználóhoz rendelhető vagy kihagyható. A nem párosítottak kimaradnak.

### Hivatkozások

- **Relatív laplink** (`sublap`, `../x`): változatlan.
- **Abszolút laplink** (`/Projekt/…`) a csomagon belülre: az új helyre átírva.
- **Csomagon kívülre mutató laplink:** megmarad, és a jelentésben szerepel („Nem található hivatkozások”).
- **`CanvasFile.source`** a csomagon belülre: az új útvonalra átírva; kívülre: az export beállítása szerint bemásolva vagy figyelmeztetés.
- **`@common`:** változatlan; ha a célszerveren nincs meg a fájl, figyelmeztetés.

### Verziók

- Régebbi sémájú lap: a `Worksheet.decodeFile` alakítja át lépésenként a jelenlegire (most: 2 → 3).
- Újabb sémájú lap: az egész import elutasítva: „A csomag újabb ThinkNodes-verzióval készült (N. séma), frissítsd a szervert.”
- Titkosított csomag ismeretlen fejlécverzióval: ugyanígy elutasítva, még a jelszó bekérése előtt.
- `.version` fájlok: ugyanezen az átalakításon mennek át; a hibás állapot kimarad (figyelmeztetéssel), a lapot nem állítja meg.
- Minden lap `revision` értéke 1-ről indul, `resetRevision` törölve.
- `.settings.json`: ha a formátuma egyszer változik, a beolvasónak a régi formát is ismernie kell.

### Biztonság

- Csak ideiglenes mappán keresztül; a végleges hely egy lépésben jön létre (mint a `.web` ZIP feltöltésnél).
- Elutasítva: `..` és abszolút útvonal (zip-slip), szimbolikus link, érvénytelen név (`WorksheetPath` szabályai, NFC), foglalt nevek.
- Korlát: tömörített és kibontott méret, fájlszám (lásd TODO.md: mérethatár, streamelés).
- Minden `.thnode` átmegy a `validate()`-en; a `.settings.json` dekódolása szigorú, a hash-mezők eldobva.
- A kibontás és a titkosítás a tároló zárján kívül fut.

## Későbbre

- Meglévő projekt felülírása / frissítése (a projektazonosító a gyökér `.settings.json`-ba kerül).
- Nagy csomagok: streamelt fel- és letöltés, folyamatjelző (TODO.md).
- Teljes szervermentés fiókokkal (csak admin).

## Megvalósítás (2026-11-23)

- **Kód:** `Sources/ThinkNodes/ProjectPackage.swift` (ZIP-író, titkosítás, export, import), `Public/package.js` (párbeszédek).
- **ZIP-író:** saját, tömörítés nélküli (stored) bejegyzések, UTF-8 nevek, „Unix” rendszerjelöléssel. MS-DOS jelöléssel
  az `unzip` kódlap-átalakítást végezne, és az ékezetes nevek elromlanának. Kicsomagolás: rendszer `unzip`, a `.web`
  feltöltéssel közös ellenőrzésekkel (`WebArchive.extractSafely`).
- **Titkosítás:** swift-crypto (`_CryptoExtras`): scrypt (N = 2^15, r = 8, p = 1, 16 bájtos só) → AES-256-GCM, 1 MiB-os
  darabok; nonce = 4 véletlen bájt + 8 bájtos sorszám; az utolsó darabot a hitelesített adat jelöli.
- **Végpontok:**
  - `POST /api/package/export/<lap>` – JSON: `scope` (`tree`|`sheet`), `versions`, `external` (`keep`|`copy`), `password`.
  - `POST /api/package/upload` (új projekt) / `POST /api/package/upload/<lap>` (allap) – a ZIP a törzsben; jelentést ad.
  - `POST /api/package/unlock` – `{token, password}` titkosított csomaghoz.
  - `POST /api/package/commit` – `{token, name, editors, projectPassword}`; `POST /api/package/cancel` – `{token}`.
- **Ideiglenes mappa:** `<adatkönyvtár>/.package-staging`, egy óra után és szerverindításkor törlődik.
- **Felület:** főoldal „Projekt importálása (.zip)”; projekt- és lapkártya menü „Letöltés (.zip)”; megtekintő „ZIP”;
  szerkesztő vászonpanel „Projektcsomag” (Letöltés, Importálás allapként + laplinkes doboz a látható terület közepén).
- **Korlát:** feltöltés 200 MiB, kibontva 1 GiB, 20 000 fájl (TODO.md: mérethatár, streamelés).
- **„web” nevű mappa:** .web prezentációra hivatkozó lap útvonalában nem lehet `web` nevű mappa (a prezentációk címében
  foglalt). Ilyen néven az import hibát ad, a javasolt név `web-lap`.
