package Plugins::UnifiedMusic::Import::Resolver;

# Za svaku stavku liste trazi album ili pesmu po redosledu izvora i vraca adrese pesama.
# Pretraga, razvijanje albuma u pesme i pauza se ubacuju.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Import::Match qw(best score movement_key EXACT THRESHOLD);

use constant MAX_MOVEMENTS => 40;
use constant MIN_ALBUM_TRACKS => 3;

sub new {
	my ($class, %args) = @_;
	return bless { delay => sub { $_[0]->() }, defer => sub { $_[0]->() }, progress => sub {}, %args }, $class;
}

sub _url {
	my ($item) = @_;
	return $item->{url} // ($item->{play} ? $item->{play}{url} : undef);
}

# Trazi jedan naslov kroz sve izvore; tacan pogodak prekida trazenje, inace pobedjuje najbolja ocena,
# a pri istoj oceni raniji izvor.
sub _find {
	my ($self, $want, $term, $done) = @_;

	my @queue = @{ $self->{order} };
	my $top;
	my $next;
	$next = sub {
		my $source = shift @queue;
		if (!defined $source) {
			undef $next;
			return $done->($top);
		}
		$self->{search}->($want->{type}, $source, $term, sub {
			my ($items) = @_;
			my @usable = $want->{type} eq 'track' ? grep { defined _url($_) } @{ $items || [] } : @{ $items || [] };
			my $match = best($want, \@usable, $want->{type});
			$match->{items} = \@usable if $match;
			$top = $match if $match && (!$top || $match->{tier} > $top->{tier} || $match->{tier} == $top->{tier} && $match->{score} > $top->{score});
			my $continue = $top && $top->{tier} && $top->{score} >= EXACT ? sub { undef $next; $done->($top) } : $next;
			return $continue->() if $source eq 'local';
			$self->{delay}->($continue);
		});
	};
	$next->();
}

# Ceo klasicni stav-po-stav: svi stavovi istog izdanja i izvora, po redosledu stavova.
sub _movements {
	my ($want, $match) = @_;

	my $top = $match->{item};
	my $album = $top->{album} // '';
	my @same = grep {
		($_->{source} // '') eq ($top->{source} // '') && ($_->{album} // '') eq $album && ($_->{artist} // '') eq ($top->{artist} // '')
			&& score($want, $_) >= THRESHOLD
	} @{ $match->{items} || [$top] };

	my $position = 0;
	my @ordered = map { $_->[0] } sort { $a->[1][0] <=> $b->[1][0] || $a->[1][1] cmp $b->[1][1] || $a->[2] <=> $b->[2] }
		map { [$_, movement_key($_->{title}), $position++] } @same;
	my %seen;
	my @urls = grep { !$seen{$_}++ } map { _url($_) } @ordered;
	splice @urls, MAX_MOVEMENTS if @urls > MAX_MOVEMENTS;
	return \@urls;
}

sub _urls_for {
	my ($self, $want, $match, $done) = @_;

	my $item = $match->{item};
	if ($want->{type} eq 'track') {
		return $done->($want->{whole_work} ? _movements($want, $match) : [_url($item)]);
	}
	$self->{expand}->($item, sub { $done->([grep { defined && length } @{ $_[0] || [] }]) });
}

sub _resolve_one {
	my ($self, $entry, $done) = @_;

	# Prvo upit modela, pa izvodjac + naslov, pa alternative.
	my @attempts;
	my %tried;
	for my $pair ([$entry->{title}, $entry->{search}], [$entry->{title}, "$entry->{artist} $entry->{title}"],
		map { [$_, "$entry->{artist} $_"] } @{ $entry->{alternatives} || [] }) {
		next unless defined $pair->[1] && length $pair->[1];
		push @attempts, $pair unless $tried{ lc $pair->[1] }++;
	}

	my ($fallback, $single);
	my $next;
	my $accept = sub {
		my ($want, $match, $other) = @_;
		my $item = $match->{item};
		$self->_urls_for($want, $match, sub {
			my ($urls) = @_;
			return $next->() unless @$urls;
			my %found = (source => $item->{source}, title => $item->{title}, urls => $urls);
			$found{other_performer} = 1 if $other;
			for my $field (qw(artist album image year)) {
				$found{$field} = $item->{$field} if defined $item->{$field};
			}
			# Za izvodjaca bez navedenog albuma singl je samo rezerva; prvo se probaju alternative.
			if ($entry->{artist_only} && @$urls < MIN_ALBUM_TRACKS && @attempts) {
				$single ||= \%found;
				return $next->();
			}
			undef $next;
			$done->(\%found);
		});
	};
	$next = sub {
		my $attempt = shift @attempts;
		if (!defined $attempt) {
			# Snimak drugog izvodjaca samo ako trazeni nije nadjen nijednim upitom.
			return $accept->($fallback->[0], $fallback->[1], 1) if $fallback && !$fallback->[2]++;
			undef $next;
			return $done->($single);
		}
		my ($title, $term) = @$attempt;
		my $want = { type => $entry->{type}, artist => $entry->{artist}, title => $title };
		$want->{composer} = $entry->{composer} if defined $entry->{composer};
		$want->{whole_work} = 1 if $entry->{whole_work};
		$self->_find($want, $term, sub {
			my ($match) = @_;
			return $next->() unless $match;
			if (!Plugins::UnifiedMusic::Import::Match::artist_ok($entry->{artist}, $match->{item}{artist})) {
				$fallback ||= [$want, $match, 0];
				return $next->();
			}
			$accept->($want, $match, 0);
		});
	};
	$next->();
}

sub resolve {
	my ($self, $entries, $done) = @_;

	my @queue = @$entries;
	my $total = scalar @queue;
	my @results;
	my $next;
	$next = sub {
		my $entry = shift @queue;
		if (!$entry) {
			undef $next;
			return $done->(\@results);
		}
		$self->{progress}->(scalar(@results) + 1, $total, $entry);
		my $record = sub {
			my ($found, $used) = @_;
			my %result = map { $_ => $used->{$_} } grep { defined $used->{$_} } qw(type artist title album composer whole_work artist_only);
			if ($found) {
				$result{found} = $found;
			}
			else {
				$result{missing} = 1;
			}
			push @results, \%result;
			# Odlaganje cuva petlju servera i izbegava duboku rekurziju.
			$self->{defer}->($next);
		};
		$self->_resolve_one($entry, sub {
			my ($found) = @_;
			return $record->($found, $entry) if $found || $entry->{type} ne 'album' || $entry->{artist_only};
			# Model ponekad delo ili pesmu oznaci kao album; tada se trazi kao (celo) delo.
			my $as_track = { %$entry, type => 'track', whole_work => 1, alternatives => [] };
			$self->_resolve_one($as_track, sub {
				my ($track) = @_;
				$record->($track, $track ? $as_track : $entry);
			});
		});
	};
	$next->();
}

1;
