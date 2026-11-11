package Plugins::UnifiedMusic::Mix::OrderedSearch;

# Trazi pesmu izvor po izvor i staje na prvom pogotku, da servisi dobiju sto manje upita.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Grouper qw(group_items);
use Plugins::UnifiedMusic::Mix::Resolver;

sub new {
	my ($class, %args) = @_;
	return bless { %args }, $class;
}

sub search {
	my ($self, $term, $done, $key) = @_;

	my @queue = @{ $self->{order} };
	my $next;
	$next = sub {
		my $name = shift @queue;
		if (!$name) {
			undef $next;
			return $done->({ tracks => [] });
		}

		$self->{sources}{$name}->search($term, { client => $self->{client} }, sub {
			my ($result) = @_;
			my $response = { tracks => group_items($result->{items}, $term, $self->{order}) };

			if (Plugins::UnifiedMusic::Mix::Resolver::match_track($response, $key)) {
				undef $next;
				return $self->_after($name, sub { $done->($response) });
			}
			$self->_after($name, $next);
		});
	};
	$next->();
}

sub _after {
	my ($self, $source, $callback) = @_;

	return $callback->() if $source eq 'local';
	$self->{delay}->($callback);
}

1;
