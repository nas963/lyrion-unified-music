use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Mix::Prompt;

*build = \&Plugins::UnifiedMusic::Mix::Prompt::build;

my $category = { name => 'Jazz', genres => ['Bebop', 'Cool Jazz', 'Fusion'] };

{
	my $p = build({ category => $category, count => 30, rng => sub { 0 } });
	is $p->{requested}, 90, 'tri puta vise predloga';
	like $p->{user}, qr/\b90\b/, 'broj predloga u zahtevu';
	like $p->{user}, qr/Jazz/, 'naziv kategorije';
	like $p->{user}, qr/Bebop/, 'izabrani zanr';
	like $p->{user}, qr/\b19\d0s|\b20\d0s/, 'decenija';
	like $p->{user}, qr/well-known/i, 'odnos poznatih i manje poznatih';
	like $p->{system}, qr/real/i, 'trazi stvarne pesme';
	like $p->{system}, qr/invent/i, 'zabranjuje izmisljanje';
}

is_deeply build({ category => $category, count => 30, rng => sub { 1 } }),
	build({ category => $category, count => 30, rng => sub { 1 } }), 'fiksan rng daje isti izlaz';

isnt build({ category => $category, count => 30, rng => sub { 0 } })->{user},
	build({ category => $category, count => 30, rng => sub { 1 } })->{user}, 'razlicit rng daje drugi naglasak';

done_testing;
