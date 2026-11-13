package Plugins::UnifiedMusic::Import::History;

# Poslednji uvozi lista, u jednom JSON fajlu. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use JSON::PP;

use constant KEEP => 30;

my $JSON = JSON::PP->new->utf8->canonical;

sub new {
	my ($class, %args) = @_;
	return bless { file => $args{file} }, $class;
}

sub list {
	my ($self) = @_;

	open my $fh, '<:raw', $self->{file} or return [];
	local $/;
	my $data = eval { $JSON->decode(scalar <$fh>) };
	return ref $data eq 'ARRAY' ? $data : [];
}

sub get {
	my ($self, $id) = @_;

	return undef unless defined $id;
	my ($entry) = grep { ($_->{id} // '') eq $id } @{ $self->list };
	return $entry;
}

sub add {
	my ($self, $entry) = @_;

	my @all = grep { ($_->{id} // '') ne $entry->{id} } @{ $self->list };
	unshift @all, $entry;
	splice @all, KEEP if @all > KEEP;
	$self->_write(\@all);
	return $entry;
}

# Dopuna postojece plejliste ide u zapis koji vec postoji za tu plejlistu.
sub add_to_playlist {
	my ($self, $entry) = @_;

	my $id = $entry->{playlist_id};
	my ($old) = defined $id ? grep { defined $_->{playlist_id} && $_->{playlist_id} eq $id } @{ $self->list } : ();
	return $self->add($old ? combine($old, $entry) : $entry);
}

sub combine {
	my ($old, $new) = @_;

	my %merged = %$old;
	$merged{items} = [@{ $old->{items} || [] }, @{ $new->{items} || [] }];
	$merged{$_} = ($old->{$_} // 0) + ($new->{$_} // 0) for qw(found total tracks);
	$merged{name} = $new->{name} if defined $new->{name} && length $new->{name};
	$merged{date} = $new->{date} if defined $new->{date};
	my $time = $new->{updated} // $new->{created};
	$merged{updated} = $time if defined $time;
	delete $merged{error} if $merged{found};
	return \%merged;
}

# Ranije verzije su svaku dopunu pisale kao poseban zapis; spaja ih u jedan po plejlisti.
sub compact {
	my ($self) = @_;

	my $all = $self->list;
	my (%at, @out);
	for my $entry (reverse @$all) {
		my $id = $entry->{playlist_id};
		if (defined $id && exists $at{$id}) {
			$out[$at{$id}] = combine($out[$at{$id}], $entry);
			next;
		}
		$at{$id} = scalar @out if defined $id;
		push @out, $entry;
	}
	return 0 if @out == @$all;

	my %order = map { $out[$_] => $_ } 0 .. $#out;
	@out = sort { _time($b) <=> _time($a) || $order{$b} <=> $order{$a} } @out;
	$self->_write(\@out);
	return 1;
}

sub _time { return $_[0]{updated} // $_[0]{created} // 0 }

sub set_name {
	my ($self, $id, $name) = @_;

	my $all = $self->list;
	my ($entry) = grep { ($_->{id} // '') eq ($id // '') } @$all;
	return undef unless $entry;
	$entry->{name} = $name;
	$self->_write($all);
	return $entry;
}

sub remove {
	my ($self, $id) = @_;

	my $all = $self->list;
	my @kept = grep { ($_->{id} // '') ne ($id // '') } @$all;
	return 0 if @kept == @$all;
	$self->_write(\@kept);
	return 1;
}

sub _write {
	my ($self, $all) = @_;

	make_path(dirname($self->{file}));
	my $temp = "$self->{file}.$$.tmp";
	open my $fh, '>:raw', $temp or die "Cannot write $temp: $!";
	print {$fh} $JSON->encode($all);
	close $fh or die "Cannot close $temp: $!";
	rename $temp, $self->{file} or die "Cannot rename $temp: $!";
}

1;
