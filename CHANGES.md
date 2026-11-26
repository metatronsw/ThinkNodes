# Változások

## 2026-11-26 – BUGS.md átnézése: előnézet átnevezéskor, gyors eszközök lenyíló listája és Szerkesztés gombja

- **Lap átnevezése:** az előnézet gyorsítótára (`.<lap>.preview[-dark].svg` / `.webp`) az új névvel megy tovább, a régi nevű nem marad a mappában; a módosítás ideje megmarad, így érvényes marad (`Model.swift moveDocument`). Teszt: `uploadedWorksheetsUseTheirOwnFolder`.
- **Gyors eszközök, lenyíló lista:** a listán kívüli kattintás és az Esc bezárja (az Esc ilyenkor csak a listát zárja, a gyors eszközöket nem).
- **Gyors eszközök, Szerkesztés:** új `properties` gomb (tulajdonságpanel ikon) dobozon, csomóponton és vonalon, a Törlés előtt; megnyitja és ki is nyitja a tulajdonságpanelt (`quick-tools.json`, `editor.js renderQuickTools`).
- Döntések: csökkentett mozgásnál a ping animációja marad; az új doboz nem kap automatikusan eltérő színt (ötlet a TODO.md-ben).
- Ellenőrzés: minden érintett Swift- és JS-teszt átmegy; a gyors eszközök fej nélküli Chromiumban kipróbálva (Safariban a távoli automatizálás ki volt kapcsolva). Verzió: `editor.js?v=101`; a helyi tesztszerver (8888) az új kóddal fut.
