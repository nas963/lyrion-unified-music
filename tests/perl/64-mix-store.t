use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Find;
use Plugins::UnifiedMusic::Mix::Store;

*slug = \&Plugins::UnifiedMusic::Mix::Store::slug;

my $dir = tempdir(CLEANUP => 1);
my $store = Plugins::UnifiedMusic::Mix::Store->new(dir => $dir);

sub mix { my ($date, $category) = @_; return { category => $category, date => $date, model => 'm', tracks => [{ title => 'Ђаз ñ', url => 'u' }] } }

$store->save(mix('2026-11-10', 'Džez'));
is_deeply $store->load('2026-11-10', 'Džez'), mix('2026-11-10', 'Džez'), 'save i load, UTF-8';
is $store->load('2026-11-11', 'Džez'), undef, 'nepostojeci dan';

for my $name ('../a/b', '"Jazz"', 'Džez', 'Ђаз', 'a/b', 'a b') {
	unlike slug($name), qr{[/\\]|\.\.}, "slug bezbedan: $name";
	like slug($name), qr/^[\w.-]+$/a, "slug je ASCII: $name";
}
isnt slug('Ђаз'), slug('Рок'), 'cirilicne kategorije se razlikuju';
isnt slug('a/b'), slug('a b'), 'slicni nazivi se razlikuju';

$store->save(mix('2026-11-08', 'Džez'));
$store->save(mix('2026-11-09', 'Džez'));
is_deeply $store->dates('Džez'), ['2026-11-10', '2026-11-09', '2026-11-08'], 'dates novije prvo';
is $store->latest('Džez')->{date}, '2026-11-10', 'latest';

{
	my $bad = "$dir/2026-11-12";
	mkdir $bad;
	open my $fh, '>', "$bad/" . slug('Džez') . '.json' or die $!;
	print $fh '{oste';
	close $fh;
	is $store->latest('Džez')->{date}, '2026-11-10', 'latest preskace osteceno';
}

{
	my @tmp;
	find(sub { push @tmp, $_ if /\.tmp$/ }, $dir);
	is scalar @tmp, 0, 'nema privremenih fajlova';
}

{
	my $s = Plugins::UnifiedMusic::Mix::Store->new(dir => tempdir(CLEANUP => 1));
	$s->save(mix($_, 'Ambiemt')) for qw(2026-11-09 2026-11-10);
	$s->save(mix('2026-11-10', 'Ambient'));
	is $s->rename_category('Ambiemt', 'Ambient'), 1, 'prenosi samo dane bez sukoba';
	is $s->load('2026-11-09', 'Ambient')->{category}, 'Ambient', 'miks ima novi naziv';
	is $s->load('2026-11-09', 'Ambiemt'), undef, 'stari fajl je uklonjen';
	ok $s->load('2026-11-10', 'Ambiemt'), 'postojeci miks novog naziva se ne brise, stari ostaje';
	is $s->rename_category('Nema', 'Nesto'), 0, 'nepostojeca kategorija';
	is $s->rename_category('Ambient', 'Ambient'), 0, 'isti naziv';
}

{
	my $s = Plugins::UnifiedMusic::Mix::Store->new(dir => tempdir(CLEANUP => 1));
	$s->save(mix($_, 'J')) for qw(2026-11-03 2026-11-04 2026-11-10);
	$s->prune('2026-11-11', 7);
	is_deeply $s->dates('J'), ['2026-11-10', '2026-11-04'], 'prune 7 dana';
}

done_testing;
