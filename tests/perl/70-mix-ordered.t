use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Mix::OrderedSearch;
use Plugins::UnifiedMusic::Normalize qw(track_key);
use Plugins::UnifiedMusic::Source::Service;
use Plugins::UnifiedMusic::Source::Local;

package FakeOrderedSource {
	sub new { my ($c, %a) = @_; bless { %a, calls => 0 }, $c }
	sub search { my ($s, $t, $ctx, $done) = @_; $s->{calls}++; $done->({ items => $s->{items} || [], missing => [] }) }
}
package main;

sub hit { my ($source, $url) = @_; return [{ kind => 'track', source => $source, title => 'T', artist => 'A', url => $url, play => { url => $url } }] }

my $key = track_key('A', 'T');

sub setup {
	my (%items) = @_;
	my %sources = map { $_ => FakeOrderedSource->new(items => $items{$_}) } qw(local qobuz tidal);
	my @delays;
	my $search = Plugins::UnifiedMusic::Mix::OrderedSearch->new(
		sources => \%sources, order => $items{order} || [qw(local qobuz tidal)], client => 'c',
		delay => sub { push @delays, 1; $_[0]->() },
	);
	return ($search, \%sources, \@delays);
}

{
	my ($search, $sources, $delays) = setup(local => hit('local', 'file:///a'), qobuz => hit('qobuz', 'q://1'));
	my @out;
	$search->search('A T', sub { push @out, $_[0] }, $key);
	is $sources->{qobuz}{calls}, 0, 'lokalni pogodak ne zove servis';
	is scalar @$delays, 0, 'bez servisa nema pauze';
	is $out[0]{tracks}[0]{versions}[0]{url}, 'file:///a', 'lokalna pesma';
}

{
	my ($search, $sources, $delays) = setup(tidal => hit('tidal', 't://1'));
	my @out;
	$search->search('A T', sub { push @out, $_[0] }, $key);
	is $sources->{qobuz}{calls}, 1, 'zove qobuz';
	is $sources->{tidal}{calls}, 1, 'zove tidal';
	is scalar @$delays, 2, 'pauza posle svakog servisa';
	is $out[0]{tracks}[0]{versions}[0]{source}, 'tidal', 'pogodak sa tidal';
}

{
	my ($search, $sources) = setup(qobuz => hit('qobuz', 'q://1'), tidal => hit('tidal', 't://1'), order => [qw(tidal local qobuz)]);
	my @out;
	$search->search('A T', sub { push @out, $_[0] }, $key);
	is $sources->{local}{calls}, 0, 'staje na prvom izvoru po redosledu';
	is $out[0]{tracks}[0]{versions}[0]{source}, 'tidal', 'primarni izvor';
}

{
	my ($search) = setup();
	my @out;
	$search->search('A T', sub { push @out, $_[0] }, $key);
	is_deeply $out[0], { tracks => [] }, 'bez pogotka';
}

{
	my @commands;
	my $run = sub { my ($c, $cmd, $cb) = @_; push @commands, $cmd->[0]; $cb->({}) };
	Plugins::UnifiedMusic::Source::Local->new(run => $run, only => 'track')->search('x', {}, sub {});
	is_deeply \@commands, ['tracks'], 'lokalno samo pesme';
}

{
	my %menu = (item_loop => [map { { text => $_, actions => { go => { params => { item_id => $_ } } } } } qw(Releases Artists Songs Playlists)]);
	my @opened;
	my $run = sub {
		my ($c, $cmd, $cb) = @_;
		return $cb->({ item_loop => [{ text => 'Qobuz', actions => { go => { params => { item_id => 'menu' } } } }] }) if grep { /^search:/ } @$cmd;
		my ($id) = map { /^item_id:(.*)/ ? $1 : () } @$cmd;
		return $cb->(\%menu) if $id eq 'menu';
		push @opened, $id;
		$cb->({ item_loop => [] });
	};
	Plugins::UnifiedMusic::Source::Service->new(service => 'qobuz', run => $run, only => 'track')->search('x', { client => 'c' }, sub {});
	is_deeply \@opened, ['Songs'], 'servis otvara samo pesme';
}

{
	my %sources = (local => FakeOrderedSource->new(items => []), tidal => FakeOrderedSource->new(items => hit('tidal', 't://1')));
	my @delays;
	my $search = Plugins::UnifiedMusic::Mix::OrderedSearch->new(
		sources => \%sources, order => [qw(qobuz local tidal)], client => 'c',
		delay => sub { push @delays, 1; $_[0]->() },
	);
	my @out;
	$search->search('A T', sub { push @out, $_[0] }, $key);
	is $out[0]{tracks}[0]{versions}[0]{url}, 't://1', 'servis bez plugina se preskace';
	is scalar @delays, 1, 'pauza samo posle stvarnog servisa';
}

done_testing;
