package Plugins::UnifiedMusic::Mix::Prompt;

# Zahtev za model i dnevni naglasak kategorije. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

my @DECADES = qw(1950s 1960s 1970s 1980s 1990s 2000s 2010s 2020s);
my @BALANCE = (
	'mostly well-known recordings',
	'an even mix of well-known and lesser-known recordings',
	'mostly lesser-known recordings',
);

my $SYSTEM = <<'END';
You recommend music for a personal playlist. Suggest only real, commercially released recordings.
Never invent an artist or a title. Give the artist name and the recording title exactly as released,
without album names, track numbers or comments.
The playlist must be varied: spread the suggestions across many different artists and albums.
Never suggest more than two recordings by the same artist, and never two recordings from the same album.
Do not group recordings by artist; mix the artists throughout the list.
END

sub build {
	my ($args) = @_;

	my ($category, $count, $rng) = @$args{qw(category count rng)};
	my @genres = @{ $category->{genres} };
	my $requested = $count * 3;
	my $genre = $genres[ $rng->(scalar @genres) ];
	my $decade = $DECADES[ $rng->(scalar @DECADES) ];
	my $balance = $BALANCE[ $rng->(scalar @BALANCE) ];
	my $list = join ', ', @genres;

	my $artists = int($requested / 2);
	my $user = "Suggest $requested different recordings for the category \"$category->{name}\".\n"
		. "Allowed genres: $list.\n"
		. "Use at least $artists different artists, at most two recordings per artist, each from a different album.\n"
		. "Emphasis for today: more $genre, recordings from the $decade where that fits, $balance.";

	return { system => $SYSTEM, user => $user, requested => $requested };
}

1;
