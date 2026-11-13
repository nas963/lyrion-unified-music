/**
 * Unified Music: dodaci za originalni Material Skin.
 * Ucitava ih custom.js koji postavlja plugin UnifiedMusic.
 */
'use strict';

const UNIFIED_SOURCE_NAMES = { local: "Local", qobuz: "Qobuz", tidal: "TIDAL" };
const UNIFIED_LISTS = [
    { key: "albums", kind: "album", title: "Albums", icon: "album" },
    { key: "artists", kind: "artist", title: "Artists", svg: "artist" },
    { key: "works", kind: "work", title: "Works", svg: "classical-work" },
    { key: "tracks", kind: "track", title: "Tracks", icon: "music_note" },
    { key: "playlists", kind: "playlist", title: "Playlists", icon: "list" }
];
const UNIFIED_SEPARATOR = " • ";

function unifiedEscape(text) {
    return String(undefined==text ? "" : text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function unifiedEscapeTitle(text) {
    return String(undefined==text ? "" : text).replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function unifiedSourceName(source) {
    return UNIFIED_SOURCE_NAMES[source] || source;
}

function unifiedSourceHtml(source, options) {
    let url = options.emblemUrl ? options.emblemUrl(source) : undefined;
    if (undefined==url) {
        return unifiedEscape(unifiedSourceName(source));
    }
    let bgnd = options.emblemBackground ? options.emblemBackground(source) : "transparent";
    return '<span title="' + unifiedEscape(unifiedSourceName(source)) + '" style="display:inline-block;width:14px;height:14px;border-radius:2px;vertical-align:text-bottom;margin-right:3px;background:' + bgnd + '">' +
           '<img src="' + url + '" style="width:14px;height:14px"></span>';
}

function unifiedImage(version, options) {
    if (undefined==version.image) {
        return options.defaultImage;
    }
    return version.image.startsWith("/music/") && options.localImageSuffix ? version.image + options.localImageSuffix : version.image;
}

function unifiedFirstImage(group, options) {
    for (let i=0, len=group.versions.length; i<len; ++i) {
        if (undefined!=group.versions[i].image) {
            return unifiedImage(group.versions[i], options);
        }
    }
    return options.defaultImage;
}

function unifiedToBrowseItems(resp, options) {
    options = options || {};
    let items = [];
    for (let l=0; l<UNIFIED_LISTS.length; ++l) {
        let list = UNIFIED_LISTS[l];
        let groups = resp[list.key] || [];
        if (groups.length<1) {
            continue;
        }
        let rows = [];
        let clamped = undefined!=options.initialLimit && groups.length>options.initialLimit;
        items.push({ id: "unified." + list.kind, title: list.title + " (" + (clamped ? options.initialLimit + " / " : "") + groups.length + ")", header: true, hidesub: true,
                     icon: list.icon, svg: list.svg, useList: true, allItems: clamped ? rows : undefined, subtitle: groups.length + " items" });
        for (let g=0; g<groups.length; ++g) {
            let group = groups[g];
            let count = group.versions.length;
            let parts = [];
            if (undefined!=group.artist) {
                parts.push(unifiedEscape(group.artist));
            }
            parts.push(count + (1==count ? " version" : " versions"));
            parts.push(group.sources.map(function (s) { return unifiedSourceHtml(s, options); }).join(" "));
            rows.push({ id: "unified." + list.kind + "." + g, title: unifiedEscapeTitle(group.title), rawTitle: group.title,
                         subtitle: parts.join(UNIFIED_SEPARATOR), image: unifiedFirstImage(group, options), unified: true, kind: list.kind,
                         versions: group.versions, sources: group.sources,
                         menu: undefined==options.playAction || "artist"==list.kind ? undefined : [options.playAction] });
        }
        items = items.concat(clamped ? rows.slice(0, options.initialLimit) : rows);
    }
    let missing = resp.missing || [];
    return { items: items, missingNote: missing.length>0 ? "Not available: " + missing.map(unifiedSourceName).join(", ") : undefined };
}

function unifiedFormat(version) {
    let parts = [];
    if (undefined!=version.format) {
        parts.push(version.format.toUpperCase());
    }
    if (undefined!=version.samplerate) {
        parts.push((version.samplerate / 1000) + " kHz");
    }
    if (undefined!=version.samplesize && version.samplesize>1) {
        parts.push(version.samplesize + " bit");
    }
    return parts.join(" ");
}

function unifiedVersionItems(group, options) {
    options = options || {};
    let id = group.id || "unified";
    return group.versions.map(function (version, index) {
        let emblem = options.getEmblem ? options.getEmblem(version.source) : undefined;
        let parts = undefined==emblem ? [unifiedSourceName(version.source)] : [];
        if (undefined!=version.artist) {
            parts.push(unifiedEscape(version.artist));
        }
        if (undefined!=version.album) {
            parts.push(unifiedEscape(version.album));
        }
        if (undefined!=version.year) {
            parts.push(version.year);
        }
        let format = unifiedFormat(version);
        if (format.length>0) {
            parts.push(format);
        }
        let item = { id: id + ".v" + index, title: unifiedEscapeTitle(version.title), subtitle: parts.join(UNIFIED_SEPARATOR),
                     image: unifiedImage(version, options), emblem: options.getEmblem ? options.getEmblem(version.source) : undefined };
        if ("artist"==group.kind) {
            item.type = "group";
            if (undefined!=version.play.artist_id) {
                item.command = ["albums"];
                item.params = ["artist_id:" + version.play.artist_id];
                if (undefined!=options.albumTags) {
                    item.params.push(options.albumTags);
                }
            } else {
                item.command = ["globalsearch", "items"];
                item.params = ["menu:1", "item_id:" + version.play.item_id];
            }
        } else {
            item.unifiedVersion = version;
            item.menu = undefined==options.playAction ? undefined : [options.playAction];
        }
        return item;
    });
}

function playCommandFor(version) {
    let play = version.play;
    let local = ["track_id", "album_id", "playlist_id", "work_id"];
    for (let i=0; i<local.length; ++i) {
        if (undefined!=play[local[i]]) {
            return ["playlistcontrol", "cmd:load", local[i] + ":" + play[local[i]]];
        }
    }
    if (undefined!=play.url) {
        return ["playlist", "play", play.url];
    }
    return ["globalsearch", "playlist", "play", "item_id:" + play.item_id];
}

/* Ispod je veza sa Material-om; koristi njegove globalne objekte. */

function unifiedBrowserOptions() {
    function emblemFor(source) {
        return getEmblem(source + ":");
    }
    return {
        playAction: PLAY_ACTION,
        localImageSuffix: LMS_IMAGE_SIZE,
        defaultImage: DEFAULT_COVER,
        initialLimit: LMS_INITIAL_SEARCH_RESULTS,
        albumTags: ALBUM_TAGS,
        getEmblem: emblemFor,
        emblemUrl: function (source) {
            let emblem = emblemFor(source);
            return undefined==emblem ? undefined : "/material/svg/" + emblem.name + "?c=" + emblem.color.substr(1) + "&r=" + LMS_MATERIAL_REVISION;
        },
        emblemBackground: function (source) {
            let emblem = emblemFor(source);
            return undefined==emblem ? "transparent" : emblem.bgnd;
        }
    };
}

function unifiedOpenVersions(view, item) {
    let items = unifiedVersionItems(item, unifiedBrowserOptions());
    browseHandleListResponse(view, { cancache: false, title: item.rawTitle, id: item.id, type: "group" }, { command: [], params: [] },
                             { items: items, subtitle: items.length + (1==items.length ? " version" : " versions"), baseActions: [], canUseGrid: false, jumplist: [], allowHoverBtns: true });
}

// Pretraga traje duze od odlaganja unosa, pa isti pojam ne sme da je ponisti.
function unifiedKeepCurrentSearch(term, currentStr, searching) {
    return !!searching && undefined!=term && term.trim().replace(/\s+/g, " ")==currentStr;
}

function unifiedPlay(view, version) {
    if (!view.$store.state.player) {
        bus.$emit('showError', undefined, i18n("No Player"));
        return;
    }
    lmsCommand(view.playerId(), playCommandFor(version)).then(({data}) => {
        bus.$emit('refreshStatus');
    }).catch(err => {
        logError(err);
        bus.$emit('showError', err);
    });
}

function unifiedHandleAction(view, act, item) {
    if (PLAY_ACTION==act) {
        unifiedPlay(view, item.unifiedVersion ? item.unifiedVersion : item.versions[0]);
    }
}

const MIX_SEPARATOR = " • ";

function mixCategoriesToItems(resp, options) {
    options = options || {};
    return (resp.categories || []).map(function (row, index) {
        let hasMix = undefined!=row.date && null!=row.date;
        let subtitle = !hasMix ? "No mix yet" : row.count + (1==row.count ? " track" : " tracks");
        if (hasMix && row.stale) {
            subtitle += MIX_SEPARATOR + row.date;
        }
        let hasPrevious = hasMix && row.previous && row.previous.length>0 && undefined!=options.previousAction;
        let item = { id: "mix.cat." + index, title: unifiedEscapeTitle(row.name), rawTitle: row.name, subtitle: subtitle, mixCategory: row.name,
                     icon: "queue_music", menu: !hasMix ? undefined : hasPrevious ? options.menu.concat([options.previousAction]) : options.menu };
        if (hasPrevious) {
            item.mixPreviousDates = row.previous;
        }
        return item;
    });
}

function mixToItems(resp, category, options) {
    options = options || {};
    let items = (resp.tracks || []).map(function (track, index) {
        let parts = [];
        if (undefined!=track.artist) {
            parts.push(unifiedEscape(track.artist));
        }
        if (undefined!=track.album) {
            parts.push(unifiedEscape(track.album));
        }
        return { id: "mix.track." + index, title: unifiedEscapeTitle(track.title), subtitle: parts.join(MIX_SEPARATOR), image: undefined==track.image ? options.defaultImage : track.image,
                 emblem: options.getEmblem ? options.getEmblem(track.source) : undefined, mixTrack: track.url, menu: options.trackMenu };
    });
    if (resp.previous && resp.previous.length>0) {
        items.push({ id: "mix.previous", title: "Previous days", subtitle: resp.previous.length + (1==resp.previous.length ? " day" : " days"),
                     icon: "history", mixPrevious: { category: category, dates: resp.previous } });
    }
    return items;
}

function mixDayItems(previous, options) {
    return previous.dates.map(function (date, index) {
        return { id: "mix.day." + index, title: date, rawTitle: date, mixCategory: previous.category, mixDate: date,
                 icon: "queue_music", menu: options.menu };
    });
}

function mixPreviousOf(item) {
    return { category: item.mixCategory, dates: item.mixPreviousDates };
}

function mixRowMenu(actions) {
    return [actions.play, actions.insert, actions.add];
}

function mixToolbarActions(actions) {
    return [actions.addToPlaylist, actions.save, actions.add, actions.insert, actions.play];
}

function mixListMenuActions(previousDates, previousAction) {
    return previousDates && previousDates.length>0 ? [{ action: previousAction, weight: 6 }] : [];
}

function mixSaveName(title, date) {
    return undefined==date ? title : title + " " + date;
}

function mixSaveMessage(result, name) {
    if (result && result.failed) {
        return 'The playlist could not be saved.';
    }
    return result && result.exists ? 'A playlist named "' + name + '" already exists. Choose another name.' : name;
}

function mixSuggestedName(item) {
    return mixSaveName(item.mixCategory, undefined==item.mixDate ? item.mixShownDate : item.mixDate);
}

function mixSelector(item) {
    let selector = ["category:" + item.mixCategory];
    if (undefined!=item.mixDate) {
        selector.push("date:" + item.mixDate);
    }
    return selector;
}

function mixActionCommand(cmd, item) {
    return ["unifiedmusic", "mix", "play", "cmd:" + cmd].concat(mixSelector(item));
}

function trackActionCommand(cmd, url) {
    return ["playlist", cmd, url];
}

/* Ispod je veza sa Material-om; koristi njegove globalne objekte. */

function mixActionIds() {
    return { play: PLAY_ACTION, insert: INSERT_ACTION, add: ADD_ACTION, addToPlaylist: ADD_TO_PLAYLIST_ACTION, save: MIX_SAVE_ACTION,
             previous: MIX_PREVIOUS_ACTION };
}

function mixBrowserOptions() {
    let menu = mixRowMenu(mixActionIds());
    return {
        menu: menu,
        trackMenu: menu,
        previousAction: MIX_PREVIOUS_ACTION,
        defaultImage: DEFAULT_COVER,
        getEmblem: function (source) { return getEmblem(source + ":"); }
    };
}

function mixIsItem(item) {
    return undefined!=item && (undefined!=item.mixCategory || undefined!=item.mixTrack);
}

function mixShow(view, title, id, items, subtitle, source, previousDates) {
    let current = { cancache: false, title: title, id: id, type: "group" };
    if (undefined!=source) {
        current.mixCategory = source.mixCategory;
        current.mixDate = source.mixDate;
        current.rawTitle = source.rawTitle;
        current.mixShownDate = subtitle;
        if (previousDates && previousDates.length>0) {
            current.mixPreviousDates = previousDates;
        }
    }
    browseHandleListResponse(view, current, { command: [], params: [] },
                             { items: items, subtitle: subtitle, baseActions: [], canUseGrid: false, jumplist: [], allowHoverBtns: true });
    if (undefined!=source) {
        view.tbarActions = mixToolbarActions(mixActionIds());
        view.currentActions = view.currentActions.concat(mixListMenuActions(previousDates, MIX_PREVIOUS_ACTION));
    }
}

function mixHandleHeaderAction(view, act, item) {
    if (!mixIsItem(item) || (mixToolbarActions(mixActionIds()).indexOf(act)<0 && MIX_PREVIOUS_ACTION!=act)) {
        return false;
    }
    mixHandleAction(view, act, item);
    return true;
}

function mixOpenCategories(view, item) {
    lmsCommand("", ["unifiedmusic", "mixes", "items"]).then(({data}) => {
        let items = mixCategoriesToItems(data.result, mixBrowserOptions());
        mixShow(view, item.title, item.id, items, items.length + (1==items.length ? " category" : " categories"));
    }).catch(err => {
        logError(err);
        bus.$emit('showError', err);
    });
}

function mixOpen(view, item) {
    lmsCommand("", ["unifiedmusic", "mix", "items"].concat(mixSelector(item))).then(({data}) => {
        let items = mixToItems(data.result, item.mixCategory, mixBrowserOptions());
        mixShow(view, item.rawTitle, item.id + ".open", items, data.result.date, item, data.result.previous);
    }).catch(err => {
        logError(err);
        bus.$emit('showError', err);
    });
}

function mixOpenPrevious(view, title, previous) {
    let count = previous.dates.length;
    mixShow(view, title, "mix.previous." + previous.category + ".open", mixDayItems(previous, mixBrowserOptions()),
            count + (1==count ? " day" : " days"));
}

function mixHandleClick(view, item, index, event) {
    if (item.id==TOP_DAILY_ID) {
        mixOpenCategories(view, item);
        return true;
    }
    if (undefined!=item.mixPrevious) {
        mixShow(view, item.title, item.id + ".open", mixDayItems(item.mixPrevious, mixBrowserOptions()), item.subtitle);
        return true;
    }
    if (undefined!=item.mixTrack) {
        browseItemMenu(view, item, index, event);
        return true;
    }
    if (undefined!=item.mixCategory) {
        mixOpen(view, item);
        return true;
    }
    return false;
}

function mixRun(view, command, message) {
    lmsCommand(view.playerId(), command).then(({data}) => {
        bus.$emit('refreshStatus');
        if (undefined!=message) {
            bus.$emit('showMessage', "function"==typeof message ? message(data.result) : message);
        }
    }).catch(err => {
        logError(err);
        bus.$emit('showError', err);
    });
}

function mixSave(view, item) {
    promptForText(i18n("Save as playlist"), i18n("Name"), mixSuggestedName(item)).then(resp => {
        if (resp.ok && resp.value && resp.value.length>0) {
            mixRun(view, ["unifiedmusic", "mix", "save"].concat(mixSelector(item)).concat(["name:" + resp.value]), function (result) { return mixSaveMessage(result, resp.value); });
        }
    });
}

function mixAddToPlaylist(view, item) {
    lmsCommand("", ["playlists", 0, 1000]).then(({data}) => {
        let items = (data.result.playlists_loop || []).map(function (p) { return { id: p.id, title: p.playlist }; });
        choose(i18n("Add to playlist"), items).then(choice => {
            if (undefined!=choice) {
                mixRun(view, ["unifiedmusic", "mix", "append"].concat(mixSelector(item)).concat(["playlist_id:" + choice.id]), choice.title);
            }
        });
    }).catch(err => {
        logError(err);
        bus.$emit('showError', err);
    });
}

function mixHandleAction(view, act, item) {
    let cmd = PLAY_ACTION==act ? "play" : INSERT_ACTION==act ? "insert" : ADD_ACTION==act ? "add" : undefined;
    if (undefined!=cmd) {
        if (!view.$store.state.player) {
            bus.$emit('showError', undefined, i18n("No Player"));
        } else {
            mixRun(view, undefined!=item.mixTrack ? trackActionCommand(cmd, item.mixTrack) : mixActionCommand(cmd, item));
        }
    } else if (ADD_TO_PLAYLIST_ACTION==act) {
        mixAddToPlaylist(view, item);
    } else if (MIX_SAVE_ACTION==act) {
        mixSave(view, item);
    } else if (MIX_PREVIOUS_ACTION==act && undefined!=item.mixPreviousDates) {
        mixOpenPrevious(view, item.rawTitle + MIX_SEPARATOR + "Previous days", mixPreviousOf(item));
    }
}

/* Uvoz liste iz teksta (npr. Gemini opis YouTube videa). */

const IMPORT_POLL_MS = 2000;

function importCount(n, one, many) {
    return n + " " + (1==n ? one : many);
}

function importSummary(entry) {
    if (undefined!=entry.error && undefined==entry.playlist_id) {
        return entry.error;
    }
    return entry.found + " of " + entry.total + " found" + MIX_SEPARATOR + importCount(entry.tracks, "track", "tracks");
}

function importListToItems(resp, options) {
    options = options || {};
    let items = [{ id: "import.new", title: "Import list from text", subtitle: resp.running ? "An import is running…" : "Paste a list of albums or songs",
                   icon: "add_circle_outline", importNew: true }];
    return items.concat((resp.imports || []).map(function (entry, index) {
        return { id: "import.entry." + index, title: unifiedEscapeTitle(entry.name || "Import " + entry.date), rawTitle: entry.name || "Import " + entry.date,
                 subtitle: unifiedEscape(entry.date + MIX_SEPARATOR + importSummary(entry)), icon: "playlist_play", importId: entry.id,
                 menu: undefined==entry.playlist_id ? options.removeMenu : options.entryMenu };
    }));
}

function importDetailToItems(resp, options) {
    options = options || {};
    return (resp.items || []).map(function (row, index) {
        let found = row.found;
        let parts = [];
        if (undefined==found) {
            parts.push("Not found");
            if (undefined!=row.artist) {
                parts.push(unifiedEscape(row.artist));
            }
            return { id: "import.item." + index, title: unifiedEscapeTitle(row.title), subtitle: parts.join(MIX_SEPARATOR), icon: "search_off", importMissing: true };
        }
        if (undefined!=found.artist) {
            parts.push(unifiedEscape(found.artist));
        }
        if ("album"==row.type) {
            parts.push(importCount(found.count, "track", "tracks"));
            if (row.artist_only) {
                parts.push("representative album");
            }
        } else {
            if (row.whole_work && found.count>1) {
                parts.push(importCount(found.count, "movement", "movements"));
            }
            if (undefined!=found.album) {
                parts.push(unifiedEscape(found.album));
            }
        }
        if (found.other_performer) {
            parts.push("other recording (wanted: " + unifiedEscape(row.artist) + ")");
        }
        return { id: "import.item." + index, title: unifiedEscapeTitle(found.title), subtitle: parts.join(MIX_SEPARATOR),
                 image: undefined==found.image ? options.defaultImage : found.image, emblem: options.getEmblem ? options.getEmblem(found.source) : undefined,
                 importId: resp.import ? resp.import.id : undefined, importIndex: index, menu: options.itemMenu };
    });
}

function importPlayCommand(cmd, id, index) {
    let command = ["unifiedmusic", "import", "play", "cmd:" + cmd, "id:" + id];
    if (undefined!=index) {
        command.push("item:" + index);
    }
    return command;
}

// Lyrion cita vrednost parametra samo do kraja reda; tekst ide URI-kodiran.
function importRunCommandFor(text, name) {
    return ["unifiedmusic", "import", "run", "encoding:uri", "text:" + encodeURIComponent(text), "name:" + name.replace(/\s+/g, " ").trim()];
}

function importStatusText(status) {
    if ("reading"==status.stage) {
        return "Reading the list with AI…";
    }
    if ("searching"==status.stage) {
        return "Searching " + Math.min((status.done || 0) + 1, status.total || 1) + " / " + (status.total || "?") + (status.current ? ": " + status.current : "") + "…";
    }
    if ("saving"==status.stage) {
        return "Saving the playlist…";
    }
    return "Working…";
}

function importResultText(last) {
    if (undefined==last) {
        return "The import finished.";
    }
    if (undefined==last.playlist_id) {
        return last.error || "The import failed.";
    }
    return 'Playlist "' + last.name + '" created: ' + importSummary(last).replace(MIX_SEPARATOR, ", ") + ".";
}

/* Ispod je veza sa Material-om; koristi njegove globalne objekte. */

let TOP_IMPORT_ID;
let importPollTimer;

function importOptions() {
    let menu = mixRowMenu(mixActionIds());
    return { entryMenu: menu.concat([REMOVE_ACTION]), removeMenu: [REMOVE_ACTION], itemMenu: menu, defaultImage: DEFAULT_COVER,
             getEmblem: function (source) { return getEmblem(source + ":"); } };
}

function importIsItem(item) {
    return undefined!=item && (item.importNew || undefined!=item.importId || item.importMissing);
}

function importShow(view, title, id, items, subtitle, current) {
    let page = Object.assign({ cancache: false, title: title, id: id, type: "group" }, current || {});
    browseHandleListResponse(view, page, { command: [], params: [] },
                             { items: items, subtitle: subtitle, baseActions: [], canUseGrid: false, jumplist: [], allowHoverBtns: true });
    if (undefined!=page.importId) {
        view.tbarActions = [ADD_ACTION, INSERT_ACTION, PLAY_ACTION];
    }
}

function importError(err) {
    logError(err);
    bus.$emit('showError', err);
}

function importOpenList(view, title, refresh) {
    lmsCommand("", ["unifiedmusic", "import", "items"]).then(({data}) => {
        let items = importListToItems(data.result, importOptions());
        let subtitle = importCount(items.length-1, "list", "lists");
        if (refresh) {
            if (view.current && view.current.importList) {
                view.items = items;
                view.headerSubTitle = subtitle;
            }
            return;
        }
        importShow(view, title || "Imported lists", TOP_IMPORT_ID + ".open", items, subtitle, { importList: true });
    }).catch(importError);
}

function importOpenDetail(view, item) {
    lmsCommand("", ["unifiedmusic", "import", "items", "id:" + item.importId]).then(({data}) => {
        if (undefined==data.result.import) {
            bus.$emit('showError', undefined, "This import no longer exists.");
            return;
        }
        let items = importDetailToItems(data.result, importOptions());
        importShow(view, item.rawTitle, "import." + item.importId, items, importSummary(data.result.import),
                   { importId: item.importId, rawTitle: item.rawTitle });
    }).catch(importError);
}

function importRunCommand(view, command) {
    if (!view.$store.state.player) {
        bus.$emit('showError', undefined, i18n("No Player"));
        return;
    }
    lmsCommand(view.playerId(), command).then(() => { bus.$emit('refreshStatus'); }).catch(importError);
}

function importHandleAction(view, act, item) {
    let cmd = PLAY_ACTION==act ? "play" : INSERT_ACTION==act ? "insert" : ADD_ACTION==act ? "add" : undefined;
    if (undefined!=cmd && undefined!=item.importId) {
        importRunCommand(view, importPlayCommand(cmd, item.importId, item.importIndex));
    } else if (REMOVE_ACTION==act && undefined!=item.importId) {
        confirm('Remove "' + item.rawTitle + '" from imported lists? The playlist itself stays.', i18n("Remove")).then(res => {
            if (res) {
                lmsCommand("", ["unifiedmusic", "import", "delete", "id:" + item.importId]).then(() => {
                    importOpenList(view, undefined, true);
                }).catch(importError);
            }
        });
    }
}

function importHandleHeaderAction(view, act, current) {
    if (undefined==current || undefined==current.importId || [ADD_ACTION, INSERT_ACTION, PLAY_ACTION].indexOf(act)<0) {
        return false;
    }
    importHandleAction(view, act, { importId: current.importId });
    return true;
}

function importHandleClick(view, item, index, event) {
    if (item.id==TOP_IMPORT_ID) {
        importOpenList(view, item.title);
        return true;
    }
    if (item.importNew) {
        importDialog(view);
        return true;
    }
    if (item.importMissing) {
        return true;
    }
    if (undefined!=item.importIndex) {
        browseItemMenu(view, item, index, event);
        return true;
    }
    if (undefined!=item.importId) {
        importOpenDetail(view, item);
        return true;
    }
    return false;
}

function importElement(tag, style, text) {
    let el = document.createElement(tag);
    if (style) {
        el.style.cssText = style;
    }
    if (undefined!=text) {
        el.textContent = text;
    }
    return el;
}

// Prozor za tekst: Material nema visestruki unos u svojim dijalozima.
function importDialog(view) {
    let overlay = importElement("div", "position:fixed;inset:0;z-index:1000;background:rgba(0,0,0,0.5);display:flex;align-items:center;justify-content:center");
    let box = importElement("div", "background:var(--popup-background-color, #fff);color:var(--text-color, #000);width:calc(100% - 32px);max-width:680px;max-height:calc(100% - 32px);" +
                                   "overflow:auto;border-radius:8px;padding:16px;box-shadow:0 8px 24px rgba(0,0,0,0.4);display:flex;flex-direction:column;gap:10px;font-size:15px");
    let field = "width:100%;box-sizing:border-box;background:transparent;color:inherit;border:1px solid var(--list-item-border-color, #888);border-radius:4px;padding:8px;font:inherit";
    let title = importElement("div", "font-size:20px", "Import list from text");
    let hint = importElement("div", "opacity:0.7;font-size:13px",
                             "Paste a list of albums, songs or artists, for example the summary Gemini writes for a YouTube video. " +
                             "AI recognises the entries; they are searched in your sources in the configured order and saved as a playlist.");
    let text = importElement("textarea", field + ";min-height:220px;resize:vertical");
    text.placeholder = "1. Jackson Browne - \"Linda Paloma\" ...";
    let name = importElement("input", field);
    name.placeholder = "Playlist name (optional, AI suggests one)";
    let status = importElement("div", "min-height:20px;font-size:14px");
    let buttons = importElement("div", "display:flex;justify-content:flex-end;gap:8px");
    let btn = "background:transparent;border:none;color:var(--active-color, #1976d2);font:inherit;font-weight:500;text-transform:uppercase;padding:8px 12px;cursor:pointer";
    let cancel = importElement("button", btn, "Close");
    let show = importElement("button", btn + ";display:none", "Show");
    let start = importElement("button", btn, "Import");
    buttons.append(cancel, show, start);
    box.append(title, hint, text, name, status, buttons);
    overlay.appendChild(box);
    // Tamna tema se ne vidi u promenljivama korena, pa se boja i font uzimaju sa Material liste.
    let sample = document.querySelector(".v-list__tile__title") || document.querySelector(".v-toolbar__title");
    if (sample) {
        let look = getComputedStyle(sample);
        box.style.color = look.color;
        box.style.fontFamily = look.fontFamily;
    }

    let closed = false;
    let close = function () {
        if (!closed) {
            closed = true;
            overlay.remove();
            document.removeEventListener("keydown", onKey, true);
        }
    };
    let onKey = function (ev) {
        if ("Escape"==ev.key) {
            ev.stopPropagation();
            close();
        }
    };
    document.addEventListener("keydown", onKey, true);
    cancel.onclick = close;
    overlay.onclick = function (ev) {
        if (ev.target==overlay && start.disabled) {
            close();
        }
    };

    let finished = function (last) {
        let message = importResultText(last);
        if (closed) {
            if (undefined!=last && undefined!=last.playlist_id) {
                bus.$emit('showMessage', message);
            } else {
                bus.$emit('showError', undefined, message);
            }
            return;
        }
        status.textContent = message;
        start.disabled = false;
        start.textContent = "Import again";
        if (undefined!=last && undefined!=last.id) {
            show.style.display = "";
            show.onclick = function () {
                close();
                importOpenDetail(view, { importId: last.id, rawTitle: last.name || "Import" });
            };
        }
    };

    start.onclick = function () {
        if (text.value.trim().length<1) {
            status.textContent = "Paste the text with the list first.";
            return;
        }
        start.disabled = true;
        show.style.display = "none";
        status.textContent = "Starting…";
        let command = importRunCommandFor(text.value, name.value);
        lmsCommand(view.$store.state.player ? view.playerId() : "", command).then(({data}) => {
            let result = data.result || {};
            if (undefined!=result.error) {
                status.textContent = result.error;
                start.disabled = false;
                return;
            }
            if (result.running) {
                status.textContent = "Another import is running; this one waits until it finishes.";
            }
            importPoll(function (state) {
                if (!closed) {
                    status.textContent = importStatusText(state);
                }
            }, finished, result.running ? command : undefined, view);
        }).catch(err => {
            start.disabled = false;
            status.textContent = "The import could not be started.";
            logError(err);
        });
    };

    document.body.appendChild(overlay);
    text.focus();
}

// Prati posao na serveru; kada se zavrsi, javlja rezultat i osvezava listu uvoza ako je otvorena.
function importPoll(onProgress, onDone, retryCommand, view) {
    if (undefined!=importPollTimer) {
        clearTimeout(importPollTimer);
    }
    let tick = function () {
        lmsCommand("", ["unifiedmusic", "import", "status"]).then(({data}) => {
            let state = data.result || {};
            if (state.running) {
                onProgress(state);
                importPollTimer = setTimeout(tick, IMPORT_POLL_MS);
                return;
            }
            if (undefined!=retryCommand) {
                let command = retryCommand;
                retryCommand = undefined;
                lmsCommand(view.$store.state.player ? view.playerId() : "", command).then(() => {
                    importPollTimer = setTimeout(tick, IMPORT_POLL_MS);
                }).catch(importError);
                return;
            }
            importPollTimer = undefined;
            onDone(state.last);
            importOpenList(view, undefined, true);
        }).catch(err => {
            importPollTimer = setTimeout(tick, IMPORT_POLL_MS * 2);
        });
    };
    importPollTimer = setTimeout(tick, IMPORT_POLL_MS);
}

/* Veza sa originalnim Material Skin-om. Ako nesto nedostaje, Material radi bez naših dodataka. */

const LMS_UNIFIED_SEARCH_TIMEOUT = 15000;
const UNIFIED_LOCAL_EMBLEM = { name: "folder-local", bgnd: "#607d8b", color: "#fff" };
const UNIFIED_REQUIRED = ["browseClick", "browseItemAction", "browseHeaderAction", "browseHandleListResponse", "browseItemMenu",
                          "getEmblem", "lmsCommand", "promptForText", "choose", "confirm", "ACTIONS", "REMOVE_ACTION", "bus", "app"];
const UNIFIED_WAIT_MS = 200;
const UNIFIED_WAIT_LIMIT = 300;
let TOP_DAILY_ID;
let MIX_SAVE_ACTION;
let MIX_PREVIOUS_ACTION;

function unifiedGlobalType(name) {
    try {
        return (0, eval)("typeof " + name);
    } catch (e) {
        return "undefined";
    }
}

function unifiedMissingGlobals() {
    return UNIFIED_REQUIRED.filter(function (name) { return "undefined"==unifiedGlobalType(name); });
}

function unifiedPatchSearchField() {
    let ctor = Vue.options.components["lms-search-field"];
    if (!ctor || !ctor.options || !ctor.options.methods || !ctor.options.methods.doSearch || !ctor.options.methods.searchNow) {
        console.warn("UnifiedMusic: search field not found, using the standard search");
        return;
    }
    let methods = ctor.options.methods;
    let originalDoSearch = methods.doSearch;
    let originalSearchNow = methods.searchNow;

    methods.searchNow = function () {
        if (unifiedKeepCurrentSearch(this.term, this.str, this.searching)) {
            this.stopDebounce();
            return;
        }
        return originalSearchNow.apply(this, arguments);
    };

    methods.doSearch = function () {
        if (this.unifiedRequest==seachReqId || queryParams.party || !this.searching) {
            return originalDoSearch.apply(this, arguments);
        }
        this.unifiedRequest = seachReqId;
        this.doUnifiedSearch(this.$store.state.library ? this.$store.state.library : LMS_DEFAULT_LIBRARY);
    };

    methods.unifiedAvailable = function () {
        if (undefined!=this.hasUnified) {
            return Promise.resolve(this.hasUnified);
        }
        return lmsCommand("", ["can", "unifiedmusic", "search", "?"]).then(({data}) => {
            this.hasUnified = 1==parseInt(data.result._can);
            return this.hasUnified;
        }).catch(err => {
            return false;
        });
    };

    methods.doUnifiedSearch = function (libId) {
        let reqId = seachReqId;
        let fallback = () => {
            if (reqId==seachReqId && this.searching) {
                originalDoSearch.apply(this, []);
            }
        };
        this.unifiedAvailable().then(available => {
            if (reqId!=seachReqId || !this.searching) {
                return;
            }
            if (!available) {
                fallback();
                return;
            }
            let command = ["unifiedmusic", "search", "term:" + this.str];
            if (libId) {
                command.push("library_id:" + libId);
            }
            lmsCommand(this.$store.state.player ? this.$store.state.player.id : "", command, reqId, LMS_UNIFIED_SEARCH_TIMEOUT).then(({data}) => {
                if (data.id==seachReqId && this.searching) {
                    this.showUnifiedResults(data.result);
                }
            }).catch(fallback);
        });
    };

    methods.showUnifiedResults = function (result) {
        let resp = unifiedToBrowseItems(result, unifiedBrowserOptions());
        this.commands = [];
        this.results = [];
        this.searching = false;
        if (0==resp.items.length) {
            bus.$emit("showMessage", undefined==resp.missingNote ? i18n("No results found") : resp.missingNote);
            return;
        }
        if (undefined!=resp.missingNote) {
            bus.$emit("showMessage", resp.missingNote);
        }
        let item = { cancache: false, title: i18n("Search") + SEPARATOR + this.str, id: SEARCH_ID, type: "search", libsearch: true };
        this.$emit("results", item, { command: [], params: [] },
                   { items: resp.items, baseActions: [], canUseGrid: false, jumplist: [], allowHoverBtns: true }, this.prevPage);
    };
}

function unifiedIsOurItem(item) {
    return undefined!=item && (item.unified || item.unifiedVersion || mixIsItem(item) || importIsItem(item));
}

function unifiedPatchGlobals() {
    let originalClick = browseClick;
    browseClick = function (view, item, index, event, ignoreOpenMenu) {
        if (undefined!=item && (item.id==TOP_DAILY_ID || item.id==TOP_IMPORT_ID || unifiedIsOurItem(item) || undefined!=item.mixPrevious) && !unifiedMenuIsOpen(view, item, ignoreOpenMenu)) {
            if (importHandleClick(view, item, index, event) || mixHandleClick(view, item, index, event)) {
                return;
            }
            if (item.unified) {
                unifiedOpenVersions(view, item);
                return;
            }
            if (item.unifiedVersion) {
                unifiedPlay(view, item.unifiedVersion);
                return;
            }
        }
        return originalClick.apply(this, arguments);
    };

    let originalAction = browseItemAction;
    browseItemAction = function (view, act, origItem) {
        if (importIsItem(origItem)) {
            importHandleAction(view, act, origItem);
            return;
        }
        if (mixIsItem(origItem)) {
            mixHandleAction(view, act, origItem);
            return;
        }
        if (undefined!=origItem && (origItem.unified || origItem.unifiedVersion)) {
            unifiedHandleAction(view, act, origItem);
            return;
        }
        return originalAction.apply(this, arguments);
    };

    let originalHeader = browseHeaderAction;
    browseHeaderAction = function (view, act, event, ignoreOpenMenus) {
        if ((ignoreOpenMenus || 0==view.$store.state.visibleMenus.size) &&
            (importHandleHeaderAction(view, act, view.current) || mixHandleHeaderAction(view, act, view.current))) {
            return;
        }
        return originalHeader.apply(this, arguments);
    };

    let originalEmblem = getEmblem;
    getEmblem = function (extid) {
        return "local:"==extid ? UNIFIED_LOCAL_EMBLEM : originalEmblem.apply(this, arguments);
    };
}

function unifiedMenuIsOpen(view, item, ignoreOpenMenu) {
    return !item.isListItemInMenu && !ignoreOpenMenu && (view.menu.show || view.$store.state.visibleMenus.size>0);
}

function unifiedDailyTopItem() {
    return { command: ["unifiedmusic", "mixes", "items"], params: [], icon: "queue_music", title: "Your Daily Mixes",
             type: "group", weight: 6, id: TOP_DAILY_ID };
}

function unifiedImportTopItem() {
    return { command: ["unifiedmusic", "import", "items"], params: [], icon: "playlist_add", title: "Imported lists",
             type: "group", weight: 7, id: TOP_IMPORT_ID };
}

function unifiedShowOnHome(view) {
    if (!view.top.some(function (i) { return i.id==TOP_DAILY_ID; })) {
        view.top.push(unifiedDailyTopItem());
    }
    if (!view.top.some(function (i) { return i.id==TOP_IMPORT_ID; })) {
        view.top.push(unifiedImportTopItem());
    }
    if (view.isTop && view.history.length<1) {
        view.items = view.topExtra && view.$store.state.detailedHomeItems.length>0 && view.grid.use ? view.topExtra.concat(view.top) : view.top;
        view.layoutGrid(true);
    }
}

function unifiedPatchView(view) {
    if (view.unifiedPatched) {
        return;
    }
    view.unifiedPatched = true;

    ["allowAdd", "allowInsert"].forEach(function (name) {
        let original = view[name];
        view[name] = function (item) {
            return !item.unified && !item.unifiedVersion && original.call(view, item);
        };
    });
    let originalShuffle = view.allowShuffle;
    view.allowShuffle = function (item) {
        return !unifiedIsOurItem(item) && originalShuffle.call(view, item);
    };
    let originalSave = view.saveTopList;
    view.saveTopList = function () {
        let all = view.top;
        view.top = all.filter(function (i) { return i.id!=TOP_DAILY_ID && i.id!=TOP_IMPORT_ID; });
        originalSave.call(view);
        view.top = all;
    };
}

function unifiedFindBrowseView(vm) {
    if (vm.initItems && vm.top) {
        return vm;
    }
    for (let i=0; i<vm.$children.length; ++i) {
        let found = unifiedFindBrowseView(vm.$children[i]);
        if (found) {
            return found;
        }
    }
    return undefined;
}

function unifiedAttachToView(view) {
    unifiedPatchView(view);
    unifiedShowOnHome(view);
}

function unifiedInstall() {
    TOP_DAILY_ID = TOP_ID_PREFIX + "daily";
    TOP_IMPORT_ID = TOP_ID_PREFIX + "import";
    MIX_SAVE_ACTION = ACTIONS.length;
    ACTIONS.push({ cmd: "save", icon: "save", title: "Save as playlist" });
    MIX_PREVIOUS_ACTION = ACTIONS.length;
    ACTIONS.push({ cmd: "previous-days", icon: "history", title: "Previous days" });

    unifiedPatchSearchField();
    unifiedPatchGlobals();

    bus.$on("homeScreenItems", function (view) {
        if (view.initItems && view.top) {
            unifiedAttachToView(view);
        }
    });
    let view = unifiedFindBrowseView(app);
    if (view) {
        unifiedAttachToView(view);
    }
}

function unifiedWaitForMaterial(attempt) {
    let missing = unifiedMissingGlobals();
    if (0==missing.length) {
        unifiedInstall();
    } else if (attempt<UNIFIED_WAIT_LIMIT) {
        setTimeout(function () { unifiedWaitForMaterial(attempt + 1); }, UNIFIED_WAIT_MS);
    } else {
        console.warn("UnifiedMusic: Material Skin changed, add-ons are disabled. Missing: " + missing.join(", "));
    }
}

if (typeof module !== "undefined") {
    module.exports = {
        unifiedToBrowseItems: unifiedToBrowseItems, unifiedVersionItems: unifiedVersionItems, playCommandFor: playCommandFor,
        unifiedKeepCurrentSearch: unifiedKeepCurrentSearch, unifiedEscape: unifiedEscape, unifiedEscapeTitle: unifiedEscapeTitle,
        mixCategoriesToItems: mixCategoriesToItems, mixToItems: mixToItems, mixActionCommand: mixActionCommand,
        trackActionCommand: trackActionCommand, mixRowMenu: mixRowMenu, mixToolbarActions: mixToolbarActions, mixListMenuActions: mixListMenuActions,
        mixSaveName: mixSaveName, mixSaveMessage: mixSaveMessage, mixSuggestedName: mixSuggestedName,
        importListToItems: importListToItems, importDetailToItems: importDetailToItems, importPlayCommand: importPlayCommand,
        importStatusText: importStatusText, importRunCommandFor: importRunCommandFor, importResultText: importResultText,
        UNIFIED_LOCAL_EMBLEM: UNIFIED_LOCAL_EMBLEM
    };
} else {
    unifiedWaitForMaterial(0);
}
