package Plugins::UnifiedMusic::Import::Prompt;

# Zahtev za model koji iz teksta (npr. Gemini opis YouTube videa) izvlaci albume i pesme.
# Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

use JSON::PP;

use constant MAX_TEXT  => 30000;
use constant MAX_ITEMS => 60;

my $SYSTEM = <<'END';
You turn a text about music into a listening list. The text was usually written by an AI assistant
that summarised a YouTube video presenting a list of albums, songs or artists. Return every music
entry in the order it appears in the text.

For each entry decide what it refers to:
- A specific recording (song, track, piece or movement): type "track". "artist" is the main performing
  artist as credited on the release, "title" is the track title as commercially released. For classical
  music use the usual release title of the work or movement (for example
  "Symphony No. 4 in B-flat Major, Op. 60: I. Adagio - Allegro vivace"), put the performers as usually
  credited in "artist" (ensemble or orchestra and conductor or soloist, for example
  "Anima Eterna Brugge, Jos van Immerseel") and the composer in "composer". Set "whole_work" true when
  the entry means a complete multi-movement work rather than one movement or piece.
  "album" is the album if the text names it, otherwise an empty string.
- A specific album: type "album", "title" is the album title as released.
- Only an artist or band, without a specific album or song: type "album" and "artist_only" true.
  Choose the album the text points to if it mentions one; otherwise choose one representative,
  well-known studio album of that artist.

"composer" is empty except for classical music. "search" is a short query of 3 to 6 words that finds the
recording in a streaming service: performer surname, composer and the main words of the title or album,
without keys, opus numbers or punctuation (for example "Immerseel Beethoven Symphony 4").

For albums put up to two other well-known albums of the same artist in "alternatives"; they are used
if the first album cannot be found. For tracks "alternatives" may hold other common spellings of the
title, otherwise it is empty.

Rules:
- Use only real, commercially released music. Never invent an artist, album or title.
- Remove ranking numbers, timestamps, links, quotes and comments from names.
- Skip people or channels that are not presented as music to listen to (for example the video host).
- "name" is a short playlist name (at most 60 characters) that describes the list, in the language of
  the text.
END

sub schema {
	my $string = { type => 'string' };
	return {
		type => 'object',
		additionalProperties => JSON::PP::false,
		required => ['name', 'items'],
		properties => {
			name  => $string,
			items => {
				type => 'array',
				items => {
					type => 'object',
					additionalProperties => JSON::PP::false,
					required => [qw(type artist title album composer search whole_work artist_only alternatives)],
					properties => {
						type         => { type => 'string', enum => ['track', 'album'] },
						artist       => $string,
						title        => $string,
						album        => $string,
						composer     => $string,
						search       => $string,
						whole_work   => { type => 'boolean' },
						artist_only  => { type => 'boolean' },
						alternatives => { type => 'array', items => $string },
					},
				},
			},
		},
	};
}

sub build {
	my ($text) = @_;

	$text //= '';
	$text = substr($text, 0, MAX_TEXT) if length $text > MAX_TEXT;

	return {
		system => $SYSTEM,
		user   => "Make a listening list from this text:\n\n<text>\n$text\n</text>",
	};
}

sub _clean {
	my ($text) = @_;
	$text //= '';
	$text =~ s/\s+/ /g;
	$text =~ s/^ | $//g;
	return $text;
}

# Odgovor modela -> { name, items } ili undef ako odgovor nije ispravan.
sub parse {
	my ($text) = @_;

	return undef unless defined $text;
	$text =~ s/^\s*```(?:json)?\s*//i;
	$text =~ s/\s*```\s*$//;

	my $data = eval { JSON::PP->new->decode($text) };
	return undef unless ref $data eq 'HASH' && ref $data->{items} eq 'ARRAY';

	my (@items, %seen);
	for my $entry (@{ $data->{items} }) {
		next unless ref $entry eq 'HASH';
		my $type = ($entry->{type} // '') eq 'track' ? 'track' : 'album';
		my $artist = _clean($entry->{artist});
		my $title = _clean($entry->{title});
		next unless length $artist && length $title;
		next if $seen{ lc "$type\x1f$artist\x1f$title" }++;

		my %alt_seen = (lc $title => 1);
		my @alternatives = grep { length && !$alt_seen{ lc $_ }++ } map { _clean($_) }
			grep { defined && !ref } @{ ref $entry->{alternatives} eq 'ARRAY' ? $entry->{alternatives} : [] };

		my %item = (type => $type, artist => $artist, title => $title, alternatives => [@alternatives[0 .. ($#alternatives < 2 ? $#alternatives : 2)]]);
		my $album = _clean($entry->{album});
		$item{album} = $album if length $album && $type eq 'track';
		$item{artist_only} = 1 if $entry->{artist_only} && $type eq 'album';
		$item{whole_work} = 1 if $entry->{whole_work} && $type eq 'track';
		for my $field (qw(composer search)) {
			my $value = _clean($entry->{$field});
			$item{$field} = $value if length $value;
		}
		push @items, \%item;
		last if @items >= MAX_ITEMS;
	}

	my $name = _clean($data->{name});
	$name = substr($name, 0, 60) if length $name > 60;
	my %result = (list => { name => $name, items => \@items });
	# Za dijagnostiku kada model ne vrati nista upotrebljivo.
	$result{raw} = substr($text, 0, 400) unless @items;
	return \%result;
}

1;
