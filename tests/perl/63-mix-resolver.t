use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Mix::Resolver;

sub group {
	my ($title, $artist, @versions) = @_;
	return { title => $title, artist => $artist, sources => [map { $_->{source} } @versions], versions => \@versions };
}
sub v { my ($source, $url, %rest) = @_; return { source => $source, play => $url ? { url => $url } : { item_id => 'x' }, url => $url, %rest } }

sub resolver {
	my ($answers, $log) = @_;
	return Plugins::UnifiedMusic::Mix::Resolver->new(search => sub {
		my ($term, $cb) = @_;
		push @$log, $term;
		$cb->($answers->{$term} // { tracks => [], missing => [] });
	});
}

sub s1 { return { artist => $_[0], title => $_[1] } }

{
	my @log;
	my $r = resolver({
		'Miles Davis So What' => { tracks => [
			group('So What (Live)', 'Miles Davis', v('local', 'file:///a')),
			group('So What', 'Miles Davis', { source => 'qobuz', play => { item_id => 'i' } }, v('tidal', 'tidal://1.flc', album => 'KOB', image => '/i')),
		], missing => ['local'] },
	}, \@log);
	my @done;
	$r->resolve([s1('Miles Davis', 'So What'), s1('Nema', 'Pesme')], 30, sub { push @done, $_[0] });
	is scalar @done, 1, 'done jednom';
	is_deeply $done[0], [{ title => 'So What', artist => 'Miles Davis', album => 'KOB', source => 'tidal', url => 'tidal://1.flc', image => '/i' }],
		'tacna grupa, prva verzija sa URL-om; bez poklapanja se preskace';
	is_deeply \@log, ['Miles Davis So What', 'Nema Pesme'], 'pojmovi redom';
}

{
	my @log;
	my %answers = map { ("A T$_" => { tracks => [group("T$_", 'A', v('local', "file:///$_"))] }) } 1 .. 5;
	my @done;
	resolver(\%answers, \@log)->resolve([map { s1('A', "T$_") } 1 .. 5], 2, sub { push @done, $_[0] });
	is scalar @{ $done[0] }, 2, 'staje na broju pesama';
	is scalar @log, 2, 'ne trazi dalje';
}

{
	my @log;
	my @done;
	resolver({ 'A T' => { tracks => [group('T', 'A', v('local', 'file:///t'))] } }, \@log)
		->resolve([s1('A', 'T'), s1('a', 't (Remastered)'), s1('A', 'T')], 10, sub { push @done, $_[0] });
	is scalar @{ $done[0] }, 1, 'duplirani predlozi daju jednu pesmu';
	is scalar @log, 1, 'duplikat se ne trazi ponovo';
}

{
	my (@deferred, @done);
	my %answers = map { ("A T$_" => { tracks => [] }) } 1 .. 3;
	my $r = Plugins::UnifiedMusic::Mix::Resolver->new(
		search => sub { $_[1]->($answers{ $_[0] }) },
		defer  => sub { push @deferred, $_[0] },
	);
	$r->resolve([map { s1('A', "T$_") } 1 .. 3], 10, sub { push @done, $_[0] });
	is scalar @done, 0, 'ceka odlozeni korak';
	(shift @deferred)->() while @deferred;
	is_deeply \@done, [[]], 'zavrsava kroz odlozene korake';
}

{
	my @log;
	my %answers = map {
		my ($artist, $title) = @$_;
		("$artist $title" => { tracks => [group($title, $artist, v('local', "file:///$artist$title"))] })
	} (map({ ['Genesis', "G$_"] } 1 .. 4), ['Rush', 'R1'], ['Yes', 'Y1']);
	my @done;
	resolver(\%answers, \@log)->resolve(
		[(map { s1('Genesis', "G$_") } 1 .. 4), s1('Rush', 'R1'), s1('Yes', 'Y1')], 4, sub { push @done, $_[0] });
	is_deeply [map { $_->{title} } @{ $done[0] }], [qw(G1 G2 R1 Y1)], 'najvise dve pesme istog izvodjaca';
	is_deeply \@log, ['Genesis G1', 'Genesis G2', 'Rush R1', 'Yes Y1'], 'visak izvodjaca se ne trazi bez potrebe';

	@done = ();
	resolver(\%answers, [])->resolve(
		[(map { s1('Genesis', "G$_") } 1 .. 4), s1('Rush', 'R1')], 5, sub { push @done, $_[0] });
	is_deeply [map { $_->{title} } @{ $done[0] }], [qw(G1 G2 R1 G3 G4)], 'visak dopunjava listu kad nema drugih';
}

{
	my @done;
	resolver({}, [])->resolve([], 10, sub { push @done, $_[0] });
	is_deeply \@done, [[]], 'prazna lista';
}

{
	my $key = Plugins::UnifiedMusic::Normalize::track_key('Mike Oldfield', 'Tubular Bells');
	my $match = sub {
		return Plugins::UnifiedMusic::Mix::Resolver::match_track({ tracks => [group('Tubular Bells (1973)', 'Mike Oldfield', @_)] }, $key);
	};
	is $match->(v('local', 'file:///cd', duration => 2677)), undef, 'ceo album u jednom fajlu se preskace';
	is $match->(v('local', 'file:///cd', duration => 2677), v('local', 'file:///t', duration => 280))->{url}, 'file:///t', 'uzima se kraca verzija';
	is $match->(v('local', 'file:///l', duration => 1713))->{url}, 'file:///l', 'duga pesma ostaje';
	is $match->(v('local', 'file:///l', duration => 1800))->{url}, 'file:///l', 'tacno na granici ostaje';
	is $match->(v('qobuz', 'qobuz://1.flac'))->{url}, 'qobuz://1.flac', 'nepoznato trajanje ne iskljucuje';
}

{
	my $find = sub {
		my ($artist, $title, @groups) = @_;
		my $t = Plugins::UnifiedMusic::Mix::Resolver::match_track({ tracks => \@groups }, Plugins::UnifiedMusic::Mix::Resolver::suggestion_key($artist, $title));
		return $t ? $t->{url} : undef;
	};
	my $g = sub { my ($title, $url, %rest) = @_; return group($title, 'M', v('local', $url, title => $title, %rest)) };

	for my $form ('TB (Part One)', 'TB {Part One}', 'TB - Part one', 'TB Part 1', 'TB, Pt. I', 'TB (Pt.1)', 'TB Pt 1', 'TB (Part One) [2009 Remaster]') {
		is $find->('M', 'TB', $g->($form, 'u')), 'u', "bez oznake nalazi: $form";
		is $find->('M', 'TB (Part 1)', $g->($form, 'u')), 'u', "isti deo: $form";
		is $find->('M', 'TB (Part 2)', $g->($form, 'u')), undef, "drugi deo se ne mesa: $form";
	}
	is $find->('M', 'TB', $g->('TB Part Two', 'u2'), $g->('TB Part One', 'u1')), 'u1', 'bira se prvi deo';
	is $find->('M', 'TB', $g->('TB Part Two', 'u2')), 'u2', 'ako nema prvog, najraniji';
	is $find->('M', 'TB', $g->('TB Part One', 'u1'), $g->('TB', 'u')), 'u', 'tacan naslov ima prednost';
	is $find->('M', 'TB', $g->('TB', 'cd', duration => 2677), $g->('TB Part One', 'u1', duration => 1531)), 'u1', 'umesto celog albuma prvi deo';
	is $find->('M', 'TB', $g->('Part One', 'a', album => 'TB (25th Anniversary Edition)')), 'a', 'deo na istoimenom albumu';
	is $find->('M', 'TB (Pt. 2)', $g->('Part TWO', 'a', album => 'TB')), 'a', 'trazeni deo na istoimenom albumu';
	is $find->('M', 'TB', $g->('Part One', 'a', album => 'TB II')), undef, 'drugi album se ne uzima';
	is $find->('M', 'TB', $g->('Part One', 'a')), undef, 'bez albuma se ne uzima';
	is $find->('M', 'TB', $g->('TB Part One (Excerpt)', 'a')), undef, 'odlomak se ne uzima';
	is $find->('M', 'TB', $g->('TB II Part One', 'a')), undef, 'drugo delo se ne uzima';
	is $find->('X', 'TB', $g->('TB Part One', 'a')), undef, 'drugi izvodjac se ne uzima';
	is $find->('M', 'Shine', $g->('Shine, Pts. 6-9', 'u6'), $g->('Shine (Parts I - V)', 'u1')), 'u1', 'raspon delova';
	is $find->('M', 'Shine (Parts 1-5)', $g->('Shine, Pts. I-V', 'u')), 'u', 'isti raspon, drugi zapis';
	is $find->('M', 'Shine (Part 1)', $g->('Shine (Parts 1-5)', 'u')), undef, 'deo nije raspon';
	is $find->('M', 'X', $g->('X Parti', 'u')), undef, 'Parti nije oznaka dela';

	is $find->('Jean-Michel Jarre', 'Oxygène (Part IV)', group('Oxygène, Part 4', 'Jean Michel Jarre', v('local', 'j'))), 'j', 'crtica u imenu';

	my (@log, @done);
	resolver({ 'M TB' => { tracks => [$g->('TB Part One', 'u1'), $g->('TB Part Two', 'u2')] } }, \@log)
		->resolve([s1('M', 'TB'), s1('M', 'TB (Pt. I)'), s1('M', 'TB, Part 2')], 10, sub { push @done, $_[0] });
	is_deeply [map { $_->{url} } @{ $done[0] }], ['u1', 'u2'], 'isti deo ne ulazi dvaput';
	is $log[1], 'M TB', 'pretraga bez oznake dela';
}

done_testing;
