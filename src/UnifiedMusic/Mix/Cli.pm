package Plugins::UnifiedMusic::Mix::Cli;

# Podaci za CLI komande dnevnih miksova. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

sub categories {
	my ($store, $config, $today) = @_;

	my @rows;
	for my $category (@{ $config->{categories} || [] }) {
		my $mix = $store->latest($category->{name});
		push @rows, {
			name     => $category->{name},
			date     => $mix ? $mix->{date} : undef,
			count    => $mix ? scalar @{ $mix->{tracks} } : 0,
			stale    => $mix && $mix->{date} ne $today ? 1 : 0,
			previous => $mix ? _previous($store, $category->{name}, $mix) : [],
		};
	}
	return \@rows;
}

sub mix_items {
	my ($store, $category, $date, $today) = @_;

	my $mix = defined $date ? $store->load($date, $category) : $store->latest($category);
	return { date => undef, tracks => [], previous => [] } unless $mix;

	return { date => $mix->{date}, tracks => $mix->{tracks}, previous => defined $date ? [] : _previous($store, $category, $mix) };
}

sub _previous {
	my ($store, $category, $mix) = @_;
	return [grep { $_ ne $mix->{date} } @{ $store->dates($category) }];
}

# Lyrion za vec postojeci naziv vraca overwritten_playlist_id i ne pravi novu plejlistu.
sub new_playlist_id {
	my ($result) = @_;

	return { error => 1 } unless $result;
	return { exists => 1 } if $result->{overwritten_playlist_id};
	return $result->{playlist_id} ? { id => $result->{playlist_id} } : { error => 1 };
}

sub queue_commands {
	my ($cmd, $urls) = @_;

	return [] unless @$urls;
	return [map { ['playlist', 'insert', $_] } reverse @$urls] if $cmd eq 'insert';
	return [map { ['playlist', 'add', $_] } @$urls] if $cmd eq 'add';

	my ($first, @rest) = @$urls;
	return [['playlist', 'play', $first], map { ['playlist', 'add', $_] } @rest];
}

1;
