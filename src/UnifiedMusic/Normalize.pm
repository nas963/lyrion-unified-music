package Plugins::UnifiedMusic::Normalize;

# Pravi kljuceve po kojima se grupisu verzije. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

use Exporter qw(import);
use Unicode::Normalize qw(NFKD NFC);

our @EXPORT_OK = qw(title_key artist_key album_key track_key plain_key);

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

sub artist_key {
	my ($name) = @_;

	return '' unless defined $name;

	my $main = $name;
	$main =~ s/\s+(?:feat\.?|ft\.?|featuring)\s.*$//i;

	return _fallback_key($main);
}

sub album_key {
	my ($artist, $title) = @_;

	return artist_key($artist) . $SEPARATOR . title_key($title);
}

sub track_key {
	my ($artist, $title) = @_;

	return artist_key($artist) . $SEPARATOR . title_key($title);
}

1;
