use strict;
use warnings;
use Test::More;

my $dir = 'lib/Plugins/UnifiedMusic';

ok -f "$dir/install.xml", 'install.xml postoji';
my $read = q{import sys,xml.etree.ElementTree as E; r=E.parse(sys.argv[1]).getroot(); print(r.find('module').text, r.find('name').text, r.find('optionsURL').text)};
my $out = `python3 -c "$read" $dir/install.xml`;
is $?, 0, 'install.xml je ispravan XML';
like $out, qr/^Plugins::UnifiedMusic::Plugin PLUGIN_UNIFIEDMUSIC plugins\/UnifiedMusic\/settings\/basic\.html/, 'modul, naziv i podesavanja';

for my $module (qw(Normalize Grouper Search Source/Local Source/Service)) {
	is system("perl -I lib -c $dir/$module.pm 2>/dev/null"), 0, "$module se kompajlira";
}

open my $strings, '<', "$dir/strings.txt" or die $!;
my $text = do { local $/; <$strings> };
like $text, qr/^PLUGIN_UNIFIEDMUSIC\n\tEN\t/m, 'string naziva plugina';
ok -f "$dir/HTML/EN/plugins/UnifiedMusic/settings/basic.html", 'stranica podesavanja';

{
	open my $page, '<', "$dir/HTML/EN/plugins/UnifiedMusic/settings/basic.html" or die $!;
	my $html = do { local $/; <$page> };
	unlike $html, qr/<option[^>]*disabled/, 'model bez kljuca mora da moze da se posalje iz forme';
	unlike $html, qr/umRunNow/, 'Run now ne zavisi od slanja forme';
	like $html, qr/id="umRun"/, 'dugme Run now';
	like $html, qr/id="umRefresh"/, 'dugme Refresh';
	like $html, qr/"mix",\s*"status"/, 'status preko CLI komande';
	like $html, qr/"mix",\s*"run"/, 'pokretanje preko CLI komande';
	like $html, qr/settings\/genres\.js/, 'kontrola zanrova';
	like $html, qr/class="umGenres"/, 'mesto za kontrolu zanrova';
	like $html, qr/no_player/, 'poruka kada nema plejera';
	like $html, qr/name="umCategoryOriginal\[% loop\.index %\]"/, 'forma pamti prethodni naziv';
	like $html, qr/name="umCategoryActive\[% loop\.index %\]"/, 'kvacica za aktivnu kategoriju';
}

done_testing;
