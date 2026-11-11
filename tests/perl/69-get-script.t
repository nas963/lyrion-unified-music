use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my $script = abs_path('packaging/get.sh');
ok -f $script, 'get.sh postoji';

sub make_release {
	my ($uninstall_text) = @_;
	my $dir = tempdir(CLEANUP => 1);
	my $build = tempdir(CLEANUP => 1);
	mkdir "$build/unifiedmusic-9.9.9";
	for my $name ('install.sh', 'uninstall.sh') {
		open my $fh, '>', "$build/unifiedmusic-9.9.9/$name" or die $!;
		print {$fh} "echo RAN-$name\n";
		close $fh;
	}
	system("cd $build && python3 -m zipfile -c $dir/unifiedmusic.zip unifiedmusic-9.9.9") == 0 or die 'zip';
	system("cd $dir && sha256sum unifiedmusic.zip > unifiedmusic.zip.sha256") == 0 or die 'sha';
	return $dir;
}

sub run_get {
	my ($dir, @args) = @_;
	my $out = `UNIFIED_BASE_URL=file://$dir bash $script @args 2>&1`;
	return ($out, $? >> 8);
}

{
	my $dir = make_release();
	my ($out, $code) = run_get($dir);
	is $code, 0, 'uspesna instalacija';
	like $out, qr/RAN-install\.sh/, 'pokrece install.sh';
}

{
	my $dir = make_release();
	my ($out, $code) = run_get($dir, 'uninstall');
	is $code, 0, 'uspesno uklanjanje';
	like $out, qr/RAN-uninstall\.sh/, 'pokrece uninstall.sh';
	unlike $out, qr/RAN-install\.sh/, 'ne pokrece install.sh';
}

{
	my $dir = make_release();
	open my $fh, '>', "$dir/unifiedmusic.zip.sha256" or die $!;
	print {$fh} ('0' x 64) . "  unifiedmusic.zip\n";
	close $fh;
	my ($out, $code) = run_get($dir);
	isnt $code, 0, 'pogresan otisak prekida rad';
	like $out, qr/provera/i, 'poruka o proveri';
	unlike $out, qr/RAN-/, 'nista se ne pokrece';
}

{
	my $dir = tempdir(CLEANUP => 1);
	my ($out, $code) = run_get($dir);
	isnt $code, 0, 'nedostupan paket prekida rad';
	like $out, qr/preuzeti/i, 'poruka o preuzimanju';
	unlike $out, qr/RAN-/, 'nista se ne pokrece';
}

{
	my $dir = make_release();
	my ($out, $code) = run_get($dir, 'nesto');
	isnt $code, 0, 'nepoznata radnja';
	like $out, qr/Upotreba/, 'uputstvo';
}

done_testing;
