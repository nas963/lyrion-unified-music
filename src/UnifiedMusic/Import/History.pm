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
