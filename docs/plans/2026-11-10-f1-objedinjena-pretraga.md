# F1: Objedinjena pretraga — plan implementacije

> **Za agente:** OBAVEZAN pod-skill: `superpowers:subagent-driven-development` ili `superpowers:executing-plans`, zadatak po zadatak. Koraci koriste `- [ ]` za praćenje.

**Cilj:** Jedna pretraga u Material Skin-u preko lokalne biblioteke, Qobuza i TIDAL-a, sa grupisanim verzijama.

**Arhitektura:** Novi Perl plugin `UnifiedMusic` radi pretragu i grupisanje i izlaže CLI komandu `unifiedmusic search`. Mali fork Material-a 6.4.14 poziva tu komandu i prikazuje grupe. Moduli dobijaju pristup Lyrion-u kroz ubačene funkcije, pa se testiraju van živog servera.

**Tehnologije:** Perl 5.38 (Test::More, Unicode::Normalize), Lyrion 9.1.1 plugin API, Vue 2 / Vuetify 1 (Material), Node `node:test`, `mkrel.py` sa Javom.

**Specifikacija:** `Lyrion-MaterialSkin/docs/specs/2026-11-10-f1-objedinjena-pretraga.md`

## Globalna ograničenja
- Komunikacija i poruke: srpski (latinica). Commit poruke se završavaju attribution linijama koje sesija zada.
- Rad na grani `f1-pretraga` spoljnog repoa. Fork ima svoj git repo.
- Bez izvlačenja ili upotrebe aplikacijskih ključeva. Prefs fajlovi `qobuz.prefs` i `tidal.prefs` se ne otvaraju.
- Kod Qobuz i TIDAL pluginova se ne kopira. Servisi se koriste samo kroz njihove Lyrion komande.
- Fork zadržava `LICENSE`, `LICENSE.GPLv2` i autorstvo Material-a.
- Ključevi i lozinke nikad u git.
- Izmene na serveru: najava, saglasnost, rezervna kopija, uputstvo za vraćanje. Čitanje preko `ssh lyrion` je dozvoljeno, a testovi smeju da pišu samo u `~/unifiedmusic-test`.
- Limit po izvoru: 5 s. Redosled izvora podrazumevano: `local,qobuz,tidal`.
- Ne koristiti `trackinfo items url:<servis>` ni `libraries getid` bez plejera.

## Fokus pregleda
1. Pretraga sa dijakritikom ili ćirilicom: „Đorđe“ i „Djordje“ daju isti ključ, ćirilica ostaje neizmenjena (Zadatak 3).
2. Naslov koji posle normalizacije ostane prazan, npr. „(Remastered)“: ključ nije prazan, a takve stavke se ne spajaju međusobno (Zadatak 3).
3. Prazna pretraga ili samo razmaci: vraća prazan odgovor bez poziva izvorima (Zadatak 6).
4. Odgovor servisa koji stigne posle limita: ne dodaje se i ne završava zahtev dvaput (Zadatak 6).
5. Lokalna godina `0`: polje `year` se izostavlja (Zadatak 5).

---

### Zadatak 0: Provere pre pisanja koda (blokirajući)

**Fajlovi:**
- Izmena: `Lyrion-MaterialSkin/docs/research/2026-11-10-provera-sekcija-6.md`

**Interfejsi:** Proizvodi: putanju za instalaciju plugina i odluku o verziji forka, koje koriste Zadaci 8 i 9.

- [ ] **Korak 1: Pronaći putanje Lyrion koda i pluginova**

Pokreni: `ssh lyrion 'ls -d /usr/share/squeezeboxserver/Slim /usr/lib/squeezeboxserver/Slim 2>/dev/null; ls -ld /var/lib/squeezeboxserver/Plugins /var/lib/squeezeboxserver/cache/InstalledPlugins/Plugins'`
Očekivano: nađen folder `Slim`. Pročitaj `Slim/Utils/OSDetect/Linux.pm` (ili Debian varijantu), funkcija `dirsFor('Plugins')`, i zapiši gde ručno instaliran plugin preživljava restart.

- [ ] **Korak 2: Proveriti da visoka verzija sprečava ažuriranje**

Pročitaj `Slim/Utils/ExtensionsManager.pm` i `Slim/Utils/PluginDownloader.pm`, tražeći poređenje verzija (`checkVersion`) i uklanjanje pluginova kojih nema u repozitorijumu.
Očekivano: zapisano da li instalirana verzija `900.6.4.14` sprečava zamenu. **Ako ne sprečava, stani i pitaj korisnika.**

- [ ] **Korak 3: Tražiti saglasnost i izbor plejera za probe**

Javi korisniku da proba menja red izabranog plejera i kratko pušta zvuk. Korisnik bira plejer. Plejer koji svira i SR11 se ne koriste.

- [ ] **Korak 4: Probati puštanje sa servisa**

Na izabranom plejeru, redom, sa proverom `status - 1 tags:u` posle svakog i `pause 1` odmah zatim:
`playlist play qobuz://13176083.flac`, `playlist play tidal://169025.flc`, `playlist play tidal://album:2178485`, zatim `globalsearch items ... menu:1 search:Kind of Blue`, spuštanje do `Qobuz` / `Releases` i `globalsearch playlist play item_id:<prvi album>`.
Očekivano: `mode` je `play` ili `pause` i `playlist_tracks` > 0 za svaki poziv. Na kraju `playlist clear`.

- [ ] **Korak 5: Zapisati rezultate i odlučiti**

Dopuni research fajl. Ako bilo koja proba ne uspe, stani i dopuni specifikaciju sa korisnikom pre Zadatka 1.

- [ ] **Korak 6: Commit**

```bash
git add Lyrion-MaterialSkin/docs/research Lyrion-MaterialSkin/docs/specs Lyrion-MaterialSkin/docs/plans
git commit -m "F1: specifikacija, plan i provere pre implementacije"
```

---

### Zadatak 1: Fork i proba build-a

**Fajlovi:**
- Kreiranje: `Lyrion-MaterialSkin/src/lms-material/` (klon, zaseban repo)
- Izmena: `.gitignore` (koren), dodati `Lyrion-MaterialSkin/src/lms-material/`

- [ ] **Korak 1: Klonirati tag**

Pokreni: `git clone --branch 6.4.14 https://github.com/CDrummond/lms-material.git Lyrion-MaterialSkin/src/lms-material` pa u njemu `git switch -c unified-search`.
Očekivano: postoje `LICENSE`, `LICENSE.GPLv2`, `mkrel.py`.

- [ ] **Korak 2: Izuzeti fork iz spoljnog repoa**

Očekivano: `git status --short` u korenu ne prikazuje `src/lms-material`.

- [ ] **Korak 3: Pokrenuti build neizmenjenog forka**

Pokreni `python mkrel.py` prema uputstvu u skripti.
Očekivano: nastaje ZIP sa `material.min.js`. **Ako skripta ne radi na Windows-u**, zapiši uzrok i ispravi lokalno ili izdvoj minifikaciju u `tools/build-material.py`; ne menjaj izvorni JS.

- [ ] **Korak 4: Commit**

```bash
git add .gitignore
git commit -m "F1: izuzet fork Material-a iz spoljnog repoa"
```

---

### Zadatak 2: Pokretač testova i fixture podaci

**Fajlovi:**
- Kreiranje: `Lyrion-MaterialSkin/tools/run-perl-tests.sh`, `Lyrion-MaterialSkin/tools/capture-fixtures.ps1`
- Kreiranje: `Lyrion-MaterialSkin/tests/fixtures/{qobuz_root,qobuz_albums,qobuz_tracks,tidal_root,tidal_albums,tidal_tracks,local_albums,local_tracks}.json`
- Test: `Lyrion-MaterialSkin/tests/perl/00-env.t`

**Interfejsi:** Proizvodi: `tools/run-perl-tests.sh` (kopira `src/UnifiedMusic` u `~/unifiedmusic-test/lib/Plugins/UnifiedMusic`, `tests/perl` u `t`, `tests/fixtures` u `t/fixtures`, pokreće `prove -r -I lib t`).

- [ ] **Korak 1: Napisati `00-env.t`**

```perl
use Test::More;
use Unicode::Normalize;
use JSON::PP;
ok(-f 't/fixtures/qobuz_tracks.json', 'fixtures kopirani');
done_testing;
```

- [ ] **Korak 2: Snimiti fixture podatke**

`capture-fixtures.ps1` poziva stvarne upite iz specifikacije, sekcija 6, za pojam „Kind of Blue“, sa neaktivnim plejerom kao parametrom, i čuva `result` u `tests/fixtures`.
Očekivano: `qobuz_tracks.json` sadrži `qobuz://13176083.flac`. Fajlovi ne sadrže `session`, `token` ni `password` (proveri pretragom).

- [ ] **Korak 3: Pokrenuti test**

Pokreni: `bash Lyrion-MaterialSkin/tools/run-perl-tests.sh`
Očekivano: `All tests successful`.

- [ ] **Korak 4: Commit**

```bash
git add Lyrion-MaterialSkin/tools Lyrion-MaterialSkin/tests
git commit -m "F1: pokretac Perl testova i fixture podaci"
```

---

### Zadatak 3: `Normalize`

**Fajlovi:**
- Kreiranje: `Lyrion-MaterialSkin/src/UnifiedMusic/Normalize.pm`
- Test: `Lyrion-MaterialSkin/tests/perl/10-normalize.t`

**Interfejsi:** Proizvodi: paket `Plugins::UnifiedMusic::Normalize` sa `artist_key($name)->$string`, `title_key($title)->$string`, `album_key($artist,$title)->$string`, `track_key($artist,$title)->$string`, `plain_key($text)->$string`.

- [ ] **Korak 1: Napisati testove**

```perl
is title_key('Kind Of Blue (Legacy Edition)'), 'kind of blue';
is title_key('Kind of Blue (Remastered)'),     'kind of blue';
is title_key('So What - Remastered 2009'),     'so what';
is title_key('Abbey Road [2019]'),             'abbey road';
is title_key('Blues (Live Remastered)'),       'blues live remastered';
is title_key('Bitter Blue - Radio Version'),   'bitter blue radio version';
is title_key('Song (Mono)'),                   'song mono';
is artist_key('Đorđe Balašević'),              'djordje balasevic';
is artist_key('Djordje Balasevic'),            'djordje balasevic';
is artist_key('Ђорђе'),                        artist_key('Ђорђе');
isnt artist_key('Ђорђе'),                      '';
is artist_key('Simon & Garfunkel'),            'simon and garfunkel';
is artist_key('Santana feat. Rob Thomas'),     'santana';
is artist_key('Santana ft. Rob Thomas'),       'santana';
is album_key('Miles Davis','Kind of Blue'),    album_key('MILES DAVIS','Kind Of Blue (Deluxe)');
isnt title_key('(Remastered)'),                '';
isnt title_key('(Remastered)'),                title_key('[Deluxe]');
```

- [ ] **Korak 2: Pokrenuti, očekivano FAIL** (`bash Lyrion-MaterialSkin/tools/run-perl-tests.sh`: nema modula)

- [ ] **Korak 3: Implementirati `Normalize.pm`**

Pravila su u specifikaciji, sekcija 3.2. Reči za uklanjanje: `remaster`, `remastered`, `deluxe`, `legacy`, `expanded`, `anniversary`, `edition`, `bonus`, `reissue`; segment koji sadrži `live` se zadržava. Ako posle uklanjanja segmenata ne ostane ništa, koristi `plain_key` celog originala (normalizacija bez koraka 3). Ključ `album_key` i `track_key` spajaju delove znakom `\x1f`. Ćirilica se ne sme izgubiti pri uklanjanju dijakritike: ukloni samo kombinacione znakove (`\p{Mn}`), posle NFKD, pa vrati NFC.

- [ ] **Korak 4: Pokrenuti, očekivano PASS**

- [ ] **Korak 5: Commit**

```bash
git add Lyrion-MaterialSkin/src/UnifiedMusic Lyrion-MaterialSkin/tests/perl
git commit -m "F1: normalizacija kljuceva grupa"
```

---

### Zadatak 4: `Grouper`

**Fajlovi:**
- Kreiranje: `Lyrion-MaterialSkin/src/UnifiedMusic/Grouper.pm`
- Test: `Lyrion-MaterialSkin/tests/perl/20-grouper.t`

**Interfejsi:**
- Koristi: `Normalize` iz Zadatka 3.
- Proizvodi: `group_items(\@items, $term, \@source_order)->\@groups`.
- Stavka: `{kind=>'album'|'track'|'artist', source=>'local'|'qobuz'|'tidal', title, artist, album?, year?, image?, format?, samplerate?, samplesize?, play=>{...}}`. Polje `kind=>'other'` znači: ne spajati.
- Grupa: `{title, artist, sources=>[...], versions=>[stavke bez kind]}`. Naslov i izvođač su iz prve verzije. `sources` je jedinstven, po `source_order`.

- [ ] **Korak 1: Napisati testove**

```perl
my @o = qw(local qobuz tidal);
# spajanje, nista se ne gubi
my $g = group_items([a('tidal','Kind Of Blue (Legacy Edition)'), a('qobuz','Kind Of Blue'), a('local','Kind of Blue')], 'kind of blue', \@o);
is scalar @$g, 1; is scalar @{$g->[0]{versions}}, 3;
is_deeply $g->[0]{sources}, ['local','qobuz','tidal'];
is $g->[0]{title}, 'Kind of Blue';
# Live je zasebna grupa
is scalar @{group_items([a('local','X'), a('local','X (Live)')], 'x', \@o)}, 2;
# lokalni kvalitet: DSD, pa samplerate, pa samplesize
my @l = (f('flc',44100,16), f('flc',96000,24), f('flc',96000,16), f('dsf',2822400,1));
my $v = group_items(\@l,'x',\@o)->[0]{versions};
is_deeply [map {"$_->{format}/$_->{samplerate}/$_->{samplesize}"} @$v], ['dsf/2822400/1','flc/96000/24','flc/96000/16','flc/44100/16'];
# servis cuva svoj redosled; izvor po podesavanju
my $s = group_items([a('tidal','X'), mark(a('qobuz','X'),1), mark(a('qobuz','X'),2)],'x',['tidal','qobuz']);
is $s->[0]{versions}[0]{source}, 'tidal'; is $s->[0]{versions}[1]{n}, 1; is $s->[0]{versions}[2]{n}, 2;
# rang grupa: tacno, pocinje, ostalo
my $r = group_items([a('qobuz','Say So What'), a('tidal','So What Now'), a('tidal','So What')],'so what',\@o);
is_deeply [map {$_->{title}} @$r], ['So What','So What Now','Say So What'];
# kind=other se ne spaja
is scalar @{group_items([o('local','P'), o('qobuz','P')],'p',\@o)}, 2;
```

(`a`, `f`, `mark`, `o` su pomoćne funkcije u testu koje prave stavke istog izvođača.)

- [ ] **Korak 2: Pokrenuti, očekivano FAIL**

- [ ] **Korak 3: Implementirati `group_items`** po sekcijama 3.3 i 3.4. Sortiranje mora biti stabilno.

- [ ] **Korak 4: Pokrenuti, očekivano PASS**

- [ ] **Korak 5: Commit**

```bash
git add Lyrion-MaterialSkin/src/UnifiedMusic/Grouper.pm Lyrion-MaterialSkin/tests/perl/20-grouper.t
git commit -m "F1: grupisanje i redosled verzija"
```

---

### Zadatak 5: Izvori

**Fajlovi:**
- Kreiranje: `Lyrion-MaterialSkin/src/UnifiedMusic/Source/Local.pm`, `Lyrion-MaterialSkin/src/UnifiedMusic/Source/Service.pm`
- Test: `Lyrion-MaterialSkin/tests/perl/30-local.t`, `Lyrion-MaterialSkin/tests/perl/31-service.t`

**Interfejsi:**
- Proizvodi: oba izvora imaju `new(run=>$run)` i `search($term, {client=>$id, library_id=>$id}, $done)`. `$done->({items=>[...], missing=>[...]})` se poziva tačno jednom.
- `$run->($client, \@cmd, $cb)` izvršava Lyrion komandu; `$cb->($result_hash)`, ili `$cb->(undef)` pri grešci.
- `Service->new(run=>$run, service=>'qobuz'|'tidal')`. Mape podmenija: Qobuz `Releases`, `Artists`, `Songs`, `Playlists`; TIDAL `Albums`, `Artists`, `Songs`, `Playlists`.
- Čista funkcija: `Service::parse_text($service, $type, $text)->{title, artist?, album?, year?}`.

- [ ] **Korak 1: Napisati testove parsiranja i mapiranja**

```perl
is_deeply parse_text('qobuz','track',"So What\nMiles Davis - Kind Of Blue"), {title=>'So What',artist=>'Miles Davis',album=>'Kind Of Blue'};
is_deeply parse_text('qobuz','album',"Kind Of Blue\nMiles Davis (1959)"), {title=>'Kind Of Blue',artist=>'Miles Davis',year=>1959};
is_deeply parse_text('tidal','track',"Bitter Blue - Radio Version\nKind Of Blue"), {title=>'Bitter Blue - Radio Version',artist=>'Kind Of Blue'};
# dvosmisleno: vise od jednog " - " u drugom redu
is_deeply parse_text('qobuz','track',"T\nA - B - C"), {title=>"T\nA - B - C"};
is_deeply parse_text('qobuz','track',"Samo naslov"), {title=>'Samo naslov'};
```

Dodatni testovi sa fixture podacima: `Local` iz `local_albums.json` daje `play=>{album_id=>17581}`, `year=>1959`; stavka sa godinom `0` nema ključ `year`; `Local` pesma ima `format`, `samplerate`, `samplesize` i `play=>{track_id=>...}`. `Service` sa lažnim `$run` nad `qobuz_*.json` daje pesmu sa `play=>{url=>'qobuz://13176083.flac'}`, album sa `play=>{item_id=>...}`, a TIDAL album `play=>{url=>'tidal://album:2178485'}`. Nedostajući podmeni ili `$cb->(undef)` daje `missing=>['qobuz']` i `$done` tačno jednom.

- [ ] **Korak 2: Pokrenuti, očekivano FAIL**

- [ ] **Korak 3: Implementirati `Local.pm`**

Komande: `artists`, `albums` (`tags:aljyeS`), `tracks` (`tags:aelyoTIJu`), `works`, `playlists`, `search:<term>`, opciono `library_id`, limit 500. Dela i plejliste su `kind=>'other'`.

- [ ] **Korak 4: Implementirati `Service.pm`**

`globalsearch items 0 50 menu:1 search:<term>`, stavka čiji je `text` naziv servisa, zatim njen podmeni, zatim paralelno liste (`0 200`). `item_id` se uzima iz `actions.go.params.item_id` ili `params.item_id`. URL iz `presetParams.favorites_url`. Ako nema klijenta, odmah `missing`.

- [ ] **Korak 5: Pokrenuti, očekivano PASS**

- [ ] **Korak 6: Commit**

```bash
git add Lyrion-MaterialSkin/src/UnifiedMusic/Source Lyrion-MaterialSkin/tests/perl
git commit -m "F1: lokalni izvor i izvori servisa"
```

---

### Zadatak 6: `Search`

**Fajlovi:**
- Kreiranje: `Lyrion-MaterialSkin/src/UnifiedMusic/Search.pm`
- Test: `Lyrion-MaterialSkin/tests/perl/40-search.t`

**Interfejsi:**
- Koristi: izvore (Zadatak 5), `group_items` (Zadatak 4).
- Proizvodi: `Search->new(sources=>{local=>$s,...}, source_order=>[...], set_timer=>$f, cancel_timer=>$f, timeout=>5)`; `->run($term,\%ctx,$done)`; `$done->(\%odgovor)` je oblik iz specifikacije, sekcija 5.
- `set_timer->($sekundi,$cb)->$handle`, `cancel_timer->($handle)`.

- [ ] **Korak 1: Napisati testove sa lažnim izvorima i tajmerom**

Slučajevi i tvrdnje:
- Sva tri izvora odgovore: odgovor ima `albums`, `tracks`, `artists`, `works`, `playlists`, `missing=>[]`; `$done` jednom; tajmer otkazan.
- Jedan izvor ćuti, lažni tajmer se okine: taj izvor je u `missing`, ostali rezultati postoje.
- Izvor odgovori **posle** tajmera: `$done` i dalje tačno jednom, odgovor se ne menja.
- Izvor vrati `missing`: vidi se u odgovoru, jedinstveno.
- `term` je `''` ili `'   '`: prazne liste, `missing=>[]`, izvori nisu pozvani.

- [ ] **Korak 2: Pokrenuti, očekivano FAIL**

- [ ] **Korak 3: Implementirati `Search.pm`**

Razvrstaj stavke po `kind` u liste odgovora; `kind=>'other'` ide u `works` ili `playlists` po polju `list` na stavci (dodaj ga u `Local` i `Service`). Polje `kind` i `list` se ne vraćaju klijentu.

- [ ] **Korak 4: Pokrenuti, očekivano PASS**

- [ ] **Korak 5: Commit**

```bash
git add Lyrion-MaterialSkin/src/UnifiedMusic Lyrion-MaterialSkin/tests/perl
git commit -m "F1: paralelna pretraga sa limitom po izvoru"
```

---

### Zadatak 7: Plugin omotač i podešavanje izvora

**Fajlovi:**
- Kreiranje: `Lyrion-MaterialSkin/src/UnifiedMusic/{Plugin.pm,Settings.pm,install.xml,strings.txt}`, `Lyrion-MaterialSkin/src/UnifiedMusic/HTML/EN/plugins/UnifiedMusic/settings/basic.html`
- Test: `Lyrion-MaterialSkin/tests/perl/50-plugin-syntax.t`

**Interfejsi:**
- Koristi: `Search`, izvore.
- Proizvodi: CLI `["unifiedmusic","search","term:...","library_id:..."]`, registrovan sa `addDispatch(['unifiedmusic','search'],[0,1,1,\&cli])`, tako da plejer nije obavezan. Rezultat je JSON iz specifikacije, sekcija 5, u ključu `result` odgovora.
- Pref `plugin.unifiedmusic:sourceOrder`, podrazumevano `local,qobuz,tidal`.

- [ ] **Korak 1: Napisati test**

Test proverava: `install.xml` je ispravan XML, `module` je `Plugins::UnifiedMusic::Plugin`, i svi `.pm` osim `Plugin.pm` i `Settings.pm` prolaze `perl -c`. (`Plugin.pm` i `Settings.pm` zavise od `Slim`, pa se proveravaju na serveru u Zadatku 9.)

- [ ] **Korak 2: Pokrenuti, očekivano FAIL**

- [ ] **Korak 3: Implementirati**

`cli` koristi `setStatusProcessing` i `setStatusDone`. `$run` koristi `Slim::Control::Request` sa `callbackParameters` za asinhrone komande. `set_timer` koristi `Slim::Utils::Timers::setTimer`. Komande izvora ne izvršavaju se bez `client` kada je komanda `globalsearch`. Stranica podešavanja menja samo `sourceOrder`.

- [ ] **Korak 4: Pokrenuti, očekivano PASS**

- [ ] **Korak 5: Commit**

```bash
git add Lyrion-MaterialSkin/src/UnifiedMusic Lyrion-MaterialSkin/tests/perl
git commit -m "F1: Lyrion plugin omotac i redosled izvora"
```

---

### Zadatak 8: Izmene forka

**Fajlovi (u repou `src/lms-material`):**
- Kreiranje: `MaterialSkin/HTML/material/html/js/unified-search.js`
- Izmena: `MaterialSkin/HTML/material/html/js/search-field.js` (`buildSearchResp`, slanje upita oko reda 196, obrada odgovora oko reda 240), lista skripti gde se navodi `search-field.js`, `MaterialSkin/install.xml`, `ChangeLog`
- Test: `Lyrion-MaterialSkin/tests/js/unified-search.test.js`

**Interfejsi:**
- Koristi: CLI iz Zadatka 7.
- Proizvodi: `unifiedToBrowseItems(resp, options)->{items, missingNote}` i `playCommandFor(version)->[komanda...]`.

- [ ] **Korak 1: Napisati testove (`node --test`)**

```js
test('grupa daje broj verzija i ikonice', () => {
  const r = unifiedToBrowseItems({albums:[g(3,['local','qobuz','tidal'])],tracks:[],artists:[],works:[],playlists:[],missing:[]});
  assert.equal(r.items[1].versions.length, 3);
  assert.deepEqual(r.items[1].sources, ['local','qobuz','tidal']);
  assert.equal(r.missingNote, undefined);
});
test('nedostajuci izvor', () => {
  assert.match(unifiedToBrowseItems(prazan(['tidal'])).missingNote, /TIDAL/);
});
test('komande pustanja', () => {
  assert.deepEqual(playCommandFor({play:{track_id:5}}), ['playlistcontrol','cmd:load','track_id:5']);
  assert.deepEqual(playCommandFor({play:{album_id:7}}), ['playlistcontrol','cmd:load','album_id:7']);
  assert.deepEqual(playCommandFor({play:{url:'qobuz://1.flac'}}), ['playlist','play','qobuz://1.flac']);
  assert.deepEqual(playCommandFor({play:{item_id:'a.1'}}), ['globalsearch','playlist','play','item_id:a.1']);
});
```

Naslovi tipova su stavke `header` u `items`, pa je prva grupa na indeksu 1.

- [ ] **Korak 2: Pokrenuti, očekivano FAIL** (`node --test Lyrion-MaterialSkin/tests/js/`)

- [ ] **Korak 3: Implementirati `unified-search.js`** (bez zavisnosti od Vue, izvoz za Node uslovno)

- [ ] **Korak 4: Povezati `search-field.js`**

Kad `can unifiedmusic search` vrati 1, šalje se jedna komanda sa ID-jem plejera i postojećim `seachReqId`. Inače ostaje postojeći tok. Stranica verzija koristi postojeći prikaz browse liste; emblem se daje preko `extid` (`qobuz:...`, `tidal:...`), za lokalno bez emblema u ovoj fazi izvor piše u podnaslovu.

- [ ] **Korak 5: Postaviti verziju `900.6.4.14` u `install.xml`** i dodati zapis u `ChangeLog`, bez uklanjanja postojećih autorskih podataka.

- [ ] **Korak 6: Pokrenuti testove i build**

Očekivano: `node --test` PASS; `mkrel.py` proizvodi ZIP, a `grep unifiedToBrowseItems` nalazi funkciju u `material.min.js`.

- [ ] **Korak 7: Commit u repou forka**

```bash
git add -A
git commit -m "Objedinjena pretraga preko plugina UnifiedMusic"
```

Testove u spoljnom repou commituj zasebno.

---

### Zadatak 9: Instalacija i provera na serveru

**Fajlovi:**
- Kreiranje: `Lyrion-MaterialSkin/tools/install-f1.sh`, `Lyrion-MaterialSkin/tools/rollback-f1.sh`, `Lyrion-MaterialSkin/docs/INSTALL-F1.md`

**Interfejsi:** Koristi: putanje iz Zadatka 0, ZIP iz Zadatka 8, plugin iz Zadatka 7.

- [ ] **Korak 1: Napisati skripte**

`install-f1.sh`: arhivira `MaterialSkin` u `/var/lib/squeezeboxserver/backup-f1-<datum>.tar.gz`, kopira plugin i fork, postavlja vlasnika `squeezeboxserver:nogroup`, restartuje `lyrionmusicserver`. `rollback-f1.sh`: vraća arhivu, uklanja `UnifiedMusic`, restartuje servis. Obe prekidaju na prvoj grešci. Komande restartuju server, što prekida reprodukciju.

- [ ] **Korak 2: Najaviti izmenu i tražiti saglasnost**

Korisniku pokaži šta se menja, uticaj restarta i komandu za vraćanje. **Bez saglasnosti ne nastavljati.**

- [ ] **Korak 3: Korisnik pokreće instalaciju**

Očekivano: `systemctl is-active lyrionmusicserver` je `active`; log nema `UnifiedMusic` greške; `can unifiedmusic search ?` vraća 1.

- [ ] **Korak 4: Provera komande**

Upiti: „Kind of Blue“, „So What“, pojam bez lokalnih rezultata, „Đorđe“, ćirilični pojam, pojam sa `:` i `/` (npr. „AC/DC: Live“), bez plejera. Meri ukupno vreme.
Očekivano: oblik iz specifikacije; „Kind of Blue“ ima grupu sa izvorima `local`, `qobuz`, `tidal`; „So What“ je na vrhu pesama; bez plejera `missing` sadrži oba servisa.

- [ ] **Korak 5: Provera u browseru**

U Material-u: red grupe, broj verzija, ikonice, klik otvara verzije, „pusti“ pušta prvu verziju (uz saglasnost, na plejeru koji odabere korisnik), promena redosleda izvora menja prvu verziju.

- [ ] **Korak 6: Regresija i simulacija**

SR11 i ostali plejeri su povezani; lista pluginova ima ostale pluginove. Simulacija izvora koji nedostaje: privremeno kratak limit u pref-u ili test na serveru, uz saglasnost.

- [ ] **Korak 7: Nezavisni pregled i zapis**

Upiši rezultate u `docs/research`, uključujući šta nije testirano i izmereno vreme.

- [ ] **Korak 8: Commit**

```bash
git add Lyrion-MaterialSkin/tools Lyrion-MaterialSkin/docs
git commit -m "F1: instalacija, vracanje i rezultati provere"
```
