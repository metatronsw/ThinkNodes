
# project migráció

+ Kész (docs/migration.md „Megvalósítás”): ZIP-export (projekt / részfa / lap, .version, külső fájlok, titkosítás), import főoldalon és allapként.
+ Hátra: ThinkNodes-csomag ZIP behúzása a vászonra (most .web-ként próbálja, különben mellékletként tölti fel) → ismerje fel és ajánlja fel az importot.

+ Projektcsomag mérethatára: most a .web ZIP max. 100 MiB, a .thnode max. 12 MiB, a teljes projekt (képek, .web, .version) ennél jóval nagyobb lehet. Dönteni kell a felső határról (és a kibontott méret/fájlszám korlátjáról); ha több száz MB vagy GB is előfordulhat, streamelt feltöltés és letöltés kell (nem `body.collect` memóriába), plusz folyamatjelző a kliensen.






# FILE KEZELÉS

+ Nagy szövegfájl szerkesztése külső szerkesztőben (docs/node-types.md, text típus). A mérethatárt is meg kell adni.
+ .thnode import: most új almunkalapot hoz létre, de nem keletkezik doboz a vásznon. Az új típusrendszerben (docs/node-types.md) a `sheet` típushoz kell kötni.

Közös fájlok / .web / lomtár – hátralévő (2026-11-23):
+ Kipróbálni két szerkesztővel: törlés („lomtárba, a többi doboz törlődik / üres lesz”) és .web átnevezés, miközben a másik lapot valaki szerkeszti (kijelölt dobozt kihagy, és szól).
+ A pillangó ikon (`webPublic`) csak az aktuális lap dobozain frissül; a többi lapon ugyanarra a fájlra / .web-re mutató doboz régi állapotot mutathat. Megoldás: a szerver adja a publikus állapotot megjelenítéskor, ne a doboz tükrözze.
+ Fájl átnevezése után a többi lapon a dobozon a régi fájlnév látszik (a hivatkozás működik).
+ Másik lapról másolt-beillesztett fájldoboz most új példányt tölt fel; közös hivatkozás legyen helyette (editor.js, beillesztés `sourcePath !== path` ága).
+ Visszavonás (undo) fájldoboz eltávolításakor nem nézi a többi lap használatát; a lomtárba tett (release) fájl undo-val nem jön vissza.
+ Közös könyvtárbeli szövegfájl tartalma a megtekintő oldalon nem jelenik meg (csak a szerkesztőben).
+ A törölt projektek a gyökér `.trash` mappájába kerülnek; ezek kezelése (lista, visszaállítás, ürítés) nincs meg.
+ `common` nevű projektet tiltani kell (a /common/ címet a közös könyvtár foglalja).
+ JS teszt hiba: Tests/Editor/gestures.mjs `ownUnderlay` (a 7e6f36e kijelölés-átírás óta).





# Google-bejelentkezés

+ Kész: belépés Google-fiókkal az admin által hozzárendelt e-mail-cím alapján (README „Google-bejelentkezés”).
+ Hátra: kipróbálás valódi Google OAuth-klienssel (Cloud Console: kliens létrehozása, visszatérési cím felvétele), helyben `http://localhost:8888`-on és élesben.
+ Kész: hozzáférés-kérés admin jóváhagyással, jelvény a fejléc Admin gombján (AdminMessages), README és server/deploy/GOOGLE.md.
+ Hátra: a kérelmező értesítése a döntésről (most nincs; a szerver nem küld e-mailt).
+ Lehetőség: további adminisztrátori jelzések (AdminMessage.Kind), pl. lemezhely, hibás mentés.
+ Lehetőség: a felhasználó maga kösse össze / válassza le a Google-fiókját (most csak az admin teheti); a Google `sub` azonosítójának rögzítése az e-mail-cím mellé.
