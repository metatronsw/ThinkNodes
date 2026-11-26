# Változások

## 2026-11-26 – Olvasható szövegszín a dobozon, nagyobb CSV-nézet, régi gyorsítótár-fájlok törölve

- **Szövegszín:** ha a doboz szövegének kontrasztja a felülettel 3 alatt van (WCAG-arány), kirajzoláskor a téma tintájának jobban olvasható (nappali vagy esti) változatát kapja. A felület a kitöltés a vászon fölött, a téma átlátszatlanságával (Liquid Glass 64 / 40 %, üveg 66 %, áttetsző 75 %, szabadkézi téma halvány tónusa); a tárolt szövegszín nem változik. Szerver: `Rendering.swift labelInk` (`Idea.labelInk`, nem tárolt mező; `Worksheet.painted` tölti), szerkesztő: `editor.js boxInk`; csak a sima doboz szövegére (kitöltött, áttetsző és vászonszínű háttérnél). Teszt: `unreadableBoxTextGetsThemeInk`.
- **CSV olvasó nézet:** legfeljebb 1000 sor × 60 oszlop (eddig 200 × 30), a szerveren és a szerkesztőben egyformán (`csvPreviewRows`, `csvPreviewColumns`).
- **Takarítás (engedéllyel):** a 12 régi `.preview-v12*.svg` és az üres `projects/a/.chat.jsonl` törölve.
- Ellenőrzés: minden Swift- és JS-teszt átmegy; release build (`deploy/build.sh --no-pull`), a szerkesztő és a megtekintő szövegszíne fej nélküli Chromiumban egyezik (világos és sötét mód); a helyi `a` lap CSV-je 417 sort mutat. Verzió: `editor.js?v=102`; a helyi tesztszerver (8888) az új builddel fut.

## 2026-11-26 – BUGS.md átnézése: előnézet átnevezéskor, gyors eszközök lenyíló listája és Szerkesztés gombja

- **Lap átnevezése:** az előnézet gyorsítótára (`.<lap>.preview[-dark].svg` / `.webp`) az új névvel megy tovább, a régi nevű nem marad a mappában; a módosítás ideje megmarad, így érvényes marad (`Model.swift moveDocument`). Teszt: `uploadedWorksheetsUseTheirOwnFolder`.
- **Gyors eszközök, lenyíló lista:** a listán kívüli kattintás és az Esc bezárja (az Esc ilyenkor csak a listát zárja, a gyors eszközöket nem).
- **Gyors eszközök, Szerkesztés:** új `properties` gomb (tulajdonságpanel ikon) dobozon, csomóponton és vonalon, a Törlés előtt; megnyitja és ki is nyitja a tulajdonságpanelt (`quick-tools.json`, `editor.js renderQuickTools`).
- Döntések: csökkentett mozgásnál a ping animációja marad; az új doboz nem kap automatikusan eltérő színt (ötlet a TODO.md-ben).
- Ellenőrzés: minden érintett Swift- és JS-teszt átmegy; a gyors eszközök fej nélküli Chromiumban kipróbálva (Safariban a távoli automatizálás ki volt kapcsolva). Verzió: `editor.js?v=101`. Helyesbítés: a szerver a release binárist futtatja, ez akkor nem készült újra, így az átnevezés javítása csak a következő buildben (lásd fent) került a futó szerverre.
