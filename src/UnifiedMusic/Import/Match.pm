package Plugins::UnifiedMusic::Import::Match;

# Ocena koliko rezultat pretrage odgovara trazenom albumu ili pesmi. Bez zavisnosti od Lyrion-a.
# Nazivi iz teksta retko su identicni izdanju ("feat.", "(Live)", klasicni stavovi), pa je
# poredjenje tolerantno, ali izvodjac mora da se slaze i brojevi iz naslova moraju da postoje.

use strict;
use warnings;
use utf8;

use Exporter qw(import);
use Plugins::UnifiedMusic::Normalize qw(plain_key title_key artist_key);

our @EXPORT_OK = qw(score best movement_key EXACT THRESHOLD OTHER_PERFORMER);

use constant EXACT           => 0.99;
use constant THRESHOLD       => 0.6;
use constant OTHER_PERFORMER => 0.8;

my %ROMAN = (I => 1, V => 5, X => 10, L => 50);

# Redosled stava iz naslova: "...: II. Adagio", "... - 3b. Ruhig". Bez oznake stav ide na kraj.
sub movement_key {
	my ($title) = @_;

	my @found;
	while (($title // '') =~ /(?:^|[:\-\x{2013}]\s*)(\d+|[IVXL]+)([a-z]?)\.\s/g) {
		@found = ($1, $2);
	}
	return [9999, ''] unless @found;
	my ($number, $letter) = @found;
	if ($number !~ /^\d+$/) {
		my ($total, $previous) = (0, 0);
		for my $value (reverse map { $ROMAN{$_} } split //, $number) {
			$total += $value < $previous ? -$value : $value;
			$previous = $value if $value > $previous;
		}
		$number = $total;
	}
	return [$number + 0, $letter];
}

my %STOP = map { $_ => 1 } qw(the a an and of feat ft featuring with);

sub _tokens {
	my ($text) = @_;
	return grep { length && !$STOP{$_} } split / /, plain_key($text);
}

# Naslov bez zagrada i dodataka iza " - ".
sub _base {
	my ($title) = @_;

	$title //= '';
	$title =~ s/\([^()]*\)|\[[^\[\]]*\]//g;
	$title =~ s/\s+-\s+.*$//;
	return plain_key($title);
}

sub _parts {
	my ($name) = @_;
	return grep { length } map { artist_key($_) } split m{\s*(?:/|,|&|;|\band\b|\bwith\b|\bfeat\.?|\bft\.?|\bfeaturing\b)\s*}i, $name;
}

# "hiromi" je pocetak "hiromi uehara"; "royal phil" (vise reci) je skracenica "royal philharmonic".
sub _prefix {
	my ($short, $long) = @_;
	return 0 unless length($short) >= 4 && length($long) > length($short) && index($long, $short) == 0;
	return substr($long, length $short, 1) eq ' ' || $short =~ / / ? 1 : 0;
}

sub artist_ok {
	my ($want, $have) = @_;

	return 0 unless defined $want && defined $have;
	my ($w, $h) = (artist_key($want), artist_key($have));
	return 0 unless length $w && length $h;
	return 1 if $w eq $h || $h =~ /(?:^| )\Q$w\E(?: |$)/ || $w =~ /(?:^| )\Q$h\E(?: |$)/;

	# Vise izvodjaca u jednom polju ("A / B", "A & B", "A, B"); skraceno ime ("Royal Phil").
	for my $wp (_parts($want)) {
		for my $hp (_parts($have)) {
			return 1 if $wp eq $hp;
			return 1 if _prefix($wp, $hp) || _prefix($hp, $wp);
		}
	}

	my @w = _tokens($want);
	my %h = map { $_ => 1 } _tokens($have);
	return 0 unless @w && %h;
	my $common = grep { $h{$_} } @w;
	my $smaller = @w < keys %h ? scalar @w : scalar keys %h;
	return $common / $smaller >= 0.5 ? 1 : 0;
}

sub _without_movement {
	my ($title) = @_;

	my $work = $title // '';
	$work =~ s/(?:^|[:\-\x{2013}]\s*)(?:\d+|[IVXL]+)[a-z]?\.\s.*$//;
	return length($work) ? $work : $title;
}

sub title_score {
	my ($want, $have) = @_;

	my ($w, $h) = (title_key($want), title_key($have));
	return 0 unless length $w && length $h;
	return 1 if $w eq $h;

	my @w = _tokens($want);
	my @h = _tokens($have);
	my %h = map { $_ => 1 } @h;

	# Broj iz naslova (Symphony No. 4, Op. 60) mora postojati u delu, bez oznake stava ("- 1. Lebhaft").
	my %work = map { $_ => 1 } _tokens(_without_movement($have));
	for my $number (grep { /^\d+$/ } @w) {
		return 0 unless $work{$number};
	}

	my ($wb, $hb) = (_base($want), _base($have));
	return 0.95 if length $wb && $wb eq $hb;
	return 0.9 if index($h, $w) == 0 || index($w, $h) == 0;

	return 0 unless @w && @h;
	my $common = grep { $h{$_} } @w;
	return 0.6 * $common / @w + 0.3 * $common / @h;
}

# Prezime kompozitora postoji negde u stavci (izvodjac, naslov ili album).
sub composer_ok {
	my ($composer, $have) = @_;

	my @tokens = _tokens($composer);
	return 1 unless @tokens;
	my $surname = $tokens[-1];
	my $haystack = ' ' . plain_key(join ' ', grep { defined } @$have{qw(artist title album)}) . ' ';
	return index($haystack, " $surname ") >= 0 ? 1 : 0;
}

# $want: { artist, title, composer? }; $have: stavka pretrage. Vraca 0 do 1.
# Klasika: naslov se poredi i sa "album + naslov", a snimak drugog izvodjaca dobija nizu ocenu.
sub score {
	my ($want, $have) = @_;

	my $classical = defined $want->{composer} && length $want->{composer};

	my $title = title_score($want->{title}, $have->{title});
	if ($classical && defined $have->{album}) {
		my $combined = title_score($want->{title}, "$have->{album} $have->{title}");
		$title = $combined if $combined > $title;
	}
	# Bez imena kompozitora prolazi samo potpuno isti naslov (inace "Organ Sonata No. 1" nadje Baha).
	return 0 if $classical && $title < EXACT && !composer_ok($want->{composer}, $have);

	return $title if artist_ok($want->{artist}, $have->{artist});
	return $classical ? $title * OTHER_PERFORMER : 0;
}

# Najbolja stavka trazene vrste: prvo trazeni izvodjac, pa ocena; pri istoj oceni ranija stavka.
sub best {
	my ($want, $items, $kind) = @_;

	my ($top, $top_score, $top_tier) = (undef, 0, -1);
	for my $item (@{ $items || [] }) {
		next unless ($item->{kind} // '') eq $kind;
		my $value = score($want, $item);
		next unless $value >= THRESHOLD;
		my $tier = artist_ok($want->{artist}, $item->{artist}) ? 1 : 0;
		($top, $top_score, $top_tier) = ($item, $value, $tier) if $tier > $top_tier || $tier == $top_tier && $value > $top_score;
	}
	return $top ? { item => $top, score => $top_score, tier => $top_tier } : undef;
}

1;
