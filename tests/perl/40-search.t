use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Search;

sub album { my ($source, $title) = @_; return { kind => 'album', source => $source, title => $title, artist => 'A', play => {} } }

package FakeSource {
	sub new { my ($class, %args) = @_; return bless { %args, calls => 0 }, $class }
	sub search {
		my ($self, $term, $ctx, $done) = @_;
		$self->{calls}++;
		$self->{done} = $done;
		$self->respond if $self->{immediate};
	}
	sub respond {
		my ($self) = @_;
		$self->{done}->({ items => $self->{items} || [], missing => $self->{missing} || [] });
	}
}

sub build {
	my (%sources) = @_;
	my %timer;
	my $search = Plugins::UnifiedMusic::Search->new(
		sources      => \%sources,
		source_order => [qw(local qobuz tidal)],
		set_timer    => sub { $timer{seconds} = $_[0]; $timer{cb} = $_[1]; return 'handle' },
		cancel_timer => sub { $timer{cancelled} = $_[0] },
		timeout      => 5,
	);
	return ($search, \%timer);
}

{
	my ($search, $timer) = build(
		local => FakeSource->new(immediate => 1, items => [album('local', 'X'), { kind => 'other', list => 'works', source => 'local', title => 'W', play => {} }]),
		qobuz => FakeSource->new(immediate => 1, items => [album('qobuz', 'X'), { kind => 'track', source => 'qobuz', title => 'T', artist => 'A', play => {} }]),
		tidal => FakeSource->new(immediate => 1, items => [{ kind => 'other', list => 'playlists', source => 'tidal', title => 'P', play => {} }, { kind => 'artist', source => 'tidal', title => 'A', play => {} }]),
	);
	my @out;
	$search->run('x', {}, sub { push @out, $_[0] });
	is scalar @out, 1, 'done jednom';
	is $timer->{seconds}, 5, 'limit 5 s';
	is $timer->{cancelled}, 'handle', 'tajmer otkazan';
	my $r = $out[0];
	is_deeply $r->{missing}, [], 'nema nedostajucih';
	is scalar @{ $r->{albums} }, 1, 'albumi spojeni';
	is scalar @{ $r->{albums}[0]{versions} }, 2, 'obe verzije';
	is scalar @{ $r->{tracks} }, 1, 'pesme';
	is scalar @{ $r->{artists} }, 1, 'izvodjaci';
	is scalar @{ $r->{works} }, 1, 'dela';
	is scalar @{ $r->{playlists} }, 1, 'plejliste';
	ok !exists $r->{works}[0]{versions}[0]{list}, 'list se ne vraca';
}

{
	my $silent = FakeSource->new(items => [album('tidal', 'Kasno')]);
	my ($search, $timer) = build(local => FakeSource->new(immediate => 1, items => [album('local', 'X')]), tidal => $silent);
	my @out;
	$search->run('x', {}, sub { push @out, $_[0] });
	is scalar @out, 0, 'ceka spori izvor';
	$timer->{cb}->();
	is scalar @out, 1, 'tajmer zavrsava';
	is_deeply $out[0]{missing}, ['tidal'], 'spori izvor nedostaje';
	is scalar @{ $out[0]{albums} }, 1, 'ostali rezultati postoje';

	$silent->respond;
	is scalar @out, 1, 'kasan odgovor ne zavrsava ponovo';
	is scalar @{ $out[0]{albums} }, 1, 'kasan odgovor ne menja rezultat';
}

{
	my ($search) = build(
		qobuz => FakeSource->new(immediate => 1, missing => ['qobuz']),
		tidal => FakeSource->new(immediate => 1, missing => ['qobuz']),
	);
	my @out;
	$search->run('x', {}, sub { push @out, $_[0] });
	is_deeply $out[0]{missing}, ['qobuz'], 'missing je jedinstven';
}

{
	*parse_source_order = \&Plugins::UnifiedMusic::Search::parse_source_order;
	is_deeply parse_source_order(undef), [qw(local qobuz tidal)], 'undef daje podrazumevani redosled';
	is_deeply parse_source_order(''), [qw(local qobuz tidal)], 'prazno daje podrazumevani redosled';
	is_deeply parse_source_order('tidal,qobuz,local'), [qw(tidal qobuz local)], 'zadati redosled';
	is_deeply parse_source_order(' tidal , qobuz'), [qw(tidal qobuz local)], 'izostavljen izvor ide na kraj';
	is_deeply parse_source_order('spotify,qobuz,qobuz'), [qw(qobuz local tidal)], 'nepoznato i duplikat se ignorisu';
}

{
	*order_for = \&Plugins::UnifiedMusic::Search::source_order_for_primary;
	*primary_from = \&Plugins::UnifiedMusic::Search::primary_from_order;
	is_deeply order_for('local'), [qw(local qobuz tidal)], 'primarni local';
	is_deeply order_for('qobuz'), [qw(qobuz local tidal)], 'primarni qobuz';
	is_deeply order_for('tidal'), [qw(tidal local qobuz)], 'primarni tidal';
	is_deeply order_for('xyz'), [qw(local qobuz tidal)], 'nepoznat primarni';
	is primary_from('tidal,qobuz,local'), 'tidal', 'migracija reda';
	is primary_from(undef), 'local', 'migracija bez vrednosti';
}

for my $term ('', '   ') {
	my $source = FakeSource->new(immediate => 1);
	my ($search, $timer) = build(local => $source);
	my @out;
	$search->run($term, {}, sub { push @out, $_[0] });
	is $source->{calls}, 0, 'prazna pretraga ne zove izvore';
	is_deeply $out[0], { albums => [], tracks => [], artists => [], works => [], playlists => [], missing => [] }, 'prazan odgovor';
	ok !$timer->{seconds}, 'prazna pretraga bez tajmera';
}

done_testing;
