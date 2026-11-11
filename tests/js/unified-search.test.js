'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { unifiedToBrowseItems, unifiedVersionItems, playCommandFor, unifiedKeepCurrentSearch } = require('../../src/UnifiedMusic/HTML/EN/plugins/UnifiedMusic/material/unified-material.js');

function version(source, extra) {
    return Object.assign({ source: source, title: 'Kind of Blue', artist: 'Miles Davis', play: { item_id: 'x' } }, extra || {});
}
function group(count, sources) {
    const versions = [];
    for (let i = 0; i < count; ++i) {
        versions.push(version(sources[i % sources.length]));
    }
    return { title: 'Kind of Blue', artist: 'Miles Davis', sources: sources, versions: versions };
}
function empty(missing, albums) {
    return { albums: albums || [], tracks: [], artists: [], works: [], playlists: [], missing: missing || [] };
}

test('grupa daje broj verzija i izvore', () => {
    const r = unifiedToBrowseItems(empty([], [group(3, ['local', 'qobuz', 'tidal'])]));
    assert.strictEqual(r.items[0].header, true);
    assert.strictEqual(r.items[1].versions.length, 3);
    assert.deepStrictEqual(r.items[1].sources, ['local', 'qobuz', 'tidal']);
    assert.match(r.items[1].subtitle, /3 versions/);
    assert.strictEqual(r.items[1].unified, true);
    assert.strictEqual(r.missingNote, undefined);
});

test('jedna verzija koristi jedninu', () => {
    const r = unifiedToBrowseItems(empty([], [group(1, ['qobuz'])]));
    assert.match(r.items[1].subtitle, /1 version\b/);
});

test('prazni tipovi nemaju zaglavlje', () => {
    assert.deepStrictEqual(unifiedToBrowseItems(empty()).items, []);
});

test('zaglavlja idu redom i imaju jedinstven id', () => {
    const resp = empty([], [group(1, ['local'])]);
    resp.tracks = [group(2, ['qobuz'])];
    const items = unifiedToBrowseItems(resp).items;
    assert.deepStrictEqual(items.filter(i => i.header).map(i => i.title), ['Albums (1)', 'Tracks (1)']);
    assert.strictEqual(new Set(items.map(i => i.id)).size, items.length);
});

test('nedostajuci izvor', () => {
    assert.match(unifiedToBrowseItems(empty(['tidal'])).missingNote, /TIDAL/);
    assert.match(unifiedToBrowseItems(empty(['local', 'qobuz'])).missingNote, /Local, Qobuz/);
});

test('ikonice izvora u podnaslovu preko getEmblem', () => {
    const options = { emblemUrl: s => '/e/' + s, emblemBackground: () => '#123' };
    const r = unifiedToBrowseItems(empty([], [group(2, ['local', 'qobuz'])]), options);
    assert.match(r.items[1].subtitle, /src="\/e\/qobuz"/);
    assert.match(r.items[1].subtitle, /Local/);
});

test('tekst iz tagova se escape-uje', () => {
    const g = group(1, ['local']);
    g.title = '<b>A&B';
    g.artist = '<i>C';
    const row = unifiedToBrowseItems(empty([], [g])).items[1];
    assert.strictEqual(row.title, '&lt;b&gt;A&B');
    assert.match(row.subtitle, /&lt;i&gt;C/);
});

test('duga sekcija se skracuje, sve stavke ostaju u allItems', () => {
    const groups = [];
    for (let i = 0; i < 5; ++i) {
        groups.push(group(1, ['qobuz']));
    }
    const resp = empty([], groups);
    resp.tracks = [group(1, ['local'])];
    const items = unifiedToBrowseItems(resp, { initialLimit: 2 }).items;
    assert.strictEqual(items[0].title, 'Albums (2 / 5)');
    assert.strictEqual(items[0].allItems.length, 5);
    assert.strictEqual(items[3].header, true);
    assert.strictEqual(items[3].title, 'Tracks (1)');
    assert.strictEqual(items[3].allItems, undefined);
    assert.strictEqual(items.length, 5);
});

test('lokalni izvor ima emblem foldera', () => {
    const fs = require('node:fs');
    const path = require('node:path');
    assert.strictEqual(require('../../src/UnifiedMusic/HTML/EN/plugins/UnifiedMusic/material/unified-material.js').UNIFIED_LOCAL_EMBLEM.name, 'folder-local');
    assert.ok(fs.existsSync(path.join(__dirname, '../../src/UnifiedMusic/HTML/EN/plugins/UnifiedMusic/material/folder-local.svg')));
});

test('verzija sa emblemom nema tekst izvora', () => {
    const v = [version('local', { year: 1959 })];
    const withEmblem = unifiedVersionItems({ versions: v }, { getEmblem: () => ({ name: 'x' }) });
    assert.doesNotMatch(withEmblem[0].subtitle, /Local/);
    assert.match(unifiedVersionItems({ versions: v })[0].subtitle, /Local/);
});

test('grupa i verzija bez omota dobijaju genericku sliku', () => {
    const g = group(1, ['local']);
    const opt = { defaultImage: '/default' };
    assert.strictEqual(unifiedToBrowseItems(empty([], [g]), opt).items[1].image, '/default');
    assert.strictEqual(unifiedVersionItems(g, opt)[0].image, '/default');
});

test('isti pojam ne ponistava pretragu u toku', () => {
    assert.strictEqual(unifiedKeepCurrentSearch('Kind of Blue', 'Kind of Blue', true), true);
    assert.strictEqual(unifiedKeepCurrentSearch('  Kind   of Blue ', 'Kind of Blue', true), true);
});

test('novi pojam ili zavrsena pretraga idu dalje', () => {
    assert.strictEqual(unifiedKeepCurrentSearch('Kind', 'Kind of Blue', true), false);
    assert.strictEqual(unifiedKeepCurrentSearch('Kind of Blue', 'Kind of Blue', false), false);
    assert.strictEqual(unifiedKeepCurrentSearch(undefined, 'Kind of Blue', true), false);
});

test('komande pustanja', () => {
    assert.deepStrictEqual(playCommandFor({ play: { track_id: 5 } }), ['playlistcontrol', 'cmd:load', 'track_id:5']);
    assert.deepStrictEqual(playCommandFor({ play: { album_id: 7 } }), ['playlistcontrol', 'cmd:load', 'album_id:7']);
    assert.deepStrictEqual(playCommandFor({ play: { playlist_id: 9 } }), ['playlistcontrol', 'cmd:load', 'playlist_id:9']);
    assert.deepStrictEqual(playCommandFor({ play: { work_id: 3 } }), ['playlistcontrol', 'cmd:load', 'work_id:3']);
    assert.deepStrictEqual(playCommandFor({ play: { url: 'qobuz://1.flac' } }), ['playlist', 'play', 'qobuz://1.flac']);
    assert.deepStrictEqual(playCommandFor({ play: { item_id: 'a.1' } }), ['globalsearch', 'playlist', 'play', 'item_id:a.1']);
});

test('verzije imaju izvor, godinu i format', () => {
    const items = unifiedVersionItems({ versions: [
        version('local', { year: 1959, format: 'dsf', samplerate: 2822400, samplesize: 1, album: 'Boks' }),
        version('qobuz', { year: 1997 }),
    ] });
    assert.strictEqual(items.length, 2);
    assert.match(items[0].subtitle, /Local/);
    assert.match(items[0].subtitle, /1959/);
    assert.match(items[0].subtitle, /DSF/);
    assert.match(items[0].subtitle, /Boks/);
    assert.strictEqual(items[0].unifiedVersion.source, 'local');
    assert.match(items[1].subtitle, /Qobuz/);
    assert.notStrictEqual(items[0].id, items[1].id);
});

test('verzije izvodjaca otvaraju izvodjaca umesto pustanja', () => {
    const items = unifiedVersionItems({ kind: 'artist', versions: [
        { source: 'local', title: 'Miles Davis', play: { artist_id: 11 } },
        { source: 'tidal', title: 'Miles Davis', play: { item_id: 'z.1' } },
    ] });
    assert.strictEqual(items[0].unifiedVersion, undefined);
    assert.deepStrictEqual(items[0].command, ['albums']);
    assert.ok(items[0].params.includes('artist_id:11'));
    assert.deepStrictEqual(items[1].command, ['globalsearch', 'items']);
    assert.ok(items[1].params.includes('item_id:z.1'));
    assert.ok(items[1].params.includes('menu:1'));
});

test('izvodjac u listi nosi tip za stranicu verzija', () => {
    const resp = empty();
    resp.artists = [{ title: 'Miles Davis', sources: ['local'], versions: [{ source: 'local', title: 'Miles Davis', play: { artist_id: 1 } }] }];
    assert.strictEqual(unifiedToBrowseItems(resp).items[1].kind, 'artist');
});
