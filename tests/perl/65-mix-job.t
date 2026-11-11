use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Mix::Job;

package FakeStore {
	sub new { bless { saved => [], pruned => [] }, shift }
	sub save { my ($s, $m) = @_; push @{ $s->{saved} }, $m }
	sub prune { my ($s, @a) = @_; push @{ $s->{pruned} }, [@a] }
}
package FakeAdapter {
	sub new { my ($c, %a) = @_; bless { %a, calls => [] }, $c }
	sub suggest {
		my ($s, $req, $done) = @_;
		push @{ $s->{calls} }, $req;
		my $next = shift @{ $s->{script} };
		$done->($next);
	}
}
package FakeResolver {
	sub new { my ($c, %a) = @_; bless { %a }, $c }
	sub resolve { my ($s, $list, $count, $done) = @_; $s->{count} = $count; $done->($s->{tracks}) }
}
package main;

my $SUGGEST = { suggestions => [{ artist => 'A', title => 'T' }] };
my $TRACKS = [{ title => 'T', artist => 'A', source => 'local', url => 'u' }];

sub run_job {
	my (%args) = @_;
	my $store = FakeStore->new;
	my $adapter = FakeAdapter->new(script => $args{script});
	my $resolver = FakeResolver->new(tracks => $args{tracks} // $TRACKS);
	my (@done, @logged);
	Plugins::UnifiedMusic::Mix::Job::run({
		config   => { categories => $args{categories}, trackCount => 30, model => 'claude-haiku-5-5', anthropicKey => 'k' },
		adapter  => $adapter, resolver => $resolver, store => $store, rng => sub { 0 },
		date     => '2026-11-11', log => sub { push @logged, $_[0] },
	}, sub { push @done, $_[0] });
	return ($store, $adapter, $resolver, \@done, \@logged);
}

my @two = ({ name => 'Jazz', genres => ['Bebop'] }, { name => 'Rock', genres => ['Punk'] });

{
	my ($store, $adapter, $resolver, $done) = run_job(categories => \@two, script => [$SUGGEST, $SUGGEST]);
	is scalar @$done, 1, 'done jednom';
	is_deeply $done->[0], { ok => ['Jazz', 'Rock'], failed => [] }, 'obe uspele';
	is_deeply [map { $_->{category} } @{ $store->{saved} }], ['Jazz', 'Rock'], 'redom';
	is $store->{saved}[0]{date}, '2026-11-11', 'datum';
	is $store->{saved}[0]{model}, 'claude-haiku-5-5', 'model';
	is $adapter->{calls}[0]{api_key}, 'k', 'kljuc modela';
	is $resolver->{count}, 30, 'broj pesama';
	is_deeply $store->{pruned}, [['2026-11-11', 7]], 'brisanje starih';
}

{
	my ($store, $adapter, undef, $done) = run_job(categories => [$two[0]],
		script => [{ error => 'x', retryable => 1 }, $SUGGEST]);
	is scalar @{ $adapter->{calls} }, 2, 'ponovljiva greska ponavlja jednom';
	is_deeply $done->[0]{ok}, ['Jazz'], 'uspeh posle ponavljanja';
}

{
	my (undef, $adapter, undef, $done) = run_job(categories => [$two[0]],
		script => [{ error => 'x', retryable => 1 }, { error => 'y', retryable => 1 }]);
	is scalar @{ $adapter->{calls} }, 2, 'najvise jedno ponavljanje';
	is $done->[0]{failed}[0]{name}, 'Jazz', 'neuspeh';
}

{
	my ($store, $adapter, undef, $done, $logged) = run_job(categories => \@two,
		script => [{ error => 'nope', retryable => 0 }, $SUGGEST]);
	is scalar @{ $adapter->{calls} }, 2, 'neponovljiva greska bez ponavljanja, ostale nastavljaju';
	is_deeply [map { $_->{category} } @{ $store->{saved} }], ['Rock'], 'neuspela ne upisuje';
	is_deeply $done->[0]{failed}, [{ name => 'Jazz', error => 'nope' }], 'greska po kategoriji';
	ok scalar @$logged, 'zapis u log';
}

{
	my ($store, $adapter, undef, $done) = run_job(categories => [{ %{ $two[0] }, active => 0 }, { %{ $two[1] }, active => 1 }], script => [$SUGGEST]);
	is scalar @{ $adapter->{calls} }, 1, 'neaktivna kategorija ne zove model';
	is_deeply $done->[0]{ok}, ['Rock'], 'samo aktivna';
	is_deeply [map { $_->{category} } @{ $store->{saved} }], ['Rock'], 'samo aktivna se upisuje';
}

{
	no warnings 'redefine';
	local *FakeStore::save = sub { my ($s, $m) = @_; die "disk\n" if $m->{category} eq 'Jazz'; push @{ $s->{saved} }, $m };
	my ($store, undef, undef, $done, $logged) = run_job(categories => \@two, script => [$SUGGEST, $SUGGEST]);
	is $done->[0]{failed}[0]{name}, 'Jazz', 'neuspeo upis je neuspeh kategorije';
	is_deeply $done->[0]{ok}, ['Rock'], 'ostale nastavljaju posle neuspelog upisa';
	ok scalar @$logged, 'neuspeo upis u log';
}

{
	no warnings 'redefine';
	local *FakeStore::prune = sub { die "disk\n" };
	my (undef, undef, undef, $done) = run_job(categories => [$two[0]], script => [$SUGGEST]);
	is scalar @$done, 1, 'neuspelo brisanje ne zaustavlja kraj posla';
}

{
	my (undef, $adapter, undef, $done) = run_job(categories => [{ %{ $two[0] }, active => 0 }], script => []);
	is scalar @{ $adapter->{calls} }, 0, 'sve neaktivne: bez poziva';
	is_deeply $done->[0], { ok => [], failed => [] }, 'sve neaktivne: prazan ishod';
}

{
	my ($store, undef, undef, $done) = run_job(categories => [$two[0]], script => [$SUGGEST], tracks => []);
	is scalar @{ $store->{saved} }, 0, 'nula pesama ne upisuje';
	is $done->[0]{failed}[0]{name}, 'Jazz', 'nula pesama je neuspeh';
}

done_testing;
