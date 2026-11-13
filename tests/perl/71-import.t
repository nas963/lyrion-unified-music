use strict;
use warnings;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempdir);

use Plugins::UnifiedMusic::AI::Anthropic;
use Plugins::UnifiedMusic::AI::OpenAI;
use Plugins::UnifiedMusic::Import::Album;
use Plugins::UnifiedMusic::Import::History;
use Plugins::UnifiedMusic::Import::Job;
use Plugins::UnifiedMusic::Import::Match qw(score best);
use Plugins::UnifiedMusic::Import::Prompt;
use Plugins::UnifiedMusic::Import::Resolver;

my $json = JSON::PP->new->utf8->canonical;

# --- Prompt ---
{
	my $prompt = Plugins::UnifiedMusic::Import::Prompt::build("1. Hiromi - Spark\n");
	like $prompt->{user}, qr/Hiromi - Spark/, 'tekst je u zahtevu';
	like $prompt->{system}, qr/representative/, 'uputstvo za izvodjace';
	my $schema = Plugins::UnifiedMusic::Import::Prompt::schema();
	is_deeply [sort @{ $schema->{properties}{items}{items}{required} }], [sort keys %{ $schema->{properties}{items}{items}{properties} }],
		'sva polja su obavezna (strogi OpenAI)';

	my $parse = \&Plugins::UnifiedMusic::Import::Prompt::parse;
	my $answer = $parse->($json->encode({ name => '  HiFi   test ', items => [
		{ type => 'track', artist => 'Jackson Browne', title => 'Linda Paloma', album => 'The Pretender', artist_only => JSON::PP::false, alternatives => [] },
		{ type => 'album', artist => 'Hiromi', title => 'Spark', album => '', artist_only => JSON::PP::true, alternatives => ['Voice', 'spark', 'Place to Be', 'Alive'] },
		{ type => 'album', artist => 'Hiromi', title => 'Spark', album => '', artist_only => JSON::PP::true, alternatives => [] },
		{ type => 'track', artist => '', title => 'X', album => '', artist_only => JSON::PP::false, alternatives => [] },
		'nije objekat',
	] }));
	my $list = $answer->{list};
	is $list->{name}, 'HiFi test', 'naziv bez viska razmaka';
	is scalar @{ $list->{items} }, 2, 'prazne i ponovljene stavke se izbacuju';
	is $list->{items}[0]{album}, 'The Pretender', 'album pesme';
	ok !$list->{items}[0]{artist_only}, 'pesma nije samo izvodjac';
	ok $list->{items}[1]{artist_only}, 'samo izvodjac';
	is_deeply $list->{items}[1]{alternatives}, ['Voice', 'Place to Be', 'Alive'], 'najvise tri alternative, bez ponavljanja naslova';
	is $parse->('nije json'), undef, 'neispravan odgovor';
}

# --- Match ---
{
	my $want = { artist => 'Miles Davis', title => 'So What' };
	is score($want, { artist => 'Miles Davis', title => 'So What' }), 1, 'tacno';
	cmp_ok score($want, { artist => 'Miles Davis', title => 'So What (feat. John Coltrane, Cannonball Adderley & Bill Evans)' }), '>=', 0.9, 'feat u zagradi';
	is score($want, { artist => 'Joe Henderson', title => 'So What (Miles Davis)' }), 0, 'drugi izvodjac';
	cmp_ok score({ artist => 'Harry Belafonte', title => 'Jamaica Farewell (Live)' }, { artist => 'Harry Belafonte', title => 'Jamaica Farewell - Live' }), '>=', 0.9, 'Live na dva nacina';
	cmp_ok score({ artist => 'JD Beck and DOMi', title => 'NOT TiGHT' }, { artist => 'DOMi & JD BECK', title => 'NOT TiGHT' }), '>=', 0.99, 'izvodjaci obrnutim redom';
	cmp_ok score({ artist => 'Howard Griffiths / Royal Phil', title => 'Kol Nidrei, Op. 47' }, { artist => 'Royal Philharmonic Orchestra', title => 'Kol Nidrei, Op. 47' }), '>=', 0.99, 'skraceni orkestar';
	is score({ artist => 'Queen', title => 'Innuendo' }, { artist => 'Queensryche', title => 'Innuendo' }), 0, 'pocetak reci nije izvodjac';
	is score({ artist => 'The Aristocrats', title => 'Culture Clash' }, { artist => 'The Beatles', title => 'Culture Clash' }), 0, 'samo "the" nije dovoljno';
	is score({ artist => 'Jos van Immerseel', title => 'Symphony No. 4 in B-flat Major, Op. 60: I. Adagio - Allegro vivace' },
		{ artist => 'Anima Eterna Brugge, Jos van Immerseel', title => 'Symphony No. 5 in C Minor, Op. 67: I. Allegro con brio' }), 0, 'drugi broj simfonije';
	cmp_ok score({ artist => 'Jos van Immerseel', title => 'Symphony No. 4 in B-flat Major, Op. 60: I. Adagio - Allegro vivace' },
		{ artist => 'Anima Eterna Brugge, Jos van Immerseel', title => 'Symphony No. 4 in B-Flat Major, Op. 60: I. Adagio - Allegro vivace' }), '>=', 0.99, 'klasika, izvodjac u nizu';
	is score({ artist => 'Hiromi', title => 'Spark' }, { artist => 'Hiromi', title => 'Voice' }), 0, 'drugi album';

	my $items = [
		{ kind => 'track', artist => 'Miles Davis', title => 'So What (Live)', source => 'local' },
		{ kind => 'album', artist => 'Miles Davis', title => 'So What', source => 'local' },
		{ kind => 'track', artist => 'Miles Davis', title => 'So What', source => 'qobuz' },
	];
	is best({ artist => 'Miles Davis', title => 'So What' }, $items, 'track')->{item}{source}, 'qobuz', 'najbolja ocena pobedjuje';
	is best({ artist => 'Nobody', title => 'So What' }, $items, 'track'), undef, 'nema pogotka';
}

# --- Klasika ---
{
	my $hindemith = { artist => 'Peter Hurford', title => 'Organ Sonata No. 1', composer => 'Paul Hindemith' };
	is score($hindemith, { artist => 'Johann Sebastian Bach, Peter Hurford', title => 'Organ Sonata No. 1 in E-Flat Major, BWV 525: II. Adagio' }), 0, 'drugi kompozitor';
	cmp_ok score($hindemith, { artist => 'Peter Hurford', title => 'Hindemith: Organ Sonata No. 1 (1937) - 3. Phantasie', album => 'Hindemith: Organ Sonatas' }), '>=', 0.6, 'kompozitor u naslovu';

	my $bruch = { artist => 'Howard Griffiths / Royal Philharmonic Orchestra', title => 'Kol Nidrei, Op. 47', composer => 'Max Bruch' };
	my $other = score($bruch, { artist => 'Max Bruch', title => 'Kol Nidrei, for Cello & Orchestra, Op. 47' });
	cmp_ok $other, '>=', 0.6, 'drugi izvodjac prolazi kod klasike';
	cmp_ok $other, '<', 0.8, '... ali sa nizom ocenom';
	is score({ artist => 'X', title => 'Kol Nidrei, Op. 47' }, { artist => 'Max Bruch', title => 'Kol Nidrei, Op. 47' }), 0, 'van klasike drugi izvodjac ne prolazi';

	my $found = best($bruch, [
		{ kind => 'track', artist => 'Steven Isserlis', title => 'Bruch: Kol Nidrei, Op. 47' },
		{ kind => 'track', artist => 'Royal Philharmonic Orchestra', title => 'Kol Nidrei, for Cello & Orchestra, Op. 47', album => 'Bruch' },
	], 'track');
	is $found->{item}{artist}, 'Royal Philharmonic Orchestra', 'trazeni izvodjac ispred boljeg naslova drugog izvodjaca';

	is_deeply Plugins::UnifiedMusic::Import::Match::movement_key('Symphony No. 4 in B-flat Major, Op. 60: IV. Allegro ma non troppo'), [4, ''], 'rimski stav';
	is_deeply Plugins::UnifiedMusic::Import::Match::movement_key('Hindemith: Organ Sonata No. 1 (1937) - 3b. Ruhig Bewegt'), [3, 'b'], 'arapski stav sa slovom';
	is_deeply Plugins::UnifiedMusic::Import::Match::movement_key('So What'), [9999, ''], 'bez stava';
}

{
	my @movements = map { { kind => 'track', artist => 'Peter Hurford', album => 'Hindemith: Organ Sonatas', source => 'qobuz', title => "Hindemith: Organ Sonata No. 1 (1937) - $_->[0]", play => { url => "q://$_->[1]" } } }
		(['3. Phantasie', 3], ['1. Massig schnell', 1], ['1b. Lebhaft', 2], ['2. Sehr langsam', 4]);
	push @movements, { kind => 'track', artist => 'Peter Hurford', album => 'Hindemith: Organ Sonatas', source => 'qobuz', title => 'Hindemith: Organ Sonata No. 2 (1937) - 1. Lebhaft', play => { url => 'q://sonata2' } };
	push @movements, { kind => 'track', artist => 'Johann Sebastian Bach, Peter Hurford', title => 'Organ Sonata No. 1, BWV 525: I. Allegro', source => 'qobuz', play => { url => 'q://bach' } };
	my ($resolver) = make_resolver(qobuz => { 'Hurford Hindemith Organ Sonata 1' => \@movements });
	my @out;
	$resolver->resolve([{ type => 'track', artist => 'Peter Hurford', title => 'Organ Sonata No. 1', composer => 'Paul Hindemith', whole_work => 1,
		search => 'Hurford Hindemith Organ Sonata 1', alternatives => [] }], sub { push @out, $_[0] });
	is_deeply $out[0][0]{found}{urls}, ['q://1', 'q://2', 'q://4', 'q://3'], 'ceo komad, stavovi po redu, bez drugog kompozitora';

	($resolver, my $searches) = make_resolver(
		qobuz => {
			'Bruch Kol Nidrei' => [{ kind => 'track', artist => 'Max Bruch', title => 'Kol Nidrei, Op. 47', source => 'qobuz', play => { url => 'q://bruch' } }],
			'Howard Griffiths Kol Nidrei, Op. 47' => [{ kind => 'track', artist => 'Howard Griffiths', title => 'Kol Nidrei, Op. 47', source => 'qobuz', play => { url => 'q://hg' } }],
		},
	);
	@out = ();
	$resolver->resolve([{ type => 'track', artist => 'Howard Griffiths', title => 'Kol Nidrei, Op. 47', composer => 'Max Bruch', search => 'Bruch Kol Nidrei', alternatives => [] }], sub { push @out, $_[0] });
	is_deeply $out[0][0]{found}{urls}, ['q://hg'], 'drugi upit nalazi trazenog izvodjaca';
	ok !$out[0][0]{found}{other_performer}, 'nije drugi izvodjac';

	($resolver) = make_resolver(qobuz => { 'Bruch Kol Nidrei' => [{ kind => 'track', artist => 'Max Bruch', title => 'Kol Nidrei, Op. 47', source => 'qobuz', play => { url => 'q://bruch' } }] });
	@out = ();
	$resolver->resolve([{ type => 'track', artist => 'Howard Griffiths', title => 'Kol Nidrei, Op. 47', composer => 'Max Bruch', search => 'Bruch Kol Nidrei', alternatives => [] }], sub { push @out, $_[0] });
	is_deeply $out[0][0]{found}{urls}, ['q://bruch'], 'na kraju snimak drugog izvodjaca';
	ok $out[0][0]{found}{other_performer}, 'oznacen kao drugi izvodjac';
}

{
	my ($resolver) = make_resolver(
		qobuz => {
			'Sungazer Sungazer' => [{ kind => 'album', artist => 'Sungazer', title => 'SUNGAZER', source => 'qobuz' }],
			'Sungazer Perihelion' => [{ kind => 'album', artist => 'Sungazer', title => 'Perihelion', source => 'qobuz' }],
		},
		albums => { SUNGAZER => ['q://single'], Perihelion => ['q://1', 'q://2', 'q://3', 'q://4'] },
	);
	my @out;
	$resolver->resolve([{ type => 'album', artist => 'Sungazer', title => 'Sungazer', artist_only => 1, alternatives => ['Perihelion'] }], sub { push @out, $_[0] });
	is $out[0][0]{found}{title}, 'Perihelion', 'singl ustupa mesto pravom albumu';

	($resolver) = make_resolver(
		qobuz => { 'Sungazer Sungazer' => [{ kind => 'album', artist => 'Sungazer', title => 'SUNGAZER', source => 'qobuz' }] },
		albums => { SUNGAZER => ['q://single'] },
	);
	@out = ();
	$resolver->resolve([{ type => 'album', artist => 'Sungazer', title => 'Sungazer', artist_only => 1, alternatives => ['Nema'] }], sub { push @out, $_[0] });
	is_deeply $out[0][0]{found}{urls}, ['q://single'], 'bez alternative ostaje singl';
}

{
	my ($resolver, $searches) = make_resolver(
		qobuz => { 'Hurford Hindemith Organ Sonata 1' => [
			{ kind => 'album', artist => 'Peter Hurford', title => 'Hindemith: Organ Sonatas', source => 'qobuz' },
			{ kind => 'track', artist => 'Peter Hurford', album => 'Hindemith: Organ Sonatas', source => 'qobuz', title => 'Hindemith: Organ Sonata No. 1 (1937) - 2. Sehr langsam', play => { url => 'q://2' } },
			{ kind => 'track', artist => 'Peter Hurford', album => 'Hindemith: Organ Sonatas', source => 'qobuz', title => 'Hindemith: Organ Sonata No. 1 (1937) - 1. Massig', play => { url => 'q://1' } },
		] },
	);
	my @out;
	$resolver->resolve([{ type => 'album', artist => 'Peter Hurford', title => 'Organ Sonata No. 1', composer => 'Paul Hindemith',
		search => 'Hurford Hindemith Organ Sonata 1', alternatives => [] }], sub { push @out, $_[0] });
	is $out[0][0]{type}, 'track', 'album koji ne postoji trazi se kao delo';
	is_deeply $out[0][0]{found}{urls}, ['q://1', 'q://2'], 'svi stavovi dela';
	ok grep({ /^track:/ } @$searches), 'druga pretraga je po pesmama';
}

# --- Album ---
{
	my $menu = { item_loop => [
		{ text => "Spark\nHiromi - Spark", presetParams => { favorites_url => 'qobuz://42100943.flac' } },
		{ text => "In A Trance\nHiromi", type => 'audio', presetParams => { favorites_url => 'tidal://77647305.flc' } },
		{ text => 'Artist: Hiromi', params => { item_id => '1.2' } },
		{ text => 'Album', presetParams => { favorites_url => 'tidal://album:2178485' } },
	] };
	is_deeply Plugins::UnifiedMusic::Import::Album::track_urls($menu), ['qobuz://42100943.flac', 'tidal://77647305.flc'], 'samo pesme albuma';
	is_deeply Plugins::UnifiedMusic::Import::Album::disc_ids({ item_loop => [{ text => 'Disc 1', params => { item_id => 'a.1' } }, { text => 'CD 2', actions => { go => { params => { item_id => 'a.2' } } } }, { text => 'Credits', params => { item_id => 'x' } }] }),
		['a.1', 'a.2'], 'podmeni diskova';
}

# --- Resolver ---
sub make_resolver {
	my (%data) = @_;
	my (@searches, @delays, @progress);
	my $resolver = Plugins::UnifiedMusic::Import::Resolver->new(
		order    => $data{order} || [qw(local qobuz tidal)],
		search   => sub { my ($type, $source, $term, $done) = @_; push @searches, "$type:$source:$term"; $done->($data{$source}{$term} || []) },
		expand   => sub { my ($item, $done) = @_; $done->($data{albums}{ $item->{title} } || []) },
		delay    => sub { push @delays, 1; $_[0]->() },
		progress => sub { push @progress, [@_[0, 1]] },
	);
	return ($resolver, \@searches, \@delays, \@progress);
}

{
	my ($resolver, $searches, $delays, $progress) = make_resolver(
		local => { 'Miles Davis So What' => [{ kind => 'track', artist => 'Miles Davis', title => 'So What', source => 'local', url => 'file:///so-what.flac', album => 'Kind of Blue' }] },
		qobuz => {
			'Hiromi Spark' => [{ kind => 'album', artist => 'Hiromi', title => 'Spark', source => 'qobuz', browse => 'b.1' }],
			'Nobody Nothing' => [],
		},
		tidal => { 'Hiromi Voice' => [{ kind => 'album', artist => 'Hiromi', title => 'Voice', source => 'tidal' }] },
		albums => { Spark => ['qobuz://1.flac', 'qobuz://2.flac', 'qobuz://3.flac'] },
	);
	my @out;
	$resolver->resolve([
		{ type => 'track', artist => 'Miles Davis', title => 'So What', alternatives => [] },
		{ type => 'album', artist => 'Hiromi', title => 'Spark', artist_only => 1, alternatives => ['Voice'] },
		{ type => 'track', artist => 'Nobody', title => 'Nothing', alternatives => [] },
	], sub { push @out, $_[0] });

	my $results = $out[0];
	is scalar @$results, 3, 'sve stavke imaju rezultat';
	is_deeply $results->[0]{found}{urls}, ['file:///so-what.flac'], 'lokalna pesma';
	is $results->[0]{found}{album}, 'Kind of Blue', 'album pesme se cuva';
	ok !grep({ /^track:qobuz:Miles/ } @$searches), 'tacan lokalni pogodak ne zove servise';
	is_deeply $results->[1]{found}{urls}, ['qobuz://1.flac', 'qobuz://2.flac', 'qobuz://3.flac'], 'album razvijen u pesme';
	ok $results->[1]{artist_only}, 'oznaka reprezentativnog albuma';
	ok !grep({ /Voice/ } @$searches), 'alternativa se ne trazi kad je prvi album nadjen';
	ok $results->[2]{missing}, 'stavka koja nije nadjena';
	is_deeply $progress, [[1, 3], [2, 3], [3, 3]], 'napredak';
}

{
	my ($resolver, $searches) = make_resolver(
		qobuz => { 'Hiromi Spark' => [{ kind => 'album', artist => 'Hiromi', title => 'Spark', source => 'qobuz' }] },
		tidal => { 'Hiromi Voice' => [{ kind => 'album', artist => 'Hiromi', title => 'Voice', source => 'tidal' }] },
		albums => { Voice => ['tidal://9.flc'] },
	);
	my @out;
	$resolver->resolve([{ type => 'album', artist => 'Hiromi', title => 'Spark', alternatives => ['Voice'] }], sub { push @out, $_[0] });
	is $out[0][0]{found}{title}, 'Voice', 'album bez pesama -> alternativa';
	is $out[0][0]{found}{source}, 'tidal', 'izvor alternative';
}

{
	my ($resolver) = make_resolver(
		order => [qw(tidal local qobuz)],
		local => { 'A T' => [{ kind => 'track', artist => 'A', title => 'T (Live)', source => 'local', url => 'file:///live' }] },
		tidal => { 'A T' => [{ kind => 'track', artist => 'A', title => 'T (Live)', source => 'tidal', play => { url => 'tidal://1.flc' } }] },
		qobuz => { 'A T' => [{ kind => 'track', artist => 'A', title => 'T', source => 'qobuz', play => { url => 'qobuz://2.flac' } }] },
	);
	my @out;
	$resolver->resolve([{ type => 'track', artist => 'A', title => 'T', alternatives => [] }], sub { push @out, $_[0] });
	is $out[0][0]{found}{source}, 'qobuz', 'tacan pogodak kasnijeg izvora je bolji od priblizng';

	($resolver) = make_resolver(
		order => [qw(tidal local qobuz)],
		local => { 'A T' => [{ kind => 'track', artist => 'A', title => 'T (Live)', source => 'local', url => 'file:///live' }] },
		tidal => { 'A T' => [{ kind => 'track', artist => 'A', title => 'T (Live)', source => 'tidal', play => { url => 'tidal://1.flc' } }] },
	);
	@out = ();
	$resolver->resolve([{ type => 'track', artist => 'A', title => 'T', alternatives => [] }], sub { push @out, $_[0] });
	is $out[0][0]{found}{source}, 'tidal', 'ista ocena -> redosled izvora';
}

# --- Job ---
package FakeAdapter {
	sub new { my ($c, @answers) = @_; bless { answers => \@answers, requests => [] }, $c }
	sub suggest { my ($s, $r, $done) = @_; push @{ $s->{requests} }, $r; $done->(shift @{ $s->{answers} }) }
}
package FakeResolver {
	sub new { my ($c, $results) = @_; bless { results => $results }, $c }
	sub resolve { my ($s, $items, $done) = @_; $s->{items} = $items; $done->($s->{results}) }
}
package main;

my $results3 = [
	{ type => 'album', artist => 'Hiromi', title => 'Spark', found => { source => 'qobuz', urls => ['q://1', 'q://2'] } },
	{ type => 'track', artist => 'X', title => 'Y', found => { source => 'local', urls => ['q://2'] } },
	{ type => 'track', artist => 'Z', title => 'W', missing => 1 },
];
my $fusion = { name => 'Fusion', items => [{ type => 'album', artist => 'Hiromi', title => 'Spark' }, { type => 'track', artist => 'X', title => 'Y' }] };

{
	my $adapter = FakeAdapter->new({ error => 'HTTP 500', retryable => 1 }, { list => { %$fusion } });
	my @out;
	Plugins::UnifiedMusic::Import::Job::extract({ adapter => $adapter, model => 'm', api_key => 'k', text => 'lista', date => '2026-11-13' }, sub { push @out, $_[0] });
	is scalar @{ $adapter->{requests} }, 2, 'ponovljen zahtev posle privremene greske';
	is $adapter->{requests}[0]{schema_name}, 'listening_list', 'sema liste';
	is $out[0]{list}{name}, 'Fusion', 'predlog naziva od modela';
	is scalar @{ $out[0]{list}{items} }, 2, 'stavke za pregled';

	@out = ();
	Plugins::UnifiedMusic::Import::Job::extract({ adapter => FakeAdapter->new({ list => { name => '  ', items => [{ type => 'track', artist => 'A', title => 'B' }] } }), text => 'x', date => '2026-11-13' }, sub { push @out, $_[0] });
	is $out[0]{list}{name}, 'Imported list 2026-11-13', 'naziv kad ga model ne predlozi';
}

{
	my (@created, @out, @progress);
	Plugins::UnifiedMusic::Import::Job::build({
		list => $fusion, target => { name => '  Moja   lista ' }, resolver => FakeResolver->new($results3), date => '2026-11-13', model => 'm',
		create => sub { push @created, [@_[0, 1]]; $_[2]->({ id => 7, name => "$_[0] (2)" }) },
		append => sub { die 'ne sme' },
		progress => sub { push @progress, $_[0]{stage} },
	}, sub { push @out, $_[0] });
	is $created[0][0], 'Moja lista', 'naziv koji je korisnik izmenio';
	is_deeply $created[0][1], ['q://1', 'q://2'], 'adrese bez ponavljanja';
	is $out[0]{name}, 'Moja lista (2)', 'stvarni naziv plejliste';
	is $out[0]{playlist_id}, 7, 'id plejliste';
	is_deeply [@{ $out[0] }{qw(found total tracks)}], [2, 3, 2], 'nadjeno, ukupno, pesama';
	ok !$out[0]{appended}, 'nova plejlista';
	is_deeply \@progress, [qw(searching saving)], 'faze';

	(@created, @out) = ();
	Plugins::UnifiedMusic::Import::Job::build({
		list => $fusion, target => { name => '' }, resolver => FakeResolver->new($results3), date => 'd',
		create => sub { push @created, $_[0]; $_[2]->({ id => 1, name => $_[0] }) },
	}, sub { push @out, $_[0] });
	is $created[0], 'Fusion', 'prazan naziv -> predlog modela';

	my @appended;
	@out = ();
	Plugins::UnifiedMusic::Import::Job::build({
		list => $fusion, target => { id => 42, name => 'Jazz favorites' }, resolver => FakeResolver->new($results3), date => 'd',
		create => sub { die 'ne sme' },
		append => sub { push @appended, [@_[0, 1]]; $_[2]->({ id => $_[0] }) },
	}, sub { push @out, $_[0] });
	is_deeply \@appended, [[42, ['q://1', 'q://2']]], 'dopuna postojece plejliste';
	is $out[0]{name}, 'Jazz favorites', 'naziv postojece plejliste';
	is $out[0]{playlist_id}, 42, 'id postojece plejliste';
	ok $out[0]{appended}, 'oznaka dopune';
}

{
	my @out;
	Plugins::UnifiedMusic::Import::Job::extract({ adapter => FakeAdapter->new, text => '  ' }, sub { push @out, $_[0] });
	like $out[0]{error}, qr/Paste/, 'prazan tekst';

	@out = ();
	Plugins::UnifiedMusic::Import::Job::build({
		list => { name => 'N', items => [{ type => 'track', artist => 'A', title => 'B' }] },
		resolver => FakeResolver->new([{ type => 'track', artist => 'A', title => 'B', missing => 1 }]),
		target => { name => 'Moja' }, create => sub { die 'ne sme' },
	}, sub { push @out, $_[0] });
	like $out[0]{error}, qr/None of the 1/, 'nista nije nadjeno';
	is scalar @{ $out[0]{items} }, 1, 'stavke ostaju za pregled';

	@out = ();
	my $adapter = FakeAdapter->new({ list => { name => 'N', items => [] }, raw => '{}' }, { list => { name => 'N', items => [{ type => 'track', artist => 'A', title => 'B' }] } });
	Plugins::UnifiedMusic::Import::Job::extract({ adapter => $adapter, text => 'x' }, sub { push @out, $_[0] });
	is scalar @{ $adapter->{requests} }, 2, 'prazna lista se ponavlja jednom';
	is scalar @{ $out[0]{list}{items} }, 1, 'drugi pokusaj uspeva';

	@out = ();
	Plugins::UnifiedMusic::Import::Job::extract({ adapter => FakeAdapter->new({ error => 'HTTP 401', retryable => 0 }), text => 'x' }, sub { push @out, $_[0] });
	like $out[0]{error}, qr/HTTP 401/, 'greska modela';
}

# --- Adapteri sa semom liste ---
{
	my $text = $json->encode({ name => 'N', items => [{ type => 'track', artist => 'A', title => 'B', album => '', artist_only => JSON::PP::false, alternatives => [] }] });
	my $request = {
		model => 'm', api_key => 'k', prompt => { system => 'S', user => 'U' },
		schema => Plugins::UnifiedMusic::Import::Prompt::schema(), schema_name => 'listening_list', parse => \&Plugins::UnifiedMusic::Import::Prompt::parse,
	};

	my (@req, @done);
	Plugins::UnifiedMusic::AI::Anthropic->new(http => sub { push @req, $_[0]; $_[1]->({ status => 200, body => $json->encode({ stop_reason => 'end_turn', content => [{ type => 'text', text => $text }] }) }) })
		->suggest($request, sub { push @done, $_[0] });
	ok $json->decode($req[0]{body})->{output_config}{format}{schema}{properties}{items}, 'anthropic salje semu liste';
	is $done[0]{list}{items}[0]{title}, 'B', 'anthropic vraca listu';

	(@req, @done) = ();
	Plugins::UnifiedMusic::AI::OpenAI->new(http => sub { push @req, $_[0]; $_[1]->({ status => 200, body => $json->encode({ status => 'completed', output => [{ type => 'message', content => [{ type => 'output_text', text => $text }] }] }) }) })
		->suggest($request, sub { push @done, $_[0] });
	is $json->decode($req[0]{body})->{text}{format}{name}, 'listening_list', 'openai naziv seme';
	is $done[0]{list}{name}, 'N', 'openai vraca listu';
}

# --- History ---
{
	my $dir = tempdir(CLEANUP => 1);
	my $history = Plugins::UnifiedMusic::Import::History->new(file => "$dir/x/imports.json");
	is_deeply $history->list, [], 'prazna istorija';
	$history->add({ id => "id$_", name => "N$_" }) for 1 .. 35;
	is scalar @{ $history->list }, 30, 'cuva se poslednjih 30';
	is $history->list->[0]{id}, 'id35', 'najnoviji prvi';
	is $history->get('id20')->{name}, 'N20', 'trazenje po id';
	ok $history->remove('id20'), 'brisanje';
	ok !$history->remove('id20'), 'drugo brisanje nema efekta';
	is $history->get('id20'), undef, 'obrisan';
}

# --- Dopuna plejliste ide u isti zapis; stari razdvojeni zapisi se spajaju ---
{
	my $dir = tempdir(CLEANUP => 1);
	my $history = Plugins::UnifiedMusic::Import::History->new(file => "$dir/imports.json");
	$history->add({ id => 'a', name => 'Jazz', playlist_id => 7, found => 3, total => 3, tracks => 24, created => 1, items => [{ title => 'A' }] });
	$history->add({ id => 'b', name => 'Druga', playlist_id => 8, found => 1, total => 1, tracks => 5, created => 2, items => [{ title => 'B' }] });
	my $saved = $history->add_to_playlist({ id => 'c', name => 'Jazz', playlist_id => 7, appended => 1, found => 1, total => 2, tracks => 7, created => 3, date => 'D', items => [{ title => 'C' }, { title => 'C2' }] });
	is $saved->{id}, 'a', 'dopuna zadrzava zapis plejliste';
	is scalar @{ $history->list }, 2, 'nema novog zapisa';
	is $history->list->[0]{id}, 'a', 'dopunjena lista ide na vrh';
	is_deeply [map { $_->{title} } @{ $saved->{items} }], ['A', 'C', 'C2'], 'stavke se nadovezuju';
	is_deeply [@$saved{qw(found total tracks date)}], [4, 5, 31, 'D'], 'zbir brojeva i novi datum';
	ok !$saved->{appended}, 'lista napravljena uvozom ostaje obicna';
	is $history->add_to_playlist({ id => 'd', name => 'Tudja', playlist_id => 9, appended => 1, items => [] })->{id}, 'd', 'prva dopuna druge plejliste je novi zapis';

	my $old = Plugins::UnifiedMusic::Import::History->new(file => "$dir/old.json");
	$old->add($_) for
		{ id => 'x1', name => 'H', playlist_id => 1, found => 12, total => 12, tracks => 82, created => 10, items => [{ title => 1 }] },
		{ id => 'y',  name => 'Y', playlist_id => 2, found => 1, total => 1, tracks => 1, created => 11, items => [] },
		{ id => 'x2', name => 'H', playlist_id => 1, appended => 1, found => 9, total => 9, tracks => 79, created => 12, items => [{ title => 2 }] },
		{ id => 'x3', name => 'H', playlist_id => 1, appended => 1, found => 17, total => 20, tracks => 182, created => 13, items => [{ title => 3 }] },
		{ id => 'e',  name => 'E', error => 'x', created => 14 };
	ok $old->compact, 'spajanje starih zapisa';
	is_deeply [map { $_->{id} } @{ $old->list }], ['e', 'x1', 'y'], 'jedan zapis po plejlisti, po vremenu';
	is_deeply [@{ $old->get('x1') }{qw(found total tracks)}], [38, 41, 343], 'zbir';
	is_deeply [map { $_->{title} } @{ $old->get('x1')->{items} }], [1, 2, 3], 'redosled stavki';
	ok !$old->compact, 'drugi put nema izmena';

	is $old->set_name('x1', 'Novo')->{name}, 'Novo', 'promena naziva';
	is $old->get('x1')->{name}, 'Novo', 'naziv je zapisan';
	is $old->set_name('nema', 'X'), undef, 'nepostojeci zapis';
}

done_testing;
