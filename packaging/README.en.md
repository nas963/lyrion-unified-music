# Unified Music for Lyrion: installation

The plugin adds to Material Skin a unified search across your local library, Qobuz and TIDAL, daily mixes suggested by AI, and playlists built from a text listing albums or songs (for example Gemini's summary of a YouTube video).

## Requirements
- Lyrion Music Server 9.x on Debian or Ubuntu, installed as a package (`lyrionmusicserver` service).
- Material Skin, installed from the Lyrion settings (Settings → Plugins).
- For Qobuz and TIDAL: their Lyrion plugins, signed in. They are optional; the plugin also works with the local library only.
- For daily mixes and list import: an API key for Anthropic (`claude-haiku-5-5`) or OpenAI (`gpt-6-luna`).

## Install and update
On the server, over SSH, run:

```bash
curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash
```

If it reports that `curl` or `python3` is missing, install it first:

```bash
sudo apt install curl python3
```

The command downloads the latest release, verifies it and runs the installer. The same command updates an existing installation.

Installing restarts Lyrion, so playback stops briefly. Afterwards, reload Material in your browser.

Material Skin itself is not modified: the plugin adds one block to its `custom.js` that loads the add-ons. If a new Material Skin version changes something the add-ons rely on, Material keeps working without the add-ons until a new release of this package is out.

## Setup
In Lyrion, open Settings → Plugins → **Unified Music** and enter:
- mix categories and their genres,
- your API key,
- the time for the nightly mix run.

Then save. The API key is stored on the server as plain text.

## Usage
- **Search:** the normal search in Material returns results from all sources at once.
- **Mixes:** **Your Daily Mixes** is on the home screen. Earlier days are in the three-dot menu, under **Previous days**.
- **List import:** on the home screen open **Imported lists** → **Import list from text** and paste a text with a list (for example what Gemini writes for a YouTube video). AI recognises albums and songs; for an artist without a named album it picks a representative album. Before the search you see the recognised entries, can change the suggested name or pick an existing playlist to extend. Everything is searched in the source order from the settings. The same list shows what was found where, and what was not; the magnifier in the top bar filters the imported lists by name, artists and titles.

## Uninstall

```bash
curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash -s uninstall
```

Removes the plugin and its block from `custom.js`. Mixes and settings stay on disk.

## Known issue
Some Qobuz hi-res tracks do not play through the Qobuz plugin on every player. If that happens, choose `FLAC 16 bits / 44.1 kHz` in the Qobuz plugin settings.

Material Skin is the work of Craig Drummond. Qobuz and TIDAL are used only through their existing Lyrion plugins.
