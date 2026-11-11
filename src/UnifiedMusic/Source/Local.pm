package Plugins::UnifiedMusic::Source::Local;

# Lokalna biblioteka preko standardnih Lyrion upita.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Normalize qw(album_key);

my $LIMIT = 500;

sub new {
	my ($class, %args) = @_;
	return bless { run => $args{run}, only => $args{only} }, $class;
}

sub _common {
	my ($row, %item) = @_;

	$item{source} = 'local';
	$item{artist} = $row->{artist} if defined $row->{artist} && !defined $item{artist};
	my $year = $row->{year} // 0;
	$item{year} = $year + 0 if $year;
	$item{image} = "/music/$row->{artwork_track_id}/cover" if $row->{artwork_track_id};
	return \%item;
}

sub _album {
	my ($row) = @_;
	return _common($row, kind => 'album', title => $row->{album}, play => { album_id => $row->{id} });
}

sub _track {
	my ($row) = @_;
	my $item = _common($row, kind => 'track', title => $row->{title}, play => { track_id => $row->{id} });
	$item->{album} = $row->{album} if defined $row->{album};
	$item->{url} = $row->{url} if defined $row->{url};
	_add_format($item, $row);
	return $item;
}

sub _add_format {
	my ($item, $row) = @_;

	$item->{format} = $row->{type} if defined $row->{type};
	$item->{samplerate} = $row->{samplerate} + 0 if $row->{samplerate};
	$item->{samplesize} = $row->{samplesize} + 0 if $row->{samplesize};
}

sub _artist {
	my ($row) = @_;
	return { kind => 'artist', source => 'local', title => $row->{artist}, play => { artist_id => $row->{id} } };
}

sub _work {
	my ($row) = @_;
	my $item = { kind => 'other', list => 'works', source => 'local', title => $row->{work} // $row->{title}, play => { work_id => $row->{work_id} } };
	$item->{artist} = $row->{composer} if defined $row->{composer};
	return $item;
}

sub _playlist {
	my ($row) = @_;
	return { kind => 'other', list => 'playlists', source => 'local', title => $row->{playlist}, play => { playlist_id => $row->{id} } };
}

my @QUERIES = (
	{ cmd => 'albums',    loop => 'albums_loop',    tags => 'aljyeS',    map => \&_album },
	{ cmd => 'artists',   loop => 'artists_loop',                        map => \&_artist },
	{ cmd => 'tracks',    loop => 'titles_loop',    tags => 'aelyoTIJu', map => \&_track },
	{ cmd => 'works',     loop => 'works_loop',                          map => \&_work },
	{ cmd => 'playlists', loop => 'playlists_loop',                      map => \&_playlist },
);

# Komanda albums ne vraca format, pa se on trazi samo kada ima vise lokalnih verzija.
sub _albums_needing_format {
	my ($items) = @_;

	my %by_key;
	for my $item (grep { $_->{kind} eq 'album' } @$items) {
		push @{ $by_key{ album_key($item->{artist}, $item->{title}) } }, $item;
	}
	return map { @$_ } grep { @$_ > 1 } values %by_key;
}

sub search {
	my ($self, $term, $ctx, $done) = @_;

	my $run = $self->{run};
	my @library = defined $ctx->{library_id} ? ("library_id:$ctx->{library_id}") : ();
	my (@items, $failed);
	my @queries = $self->{only} ? grep { $_->{cmd} eq 'tracks' } @QUERIES : @QUERIES;
	my $pending = scalar @queries;

	my $finish = sub {
		$done->({ items => \@items, missing => $failed ? ['local'] : [] });
	};

	my $enrich = sub {
		my @albums = _albums_needing_format(\@items);
		return $finish->() unless @albums;

		my $left = scalar @albums;
		for my $album (@albums) {
			$run->(undef, ['titles', 0, 1, "album_id:$album->{play}{album_id}", 'tags:oTI'], sub {
				my ($result) = @_;
				my $row = $result && $result->{titles_loop} ? $result->{titles_loop}[0] : undef;
				_add_format($album, $row) if $row;
				$finish->() unless --$left;
			});
		}
	};

	for my $query (@queries) {
		my @tags = $query->{tags} ? ("tags:$query->{tags}") : ();
		$run->(undef, [$query->{cmd}, 0, $LIMIT, "search:$term", @tags, @library], sub {
			my ($result) = @_;
			if ($result) {
				push @items, map { $query->{map}->($_) } @{ $result->{ $query->{loop} } || [] };
			}
			else {
				$failed = 1;
			}
			$enrich->() unless --$pending;
		});
	}
}

1;
