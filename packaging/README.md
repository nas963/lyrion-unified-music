# Unified Music za Lyrion: instalacija

Plugin dodaje u Material Skin zajedničku pretragu lokalne biblioteke, Qobuz-a i TIDAL-a, dnevne miksove koje predlaže AI i plejliste napravljene iz teksta sa spiskom albuma ili pesama (npr. Gemini opis YouTube videa).

## Šta ti treba
- Lyrion Music Server 9.x na Debianu ili Ubuntu-u, instaliran kao paket (`lyrionmusicserver` servis).
- Material Skin, instaliran iz Lyrion podešavanja (Settings → Plugins).
- Za Qobuz i TIDAL: njihovi Lyrion pluginovi, prijavljeni. Nisu obavezni, plugin radi i samo sa lokalnom bibliotekom.
- Za dnevne miksove i uvoz lista: API ključ za Anthropic (`claude-haiku-5-5`) ili OpenAI (`gpt-6-luna`).

## Instalacija i ažuriranje
Na serveru, preko SSH-a, pokreni:

```bash
curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash
```

Ako javi da mu treba `curl` ili `python3`, prvo instaliraj šta fali:

```bash
sudo apt install curl python3
```

Komanda preuzima poslednje izdanje, proverava mu ispravnost i pokreće instalaciju. Ista komanda služi i za ažuriranje.

Instalacija restartuje Lyrion, pa će muzika na kratko stati. Posle toga osveži Material u browser-u.

Material Skin se ne menja: plugin u njegov `custom.js` dodaje jedan blok koji učitava dodatke. Ako nova verzija Material Skin-a promeni ono na šta se dodaci oslanjaju, Material nastavlja da radi, samo bez dodataka, dok ne izađe novo izdanje ovog paketa.

## Podešavanje
U Lyrion-u otvori Settings → Plugins → **Unified Music**. Unesi:
- kategorije miksova i žanrove za njih,
- API ključ,
- vreme noćnog pravljenja miksova.

Zatim sačuvaj. API ključ se na serveru čuva kao običan tekst.

## Korišćenje
- **Pretraga:** običnom pretragom u Material-u dobijaš rezultate iz svih izvora odjednom.
- **Miksovi:** na početnoj strani je **Your Daily Mixes**. Stariji dani su u meniju sa tri tačke, pod **Previous days**.
- **Uvoz liste:** na početnoj strani je **Imported lists** → **Import list from text**. Nalepi tekst sa spiskom (npr. ono što Gemini napiše za YouTube video). AI prepoznaje albume i pesme; za izvođača bez navedenog albuma bira reprezentativni album. Pre pretrage vidiš prepoznate stavke, možeš da izmeniš predloženi naziv ili izabereš postojeću plejlistu koju treba dopuniti. Sve se traži po redosledu izvora iz podešavanja. U istoj listi se vidi šta je nađeno i gde, a šta nije; lupa u gornjoj traci filtrira uvezene liste po nazivu, izvođačima i naslovima.

## Uklanjanje

```bash
curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash -s uninstall
```

Uklanja plugin i njegov blok iz `custom.js`. Miksovi i podešavanja ostaju na disku.

## Poznato ograničenje
Neke Qobuz hi-res pesme ne puštaju se preko Qobuz plugina na svim plejerima. Ako se to desi, u podešavanjima Qobuz plugina izaberi `FLAC 16 bits / 44.1 kHz`.

Material Skin je delo Craiga Drummonda. Qobuz i TIDAL se koriste isključivo kroz njihove postojeće Lyrion pluginove.
