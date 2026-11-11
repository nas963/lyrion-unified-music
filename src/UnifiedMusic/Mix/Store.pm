package Plugins::UnifiedMusic::Mix::Store;

# Cuva miksove kao JSON fajlove: <dir>/YYYY-MM-DD/<slug>.json

use strict;
use warnings;
use utf8;

use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);
use File::Path qw(make_path);
use JSON::PP;
use POSIX qw(strftime);
use Time::Local qw(timegm);

my $JSON = JSON::PP->new->utf8->canonical;

sub new {
	my ($class, %args) = @_;
	return bless { dir => $args{dir} }, $class;
}

sub slug {
	my ($category) = @_;

	my $ascii = lc $category;
	$ascii =~ s/[^a-z0-9]+/-/g;
	$ascii =~ s/^-+|-+$//g;
	$ascii = substr($ascii, 0, 40);
	my $hash = substr(md5_hex(encode_utf8($category)), 0, 10);

	return length $ascii ? "$ascii-$hash" : $hash;
}

sub _path {
	my ($self, $date, $category) = @_;
	return "$self->{dir}/$date/" . slug($category) . '.json';
}

sub save {
	my ($self, $mix) = @_;

	my $folder = "$self->{dir}/$mix->{date}";
	make_path($folder);
	my $path = $self->_path($mix->{date}, $mix->{category});
	my $temp = "$path.$$.tmp";

	open my $fh, '>:raw', $temp or die "Cannot write $temp: $!";
	print {$fh} $JSON->encode($mix);
	close $fh or die "Cannot close $temp: $!";
	rename $temp, $path or die "Cannot rename $temp: $!";
}

sub load {
	my ($self, $date, $category) = @_;

	open my $fh, '<:raw', $self->_path($date, $category) or return undef;
	local $/;
	my $mix = eval { $JSON->decode(scalar <$fh>) };
	return ref $mix eq 'HASH' ? $mix : undef;
}

sub _all_dates {
	my ($self) = @_;

	opendir my $dh, $self->{dir} or return ();
	return sort { $b cmp $a } grep { /^\d{4}-\d\d-\d\d$/ && -d "$self->{dir}/$_" } readdir $dh;
}

sub rename_category {
	my ($self, $old, $new) = @_;

	return 0 if $old eq $new;
	my $moved = 0;
	for my $date ($self->_all_dates) {
		my $mix = $self->load($date, $old) or next;
		next if $self->load($date, $new);
		$mix->{category} = $new;
		$self->save($mix);
		unlink $self->_path($date, $old);
		$moved++;
	}
	return $moved;
}

sub dates {
	my ($self, $category) = @_;
	return [grep { $self->load($_, $category) } $self->_all_dates];
}

sub latest {
	my ($self, $category) = @_;

	for my $date ($self->_all_dates) {
		my $mix = $self->load($date, $category);
		return $mix if $mix;
	}
	return undef;
}

sub prune {
	my ($self, $today, $days) = @_;

	my ($year, $month, $day) = split /-/, $today;
	my $cutoff = strftime('%Y-%m-%d', gmtime(timegm(0, 0, 12, $day, $month - 1, $year) - $days * 86400));

	for my $date (grep { $_ lt $cutoff } $self->_all_dates) {
		my $folder = "$self->{dir}/$date";
		unlink glob("$folder/*.json");
		rmdir $folder;
	}
}

1;
