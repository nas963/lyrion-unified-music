use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use Plugins::UnifiedMusic::Mix::Store;
use Plugins::UnifiedMusic::Mix::Cli;

*categories = \&Plugins::UnifiedMusic::Mix::Cli::categories;
*mix_items = \&Plugins::UnifiedMusic::Mix::Cli::mix_items;
*queue_commands = \&Plugins::UnifiedMusic::Mix::Cli::queue_commands;

my $store = Plugins::UnifiedMusic::Mix::Store->new(dir => tempdir(CLEANUP => 1));
my $config = { categories => [{ name => 'Jazz', genres => ['B'] }, { name => 'Rock', genres => ['P'] }, { name => 'Nov', genres => ['X'] }] };

sub mix { my ($date, $category, @urls) = @_; return { category => $category, date => $date, model => 'm', tracks => [map { { title => $_, artist => 'A', source => 'local', url => $_ } } @urls] } }

$store->save(mix('2026-11-11', 'Jazz', 'a', 'b'));
$store->save(mix('2026-11-10', 'Jazz', 'c'));
$store->save(mix('2026-11-10', 'Rock', 'd'));

{
	my $rows = categories($store, $config, '2026-11-11');
	is scalar @$rows, 3, 'sve kategorije';
	is_deeply $rows->[0], { name => 'Jazz', date => '2026-11-11', count => 2, stale => 0, previous => ['2026-11-10'] }, 'danasnji miks';
	is_deeply $rows->[1], { name => 'Rock', date => '2026-11-10', count => 1, stale => 1, previous => [] }, 'zastareo miks';
	is_deeply $rows->[2], { name => 'Nov', date => undef, count => 0, stale => 0, previous => [] }, 'bez miksa';
}

{
	my $resp = mix_items($store, 'Jazz', undef, '2026-11-11');
	is $resp->{date}, '2026-11-11', 'danasnji datum';
	is scalar @{ $resp->{tracks} }, 2, 'pesme';
	is_deeply $resp->{previous}, ['2026-11-10'], 'prethodni dani';
	is_deeply mix_items($store, 'Jazz', '2026-11-10', '2026-11-11')->{previous}, [], 'stariji dan nema prethodne';
	is_deeply mix_items($store, 'Rock', undef, '2026-11-11')->{previous}, [], 'nema starijih';
	is_deeply mix_items($store, 'Nema', undef, '2026-11-11'), { date => undef, tracks => [], previous => [] }, 'nepostojeca';
}

{
	my $new = \&Plugins::UnifiedMusic::Mix::Cli::new_playlist_id;
	is_deeply $new->({ playlist_id => 5 }), { id => 5 }, 'nova plejlista';
	is_deeply $new->({ overwritten_playlist_id => 7 }), { exists => 1 }, 'naziv vec postoji';
	is_deeply $new->(undef), { error => 1 }, 'komanda nije uspela';
	is_deeply $new->({}), { error => 1 }, 'prazan odgovor';
}

is_deeply queue_commands('play', ['a', 'b']), [['playlist', 'play', 'a'], ['playlist', 'add', 'b']], 'play';
is_deeply queue_commands('add', ['a', 'b']), [['playlist', 'add', 'a'], ['playlist', 'add', 'b']], 'add';
is_deeply queue_commands('insert', ['a', 'b']), [['playlist', 'insert', 'b'], ['playlist', 'insert', 'a']], 'insert zadrzava redosled';
is_deeply queue_commands('play', []), [], 'prazan miks';

done_testing;
