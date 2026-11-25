package Plugins::UnifiedMusic::Normalize;

# Pravi kljuceve po kojima se grupisu verzije. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

use Exporter qw(import);
use Unicode::Normalize qw(NFKD NFC);

our @EXPORT_OK = qw(title_key artist_key album_key track_key plain_key same_artist_key part_title without_part);

my $SEPARATOR = "\x1f";
my $EDITION_RE = qr/\b(?:remaster|remastered|deluxe|legacy|expanded|anniversary|edition|bonus|reissue)\b/i;

sub _is_edition_segment {
	my ($segment) = @_;

	return 0 if $segment =~ /\blive\b/i;
	return 1 if $segment =~ /^\s*\d{4}\s*$/;
	return $segment =~ $EDITION_RE ? 1 : 0;
}

# Mala slova, bez latinicne dijakritike, bez interpunkcije, jedan razmak.
sub plain_key {
	my ($text) = @_;

	return '' unless defined $text;

	$text = lc $text;
	$text =~ s/đ/dj/g;
	$text =~ s/&/ and /g;
	$text = NFKD($text);
	$text =~ s/(\p{Latin})\p{Mn}+/$1/g;
	$text = NFC($text);
	$text =~ s/[^\p{L}\p{N}\s]//g;
	$text =~ s/\s+/ /g;
	$text =~ s/^ //;
	$text =~ s/ $//;

	return $text;
}

sub title_key {
	my ($title) = @_;

	return '' unless defined $title;

	my $stripped = $title;
	$stripped =~ s/\(([^()]*)\)/_is_edition_segment($1) ? '' : $&/ge;
	$stripped =~ s/\[([^\[\]]*)\]/_is_edition_segment($1) ? '' : $&/ge;

	my ($first, @rest) = split /\s+-\s+/, $stripped;
	$stripped = join ' ', grep { defined && length } $first, grep { !_is_edition_segment($_) } @rest;

	my $key = plain_key($stripped);

	return length $key ? $key : _fallback_key($title);
}

# Naslov ili ime samo od simbola ostaje svoj kljuc, da se razliciti ne spoje.
sub _fallback_key {
	my ($text) = @_;

	my $key = plain_key($text);
	return $key if length $key;

	$key = NFC(lc $text);
	$key =~ s/^\s+|\s+$//g;
	return $key;
}

my @ROMAN = qw(i ii iii iv v vi vii viii ix x xi xii xiii xiv xv xvi xvii xviii xix xx);
my @WORDS = qw(one two three four five six seven eight nine ten eleven twelve);
my %NUMBER = (
	(map { $ROMAN[$_] => $_ + 1 } 0 .. $#ROMAN),
	(map { $WORDS[$_] => $_ + 1 } 0 .. $#WORDS),
);
my $NUMBER_RE = join '|', '\d{1,2}', sort { length $b <=> length $a || $a cmp $b } keys %NUMBER;
# "Pt.1" i "Part1" su oznake dela, ali "Parti" nije.
my $PART_RE = qr/(?<![\p{L}\p{N}])(?:parts?|pts?)(?:\.\s*|\s+|(?=\d))($NUMBER_RE)(?:\s*(?:[-–—\/&]|\bto\b|\band\b)\s*($NUMBER_RE))?(?![\p{L}\p{N}])/i;

sub _number {
	my ($text) = @_;
	return $NUMBER{ lc $text } // $text + 0;
}

# Svi zapisi dela ("Part One", "Pt. I", "Parts 1-5") svode se na "part 1" odnosno "part 1 to 5".
sub part_title {
	my ($title) = @_;

	return $title unless defined $title;
	$title =~ s/$PART_RE/'part ' . _number($1) . (defined $2 ? ' to ' . _number($2) : '')/ge;
	return $title;
}

# Naslov bez oznake dela, za siru pretragu. Naslov koji je samo oznaka ostaje.
sub without_part {
	my ($title) = @_;

	my $short = $title // '';
	return $short unless $short =~ s/$PART_RE//g;
	$short =~ s/\(\s*\)|\[\s*\]|\{\s*\}//g;
	$short =~ s/\s+/ /g;
	$short =~ s/^[\s,:;\-–—]+|[\s,:;\-–—]+$//g;
	return length plain_key($short) ? $short : $title;
}

sub artist_key {
	my ($name) = @_;

	return '' unless defined $name;

	my $main = $name;
	$main =~ s/\s+(?:feat\.?|ft\.?|featuring)\s.*$//i;

	return _fallback_key($main);
}

# Za poredjenje jednakosti: "Jean-Michel", "Jean Michel" i "JeanMichel" su isti izvodjac.
# artist_key zadrzava razmake jer uvoz liste poredi i pojedinacne reci.
sub same_artist_key {
	my ($name) = @_;

	my $key = artist_key($name);
	$key =~ s/\s+//g;
	return $key;
}

sub album_key {
	my ($artist, $title) = @_;

	return same_artist_key($artist) . $SEPARATOR . title_key($title);
}

sub track_key {
	my ($artist, $title) = @_;

	return same_artist_key($artist) . $SEPARATOR . title_key($title);
}

1;
