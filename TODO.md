
# project migráció

+ Kész (docs/migration.md „Megvalósítás”): ZIP-export (projekt / részfa / lap, .version, külső fájlok, titkosítás), import főoldalon és allapként.
+ Kész (2026-11-24): a vászonra húzott ThinkNodes-csomag ZIP-et a szerkesztő felismeri, és felajánlja az importot allapként.

+ Projektcsomag mérethatára: most a .web ZIP max. 100 MiB, a .thnode max. 12 MiB, a teljes projekt (képek, .web, .version) ennél jóval nagyobb lehet. Dönteni kell a felső határról (és a kibontott méret/fájlszám korlátjáról); ha több száz MB vagy GB is előfordulhat, streamelt feltöltés és letöltés kell (nem `body.collect` memóriába), plusz folyamatjelző a kliensen.






# FILE KEZELÉS

+ Nagy szövegfájl szerkesztése külső szerkesztőben (docs/node-types.md, text típus). A mérethatárt is meg kell adni.

Közös fájlok / .web / lomtár – hátralévő (2026-11-23):
+ Kipróbálni két szerkesztővel: törlés („lomtárba, a többi doboz törlődik / üres lesz”) és .web átnevezés, miközben a másik lapot valaki szerkeszti (kijelölt dobozt kihagy, és szól).
+ Visszavonás lomtárba tétel után: a fájl visszaáll (2026-11-24), de a többi lapon a törölt / üres dobozzá alakított dobozok nem állnak vissza. Ehhez a lomtárba tételkor fel kellene jegyezni a többi lap érintett dobozait.
+ A pillangó ikon és az átnevezett fájlnév a többi lapon a következő betöltéskor frissül (a szerver olvasáskor adja); nyitott szerkesztőben azonnali frissítéshez értesítés kellene a többi lapnak.
+ Másik projektből beillesztett fájldoboz továbbra is új példányt tölt fel (projektek között nincs közös hivatkozás).
+ Törölt projekt visszaállítása más néven (most csak az eredeti néven, ha szabad).





# Google-bejelentkezés

+ Kész: belépés Google-fiókkal az admin által hozzárendelt e-mail-cím alapján (README „Google-bejelentkezés”).
+ Hátra: kipróbálás valódi Google OAuth-klienssel (Cloud Console: kliens létrehozása, visszatérési cím felvétele), helyben `http://localhost:8888`-on és élesben.
+ Kész: hozzáférés-kérés admin jóváhagyással, jelvény a fejléc Admin gombján (AdminMessages), README és server/deploy/GOOGLE.md.
+ Hátra: a kérelmező értesítése a döntésről (most nincs; a szerver nem küld e-mailt).
+ Lehetőség: további adminisztrátori jelzések (AdminMessage.Kind), pl. lemezhely, hibás mentés.
+ Lehetőség: a felhasználó maga kösse össze / válassza le a Google-fiókját (most csak az admin teheti); a Google `sub` azonosítójának rögzítése az e-mail-cím mellé.

# Teljesítmény (server/docs/PERF.md „Betöltés és szerver – 2026-11-25”)

+ Szerver: HTTP/2 élesben, előre tömörített statikus fájlok, megtekintő oldal gyorsítótára, `usageLocked` és `reconcile` ritkítása.
+ Kliens: szűkített d3-csomag (külső letöltés), `modulepreload`, `commonmark.js` halasztott betöltése.
+ Mérés: a táblázatszerkesztő görgetése az új fejlécsávokkal (Safari, `perf.py --only table`); a `perf.py` `tabla` lapos futása javítandó (a keresett `n00005` doboz nincs meg).
