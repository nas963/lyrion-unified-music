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
	my @done;
	resolver({}, [])->resolve([], 10, sub { push @done, $_[0] });
	is_deeply \@done, [[]], 'prazna lista';
}

done_testing;
