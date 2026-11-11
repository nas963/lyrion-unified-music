use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Normalize qw(title_key artist_key album_key track_key plain_key);

is title_key('Kind Of Blue (Legacy Edition)'), 'kind of blue', 'Legacy Edition';
is title_key('Kind of Blue (Remastered)'),     'kind of blue', 'Remastered';
is title_key('So What - Remastered 2009'),     'so what',      'sufiks iza crtice';
is title_key('Abbey Road [2019]'),             'abbey road',   'godina u zagradi';
is title_key('Album (Deluxe) [Bonus Tracks]'), 'album',        'vise segmenata';
is title_key('Blues (Live Remastered)'),       'blues live remastered', 'Live ostaje';
is title_key('Bitter Blue - Radio Version'),   'bitter blue radio version', 'Radio Version ostaje';
is title_key('Song (Mono)'),                   'song mono', 'Mono ostaje';

is artist_key('Đorđe Balašević'),   'djordje balasevic', 'dj i dijakritika';
is artist_key('Djordje Balasevic'), 'djordje balasevic', 'latinica bez dijakritike';
is artist_key('Đorđe') , artist_key('ĐORĐE'), 'veliko slovo Dj';
is artist_key('Ђорђе'), 'ђорђе', 'cirilica ostaje';
is artist_key('Чайковский'), 'чайковский', 'cirilicno i-kratko ostaje';
is artist_key('Simon & Garfunkel'),      'simon and garfunkel', 'ampersand';
is artist_key('Santana feat. Rob Thomas'), 'santana', 'feat.';
is artist_key('Santana ft. Rob Thomas'),   'santana', 'ft.';
is artist_key('Santana featuring Rob'),    'santana', 'featuring';

is album_key('Miles Davis', 'Kind of Blue'), album_key('MILES DAVIS', 'Kind Of Blue (Deluxe)'), 'album_key spaja';
isnt album_key('A', 'B C'), album_key('A B', 'C'), 'delovi kljuca se ne mesaju';
is track_key('Miles Davis', 'So What'), track_key('Miles Davis', 'So What - Remastered'), 'track_key spaja';

isnt title_key('(Remastered)'), '', 'naslov samo od sufiksa nije prazan';
isnt title_key('(Remastered)'), title_key('[Deluxe]'), 'ni sa drugim sufiksom';
is plain_key('(Remastered)'), 'remastered', 'plain_key bez uklanjanja segmenata';
is title_key(undef), '', 'undef je prazan kljuc';

is title_key('÷'), '÷', 'naslov od simbola ostaje';
isnt title_key('÷'), title_key('×'), 'razliciti simboli se ne spajaju';
is title_key(' ÷ '), title_key('÷'), 'razmaci oko simbola se uklanjaju';
is artist_key('!!!'), '!!!', 'izvodjac od simbola ostaje';
isnt artist_key('+/-'), artist_key('***'), 'razliciti izvodjaci od simbola';

done_testing;
