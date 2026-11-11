'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { filterGenres, parseGenres, serializeGenres, toggleGenre } = require('../../src/UnifiedMusic/HTML/EN/plugins/UnifiedMusic/settings/genres.js');

const all = ['Art Rock', 'Bebop', 'Progressive Rock', 'Prog Metal', 'Rock, Pop', 'Žurka'];

test('filter trazi deo naziva bez razlike slova i dijakritike', () => {
    assert.deepStrictEqual(filterGenres(all, 'PROG', 50), ['Progressive Rock', 'Prog Metal']);
    assert.deepStrictEqual(filterGenres(all, 'zurka', 50), ['Žurka']);
    assert.deepStrictEqual(filterGenres(all, 'rock', 50), ['Art Rock', 'Progressive Rock', 'Rock, Pop']);
});

test('prazan unos prikazuje sve do granice', () => {
    assert.deepStrictEqual(filterGenres(all, '', 2), ['Art Rock', 'Bebop']);
});

test('razmak oko pojma se ignorise', () => {
    assert.deepStrictEqual(filterGenres(all, '  bebop ', 50), ['Bebop']);
});

test('zapis zanrova cuva zarez u nazivu', () => {
    const list = ['Rock, Pop', 'Bebop'];
    assert.deepStrictEqual(parseGenres(serializeGenres(list)), list);
});

test('jedan zanr sa zarezima ostaje jedan', () => {
    assert.deepStrictEqual(parseGenres('Folk, World, & Country'), ['Folk, World, & Country']);
    assert.deepStrictEqual(parseGenres(''), []);
});

test('izbor ukljucuje i iskljucuje zanr bez duplikata', () => {
    assert.deepStrictEqual(toggleGenre(['A'], 'B'), ['A', 'B']);
    assert.deepStrictEqual(toggleGenre(['A', 'B'], 'A'), ['B']);
    assert.deepStrictEqual(toggleGenre(['Bebop'], ' bebop '), []);
    assert.deepStrictEqual(toggleGenre(['A'], '   '), ['A']);
});
