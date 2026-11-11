use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Grouper qw(group_items);

sub a { my ($source, $title) = @_; return { kind => 'album', source => $source, title => $title, artist => 'Miles Davis', play => {} } }
sub o { my ($source, $title) = @_; return { kind => 'other', source => $source, title => $title, play => {} } }
sub f { my ($format, $rate, $size) = @_; return { %{ a('local', 'X') }, format => $format, samplerate => $rate, samplesize => $size } }
sub mark { my ($item, $n) = @_; $item->{n} = $n; return $item }

my @order = qw(local qobuz tidal);

{
	my $g = group_items([a('tidal', 'Kind Of Blue (Legacy Edition)'), a('qobuz', 'Kind Of Blue'), a('local', 'Kind of Blue')], 'kind of blue', \@order);
	is scalar @$g, 1, 'verzije su jedna grupa';
	is scalar @{ $g->[0]{versions} }, 3, 'nista se ne gubi';
	is_deeply $g->[0]{sources}, ['local', 'qobuz', 'tidal'], 'izvori po podesavanju';
	is $g->[0]{title}, 'Kind of Blue', 'naslov iz prve verzije';
	is $g->[0]{artist}, 'Miles Davis', 'izvodjac iz prve verzije';
	ok !exists $g->[0]{versions}[0]{kind}, 'kind se ne vraca';
}

is scalar @{ group_items([a('local', 'X'), a('local', 'X (Live)')], 'x', \@order) }, 2, 'Live je zasebna grupa';

{
	my $v = group_items([f('flc', 44100, 16), f('flc', 96000, 24), f('flc', 96000, 16), f('dsf', 2822400, 1)], 'x', \@order)->[0]{versions};
	is_deeply [map { "$_->{format}/$_->{samplerate}/$_->{samplesize}" } @$v],
		['dsf/2822400/1', 'flc/96000/24', 'flc/96000/16', 'flc/44100/16'], 'lokalni kvalitet';
}

{
	my $s = group_items([a('tidal', 'X'), mark(a('qobuz', 'X'), 1), mark(a('qobuz', 'X'), 2)], 'x', ['tidal', 'qobuz']);
	is $s->[0]{versions}[0]{source}, 'tidal', 'izvor po podesavanju';
	is $s->[0]{versions}[1]{n}, 1, 'servis cuva svoj redosled';
	is $s->[0]{versions}[2]{n}, 2, 'servis cuva svoj redosled 2';
}

{
	my $r = group_items([a('qobuz', 'Say So What'), a('tidal', 'So What Now'), a('tidal', 'So What')], 'so what', \@order);
	is_deeply [map { $_->{title} } @$r], ['So What', 'So What Now', 'Say So What'], 'rang: tacno, pocinje, ostalo';
}

{
	my $r = group_items([a('tidal', 'Blue'), a('qobuz', 'Blue Two'), a('local', 'Blue Three'), a('local', 'Blue Alpha')], 'zzz', \@order);
	is_deeply [map { $_->{title} } @$r], ['Blue Alpha', 'Blue Three', 'Blue Two', 'Blue'], 'unutar nivoa izvor pa naslov';
}

is scalar @{ group_items([o('local', 'P'), o('qobuz', 'P')], 'p', \@order) }, 2, 'other se ne spaja';
is_deeply group_items([], 'x', \@order), [], 'prazan ulaz';

done_testing;
