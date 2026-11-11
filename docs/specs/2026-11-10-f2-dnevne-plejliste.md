# F2: Dnevne plejliste (specifikacija)

Status: dizajn odobren 2026-11-10, specifikacija čeka pregled.
Osnova: `docs/HANDOFF-Lyrion-MaterialSkin.md`, F1 specifikacija, `docs/research/2026-11-10-provera-sekcija-6.md`.

## 1. Cilj
Svakog dana postoje nove plejliste po kategorijama koje definiše korisnik. Pravi ih noću jeftin AI model, bez istorije slušanja. Miksovi se slušaju iz nove stavke **Your Daily Mixes** na Home stranici Material-a.

Uspeh znači:
- Svaka kategorija ujutru ima novi miks od pesama koje stvarno postoje na nekom izvoru.
- Svaka pesma pokazuje sa kog izvora dolazi.
- Neuspeh noćnog posla ne ostavlja praznu listu.
- Dobar miks može da se sačuva za stalno kao LMS plejlista.

## 2. Van obima
- Istorija slušanja kao ulaz modelu.
- Provajderi osim Anthropic i OpenAI.
- Stranica podešavanja u izgledu Material-a.
- Ikonica izvora u redu reprodukcije desno.
- Rešavanje kvara Qobuz plugina za hi-res pesme.

## 3. Ponašanje
### 3.1 Navigacija
```text
Your Daily Mixes
└── <kategorija> (Add · Next · Play)   današnji miks, ili poslednji uspešan
    ├── pesme miksa (Add · Next · Play)
    └── Previous days
        └── YYYY-MM-DD (Add · Next · Play)
            └── pesme tog dana (Add · Next · Play)
```
- Stavka je na Home odmah ispod `Extras`.
- Dugmad su **Append to queue**, **Play next** i **Play now**, sa istim značenjem kao u Material-u.
- Klik na red otvara sledeći nivo.
- Ako kategorija nema današnji miks, prikazuje se poslednji uspešan, sa datumom u podnaslovu.
- Svaka pesma ima emblem izvora.

### 3.2 Čuvanje
Meni reda kategorije i reda dana ima:
- **Save as playlist**, sa predloženim imenom `<kategorija> YYYY-MM-DD`.
- **Add to playlist**, sa izborom postojeće LMS plejliste.

Plejlista se puni URL-ovima iz sačuvanog miksa, uključujući `qobuz://` i `tidal://`.

### 3.3 Izbor pesama
- Model dobija zahtev za 3 puta više predloga od broja pesama.
- Predlog se traži F1 pretragom. Prihvata se samo pesma čiji se `track_key` poklapa sa predlogom.
- Bira se prvi izvor po redosledu iz sekcije 3.4 koji je ima.
- Traženje staje kad se skupi broj pesama. Ako ih je manje, čuva se kraća lista.
- Ponavljanje iz dana u dan je dozvoljeno.

### 3.4 Primarni izvor
Jedan parametar za F1 i F2. Primarni izvor ide prvi, a ostali zadržavaju redosled `local, qobuz, tidal`.

| Primarni izvor | Redosled |
|---|---|
| `local` (podrazumevano) | local, qobuz, tidal |
| `qobuz` | qobuz, local, tidal |
| `tidal` | tidal, local, qobuz |

Ovaj parametar zamenjuje `sourceOrder` iz F1. Postojeća vrednost se pri migraciji pretvara: prvi izvor postaje primarni.

### 3.5 Raznovrsnost
Modeli se pozivaju bez `temperature`, jer ga `claude-haiku-5-5` odbija. Kod za svaku kategoriju i dan nasumično bira naglasak i šalje ga u promptu:
- jedan od žanrova kategorije,
- deceniju,
- odnos poznatih i manje poznatih pesama.

## 4. Podešavanja
Stranica u Lyrion podešavanjima plugina, sa prečicom u `Extras`. Sve se čuva na serveru.

| Podešavanje | Pravila |
|---|---|
| Primarni izvor | Padajuća lista: local, qobuz, tidal |
| Kategorije | Redovi sa nazivom i listom žanrova; dodavanje i brisanje. Naziv je jedinstven i nije prazan, a lista žanrova nije prazna. |
| Broj pesama po kategoriji | Ceo broj 5–100, podrazumevano 30 |
| Model | Padajuća lista: `claude-haiku-5-5`, `gpt-6-luna` |
| Anthropic ključ, OpenAI ključ | Polja koja ne prikazuju sačuvanu vrednost |
| Vreme pokretanja | HH:MM, podrazumevano 04:00 |
| Vremenska zona | Naziv zone, podrazumevano `Europe/Belgrade` |
| Pokreni sada | Dugme koje odmah pokreće posao i prikazuje ishod |

**Validacija:** model bez unetog ključa svog provajdera označen je kao nedostupan. Podešavanja se ne čuvaju ako izabrani model nema ključ, uz poruku korisniku.

## 5. Arhitektura
Proširenje plugina `UnifiedMusic`:

| Modul | Zadatak | Zavisi od Lyrion-a |
|---|---|---|
| `Mix/Config.pm` | Čitanje i validacija podešavanja | ne (prefs se ubacuju) |
| `Mix/Prompt.pm` | Zahtev i dnevni naglasak; generator slučajnih brojeva se ubacuje | ne |
| `AI/Anthropic.pm`, `AI/OpenAI.pm` | Izgradnja zahteva i čitanje odgovora | ne (HTTP se ubacuje) |
| `Mix/Resolver.pm` | Predlog u pesmu, jedan po jedan | ne (pretraga se ubacuje) |
| `Mix/Store.pm` | JSON fajlovi i brisanje starih | ne (folder se ubacuje) |
| `Mix/Scheduler.pm` | Tajmer, nadoknada, zaključavanje, ponovni pokušaji | ne (vreme i tajmer se ubacuju) |
| `Plugin.pm` | CLI komande i veza sa Lyrion-om | da |
| `Settings.pm` i stranica | Podešavanja iz sekcije 4 | da |

Oba adaptera imaju isti interfejs:
`suggest({model, api_key, prompt, count}, $done)`, gde `$done` dobija `{suggestions => [{artist, title}]}` ili `{error => tekst}`, tačno jednom.

Adapteri koriste izvorne API-je: Anthropic `POST /v1/messages`, OpenAI njegov aktuelni API sa JSON šemom. Tačna polja i verzije zaglavlja potvrđuju se iz zvanične dokumentacije pre pisanja adaptera. OpenAI-kompatibilni sloj Anthropic-a se ne koristi. Izlaz je strukturiran po JSON šemi, a izlazni tokeni su ograničeni na 16.000 po pozivu.

Skladište: folder `unifiedmusic/mixes/YYYY-MM-DD/<slug-kategorije>.json` u Lyrion prefs folderu, sa poljima:
```json
{ "category": "Jazz", "date": "2026-11-11", "model": "claude-haiku-5-5",
  "tracks": [{ "title": "So What", "artist": "Miles Davis", "album": "Kind Of Blue",
               "source": "qobuz", "url": "qobuz://13176083.flac", "image": "..." }] }
```
Fajlovi stariji od 7 dana se brišu posle svakog posla.

**Fork menja samo:** stavku na Home, prikaz listi preko postojećih tipova, tri dugmeta, stavke menija iz 3.2.

**Emblem za lokalni izvor (F1 i F2):** ikonica foldera, dodata u `emblems.json`. U F1 zamenjuje tekst „Local“ u redu grupe i na listi verzija.

## 6. CLI
```json
["unifiedmusic", "mixes", "items"]
["unifiedmusic", "mix", "items", "category:<naziv>", "date:<YYYY-MM-DD>"]
["unifiedmusic", "mix", "play", "cmd:play|add|insert", "category:<naziv>", "date:<YYYY-MM-DD>"]
["unifiedmusic", "mix", "save", "category:<naziv>", "date:<YYYY-MM-DD>", "name:<naziv>"]
["unifiedmusic", "mix", "append", "category:<naziv>", "date:<YYYY-MM-DD>", "playlist_id:<id>"]
["unifiedmusic", "mix", "run"]
```
`date` je opciono; bez njega važi današnji ili poslednji uspešan miks. Puštanje jedne pesme koristi postojeće `playlist play|add|insert <url>`.

## 7. Noćni posao
1. U zadato vreme pokreće se posao. Server radi u UTC, pa se vreme računa u vremenskoj zoni iz podešavanja.
2. Kategorije se obrađuju jedna po jedna, a predlozi jedan po jedan.
3. Pri startu servera, ako današnji posao nije urađen a zakazano vreme je prošlo, posao se pokreće jednom.
4. Istovremeno može da traje samo jedan posao.

## 8. Greške
| Situacija | Ponašanje |
|---|---|
| API greška, odbijen ključ, odbijen zahtev modela | Kategorija se preskače, ostaje poslednji miks, zapis u log. |
| Neispravan JSON ili prekid zbog `max_tokens` | Jedan ponovljen poziv, zatim preskakanje. |
| Manje pesama od traženog | Čuva se kraća lista. |
| Nijedna pesma | Ne upisuje se prazan miks. |
| Nijedan plejer nije povezan | Ponovni pokušaj na sat vremena, najviše 6 puta. |
| Server ugašen u zakazano vreme | Nadoknada pri startu, jednom dnevno. |
| Posao već traje | Novi se ne pokreće; „Pokreni sada“ to javlja. |
| Oštećen fajl miksa | Preskače se, sa zapisom u log; koristi se prethodni. |

Ključevi se ne zapisuju u log i ne vraćaju u odgovorima podešavanja. Lyrion prefs su običan tekst na serveru.

## 9. Instalacija i testiranje
| Nivo | Način |
|---|---|
| Moduli bez Lyrion-a | TDD preko `ssh lyrion`, van živog plugina, sa snimljenim primerima odgovora API-ja |
| Fork | `node --test`, build `mkrel.py` |
| Probe pre pisanja (uz saglasnost) | Čuvanje `qobuz://` i `tidal://` URL-ova u LMS plejlistu |
| Na serveru | „Pokreni sada“ sa oba modela (po jedan poziv, sa ključevima korisnika), tri dugmeta na oba nivoa, Previous days, Save i Add to playlist, nadoknada pri startu |
| Regresija | F1 pretraga, primarni izvor, SR11 |

- Svako izdanje forka dobija novu verziju (`900.6.4.15` i dalje), da browser ne zadrži stari JavaScript.
- `install-f1.sh` dobija proveru verzije `900.` u ZIP-u i uputstvo za vraćanje ako padne usred rada.
- Izmene na serveru: najava, saglasnost, rezervna kopija, korisnik pokreće `sudo` korak.

## 10. Rizici
- Tekstualni format servisa i dalje nije stabilan interfejs (F1).
- Modeli mogu da predlože pesme koje ne postoje. Zato se traži 3 puta više predloga.
- Trajanje traženja je procena: oko 3 s po predlogu.
- Qobuz hi-res pesme mogu da ne sviraju zbog poznatog kvara plugina; podešavanje plugina je 16/44.1.
- Cena po modelu je procena i može da se promeni.
