use strict;
use warnings;
use utf8;
use Test::More;
use JSON::PP;
use Plugins::UnifiedMusic::Source::Local;

sub fixture {
	my ($name) = @_;
	open my $fh, '<:raw', "t/fixtures/$name.json" or die "$name: $!";
	local $/;
	return JSON::PP->new->utf8->decode(scalar <$fh>);
}

my %FILE = (albums => 'local_albums', tracks => 'local_tracks', artists => 'local_artists', works => 'local_works', playlists => 'local_playlists');

sub fake_run {
	my ($commands, %opts) = @_;
	return sub {
		my ($client, $cmd, $cb) = @_;
		push @$commands, [@$cmd];
		return $cb->(undef) if $opts{fail};
		return $cb->($opts{override}{ $cmd->[0] }) if $opts{override} && $opts{override}{ $cmd->[0] };
		return $cb->({}) unless $FILE{ $cmd->[0] };
		return $cb->(fixture($FILE{ $cmd->[0] }));
	};
}

sub run_search {
	my ($run, $ctx) = @_;
	my @done;
	Plugins::UnifiedMusic::Source::Local->new(run => $run)->search('Kind of Blue', $ctx // {}, sub { push @done, $_[0] });
	return \@done;
}

{
	my @commands;
	my $done = run_search(fake_run(\@commands), { library_id => 'lib1' });
	is scalar @$done, 1, 'done jednom';
	is_deeply $done->[0]{missing}, [], 'nista ne nedostaje';
	my $items = $done->[0]{items};

	my ($album) = grep { $_->{kind} eq 'album' && $_->{play}{album_id} == 17581 } grep { $_->{kind} eq 'album' } @$items;
	ok $album, 'album 17581';
	is $album->{year}, 1959, 'godina';
	is $album->{source}, 'local', 'izvor';
	is $album->{artist}, 'Miles Davis', 'izvodjac';
	like $album->{image}, qr{^/music/.+/cover$}, 'omot';

	my ($zero) = grep { $_->{kind} eq 'album' && $_->{play}{album_id} == 17717 } @$items;
	ok $zero, 'album sa godinom 0';
	ok !exists $zero->{year}, 'godina 0 se izostavlja';

	my ($track) = grep { $_->{kind} eq 'track' } @$items;
	is $track->{format}, 'flc', 'format pesme';
	is $track->{samplerate}, 44100, 'samplerate pesme';
	is $track->{samplesize}, 16, 'samplesize pesme';
	ok $track->{play}{track_id}, 'track_id';
	like $track->{url}, qr{^file:///}, 'pesma ima url';

	my ($artist) = grep { $_->{kind} eq 'artist' } @$items;
	ok $artist->{play}{artist_id}, 'artist_id';
	my ($playlist) = grep { $_->{kind} eq 'other' && $_->{list} eq 'playlists' } @$items;
	ok $playlist->{play}{playlist_id}, 'playlist_id';

	my ($albums) = grep { $_->[0] eq 'albums' && grep({ /^search:/ } @$_) } @commands;
	ok scalar(grep { $_ eq 'library_id:lib1' } @$albums), 'library_id se prosledjuje';
}

{
	my @commands;
	my $override = {
		albums  => { albums_loop => [
			{ id => 1, album => 'X', artist => 'A', year => 2000 },
			{ id => 2, album => 'X (Deluxe)', artist => 'A', year => 2000 },
			{ id => 3, album => 'Sam', artist => 'A', year => 2000 },
		] },
		tracks  => { titles_loop => [] },
		artists => { artists_loop => [] },
		works   => {},
		playlists => {},
	};
	my $base = fake_run(\@commands, override => $override);
	my $run = sub {
		my ($client, $cmd, $cb) = @_;
		my ($id) = map { /^album_id:(\d+)/ ? $1 : () } @$cmd;
		if ($id) {
			push @commands, [@$cmd];
			return $cb->({ titles_loop => [{ type => 'dsf', samplerate => '2822400', samplesize => '1' }] });
		}
		return $base->($client, $cmd, $cb);
	};
	my $done = run_search($run);
	my %album = map { $_->{play}{album_id} => $_ } grep { $_->{kind} eq 'album' } @{ $done->[0]{items} };
	is $album{1}{format}, 'dsf', 'duplikat dobija format';
	is $album{2}{samplerate}, 2822400, 'duplikat dobija samplerate';
	ok !exists $album{3}{format}, 'album bez duplikata nema format';
	is scalar(grep { grep({ /^album_id:/ } @$_) } @commands), 2, 'upit samo za duplikate';
}

{
	my $override = {
		albums => {}, tracks => {}, artists => {}, playlists => {},
		works  => { works_loop => [{ work_id => 77, composer => 'Beethoven', title => 'Symphony No. 5' }] },
	};
	my $done = run_search(fake_run([], override => $override));
	my ($work) = grep { $_->{kind} eq 'other' && $_->{list} eq 'works' } @{ $done->[0]{items} };
	is $work->{play}{work_id}, 77, 'delo koristi work_id';
	is $work->{title}, 'Symphony No. 5', 'naslov dela';
}

{
	my $done = run_search(fake_run([], fail => 1));
	is scalar @$done, 1, 'greska: done jednom';
	is_deeply $done->[0], { items => [], missing => ['local'] }, 'greska: missing';
}

done_testing;
