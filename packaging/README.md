# Unified Music za Lyrion: instalacija

Objedinjena pretraga lokalne biblioteke, Qobuza i TIDAL-a, i dnevni AI miksovi u Material Skin-u.

## Uslovi
- Lyrion Music Server 9.x na Debian ili Ubuntu sistemu, instaliran paketom (`lyrionmusicserver` servis).
- Instaliran originalni Material Skin plugin iz Lyrion podešavanja.
- Za servise: instalirani i prijavljeni Qobuz i TIDAL pluginovi.
- Za miksove: API ključ za `claude-haiku-5-5` (Anthropic) ili `gpt-6-luna` (OpenAI).

## Instalacija i ažuriranje
Na serveru pokreni jednu komandu:

```bash
curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash
```

Komanda preuzima poslednje izdanje, proverava mu ispravnost i pokreće instalaciju. Isto važi i za ažuriranje. Radi samo dok je repo javan.

Instalacija postavlja plugin i restartuje Lyrion, što prekida reprodukciju. Material Skin se ne menja: plugin u njegov `custom.js` dodaje jedan blok koji učitava naše dodatke.

Ako nova verzija Material Skin-a promeni ono na šta se dodaci oslanjaju, Material nastavlja da radi, samo bez dodataka, dok ne izađe novo izdanje ovog paketa.

## Podešavanje
U Lyrion podešavanjima pluginova otvori **Unified Music**: unesi kategorije, API ključ i vreme noćnog pokretanja, pa sačuvaj. API ključevi se čuvaju na serveru kao običan tekst.

## Uklanjanje

```bash
curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash -s uninstall
```

Uklanja plugin i njegov blok iz `custom.js`. Miksovi i podešavanja ostaju na disku.

## Poznato ograničenje
Neke Qobuz hi-res pesme ne puštaju se preko Qobuz plugina na svim plejerima. Ako se to desi, u podešavanjima Qobuz plugina izaberi `FLAC 16 bits / 44.1 kHz`.

Material Skin je delo Craiga Drummonda. Qobuz i TIDAL se koriste isključivo kroz njihove postojeće Lyrion pluginove.
