# F1: Objedinjena pretraga (specifikacija)

Status: dizajn odobren 2026-11-10, specifikacija čeka pregled.
Osnova: `docs/HANDOFF-Lyrion-MaterialSkin.md`, `docs/research/2026-11-10-provera-sekcija-6.md`.

## 1. Cilj
Jedna pretraga u Material Skin-u ide na lokalnu biblioteku, Qobuz i TIDAL. Rezultati se spajaju, a verzije istog albuma ili pesme grupišu se kao u Roon-u. Ništa se ne izbacuje iz rezultata.

Uspeh znači:
- „Kind of Blue“ daje jedan red albuma sa verzijama iz svih izvora koji ga imaju.
- Najpoželjniji izvor je prvi i pušta se jednim klikom.
- Ispad jednog izvora ne ruši pretragu.

## 2. Van obima
- F2 (dnevne plejliste) i ostatak F3 (kategorije, AI, tajmer).
- Spajanje dela (works) i plejlista između izvora.
- ISRC ili UPC grupisanje (podaci nisu dostupni).
- Prikaz kvaliteta za Qobuz i TIDAL (podaci nisu dostupni).
- Prikazivanje rezultata izvor po izvor dok stižu.
- Lokalizovani nazivi podmenija servisa.

## 3. Ponašanje
### 3.1 Šta se spaja
| Tip | Ponašanje |
|---|---|
| Albumi | Grupišu se preko sva tri izvora. |
| Pesme | Grupišu se preko sva tri izvora. |
| Izvođači | Spajaju se po imenu. Klik vodi na izbor izvora. |
| Dela, plejliste | Ostaju odvojeni po izvoru. |

Nova pretraga zamenjuje postojeće polje za pretragu u Material-u.

### 3.2 Ključ grupe
- Album: `normalizovan izvođač + normalizovan naslov`.
- Pesma: `normalizovan izvođač + normalizovan naslov`. Album nije deo ključa, jer ga TIDAL uz pesmu ne daje.
- Izvođač: `normalizovano ime`.

Normalizacija, redom:
1. Mala slova, Unicode NFKD, uklanjanje dijakritike. `đ` postaje `dj`. Ćirilica ostaje ćirilica.
2. `&` postaje `and`. U izvođaču se odbacuje sve od `feat.`, `ft.` ili `featuring`.
3. Segment u zagradama (`()`, `[]`) ili iza ` - ` uklanja se ako je samo godina ili sadrži reč: `remaster`, `remastered`, `deluxe`, `legacy`, `expanded`, `anniversary`, `edition`, `bonus`, `reissue`.
4. Segment se **zadržava** ako sadrži `live`, čak i uz neku reč iz tačke 3. Sve ostalo (npr. `Radio Version`, `Mono`) takođe ostaje, pa je zasebna grupa.
5. Interpunkcija se uklanja, a razmaci svode na jedan.

Originalni naslov se uvek čuva i prikazuje na verziji.

### 3.3 Redosled verzija u grupi
1. Izvor po podešavanju (podrazumevano: lokalno, Qobuz, TIDAL).
2. Lokalne verzije: DSD (`dsf`, `dff`), zatim viši `samplerate`, pa viši `samplesize`.
3. Verzije sa servisa: redosled koji je vratio servis.

### 3.4 Redosled grupa
1. Normalizovan naslov jednak normalizovanoj pretrazi.
2. Naslov počinje pretragom.
3. Ostalo.

Unutar nivoa: najpoželjniji izvor koji grupa ima, pa naslov abecedno.

### 3.5 Prikaz
- Red grupe: naslov, izvođač, broj verzija, ikonice izvora.
- Klik na red otvara listu verzija iz već dobijenog odgovora, bez novog upita.
- Dugme „pusti“ pušta prvu verziju.
- Ako izvora nema u odgovoru, prikazuje se napomena koji izvor nedostaje.

## 4. Arhitektura
```text
src/UnifiedMusic/          Perl plugin (radni naziv)
  Normalize.pm             ključ grupe; bez zavisnosti od Lyrion-a
  Grouper.pm               grupe i redosled; bez zavisnosti od Lyrion-a
  Source/Local.pm          lokalni JSON-RPC upiti
  Source/Service.pm        globalsearch i parsiranje teksta
  Search.pm                paralelni izvori, limit, spajanje
  Plugin.pm                registracija CLI komande
  Settings.pm              redosled izvora
src/lms-material/          fork na tagu 6.4.14, zaseban git repo, izuzet iz spoljnog
```

Izmene forka su ograničene na:
- `search-field.js`: poziv naše komande umesto današnjih pojedinačnih.
- Prikaz reda grupe i stranicu verzija.
- `install.xml`: verzija `900.6.4.14` (sekcija 8).

Licence i autorstvo Material-a (MIT, GPL-2.0) ostaju. Kod Qobuz i TIDAL pluginova se ne kopira, servisima se pristupa isključivo kroz njihove Lyrion komande.

## 5. Interfejs
Komanda (ne zahteva plejer, a prosleđuje ga ako postoji):
```json
["unifiedmusic", "search", "term:<tekst>", "library_id:<id>"]
```

Odgovor:
```json
{
  "albums": [{
    "title": "Kind of Blue", "artist": "Miles Davis",
    "sources": ["local", "qobuz", "tidal"],
    "versions": [{
      "source": "local", "title": "Kind of Blue", "artist": "Miles Davis",
      "year": 1959, "image": "...",
      "format": "dsf", "samplerate": 2822400, "samplesize": 1,
      "play": { "album_id": 17581 }
    }]
  }],
  "tracks": [], "artists": [], "works": [], "playlists": [],
  "missing": ["tidal"]
}
```

Polje `play`:
| Stavka | Sadržaj |
|---|---|
| Lokalna pesma | `track_id` |
| Lokalni album | `album_id` |
| Pesma sa servisa | `url` (`qobuz://...`, `tidal://...`) |
| TIDAL album | `url` (`tidal://album:<id>`) |
| Qobuz album | `item_id` iz istog odgovora (Qobuz u odgovoru ne daje stabilan URL) |

Polja koja izvor ne daje izostavljaju se. Prazni rezultati su prazne liste.

## 6. Tok
1. Fork šalje `unifiedmusic search`.
2. `Search` paralelno poziva izvore.
   - Lokalno: `artists`, `albums`, `tracks`, `works`, `playlists`, do 500 po tipu.
   - Servisi: `globalsearch items` sa `menu:1`, sve što servis vrati (Qobuz do 200, TIDAL do 100 po tipu).
3. `Source::Service` bira servis (`Qobuz`, `TIDAL`) i podmeni po engleskom nazivu: Qobuz `Releases`, `Artists`, `Songs`; TIDAL `Albums`, `Artists`, `Songs`.
4. Parsiranje polja `text`:
   - Qobuz pesma: `naslov\nizvođač - album`
   - Qobuz album: `naslov\nizvođač (godina)`
   - TIDAL pesma ili album: `naslov\nizvođač`
   - URL se čita iz `presetParams.favorites_url`.
5. `Grouper` pravi odgovor iz sekcije 5.

## 7. Greške
| Situacija | Ponašanje |
|---|---|
| Izvor ne odgovori za 5 s | Izvor ide u `missing`, ostatak se prikazuje. |
| Plejer nije izabran | Radi samo lokalno, servisi idu u `missing`. |
| Nije nađen naziv servisa ili podmenija | Izvor ide u `missing`, uz zapis u log. |
| `text` se ne može pouzdano podeliti | Stavka ostaje kao zasebna grupa sa celim tekstom kao naslovom. |
| Naša komanda nije dostupna | Fork prelazi na postojeću pretragu Material-a. |

Noviji upit poništava stariji, preko postojećeg `seachReqId` mehanizma. Pozivi za koje je utvrđeno da server odbija (`trackinfo` sa URL-om servisa van reda, `libraries getid` bez plejera) ne koriste se.

## 8. Instalacija
- Fork se gradi Material-ovom skriptom `mkrel.py` (zahteva Javu, postoji na PC-u).
- Automatsko ažuriranje pluginova je uključeno. Fork zato dobija verziju `900.6.4.14`. Pre instalacije u kodu Lyrion-a se proverava da to sprečava zamenu. Ako ne sprečava, instalacija staje i o rešenju odlučuje korisnik.
- Pre izmene se arhivira trenutni `MaterialSkin` folder.
- `tools\` sadrži skripte za instalaciju i vraćanje. Korisnik ih pokreće, jer traže `sudo`.
- Svaka izmena na serveru se najavljuje pre pokretanja i traži saglasnost.
- Ključevi i lozinke ne idu u git.

## 9. Testiranje
| Nivo | Način |
|---|---|
| `Normalize`, `Grouper` | TDD, sa fixture podacima iz stvarnih odgovora; pokretanje preko `ssh lyrion` u korisničkom folderu, van živog plugina |
| Probe pre pisanja plugina (neaktivan plejer, uz saglasnost) | puštanje `qobuz://` i `tidal://` URL-a; otvaranje i puštanje Qobuz albuma preko `item_id` |
| Build forka | `mkrel.py` proizvodi radni paket na PC-u |
| Na serveru, posle instalacije | „Kind of Blue“, „So What“, pojam bez lokalnih rezultata, pojam sa ćirilicom i dijakritikom; simulacija izvora koji nedostaje |
| Regresija | SR11 i ostali plejeri rade kao pre |

Vreme pretrage se meri na ceo tok. Očekivano je oko 2 s, što još nije izmereno.

## 10. Rizici
- Tekstualni format servisa nije stabilan interfejs. Nova verzija plugina može da pokvari parsiranje; posledica je lošije spajanje ili `missing`, ne pad.
- Grupisanje po nazivu može pogrešno spojiti različita izdanja istog naziva, ili ne spojiti npr. `Miles Davis` i `Miles Davis Sextet`. Verzije ostaju vidljive i birive.
- Nova verzija Material-a se u fork spaja ručno.
- Ako probe iz sekcije 9 pokažu da URL servisa ne može da se pusti, tok puštanja se menja pre pisanja plugina i specifikacija se dopunjuje.
