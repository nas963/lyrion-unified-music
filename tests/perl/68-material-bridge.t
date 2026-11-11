use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::MaterialBridge;

*merge = \&Plugins::UnifiedMusic::MaterialBridge::merge_custom_js;
*remove = \&Plugins::UnifiedMusic::MaterialBridge::remove_custom_js;

my $empty = merge('');
like $empty, qr{/plugins/UnifiedMusic/material/unified-material\.js}, 'ucitava skriptu';
is merge($empty), $empty, 'ponovno spajanje ne dodaje blok';

my $user = "console.log('moje');\n";
my $merged = merge($user);
like $merged, qr/console\.log\('moje'\);/, 'cuva postojeci sadrzaj';
is remove($merged), $user, 'uklanjanje vraca postojeci sadrzaj';
is remove($empty), '', 'uklanjanje iz praznog';
is remove($user), $user, 'bez bloka nema izmene';

my $old = merge('') =~ s/unified-material\.js/stara.js/r;
my $updated = merge($old);
unlike $updated, qr/stara\.js/, 'stari blok se zamenjuje';
is(() = $updated =~ /UnifiedMusic start/g, 1, 'samo jedan blok');

done_testing;
