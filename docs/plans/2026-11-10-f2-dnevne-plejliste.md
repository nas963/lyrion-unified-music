# F2: Dnevne plejliste — plan implementacije

> **Za agente:** OBAVEZAN pod-skill: `superpowers:subagent-driven-development` ili `superpowers:executing-plans`, zadatak po zadatak. Koraci koriste `- [ ]` za praćenje.

**Cilj:** Noćni AI miksovi po kategorijama, dostupni iz stavke Your Daily Mixes u Material-u, sa ikonicama izvora, 7 dana istorije i čuvanjem u LMS plejlistu.

**Arhitektura:** Novi moduli u pluginu `UnifiedMusic` bez zavisnosti od Lyrion-a, kojima `Plugin.pm` ubacuje HTTP, tajmer i pretragu. Adapteri `AI::Anthropic` i `AI::OpenAI` dele jedan interfejs. Fork dobija stavku na Home i liste preko postojećih tipova.

**Tehnologije:** Perl 5.38 (Test::More, JSON::PP, POSIX), Lyrion 9.1.1 plugin API, Vue 2 (Material), Node `node:test`, `mkrel.py`.

**Specifikacija:** `Lyrion-MaterialSkin/docs/specs/2026-11-10-f2-dnevne-plejliste.md`

## Globalna ograničenja
- Komunikacija i poruke: srpski (latinica). Commit poruke se završavaju attribution linijama koje sesija zada.
- Rad na grani `f2-dnevne` spoljnog repoa i `unified-search` u forku.
- Build forka: `PYTHONUTF8=1 python mkrel.py <verzija> --nocheck`, posle toga `git checkout public.xml`. Pre builda obrisati `build/` i stari ZIP.
- Verzija forka: `900.6.4.15`, svako sledeće izdanje povećava zadnji broj.
- Testovi: `bash Lyrion-MaterialSkin/tools/run-perl-tests.sh` (iz Bash alata) i `node --test Lyrion-MaterialSkin/tests/js/`.
- Prefs `qobuz.prefs` i `tidal.prefs` se ne otvaraju. Aplikacijski ključevi servisa se ne koriste. Pri čitanju DEBUG loga obavezno skrivati adrese i `app_id`.
- Ključevi korisnika nikad u git, log, odgovore CLI komandi ni greške.
- Izmene na serveru: najava, saglasnost, rezervna kopija, korisnik pokreće `sudo` korak.
- Modeli: `claude-haiku-5-5`, `gpt-6-luna`. Bez `temperature`. Izlaz po JSON šemi, najviše 16.000 izlaznih tokena.
- Predloga: 3 puta broj pesama. Istorija: 7 dana. Broj pesama: 5–100, podrazumevano 30.

## Fokus pregleda
1. Naziv kategorije sa ćirilicom, `/`, `..` ili navodnicima: bezbedan naziv fajla, nikad van foldera miksova, a dve kategorije ne dele fajl (Zadatak 6).
2. Model vrati istu pesmu više puta: u miksu samo jednom (Zadatak 5).
3. Model vrati JSON u Markdown bloku, višak polja ili prazne vrednosti: blok se prihvata, stavka bez izvođača ili naslova se preskače (Zadatak 4).
4. Promena dana ili zakazano vreme uz „Pokreni sada“: posao najviše jednom u isto vreme, nadoknada najviše jednom dnevno (Zadatak 7).
5. API greška koja sadrži ključ: tekst greške ga ne prenosi dalje (Zadatak 4).

---

### Zadatak 0: Provere pre koda (blokirajući)

**Fajlovi:** Izmena: `Lyrion-MaterialSkin/docs/research/2026-11-10-provera-sekcija-6.md`

- [ ] **Korak 1: Grana.** `git switch -c f2-dnevne` u spoljnom repou.
- [ ] **Korak 2: API.** Iz zvanične dokumentacije zapisati: Anthropic `POST /v1/messages` (zaglavlja, `output_config.format`, `output_config.effort`, polja odgovora, `stop_reason`) i OpenAI API za `gpt-6-luna` sa JSON šemom, kao i njegovu cenu. Očekivano: zapis u research fajlu, sa adresama izvora.
- [ ] **Korak 3: Vremenska zona.** `ssh lyrion "TZ=Europe/Belgrade date"`. Očekivano: lokalno vreme.
- [ ] **Korak 4: Proba LMS plejliste, uz saglasnost.** Preko `playlists new name:` i `playlists edit cmd:add playlist_id:<id> url:<qobuz|tidal>` napraviti probnu plejlistu `F2-proba`, proveriti `playlists tracks` (tag `u`), obrisati je sa `playlists delete`. Očekivano: oba URL-a su u plejlisti. Ako ne uspe, stani i dopuni specifikaciju sa korisnikom.
- [ ] **Korak 5: Commit** specifikacije, plana i research fajla.

---

### Zadatak 1: Primarni izvor i emblem za lokalno (F1)

**Fajlovi:** Izmena: `src/UnifiedMusic/Search.pm`, `Plugin.pm`, `Settings.pm`, `HTML/EN/plugins/UnifiedMusic/settings/basic.html`, `src/UnifiedMusic/Source/Local.pm`; fork: `html/misc/emblems.json`, `unified-search.js`. Test: `tests/perl/40-search.t`, `tests/perl/30-local.t`, `tests/js/unified-search.test.js`.

**Interfejsi:** Proizvodi: `Search::source_order_for_primary($primary)->\@order`, `Search::primary_from_order($text)->$primary`. Lokalna pesma dobija polje `url` iz `titles_loop.url`.

- [ ] **Korak 1: Testovi.**
```perl
is_deeply source_order_for_primary('local'), [qw(local qobuz tidal)];
is_deeply source_order_for_primary('qobuz'), [qw(qobuz local tidal)];
is_deeply source_order_for_primary('tidal'), [qw(tidal local qobuz)];
is_deeply source_order_for_primary('xyz'), [qw(local qobuz tidal)];
is primary_from_order('tidal,qobuz,local'), 'tidal';
is primary_from_order(undef), 'local';
```
U `30-local.t`: lokalna pesma ima `url` koji počinje sa `file:///`. U JS testu: izvor `local` sa `emblemUrl` daje `<img`, a bez `emblemUrl` daje tekst „Local“.
- [ ] **Korak 2:** Pokrenuti, očekivano FAIL.
- [ ] **Korak 3: Implementacija.** Pref `primarySource`; pri `initPlugin`, ako postoji `sourceOrder` a nema `primarySource`, upisati `primary_from_order`. Padajuća lista u podešavanjima umesto tekstualnog polja. U `emblems.json` dodati `"local"` sa ikonicom foldera; ako u `/material/svg/` nema SVG-a `folder`, dodati ga u fork.
- [ ] **Korak 4:** Pokrenuti, očekivano PASS.
- [ ] **Korak 5: Commit** u oba repoa.

---

### Zadatak 2: `Mix::Config`

**Fajlovi:** Kreiranje: `src/UnifiedMusic/Mix/Config.pm`. Test: `tests/perl/60-mix-config.t`.

**Interfejsi:** Proizvodi: `validate(\%input)->{ok=>1, config=>\%c}` ili `{ok=>0, errors=>[tekst...]}`. Polja: `primarySource, categories=>[{name,genres=>[...]}], trackCount, model, anthropicKey, openaiKey, runTime, timeZone`. `key_for_model(\%c)->$key`, `provider_for_model($model)->'anthropic'|'openai'`, `available_models(\%c)->[{id, available}]`.

- [ ] **Korak 1: Testovi** za: podrazumevani `trackCount` 30, `runTime` `04:00`, `timeZone` `Europe/Belgrade`; granice 5 i 100 prolaze, 4 i 101 ne; nepostojeći model ne prolazi; izabrani model bez svog ključa daje grešku koja ne sadrži ključ; drugi ključ nije obavezan; prazan ili dupli naziv (posle `trim`, bez razlike velikih slova) ne prolazi; kategorija bez žanrova ne prolazi; `runTime` `25:00` ne prolazi; `available_models` označava model bez ključa sa `available=>0`.
- [ ] **Korak 2:** FAIL.
- [ ] **Korak 3:** Implementacija.
- [ ] **Korak 4:** PASS.
- [ ] **Korak 5: Commit.**

---

### Zadatak 3: `Mix::Prompt`

**Fajlovi:** Kreiranje: `src/UnifiedMusic/Mix/Prompt.pm`. Test: `tests/perl/61-mix-prompt.t`.

**Interfejsi:** Proizvodi: `build({category=>{name,genres}, count=>$n, rng=>$coderef})->{system=>$tekst, user=>$tekst, requested=>$n3}`. `rng->($broj)` vraća ceo broj od 0 do `$broj-1`.

- [ ] **Korak 1: Testovi.** Sa `count=>30` je `requested` 90 i `user` sadrži `90`. `user` sadrži naziv kategorije, izabrani žanr, deceniju i odnos poznatih i manje poznatih. Različit `rng` daje različit naglasak. Fiksni `rng` daje isti izlaz. `system` traži stvarne, objavljene pesme i zabranjuje izmišljanje.
- [ ] **Korak 2:** FAIL.
- [ ] **Korak 3:** Implementacija.
- [ ] **Korak 4:** PASS.
- [ ] **Korak 5: Commit.**

---

### Zadatak 4: Adapteri

**Fajlovi:** Kreiranje: `src/UnifiedMusic/AI/Anthropic.pm`, `AI/OpenAI.pm`, `AI/Common.pm`. Test: `tests/perl/62-ai.t`, fixture `tests/fixtures/ai_*.json`.

**Interfejsi:** `new(http=>$f)`, `suggest({model, api_key, prompt=>{system,user}}, $done)`; `$done->({suggestions=>[{artist,title}]})` ili `{error=>$tekst, retryable=>0|1}`, tačno jednom. `http->({url, headers=>{}, body=>$json}, $cb)`, `$cb->({status, body})` ili `{error}`. `Common::parse_suggestions($text)->\@list | undef`; `Common::redact($text, @keys)->$text`.

- [ ] **Korak 1: Testovi** sa snimljenim primerima oblika iz Zadatka 0: telo sadrži tačan model i JSON šemu, a ne sadrži `temperature`; ključ je samo u zaglavlju; ispravan odgovor daje predloge. `parse_suggestions` prihvata JSON u Markdown bloku, ignoriše višak polja, preskače stavke bez `artist` ili `title`, vraća `undef` za neispravan JSON. Odbijanje modela i HTTP 401 daju `retryable=>0`; neispravan JSON i prekid zbog `max_tokens` daju `retryable=>1`. Greška čiji tekst sadrži ključ ne sadrži ga posle `redact`.
- [ ] **Korak 2:** FAIL.
- [ ] **Korak 3:** Implementacija po zapisu iz Zadatka 0; `max_tokens` 16000; za Haiku `output_config.effort` `low`.
- [ ] **Korak 4:** PASS.
- [ ] **Korak 5: Commit.**

---

### Zadatak 5: `Mix::Resolver`

**Fajlovi:** Kreiranje: `src/UnifiedMusic/Mix/Resolver.pm`. Test: `tests/perl/63-mix-resolver.t`.

**Interfejsi:** `new(search=>$f)`, `resolve(\@suggestions, $count, $done)`; `search->($term, $cb)`, `$cb->(\%odgovor_F1)`. `$done->(\@tracks)`, stavke `{title, artist, album?, source, url, image?}`.

- [ ] **Korak 1: Testovi.** Pojam je `"artist title"`. Prihvata se samo grupa čiji je `track_key` jednak predlogu. Uzima se prva verzija grupe koja ima URL (poštuje redosled izvora). Predlog bez poklapanja se preskače. Staje se posle `$count` pesama i ne poziva više pretragu. Duplirani predlozi (isti `track_key`) daju jednu pesmu. Pretraga koja vrati `missing` ne prekida rad. Predlozi se obrađuju sekvencijalno.
- [ ] **Korak 2:** FAIL.
- [ ] **Korak 3:** Implementacija. Qobuz stavke sa `play.item_id` bez URL-a se ne prihvataju.
- [ ] **Korak 4:** PASS.
- [ ] **Korak 5: Commit.**

---

### Zadatak 6: `Mix::Store`

**Fajlovi:** Kreiranje: `src/UnifiedMusic/Mix/Store.pm`. Test: `tests/perl/64-mix-store.t`.

**Interfejsi:** `new(dir=>$d)`; `save(\%mix)`; `load($date,$category)->\%mix|undef`; `dates($category)->[YYYY-MM-DD novije prvo]`; `latest($category)->\%mix|undef`; `prune($today, 7)`; `slug($category)->$tekst`.

- [ ] **Korak 1: Testovi** u privremenom folderu: `save` pa `load` vraća isto, uključujući ćirilicu. `slug` za `../a/b`, `"Jazz"`, `Džez` i `Ђаз` ne izlazi iz foldera i različite kategorije daju različit `slug`. `dates` ređa novije prvo. `latest` preskače oštećen fajl i vraća prethodni. Upis je atomski (privremeni fajl pa `rename`). `prune('2026-11-11', 7)` briše `2026-11-03` a zadržava `2026-11-04`.
- [ ] **Korak 2:** FAIL.
- [ ] **Korak 3:** Implementacija. `slug` je ASCII deo plus heš punog naziva.
- [ ] **Korak 4:** PASS.
- [ ] **Korak 5: Commit.**

---

### Zadatak 7: `Mix::Job` i `Mix::Scheduler`

**Fajlovi:** Kreiranje: `src/UnifiedMusic/Mix/Job.pm`, `Mix/Scheduler.pm`. Test: `tests/perl/65-mix-job.t`, `66-mix-scheduler.t`.

**Interfejsi:**
- `Job::run({config, adapter, resolver, store, rng, date, log}, $done)`; `$done->({ok=>[nazivi], failed=>[{name,error}]})`.
- `Scheduler->new(now=>$f, set_timer=>$f, cancel_timer=>$f, run_job=>$f, has_player=>$f, last_run=>$f, set_last_run=>$f, config=>$f)`; `start()`, `run_now($cb)`. `now->()` vraća `{date, hhmm, epoch}` u zoni iz podešavanja.

- [ ] **Korak 1: Testovi za `Job`.** Kategorije se obrađuju redom. Ponovljiva greška ponavlja poziv jednom, neponovljiva ne. Greška jedne kategorije ne zaustavlja ostale i ne briše stari miks. Nula pesama ne upisuje fajl. Posle posla se poziva `prune`.
- [ ] **Korak 2: Testovi za `Scheduler`.** Posao se pokreće u zadato vreme. Pri startu posle zakazanog vremena, ako je `last_run` juče, pokreće se jednom; ako je `last_run` danas, ne pokreće se. Pre zakazanog vremena se ne pokreće. Bez plejera se ponavlja na 3600 s, najviše 6 puta, pa odustaje do sutra. `run_now` dok posao traje vraća `{running=>1}` i ne pokreće drugi. Izmena vremena u podešavanjima važi za sledeće planiranje. Posle posla se planira sledeći dan.
- [ ] **Korak 3:** FAIL.
- [ ] **Korak 4:** Implementacija.
- [ ] **Korak 5:** PASS.
- [ ] **Korak 6: Commit.**

---

### Zadatak 8: CLI i podešavanja

**Fajlovi:** Izmena: `src/UnifiedMusic/Plugin.pm`, `Settings.pm`, `strings.txt`, `HTML/EN/plugins/UnifiedMusic/settings/basic.html`. Kreiranje: `src/UnifiedMusic/Mix/Cli.pm`. Test: `tests/perl/67-mix-cli.t`.

**Interfejsi:** Komande iz sekcije 6 specifikacije. `Cli::categories($store,$config)->\@rows`, `Cli::mix_items($store,$category,$date)->\%resp`, `Cli::queue_commands($cmd,\@urls)->[[...]]`.

- [ ] **Korak 1: Testovi.** `categories` daje današnji ili poslednji datum i oznaku `stale` kad nije današnji. `mix_items` daje pesme i red `Previous days` samo ako ima starijih dana. `queue_commands('play', [a,b])` daje `[playlist,play,a]` pa `[playlist,add,b]`; `add` daje samo `add`; `insert` zadržava redosled pesama u redu. Prazan miks daje prazne komande.
- [ ] **Korak 2:** FAIL.
- [ ] **Korak 3: Implementacija.** `Plugin.pm` ubacuje `Slim::Networking::SimpleAsyncHTTP`, `Slim::Utils::Timers`, zonu preko `POSIX::tzset` sa `TZ`, plejer iz `Slim::Player::Client::clients`. Podešavanja koriste `Mix::Config::validate`; prazno polje ključa zadržava sačuvanu vrednost; ključ se ne prikazuje. Kategorije su redovi u formi. Dugme „Pokreni sada“ poziva `run_now` i prikazuje ishod.
- [ ] **Korak 4:** PASS.
- [ ] **Korak 5: Commit.**

---

### Zadatak 9: Izmene forka

**Fajlovi (u `src/lms-material`):** Kreiranje: `html/js/unified-mixes.js`. Izmena: `browse-page.js` (Home lista i `updateTopList`), `browse-functions.js` (`browseClick`, `browseItemAction`), `MaterialSkin/HTML/material/index.html`, `ChangeLog`. Test: `tests/js/unified-mixes.test.js`.

**Interfejsi:** `mixCategoriesToItems(resp, options)->items`, `mixToItems(resp, options)->items`, `mixActionCommand(act, item)->[...]`, `trackActionCommand(act, track)->[...]`.

- [ ] **Korak 1: Testovi.** Red kategorije ima tri radnje; zastareo miks ima datum u podnaslovu. Red pesme ima emblem po izvoru. `Previous days` je stavka sa kategorijom i otvara spisak dana. Komande: `Play now`, `Play next` i `Append` daju `cmd:play`, `cmd:insert`, `cmd:add`. Tekst iz naziva se escape-uje.
- [ ] **Korak 2:** FAIL.
- [ ] **Korak 3: Implementacija.** Stavka `TOP_DAILY_ID` odmah posle `Extras`, sa istom zaštitom u `updateTopList` kao za `Extras`, da je vide browseri sa sačuvanom listom. `allowAdd` i `allowInsert` ostaju uključeni za redove miksa. Save i Add to playlist u meniju, sa `promptForText` i `choose`.
- [ ] **Korak 4:** PASS, build sa `900.6.4.15`, provera da je `mixToItems` u `material.min.js`.
- [ ] **Korak 5: Commit** u oba repoa.

---

### Zadatak 10: Instalacija i provera

**Fajlovi:** Izmena: `tools/install-f1.sh`, `docs/INSTALL-F1.md`.

- [ ] **Korak 1: Skripta.** Odbijanje ZIP-a bez `<version>900\.`. `trap` posle `systemctl stop` koji ispisuje komandu za vraćanje. Plugin ostaje u `/usr/share/squeezeboxserver/Plugins/UnifiedMusic`.
- [ ] **Korak 2: Priprema.** Kopirati u `~/f1-install`, `bash -n`, najaviti izmenu, tražiti saglasnost. Bez saglasnosti ne nastavljati.
- [ ] **Korak 3: Korisnik pokreće instalaciju.** Očekivano: `F1-INSTALIRAN`, u logu nema `parseStrings` ni `UnifiedMusic` grešaka, `can unifiedmusic mixes items ?` je 1.
- [ ] **Korak 4: Podešavanja.** Korisnik unosi ključeve i kategorije; greške validacije rade.
- [ ] **Korak 5: Pokreni sada, oba modela.** Očekivano: miks sa stvarnim pesmama, izmereno trajanje i potrošnja.
- [ ] **Korak 6: Browser.** Home stavka, tri dugmeta na oba nivoa, Previous days, ikonice uključujući folder, Save i Add to playlist, primarni izvor u F1.
- [ ] **Korak 7: Noćni posao.** Zakazati vreme nekoliko minuta unapred; proveriti pokretanje i nadoknadu posle restarta.
- [ ] **Korak 8: Regresija i zapis.** F1 pretraga, SR11. Rezultate upisati u `docs/research`, sa onim što nije testirano.
- [ ] **Korak 9: Nezavisni pregled grane i commit.**
