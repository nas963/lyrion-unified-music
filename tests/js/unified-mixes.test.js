'use strict';

const test = require('node:test');
const assert = require('node:assert');
const bundle = '../../src/UnifiedMusic/HTML/EN/plugins/UnifiedMusic/material/unified-material.js';
const { mixCategoriesToItems, mixToItems, mixActionCommand, trackActionCommand } = require(bundle);

const options = { menu: ['P', 'I', 'A'], trackMenu: ['P', 'I', 'A'], getEmblem: s => ({ name: s }) };

test('red kategorije ima radnje i broj pesama', () => {
    const items = mixCategoriesToItems({ categories: [{ name: 'Jazz', date: '2026-11-11', count: 2, stale: 0 }] }, options);
    assert.strictEqual(items[0].title, 'Jazz');
    assert.strictEqual(items[0].mixCategory, 'Jazz');
    assert.deepStrictEqual(items[0].menu, ['P', 'I', 'A']);
    assert.match(items[0].subtitle, /2 tracks/);
    assert.doesNotMatch(items[0].subtitle, /2026/);
});

test('zastareo miks ima datum, a kategorija bez miksa nema radnje', () => {
    const items = mixCategoriesToItems({ categories: [
        { name: 'Rock', date: '2026-11-10', count: 1, stale: 1 },
        { name: 'Nov', date: null, count: 0, stale: 0 },
    ] }, options);
    assert.match(items[0].subtitle, /2026-11-10/);
    assert.strictEqual(items[1].menu, undefined);
    assert.match(items[1].subtitle, /No mix yet/);
});

test('pesme imaju emblem izvora i url', () => {
    const items = mixToItems({ date: '2026-11-11', tracks: [{ title: 'T', artist: 'A', album: 'B', source: 'qobuz', url: 'qobuz://1.flac', image: '/x' }], previous: [] }, 'Jazz', options);
    assert.strictEqual(items.length, 1);
    assert.strictEqual(items[0].mixTrack, 'qobuz://1.flac');
    assert.deepStrictEqual(items[0].emblem, { name: 'qobuz' });
    assert.match(items[0].subtitle, /A/);
    assert.match(items[0].subtitle, /B/);
});

test('pesma bez omota dobija genericku sliku', () => {
    const resp = { date: 'd', tracks: [{ title: 'T', source: 'local', url: 'u' }, { title: 'S', source: 'local', url: 'v', image: '/x' }], previous: [] };
    const items = mixToItems(resp, 'Jazz', Object.assign({ defaultImage: '/default' }, options));
    assert.strictEqual(items[0].image, '/default');
    assert.strictEqual(items[1].image, '/x');
});

test('Previous days otvara spisak dana', () => {
    const items = mixToItems({ date: '2026-11-11', tracks: [], previous: ['2026-11-10', '2026-11-09'] }, 'Jazz', options);
    assert.strictEqual(items.length, 1);
    assert.strictEqual(items[0].title, 'Previous days');
    assert.deepStrictEqual(items[0].mixPrevious, { category: 'Jazz', dates: ['2026-11-10', '2026-11-09'] });
});

test('kategorija sa starijim danima ima Previous days u meniju', () => {
    const withPrevious = Object.assign({ previousAction: 'H' }, options);
    const items = mixCategoriesToItems({ categories: [
        { name: 'Jazz', date: '2026-11-11', count: 2, stale: 0, previous: ['2026-11-10'] },
        { name: 'Rock', date: '2026-11-11', count: 1, stale: 0, previous: [] },
    ] }, withPrevious);
    assert.deepStrictEqual(items[0].menu, ['P', 'I', 'A', 'H']);
    assert.deepStrictEqual(items[0].mixPreviousDates, ['2026-11-10']);
    assert.deepStrictEqual(items[1].menu, ['P', 'I', 'A']);
    assert.strictEqual(items[1].mixPreviousDates, undefined);
    assert.deepStrictEqual(options.menu, ['P', 'I', 'A']);
});

test('meni liste miksa ima Previous days samo kad postoje stariji dani', () => {
    const { mixListMenuActions } = require(bundle);
    assert.deepStrictEqual(mixListMenuActions(['2026-11-10'], 'H'), [{ action: 'H', weight: 6 }]);
    assert.deepStrictEqual(mixListMenuActions([], 'H'), []);
    assert.deepStrictEqual(mixListMenuActions(undefined, 'H'), []);
});

test('komande za miks', () => {
    const item = { mixCategory: 'Jazz', mixDate: '2026-11-10' };
    assert.deepStrictEqual(mixActionCommand('play', item), ['unifiedmusic', 'mix', 'play', 'cmd:play', 'category:Jazz', 'date:2026-11-10']);
    assert.deepStrictEqual(mixActionCommand('insert', { mixCategory: 'Rock & Roll' }), ['unifiedmusic', 'mix', 'play', 'cmd:insert', 'category:Rock & Roll']);
    assert.deepStrictEqual(trackActionCommand('add', 'tidal://1.flc'), ['playlist', 'add', 'tidal://1.flc']);
});

test('naslov sa & ostaje citljiv u obe vrste listi', () => {
    const items = mixCategoriesToItems({ categories: [{ name: 'New Age & Ambient', date: null, count: 0, stale: 0 }] }, options);
    assert.strictEqual(items[0].title, 'New Age & Ambient');
});

test('Save i Add su na listi pesama, a ne na kategoriji', () => {
    const { mixRowMenu, mixToolbarActions } = require(bundle);
    const a = { play: 'P', insert: 'I', add: 'A', addToPlaylist: 'L', save: 'S' };
    assert.deepStrictEqual(mixRowMenu(a), ['P', 'I', 'A']);
    assert.deepStrictEqual(mixToolbarActions(a), ['L', 'S', 'A', 'I', 'P']);
});

test('predlozeno ime plejliste ima datum', () => {
    const { mixSaveName } = require(bundle);
    assert.strictEqual(mixSaveName('Prog', '2026-11-10'), 'Prog 2026-11-10');
    assert.strictEqual(mixSaveName('Prog', undefined), 'Prog');
});

test('postojeci naziv plejliste daje jasnu poruku', () => {
    const { mixSaveMessage } = require(bundle);
    assert.match(mixSaveMessage({ exists: 1 }, 'Prog'), /already exists/);
    assert.strictEqual(mixSaveMessage({ playlist_id: 5 }, 'Prog'), 'Prog');
});

test('neuspelo cuvanje i ime za prethodni dan', () => {
    const { mixSaveMessage, mixSuggestedName } = require(bundle);
    assert.match(mixSaveMessage({ failed: 1 }, 'Prog'), /could not/i);
    assert.strictEqual(mixSuggestedName({ mixCategory: 'Prog', mixDate: '2026-11-09', rawTitle: '2026-11-09' }), 'Prog 2026-11-09');
    assert.strictEqual(mixSuggestedName({ mixCategory: 'Prog', mixShownDate: '2026-11-10', rawTitle: 'Prog' }), 'Prog 2026-11-10');
});

test('tekst iz naziva se escape-uje', () => {
    const items = mixCategoriesToItems({ categories: [{ name: '<b>', date: null, count: 0, stale: 0 }] }, options);
    assert.strictEqual(items[0].title, '&lt;b&gt;');
    assert.strictEqual(items[0].mixCategory, '<b>');
});
