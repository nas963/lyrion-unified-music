package Plugins::UnifiedMusic::Mix::Resolver;

# Pretvara predloge modela u stvarne pesme. Pretraga se ubacuje.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Normalize qw(title_key same_artist_key track_key part_title without_part);

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

sub suggestion_key {
	my ($artist, $title) = @_;
	return track_key($artist, part_title($title));
}

# Osnova i redni broj dela iz vec sredjenog naslova.
sub _split_part {
	my ($key) = @_;
	return ($1, $2) if $key =~ /^(?:(.+) )?part (\d+)(?: to \d+)?$/;
	return ($key);
}

# Najbolja verzija: tacan naslov, zatim isti deo na istoimenom albumu ("Part One" sa "Tubular Bells"),
# a za predlog bez oznake dela najraniji deo.
sub _find {
	my ($response, $key) = @_;

	my ($artist, $wanted) = split /\x1f/, $key, 2;
	my (undef, $part) = _split_part($wanted);
	my ($best, $best_rank);

	for my $group (@{ $response->{tracks} || [] }) {
		next unless same_artist_key($group->{artist}) eq $artist;
		for my $version (@{ $group->{versions} }) {
			next unless defined _version_url($version) && ($version->{duration} // 0) <= MAX_SECONDS;

			my $title = title_key(part_title($version->{title} // $group->{title}));
			my $rank = [0, 0];
			if ($title ne $wanted) {
				my ($base, $own_part) = _split_part($title);
				next unless defined $own_part;
				my $from_album = defined $base ? 0 : 1;
				if ($from_album) {
					next unless defined $version->{album};
					$base = title_key($version->{album});
					$title = "$base $title";
				}
				next unless (defined $part ? $title : $base) eq $wanted;
				$rank = [$own_part, $from_album];
			}
			next if $best_rank && ($best_rank->[0] <=> $rank->[0] || $best_rank->[1] <=> $rank->[1]) <= 0;
			$best_rank = $rank;
			$best = { group => $group, version => $version, key => "$artist\x1f$title" };
		}
	}
	return $best;
}

sub _track {
	my ($found) = @_;

	my ($group, $version) = @$found{qw(group version)};
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

sub match_track {
	my ($response, $key) = @_;

	my $found = _find($response, $key);
	return $found ? _track($found) : undef;
}

# Najvise pesama istog izvodjaca dok ima drugih predloga; visak dopunjava listu tek na kraju.
use constant MAX_PER_ARTIST => 2;

sub _artist_key {
	my ($artist) = @_;
	my $name = $artist // '';
	$name =~ s/^\s*the\s+//i;
	return same_artist_key($name);
}

sub resolve {
	my ($self, $suggestions, $count, $done) = @_;

	my @queue = @$suggestions;
	my (@tracks, %seen, %taken, %per_artist, @overflow);
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
			my $key = suggestion_key($suggestion->{artist}, $suggestion->{title});
			my $artist = _artist_key($suggestion->{artist});
			if ($capped && ($per_artist{$artist} // 0) >= MAX_PER_ARTIST) {
				push @overflow, $suggestion;
				next;
			}
			next if $seen{$key}++;

			$self->{search}->("$suggestion->{artist} " . without_part($suggestion->{title}), sub {
				my ($response) = @_;
				my $found = _find($response, $key);
				# "Tubular Bells" i "Tubular Bells (Part One)" mogu dati istu pesmu.
				if ($found && !$taken{ $found->{key} }++) {
					push @tracks, _track($found);
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
