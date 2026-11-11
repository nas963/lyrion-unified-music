use strict;
use warnings;
use utf8;
use Test::More;
use JSON::PP;
use Plugins::UnifiedMusic::Source::Service;

*parse_text = \&Plugins::UnifiedMusic::Source::Service::parse_text;

sub fixture {
	my ($name) = @_;
	open my $fh, '<:raw', "t/fixtures/$name.json" or die "$name: $!";
	local $/;
	return JSON::PP->new->utf8->decode(scalar <$fh>);
}

sub go_id {
	my ($menu, $text) = @_;
	my ($item) = grep { $_->{text} eq $text } @{ $menu->{item_loop} };
	return $item->{actions}{go}{params}{item_id};
}

sub fake_run {
	my (%opts) = @_;
	my $root = fixture('gs_root');
	my %map;
	for my $service (['Qobuz', 'qobuz', 'Releases'], ['TIDAL', 'tidal', 'Albums']) {
		my ($name, $key, $albums) = @$service;
		my $menu = fixture("${key}_root");
		$map{ go_id($root, $name) } = $menu;
		$map{ go_id($menu, $albums) } = fixture("${key}_albums");
		$map{ go_id($menu, 'Songs') } = fixture("${key}_tracks");
		$map{ go_id($menu, 'Artists') } = fixture("${key}_artists");
		$map{ go_id($menu, 'Playlists') } = fixture("${key}_playlists") unless $opts{no_playlists};
	}
	return sub {
		my ($client, $cmd, $cb) = @_;
		return $cb->(undef) if $opts{fail};
		my ($search) = grep { /^search:/ } @$cmd;
		return $cb->($root) if $search;
		my ($id) = map { /^item_id:(.*)/ ? $1 : () } @$cmd;
		return $cb->($map{$id});
	};
}

sub run_search {
	my ($service, $run, $ctx) = @_;
	my @calls;
	my @logged;
	my $source = Plugins::UnifiedMusic::Source::Service->new(service => $service, run => $run, log => sub { push @logged, $_[0] });
	$source->search('Kind of Blue', $ctx // { client => 'aa:bb' }, sub { push @calls, $_[0] });
	return (\@calls, \@logged);
}

sub by_title {
	my ($items, $kind, $title) = @_;
	my ($found) = grep { $_->{kind} eq $kind && $_->{title} eq $title } @$items;
	return $found;
}

is_deeply parse_text('qobuz', 'track', "So What\nMiles Davis - Kind Of Blue"),
	{ title => 'So What', artist => 'Miles Davis', album => 'Kind Of Blue' }, 'qobuz pesma';
is_deeply parse_text('qobuz', 'album', "Kind Of Blue\nMiles Davis (1959)"),
	{ title => 'Kind Of Blue', artist => 'Miles Davis', year => 1959 }, 'qobuz album';
is_deeply parse_text('qobuz', 'album', "Kind Of Blue\nMiles Davis"),
	{ title => 'Kind Of Blue', artist => 'Miles Davis' }, 'qobuz album bez godine';
is_deeply parse_text('tidal', 'track', "Bitter Blue - Radio Version\nKind Of Blue"),
	{ title => 'Bitter Blue - Radio Version', artist => 'Kind Of Blue' }, 'tidal pesma';
is_deeply parse_text('tidal', 'album', "Kind Of Blue (Legacy Edition)\nMiles Davis"),
	{ title => 'Kind Of Blue (Legacy Edition)', artist => 'Miles Davis' }, 'tidal album';
is_deeply parse_text('qobuz', 'track', "T\nA - B - C"), { title => "T\nA - B - C" }, 'dvosmislen tekst';
is_deeply parse_text('qobuz', 'track', 'Samo naslov'), { title => 'Samo naslov' }, 'jedan red';

{
	my ($calls) = run_search('qobuz', fake_run());
	is scalar @$calls, 1, 'qobuz: done jednom';
	is_deeply $calls->[0]{missing}, [], 'qobuz: nista ne nedostaje';
	my $items = $calls->[0]{items};
	my $track = by_title($items, 'track', 'So What');
	is_deeply $track->{play}, { url => 'qobuz://13176083.flac' }, 'qobuz pesma ima url';
	is $track->{source}, 'qobuz', 'qobuz izvor';
	is $track->{album}, 'Kind Of Blue', 'qobuz album uz pesmu';
	my $album = by_title($items, 'album', 'Kind Of Blue');
	ok $album->{play}{item_id}, 'qobuz album ima item_id';
	ok !$album->{play}{url}, 'qobuz album nema url';
	is $album->{year}, 1959, 'qobuz godina';
	ok $album->{image}, 'qobuz slika';
	my ($other) = grep { $_->{kind} eq 'other' } @$items;
	is $other->{list}, 'playlists', 'plejlista ide u listu playlists';
	ok grep({ $_->{kind} eq 'artist' } @$items), 'qobuz izvodjaci';
}

{
	my ($calls) = run_search('tidal', fake_run());
	is_deeply $calls->[0]{missing}, [], 'tidal: nista ne nedostaje';
	my $album = by_title($calls->[0]{items}, 'album', 'Kind Of Blue (Legacy Edition)');
	is_deeply $album->{play}, { url => 'tidal://album:2178485' }, 'tidal album ima url';
	my $track = by_title($calls->[0]{items}, 'track', 'Bitter Blue - Radio Version');
	is_deeply $track->{play}, { url => 'tidal://169025.flc' }, 'tidal pesma ima url';
}

{
	my ($calls, $logged) = run_search('qobuz', fake_run(no_playlists => 1));
	is scalar @$calls, 1, 'neuspeo podmeni: done jednom';
	is_deeply $calls->[0]{missing}, ['qobuz'], 'neuspeo podmeni: missing';
	ok scalar @$logged, 'neuspeo podmeni: zapis u log';
	ok scalar @{ $calls->[0]{items} }, 'neuspeo podmeni: ostale liste se cuvaju';
}

{
	my $menu = fixture('qobuz_root');
	$menu->{item_loop} = [grep { $_->{text} ne 'Playlists' } @{ $menu->{item_loop} }];
	my $root = fixture('gs_root');
	my $albums_id = go_id($menu, 'Releases');
	my $run = sub {
		my ($client, $cmd, $cb) = @_;
		return $cb->($root) if grep { /^search:/ } @$cmd;
		my ($id) = map { /^item_id:(.*)/ ? $1 : () } @$cmd;
		return $cb->($menu) if $id eq go_id($root, 'Qobuz');
		return $cb->($id eq $albums_id ? fixture('qobuz_albums') : { item_loop => [] });
	};
	my ($calls, $logged) = run_search('qobuz', $run);
	is_deeply $calls->[0]{missing}, [], 'prazna kategorija nije ispad';
	is scalar @$logged, 0, 'prazna kategorija bez zapisa u log';
	ok by_title($calls->[0]{items}, 'album', 'Kind Of Blue'), 'ostale kategorije ostaju';
}

{
	# Qobuz spljosti meni kada samo jedna kategorija ima pogotke.
	my $root = fixture('gs_root');
	my $flat = fixture('qobuz_tracks');
	my $run = sub {
		my ($client, $cmd, $cb) = @_;
		return $cb->($root) if grep { /^search:/ } @$cmd;
		return $cb->($flat);
	};
	my ($calls) = run_search('qobuz', $run);
	is_deeply $calls->[0]{missing}, [], 'spljosten meni nije ispad';
	my $track = by_title($calls->[0]{items}, 'track', 'So What');
	is_deeply $track->{play}, { url => 'qobuz://13176083.flac' }, 'spljosten meni daje pesme';
}

{
	my $classify = \&Plugins::UnifiedMusic::Source::Service::classify_flat;
	is $classify->({ text => "A\nB (1999)", type => 'playlist' }), 'album', 'album sa godinom';
	is $classify->({ text => "Lista\nQobuz UK", type => 'playlist' }), 'other', 'plejlista';
	is $classify->({ text => 'Miles', actions => { go => {} } }), 'artist', 'izvodjac';
	is $classify->({ text => 'Empty', type => 'text' }), undef, 'tekst se preskace';
	is $classify->({ text => "T\nA - B", presetParams => { favorites_url => 'qobuz://1.flac' } }), 'track', 'pesma';
}

{
	my $menu = fixture('tidal_root');
	my $root = fixture('gs_root');
	my $run = sub {
		my ($client, $cmd, $cb) = @_;
		return $cb->($root) if grep { /^search:/ } @$cmd;
		my ($id) = map { /^item_id:(.*)/ ? $1 : () } @$cmd;
		return $cb->($menu) if $id eq go_id($root, 'TIDAL');
		return $cb->({ item_loop => [{ text => 'Empty', type => 'text', style => 'itemNoAction', action => 'none' }] });
	};
	my ($calls) = run_search('tidal', $run);
	is_deeply $calls->[0], { items => [], missing => [] }, 'poruka Empty nije rezultat';
}

{
	my ($calls) = run_search('tidal', fake_run(fail => 1));
	is scalar @$calls, 1, 'greska: done jednom';
	is_deeply $calls->[0], { items => [], missing => ['tidal'] }, 'greska: missing';
}

{
	my $called = 0;
	my ($calls) = run_search('qobuz', sub { $called++ }, {});
	is_deeply $calls->[0], { items => [], missing => ['qobuz'] }, 'bez plejera: missing';
	is $called, 0, 'bez plejera: nema poziva';
}

done_testing;
