package Plugins::UnifiedMusic::Search;

# Pokrece izvore paralelno, primenjuje limit i pravi konacan odgovor.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Grouper qw(group_items);

my %LIST_FOR_KIND = (album => 'albums', track => 'tracks', artist => 'artists');
my @LISTS = qw(albums tracks artists works playlists);

my @DEFAULT_ORDER = qw(local qobuz tidal);

sub new {
	my ($class, %args) = @_;
	return bless { %args }, $class;
}

sub source_order_for_primary {
	my ($primary) = @_;

	my %known = map { $_ => 1 } @DEFAULT_ORDER;
	$primary = 'local' unless defined $primary && $known{$primary};

	return [$primary, grep { $_ ne $primary } @DEFAULT_ORDER];
}

sub primary_from_order {
	my ($text) = @_;

	return parse_source_order($text)->[0];
}

sub parse_source_order {
	my ($text) = @_;

	my %known = map { $_ => 1 } @DEFAULT_ORDER;
	my %seen;
	my @order = grep { $known{$_} && !$seen{$_}++ } split /\s*,\s*/, ($text // '') =~ s/^\s+|\s+$//gr;

	return [@order, grep { !$seen{$_} } @DEFAULT_ORDER];
}

sub run {
	my ($self, $term, $ctx, $done) = @_;

	$term //= '';
	if ($term !~ /\S/) {
		return $done->({ (map { $_ => [] } @LISTS), missing => [] });
	}

	my %sources = %{ $self->{sources} };
	my %pending = map { $_ => 1 } keys %sources;
	my (@items, %missing, $handle, $finished);

	my $finish = sub {
		return if $finished;
		$finished = 1;
		$self->{cancel_timer}->($handle) if defined $handle;
		$missing{$_} = 1 for keys %pending;
		$done->($self->_response(\@items, $term, \%missing));
	};

	$handle = $self->{set_timer}->($self->{timeout}, $finish);

	for my $name (keys %sources) {
		$sources{$name}->search($term, $ctx, sub {
			my ($result) = @_;
			return if $finished;
			delete $pending{$name};
			push @items, @{ $result->{items} };
			$missing{$_} = 1 for @{ $result->{missing} };
			$finish->() unless %pending;
		});
	}
}

sub _response {
	my ($self, $items, $term, $missing) = @_;

	my %buckets = map { $_ => [] } @LISTS;
	for my $item (@$items) {
		my %copy = %$item;
		my $list = delete($copy{list}) // $LIST_FOR_KIND{ $copy{kind} };
		push @{ $buckets{$list} }, \%copy;
	}

	my %response = map { $_ => group_items($buckets{$_}, $term, $self->{source_order}) } @LISTS;
	my $position = 0;
	my %rank = map { $_ => $position++ } @{ $self->{source_order} };
	$response{missing} = [sort { ($rank{$a} // $position) <=> ($rank{$b} // $position) || $a cmp $b } keys %$missing];

	return \%response;
}

1;
