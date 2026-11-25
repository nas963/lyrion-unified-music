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

# Duza snimka je po pravilu ceo album u jednom fajlu. Servisi ne vracaju trajanje, pa se tada ne proverava.
use constant MAX_SECONDS => 30 * 60;

sub _version_url {
	my ($version) = @_;
	return $version->{url} // ($version->{play} ? $version->{play}{url} : undef);
}

sub match_track {
	my ($response, $key) = @_;

	for my $group (@{ $response->{tracks} || [] }) {
		next unless track_key($group->{artist}, $group->{title}) eq $key;
		my ($version) = grep { defined _version_url($_) && ($_->{duration} // 0) <= MAX_SECONDS } @{ $group->{versions} };
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

# Najvise pesama istog izvodjaca dok ima drugih predloga; visak dopunjava listu tek na kraju.
use constant MAX_PER_ARTIST => 2;

sub _artist_key {
	my ($artist) = @_;
	my $key = lc($artist // '');
	$key =~ s/^\s*the\s+//;
	$key =~ s/\s+/ /g;
	$key =~ s/^\s+|\s+$//g;
	return $key;
}

sub resolve {
	my ($self, $suggestions, $count, $done) = @_;

	my @queue = @$suggestions;
	my (@tracks, %seen, %per_artist, @overflow);
	my $capped = 1;

	my $next;
	$next = sub {
		while (@tracks < $count) {
			if (!@queue) {
				last unless $capped && @overflow;
				$capped = 0;
				@queue = splice @overflow;
			}
			my $suggestion = shift @queue;
			my $key = track_key($suggestion->{artist}, $suggestion->{title});
			my $artist = _artist_key($suggestion->{artist});
			if ($capped && ($per_artist{$artist} // 0) >= MAX_PER_ARTIST) {
				push @overflow, $suggestion;
				next;
			}
			next if $seen{$key}++;

			$self->{search}->("$suggestion->{artist} $suggestion->{title}", sub {
				my ($response) = @_;
				my $track = match_track($response, $key);
				if ($track) {
					push @tracks, $track;
					$per_artist{$artist}++;
				}
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
