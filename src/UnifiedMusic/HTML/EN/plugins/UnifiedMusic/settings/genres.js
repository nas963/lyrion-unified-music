/* Izbor zanrova u podesavanjima: pretraga, lista sa kvacicama i izabrani zanrovi sa x. */
(function () {
	'use strict';

	var LIST_LIMIT = 100;

	function fold(text) {
		return String(text).trim().toLowerCase().replace(/đ/g, 'dj').normalize('NFD').replace(/[̀-ͯ]/g, '');
	}

	function filterGenres(all, term, limit) {
		var wanted = fold(term);
		return all.filter(function (genre) {
			return fold(genre).indexOf(wanted) !== -1;
		}).slice(0, limit);
	}

	function parseGenres(value) {
		if (!value) {
			return [];
		}
		return value.split('\n').map(function (genre) { return genre.trim(); }).filter(function (genre) { return genre.length > 0; });
	}

	function serializeGenres(list) {
		return list.join('\n');
	}

	function toggleGenre(list, genre) {
		var name = String(genre).trim();
		if (name.length === 0) {
			return list;
		}
		var key = fold(name);
		var kept = list.filter(function (item) { return fold(item) !== key; });
		return kept.length === list.length ? list.concat([name]) : kept;
	}

	function addStyles() {
		var style = document.createElement('style');
		style.textContent =
			'.umRow{display:flex;gap:8px;align-items:flex-start;margin-bottom:6px}' +
			'.umGenres{position:relative;flex:1;min-width:280px;border-bottom:1px solid currentColor;padding:2px 0;display:flex;flex-wrap:wrap;gap:4px;align-items:center}' +
			'.umChip{display:inline-flex;align-items:center;gap:4px;border:1px solid currentColor;border-radius:12px;padding:1px 8px;font-size:13px}' +
			'.umChip button{all:unset;cursor:pointer;font-weight:bold;padding:0 2px}' +
			'.umGenreInput{flex:1;min-width:120px;background:transparent;border:0;outline:0;color:inherit;font:inherit;padding:3px}' +
			'.umGenreList{position:absolute;left:0;right:0;top:100%;z-index:1000;max-height:240px;overflow:auto;border:1px solid currentColor;padding:4px}' +
			'.umGenreList label{display:flex;gap:6px;align-items:center;cursor:pointer;padding:2px}' +
			'.umGenreNone{padding:4px;opacity:0.7}';
		document.head.appendChild(style);
	}

	function pageBackground() {
		var color = window.getComputedStyle(document.body).backgroundColor;
		return !color || color === 'transparent' || color === 'rgba(0, 0, 0, 0)' ? '#333' : color;
	}

	function buildControl(box, allGenres) {
		var hidden = box.querySelector('input[type=hidden]');
		var selected = parseGenres(hidden.value);
		var chips = document.createElement('span');
		chips.style.display = 'contents';
		var input = document.createElement('input');
		input.type = 'text';
		input.className = 'umGenreInput';
		input.placeholder = 'Search genres';
		input.autocomplete = 'off';
		var list = document.createElement('div');
		list.className = 'umGenreList';
		list.style.display = 'none';
		list.style.background = pageBackground();
		box.appendChild(chips);
		box.appendChild(input);
		box.appendChild(list);

		function isSelected(genre) {
			return selected.some(function (item) { return fold(item) === fold(genre); });
		}

		function change(genre) {
			selected = toggleGenre(selected, genre);
			hidden.value = serializeGenres(selected);
			renderChips();
			renderList();
		}

		function renderChips() {
			chips.textContent = '';
			selected.forEach(function (genre) {
				var chip = document.createElement('span');
				chip.className = 'umChip';
				var label = document.createElement('span');
				label.textContent = genre;
				var remove = document.createElement('button');
				remove.type = 'button';
				remove.textContent = '×';
				remove.title = 'Remove';
				remove.addEventListener('click', function () { change(genre); });
				chip.appendChild(label);
				chip.appendChild(remove);
				chips.appendChild(chip);
			});
		}

		function renderList() {
			list.textContent = '';
			var matches = filterGenres(allGenres, input.value, LIST_LIMIT);
			matches.forEach(function (genre) {
				var row = document.createElement('label');
				var check = document.createElement('input');
				check.type = 'checkbox';
				check.checked = isSelected(genre);
				check.addEventListener('change', function () { change(genre); });
				var text = document.createElement('span');
				text.textContent = genre;
				row.appendChild(check);
				row.appendChild(text);
				list.appendChild(row);
			});
			if (matches.length === 0) {
				var none = document.createElement('div');
				none.className = 'umGenreNone';
				none.textContent = 'No matching genre. Press Enter to add it.';
				list.appendChild(none);
			}
		}

		function open() {
			renderList();
			list.style.display = 'block';
		}

		input.addEventListener('focus', open);
		input.addEventListener('input', open);
		input.addEventListener('keydown', function (event) {
			if (event.key === 'Enter') {
				event.preventDefault();
				if (input.value.trim().length > 0 && !isSelected(input.value)) {
					change(input.value);
				}
				input.value = '';
				renderList();
			} else if (event.key === 'Backspace' && input.value.length === 0 && selected.length > 0) {
				change(selected[selected.length - 1]);
			} else if (event.key === 'Escape') {
				list.style.display = 'none';
			}
		});
		document.addEventListener('mousedown', function (event) {
			if (!box.contains(event.target)) {
				list.style.display = 'none';
			}
		});

		renderChips();
	}

	function init() {
		addStyles();
		fetch('/jsonrpc.js', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ id: 1, method: 'slim.request', params: ['', ['genres', 0, 10000]] })
		}).then(function (response) { return response.json(); }).catch(function () {
			return { result: {} };
		}).then(function (data) {
			var genres = (data.result.genres_loop || []).map(function (row) { return row.genre; });
			document.querySelectorAll('.umGenres').forEach(function (box) { buildControl(box, genres); });
		});
	}

	if (typeof module !== 'undefined') {
		module.exports = { filterGenres: filterGenres, parseGenres: parseGenres, serializeGenres: serializeGenres, toggleGenre: toggleGenre };
	} else {
		window.UnifiedGenres = { init: init };
	}
})();
