package Plugins::UnifiedMusic::Grouper;

# Spaja stavke u grupe verzija i odredjuje redosled. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

use Exporter qw(import);
use Plugins::UnifiedMusic::Normalize qw(title_key artist_key album_key track_key);

our @EXPORT_OK = qw(group_items);

my %DSD = map { $_ => 1 } qw(dsf dff);

sub _key {
	my ($item, $index) = @_;

	return album_key($item->{artist}, $item->{title}) if $item->{kind} eq 'album';
	return track_key($item->{artist}, $item->{title}) if $item->{kind} eq 'track';
	return artist_key($item->{title}) if $item->{kind} eq 'artist';
	return "other:$index";
}

sub _quality_compare {
	my ($left, $right) = @_;

	return ($DSD{ $right->{format} // '' } ? 1 : 0) <=> ($DSD{ $left->{format} // '' } ? 1 : 0)
		|| ($right->{samplerate} // 0) <=> ($left->{samplerate} // 0)
		|| ($right->{samplesize} // 0) <=> ($left->{samplesize} // 0);
}

sub _title_level {
	my ($title, $term_key) = @_;

	my $key = title_key($title);
	return 0 if $key eq $term_key;
	return 1 if length $term_key && index($key, $term_key) == 0;
	return 2;
}

sub group_items {
	my ($items, $term, $source_order) = @_;

	my $position = 0;
	my %source_rank = map { $_ => $position++ } @$source_order;
	my $unknown_rank = $position;
	my $rank = sub { $source_rank{ $_[0] } // $unknown_rank };

	my (@groups, %by_key);
	for my $index (0 .. $#$items) {
		my $item = $items->[$index];
		my $key = _key($item, $index);
		my $group = $by_key{$key};
		if (!$group) {
			$group = $by_key{$key} = { versions => [], first => $index };
			push @groups, $group;
		}
		my %version = %$item;
		delete $version{kind};
		push @{ $group->{versions} }, { version => \%version, index => $index };
	}

	for my $group (@groups) {
		my @sorted = map { $_->{version} } sort {
			$rank->($a->{version}{source}) <=> $rank->($b->{version}{source})
				|| ($a->{version}{source} eq 'local' ? _quality_compare($a->{version}, $b->{version}) : 0)
				|| $a->{index} <=> $b->{index}
		} @{ $group->{versions} };

		my %seen;
		$group->{versions} = \@sorted;
		$group->{sources} = [grep { !$seen{$_}++ } map { $_->{source} } @sorted];
		$group->{title} = $sorted[0]{title};
		$group->{artist} = $sorted[0]{artist};
	}

	my $term_key = title_key($term);
	my @ranked = sort {
		_title_level($a->{title}, $term_key) <=> _title_level($b->{title}, $term_key)
			|| $rank->($a->{sources}[0]) <=> $rank->($b->{sources}[0])
			|| lc($a->{title}) cmp lc($b->{title})
			|| $a->{first} <=> $b->{first}
	} @groups;

	delete $_->{first} for @ranked;
	for my $group (@ranked) {
		delete $group->{artist} unless defined $group->{artist};
	}

	return \@ranked;
}

1;
