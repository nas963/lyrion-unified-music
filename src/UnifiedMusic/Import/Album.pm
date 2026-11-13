package Plugins::UnifiedMusic::Import::Album;

# Iz menija albuma (Qobuz, TIDAL kroz globalsearch) vadi adrese pesama. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

# Pesma servisa: qobuz://42100943.flac, tidal://77647304.flc
my $TRACK_URL = qr{^\w+://\d+\.\w+$};

sub _id {
	my ($entry) = @_;
	my $go = $entry->{actions} && $entry->{actions}{go} ? $entry->{actions}{go}{params} : undef;
	return ($go ? $go->{item_id} : undef) // ($entry->{params} ? $entry->{params}{item_id} : undef);
}

sub track_urls {
	my ($menu) = @_;

	my @urls;
	for my $entry (@{ $menu && $menu->{item_loop} || [] }) {
		my $url = $entry->{presetParams} ? $entry->{presetParams}{favorites_url} : undef;
		push @urls, $url if defined $url && $url =~ $TRACK_URL;
	}
	return \@urls;
}

# Albumi sa vise diskova ponekad imaju podmeni po disku.
sub disc_ids {
	my ($menu) = @_;

	return [grep { defined } map { _id($_) } grep { ($_->{text} // '') =~ /^\s*(?:disc|cd|disk)\s*\d+/i } @{ $menu && $menu->{item_loop} || [] }];
}

# Adrese koje vrati explodePlaylist servisa: samo pojedinacne pesme.
sub only_tracks {
	my ($urls) = @_;
	return [grep { defined && $_ =~ $TRACK_URL } @{ $urls || [] }];
}

1;
