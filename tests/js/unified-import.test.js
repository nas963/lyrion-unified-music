'use strict';

const test = require('node:test');
const assert = require('node:assert');
const bundle = '../../src/UnifiedMusic/HTML/EN/plugins/UnifiedMusic/material/unified-material.js';
const { importListToItems, importDetailToItems, importPlayCommand, importStatusText, importResultText } = require(bundle);

const options = { entryMenu: ['P', 'I', 'A', 'R'], removeMenu: ['R'], itemMenu: ['P', 'I', 'A'], defaultImage: '/d', getEmblem: s => ({ name: s }) };

test('lista uvoza pocinje stavkom za novi uvoz', () => {
    const items = importListToItems({ imports: [
        { id: '1', name: 'Fusion & Co', date: '2026-11-13', found: 9, total: 10, tracks: 87, playlist_id: 5 },
        { id: '2', date: '2026-11-12', error: 'None of the 3 items were found.', found: 0, total: 3 },
    ] }, options);
    assert.strictEqual(items.length, 3);
    assert.ok(items[0].importNew);
    assert.strictEqual(items[1].importId, '1');
    assert.strictEqual(items[1].rawTitle, 'Fusion & Co');
    assert.match(items[1].subtitle, /9 of 10 found/);
    assert.match(items[1].subtitle, /87 tracks/);
    assert.deepStrictEqual(items[1].menu, ['P', 'I', 'A', 'R']);
    assert.match(items[2].subtitle, /None of the 3/);
    assert.deepStrictEqual(items[2].menu, ['R']);
    assert.strictEqual(items[2].rawTitle, 'Import 2026-11-12');
});

test('uvoz u toku se vidi na prvoj stavci', () => {
    assert.match(importListToItems({ imports: [], running: 1 }, options)[0].subtitle, /running/);
});

test('detalji: nadjeni album, pesma i stavka koja nije nadjena', () => {
    const items = importDetailToItems({ import: { id: 'x' }, items: [
        { type: 'album', artist: 'Hiromi', title: 'Spark', artist_only: 1, found: { source: 'qobuz', title: 'Spark', artist: 'Hiromi', count: 9, image: '/i' } },
        { type: 'track', artist: 'Jackson Browne', title: 'Linda Paloma', found: { source: 'local', title: 'Linda Paloma', artist: 'Jackson Browne', album: 'The Pretender', count: 1 } },
        { type: 'track', artist: 'Nobody', title: 'Nothing', missing: 1 },
    ] }, options);
    assert.match(items[0].subtitle, /9 tracks/);
    assert.match(items[0].subtitle, /representative album/);
    assert.deepStrictEqual(items[0].emblem, { name: 'qobuz' });
    assert.strictEqual(items[0].importId, 'x');
    assert.strictEqual(items[0].importIndex, 0);
    assert.match(items[1].subtitle, /The Pretender/);
    assert.strictEqual(items[1].image, '/d');
    assert.ok(items[2].importMissing);
    assert.match(items[2].subtitle, /Not found/);
    assert.strictEqual(items[2].menu, undefined);
});

test('komande za pustanje uvoza', () => {
    assert.deepStrictEqual(importPlayCommand('play', 'x'), ['unifiedmusic', 'import', 'play', 'cmd:play', 'id:x']);
    assert.deepStrictEqual(importPlayCommand('add', 'x', 0), ['unifiedmusic', 'import', 'play', 'cmd:add', 'id:x', 'item:0']);
});

test('tekst napretka i rezultata', () => {
    assert.match(importStatusText({ stage: 'reading' }), /AI/);
    assert.strictEqual(importStatusText({ stage: 'searching', done: 2, total: 10, current: 'Hiromi - Spark' }), 'Searching 3 / 10: Hiromi - Spark…');
    assert.match(importResultText({ name: 'Fusion', playlist_id: 3, found: 9, total: 10, tracks: 87 }), /Playlist "Fusion" created: 9 of 10 found, 87 tracks/);
    assert.strictEqual(importResultText({ error: 'No albums or tracks were recognised in the text.' }), 'No albums or tracks were recognised in the text.');
});

test('tekst sa vise redova ide URI-kodiran', () => {
    const { importRunCommandFor } = require(bundle);
    const command = importRunCommandFor('1. A - "B"\n2. Č: D', '  Moja   lista ');
    assert.deepStrictEqual(command.slice(0, 4), ['unifiedmusic', 'import', 'run', 'encoding:uri']);
    assert.ok(!/\n/.test(command[4]));
    assert.strictEqual(decodeURIComponent(command[4].slice(5)), '1. A - "B"\n2. Č: D');
    assert.strictEqual(command[5], 'name:Moja lista');
});

test('klasika: stavovi i drugi snimak', () => {
    const items = importDetailToItems({ import: { id: 'x' }, items: [
        { type: 'track', artist: 'Howard Griffiths', title: 'Kol Nidrei', composer: 'Max Bruch', whole_work: 1,
          found: { source: 'qobuz', title: 'Kol Nidrei', artist: 'Max Bruch', count: 3, other_performer: 1 } },
    ] }, options);
    assert.match(items[0].subtitle, /3 movements/);
    assert.match(items[0].subtitle, /other recording \(wanted: Howard Griffiths\)/);
});
