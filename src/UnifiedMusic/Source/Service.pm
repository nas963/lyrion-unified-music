package Plugins::UnifiedMusic::Source::Service;

# Qobuz i TIDAL kroz njihove registracije u globalsearch-u.
# Tekstualni format je opisan u specifikaciji, sekcija 6.

use strict;
use warnings;
use utf8;

my $LIST_LIMIT = 200;
my @TYPES = qw(album artist track other);

my %SERVICES = (
	qobuz => { name => 'Qobuz', album => 'Releases' },
	tidal => { name => 'TIDAL', album => 'Albums' },
);
my %COMMON_MENUS = (artist => 'Artists', track => 'Songs', other => 'Playlists');

sub new {
	my ($class, %args) = @_;
	return bless { run => $args{run}, service => $args{service}, log => $args{log} || sub {}, only => $args{only} }, $class;
}

sub parse_text {
	my ($service, $type, $text) = @_;

	my $fallback = { title => $text };
	my @lines = split /\n/, $text, -1;
	return $fallback unless @lines == 2 && length $lines[0] && length $lines[1];

	my ($title, $detail) = @lines;

	if ($service eq 'qobuz' && $type eq 'track') {
		my @parts = split / - /, $detail, -1;
		return $fallback unless @parts == 2 && length $parts[0] && length $parts[1];
		return { title => $title, artist => $parts[0], album => $parts[1] };
	}

	if ($service eq 'qobuz' && $type eq 'album' && $detail =~ /^(.+?)\s+\((\d{4})\)$/) {
		return { title => $title, artist => $1, year => $2 + 0 };
	}

	return { title => $title, artist => $detail };
}

# Vrsta stavke kada servis vrati spljosten meni (samo jedna kategorija ima pogotke).
sub classify_flat {
	my ($entry) = @_;

	return undef if !defined $entry->{text} || ($entry->{type} // '') eq 'text';

	my $url = $entry->{presetParams} ? $entry->{presetParams}{favorites_url} : undef;
	return $url =~ /:album:/ ? 'album' : 'track' if $url && $url =~ m{^\w+://} && $url !~ /playlist:/;

	if (($entry->{type} // '') eq 'playlist') {
		return $entry->{text} =~ /\n.+\(\d{4}\)$/ ? 'album' : 'other';
	}

	return $entry->{actions} && $entry->{actions}{go} ? 'artist' : undef;
}

sub _item_id {
	my ($entry) = @_;
	return $entry->{actions}{go}{params}{item_id} // $entry->{params}{item_id};
}

sub _find_id {
	my ($menu, $text) = @_;

	my ($entry) = grep { defined $_->{text} && $_->{text} eq $text } @{ $menu->{item_loop} || [] };
	return $entry ? _item_id($entry) : undef;
}

sub _to_item {
	my ($service, $type, $entry) = @_;

	my $fields = $type eq 'artist' ? { title => $entry->{text} } : parse_text($service, $type, $entry->{text});
	my %item = (%$fields, kind => $type, source => $service);
	$item{list} = 'playlists' if $type eq 'other';
	$item{image} = $entry->{icon} if $entry->{icon};

	my $url = $entry->{presetParams} ? $entry->{presetParams}{favorites_url} : undef;
	$item{play} = ($url && ($type eq 'album' || $type eq 'track')) ? { url => $url } : { item_id => _item_id($entry) };

	return \%item;
}

sub search {
	my ($self, $term, $ctx, $done) = @_;

	my $service = $self->{service};
	my $config = $SERVICES{$service};
	my $client = $ctx->{client};
	my $missing = sub { $done->({ items => [], missing => [$service] }) };

	return $missing->() unless $client;

	my $run = $self->{run};

	$run->($client, ['globalsearch', 'items', 0, 50, 'menu:1', "search:$term"], sub {
		my ($root) = @_;
		my $service_id = $root ? _find_id($root, $config->{name}) : undef;
		if (!defined $service_id) {
			$self->{log}->("UnifiedMusic: servis nije nadjen u globalsearch: $config->{name}");
			return $missing->();
		}

		$run->($client, ['globalsearch', 'items', 0, $LIST_LIMIT, 'menu:1', "item_id:$service_id"], sub {
			my ($menu) = @_;
			if (!$menu) {
				$self->{log}->("UnifiedMusic: meni servisa nije dostupan: $config->{name}");
				return $missing->();
			}
			$self->_read_lists($client, $menu, $done);
		});
	});
}

sub _read_lists {
	my ($self, $client, $menu, $done) = @_;

	my $service = $self->{service};
	my @labels = ($SERVICES{$service}{album}, values %COMMON_MENUS);
	if (!grep { defined _find_id($menu, $_) } @labels) {
		my @items;
		for my $entry (@{ $menu->{item_loop} || [] }) {
			my $type = classify_flat($entry);
			push @items, _to_item($service, $type, $entry) if $type;
		}
		return $done->({ items => \@items, missing => [] });
	}

	my @types = $self->{only} ? ($self->{only}) : @TYPES;
	my %results;
	my $failed;
	my $pending = scalar @types;

	my $complete = sub {
		return if --$pending;
		$done->({
			items   => [map { @{ $results{$_} || [] } } @types],
			missing => $failed ? [$service] : [],
		});
	};

	for my $type (@types) {
		my $label = $type eq 'album' ? $SERVICES{$service}{album} : $COMMON_MENUS{$type};
		my $id = _find_id($menu, $label);
		if (!defined $id) {
			# Servis izostavlja kategorije bez pogodaka.
			$complete->();
			next;
		}

		$self->{run}->($client, ['globalsearch', 'items', 0, $LIST_LIMIT, 'menu:1', "item_id:$id"], sub {
			my ($list) = @_;
			if ($list) {
				$results{$type} = [map { _to_item($service, $type, $_) } grep { defined $_->{text} && ($_->{type} // '') ne 'text' } @{ $list->{item_loop} || [] }];
			}
			else {
				$self->{log}->("UnifiedMusic: lista nije dostupna: $service/$label");
				$failed = 1;
			}
			$complete->();
		});
	}
}

1;
