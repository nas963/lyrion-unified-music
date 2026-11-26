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

# Odstupanje od trajanja koje je naveo model, a koje se jos smatra istom verzijom.
sub _off_length {
	my ($version, $minutes) = @_;

	my $seconds = $version->{duration};
	return 0 unless $minutes && $seconds;
	my $expected = $minutes * 60;
	my $diff = abs($seconds - $expected);
	my $tolerance = $expected * 0.35 > 90 ? $expected * 0.35 : 90;
	return $diff <= $tolerance ? 0 : $diff;
}

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
# a za predlog bez oznake dela najraniji deo. Medju istim naslovima prednost ima trajanje koje je naveo model.
sub _find {
	my ($response, $key, $minutes, $used_albums) = @_;

	my ($artist, $wanted) = split /\x1f/, $key, 2;
	my (undef, $part) = _split_part($wanted);
	my ($best, $best_rank);

	for my $group (@{ $response->{tracks} || [] }) {
		next unless same_artist_key($group->{artist}) eq $artist;
		for my $version (@{ $group->{versions} }) {
			next unless defined _version_url($version) && ($version->{duration} // 0) <= MAX_SECONDS;

			my $title = title_key(part_title($version->{title} // $group->{title}));
			my $rank = [0, 0, 0, 0];
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
				$rank = [$own_part, 0, 0, $from_album];
			}
			$rank->[1] = _off_length($version, $minutes);
			# Verzija sa albuma koji je vec u miksu dolazi tek posle ostalih.
			my $album = _album_key($version->{album});
			$rank->[2] = $used_albums && defined $album && $used_albums->{$album} ? 1 : 0;
			next if $best_rank && _compare($best_rank, $rank) <= 0;
			$best_rank = $rank;
			$best = { group => $group, version => $version, key => "$artist\x1f$title" };
		}
	}
	return $best;
}

sub _compare {
	my ($left, $right) = @_;
	for my $index (0 .. $#$left) {
		my $result = $left->[$index] <=> $right->[$index];
		return $result if $result;
	}
	return 0;
}

sub _album_key {
	my ($album) = @_;
	return undef unless defined $album;
	my $key = title_key($album);
	return length $key ? $key : undef;
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
	my ($response, $key, $minutes) = @_;

	my $found = _find($response, $key, $minutes);
	return $found ? _track($found) : undef;
}

# Najvise dve pesme istog izvodjaca i jedna sa istog albuma dok ima drugih predloga; visak dopunjava listu tek na kraju.
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
	my (@tracks, %seen, %taken, %per_artist, %per_album, @overflow, @held);
	my $capped = 1;

	my $next;
	$next = sub {
		while (@tracks < $count) {
			if (!@queue) {
				last unless $capped && (@overflow || @held);
				$capped = 0;
				for my $found (splice @held) {
					push @tracks, _track($found) if @tracks < $count && !$taken{ $found->{key} }++;
				}
				@queue = splice @overflow;
				next;
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
				my $found = _find($response, $key, $suggestion->{minutes}, $capped ? \%per_album : undef);
				# "Tubular Bells" i "Tubular Bells (Part One)" mogu dati istu pesmu.
				if ($found && !$taken{ $found->{key} }) {
					my $album = _album_key($found->{version}{album});
					if ($capped && defined $album && $per_album{$album}) {
						push @held, $found;
					}
					else {
						$taken{ $found->{key} }++;
						push @tracks, _track($found);
						$per_artist{$artist}++;
						$per_album{$album}++ if defined $album;
					}
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
