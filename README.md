# Unified Music for Lyrion

Unified search, daily AI mixes and playlists imported from text lists (for example Gemini summaries of YouTube videos) for Lyrion Music Server and the standard Material Skin.

- `src/UnifiedMusic`: Lyrion plugin, including the add-on script for Material Skin.
- `packaging`: installation scripts and user instructions.
- `tests`: Perl and Node tests.
- `docs`: specifications and plans.

Install on the server with one command:

```bash
curl -fsSL https://github.com/nas963/lyrion-unified-music/releases/latest/download/get.sh | sudo bash
```

You only need it once. Lyrion then updates the plugin itself from the repository
`https://nas963.github.io/lyrion-unified-music/repo.xml`, like any other plugin.

Installation guide with requirements, setup and removal: [English](packaging/README.en.md), [Serbian](packaging/README.md).

## License

MIT, see `LICENSE`. The add-on script works with the unmodified
[Material Skin](https://github.com/CDrummond/lms-material) by Craig Drummond (MIT).
