package Plugins::UnifiedMusic::Mix::Resolver;

# Pretvara predloge modela u stvarne pesme. Pretraga se ubacuje.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Normalize qw(track_key);

sub new {
	my ($class, %args) = @_;
	return bless { search => $args{search}, defer => $args{defer} }, $class;
}

sub _version_url {
	my ($version) = @_;
	return $version->{url} // ($version->{play} ? $version->{play}{url} : undef);
}

sub match_track {
	my ($response, $key) = @_;

	for my $group (@{ $response->{tracks} || [] }) {
		next unless track_key($group->{artist}, $group->{title}) eq $key;
		my ($version) = grep { defined _version_url($_) } @{ $group->{versions} };
		next unless $version;

		my %track = (
			title  => $version->{title} // $group->{title},
			artist => $version->{artist} // $group->{artist},
			source => $version->{source},
			url    => _version_url($version),
		);
		for my $field (qw(album image)) {
			$track{$field} = $version->{$field} if defined $version->{$field};
		}
		return \%track;
	}
	return undef;
}

sub resolve {
	my ($self, $suggestions, $count, $done) = @_;

	my @queue = @$suggestions;
	my (@tracks, %seen);

	my $next;
	$next = sub {
		while (@queue && @tracks < $count) {
			my $suggestion = shift @queue;
			my $key = track_key($suggestion->{artist}, $suggestion->{title});
			next if $seen{$key}++;

			$self->{search}->("$suggestion->{artist} $suggestion->{title}", sub {
				my ($response) = @_;
				my $track = match_track($response, $key);
				push @tracks, $track if $track;
				# Odlaganje cuva petlju servera i izbegava duboku rekurziju.
				return $self->{defer}->($next) if $self->{defer};
				$next->();
			}, $key);
			return;
		}
		undef $next;
		$done->(\@tracks);
	};
	$next->();
}

1;
