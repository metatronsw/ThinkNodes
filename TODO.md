
# project migráció

+ Kész (docs/migration.md „Megvalósítás”): ZIP-export (projekt / részfa / lap, .version, külső fájlok, titkosítás), import főoldalon és allapként.
+ Kész (2026-11-24): a vászonra húzott ThinkNodes-csomag ZIP-et a szerkesztő felismeri, és felajánlja az importot allapként.

+ Kész (2026-11-25): csomag-mérethatár 4 GiB (kibontva 8 GiB, 20 000 fájl); darabolt, megszakadás után folytatható feltöltés folyamatjelzővel; a letöltést a böngésző közvetlenül lemezre végzi.
+ Hátra: a darabolt feltöltés kipróbálása valódi, több GB-os csomaggal és megszakított hálózattal (eddig tesztek és kis csomag); a `.web` ZIP (100 MiB) és a `.thnode` (12 MiB) feltöltése továbbra is egyben megy.






# FILE KEZELÉS

+ Kész (2026-11-25): 256 KB fölötti szövegfájl külön ablakban szerkeszthető (`/edit/<lap>?text=<doboz>`, `text-editor.js`). Hátra: a nagy fájl a vászonhoz is egészben töltődik le (elég lenne az eleje); a külön ablak kinézete szemmel nézendő.

Közös fájlok / .web / lomtár – hátralévő (2026-11-23):
+ Kipróbálni két szerkesztővel: törlés („lomtárba, a többi doboz törlődik / üres lesz”) és .web átnevezés, miközben a másik lapot valaki szerkeszti (kijelölt dobozt kihagy, és szól).
+ Visszavonás lomtárba tétel után: a fájl visszaáll (2026-11-24), de a többi lapon a törölt / üres dobozzá alakított dobozok nem állnak vissza. Ehhez a lomtárba tételkor fel kellene jegyezni a többi lap érintett dobozait.
+ A pillangó ikon és az átnevezett fájlnév a többi lapon a következő betöltéskor frissül (a szerver olvasáskor adja); nyitott szerkesztőben azonnali frissítéshez értesítés kellene a többi lapnak.
+ Törölt projekt visszaállítása más néven (most csak az eredeti néven, ha szabad).





# Google-bejelentkezés

+ Kész: belépés Google-fiókkal az admin által hozzárendelt e-mail-cím alapján (README „Google-bejelentkezés”).
+ Hátra: kipróbálás valódi Google OAuth-klienssel (Cloud Console: kliens létrehozása, visszatérési cím felvétele), helyben `http://localhost:8888`-on és élesben.
+ Kész: hozzáférés-kérés admin jóváhagyással, jelvény a fejléc Admin gombján (AdminMessages), README és server/deploy/GOOGLE.md.
+ Döntés (2026-11-25): a kérelmező nem kap levelet a döntésről; visszatéréskor látja az állapotot.
+ Lehetőség: további adminisztrátori jelzések (AdminMessage.Kind), pl. lemezhely, hibás mentés.
+ Lehetőség: a felhasználó maga kösse össze / válassza le a Google-fiókját (most csak az admin teheti); a Google `sub` azonosítójának rögzítése az e-mail-cím mellé.

# Teljesítmény (server/docs/PERF.md „Betöltés és szerver – 2026-11-25”)

+ Szerver: HTTP/2 élesben, előre tömörített statikus fájlok, megtekintő oldal gyorsítótára, `usageLocked` és `reconcile` ritkítása.
+ Kliens: `modulepreload`, `commonmark.js` halasztott betöltése. (A szűkített d3-csomag kész: 2026-11-25.)
+ Mérés: a táblázatszerkesztő görgetése az új fejlécsávokkal (Safari, `perf.py --only table`); a `perf.py` `tabla` lapos futása javítandó (a keresett `n00005` doboz nincs meg).

# Grafikon (Public/chart.js)
- Safari-ellenőrzés: a grafikon követi-e a táblázat szerkesztését gépelés közben és a másik résztvevőnél; helyi menü „Grafikon készítése”; `.tntable` forrás; világos téma.
- SVG-exportban és az előnézeti képen a grafikon doboza táblázatként jelenik meg (a rajz a böngészőben készül). Megoldás lehet: a szerkesztő mentéskor a kész SVG-t is eltárolja.
- További lehetőségek: halmozott oszlop, vízszintes sáv, területdiagram, tengelycím, saját színek, sorok helyett oszlopok mint sorozatok, dátumtengely.
- A grafikon buboréksúgója a böngésző saját `<title>` súgója; a szerkesztő közös buboréksúgójára (tooltip.js) érdemes átállni.
- A helyi próbalap (`projects/a/grafikon`) törölhető, ha már nem kell.
