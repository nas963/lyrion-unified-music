package Plugins::UnifiedMusic::MaterialBridge;

# Blok koji Material-ov custom.js ucitava nasu skriptu. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

my $START = '// UnifiedMusic start';
my $END   = '// UnifiedMusic end';

my $BLOCK = <<"END_BLOCK";
$START
(function () {
    var script = document.createElement("script");
    script.src = "/plugins/UnifiedMusic/material/unified-material.js?v=" + Math.floor(Date.now() / 3600000);
    document.body.appendChild(script);
})();
$END
END_BLOCK

sub remove_custom_js {
	my ($text) = @_;

	$text //= '';
	$text =~ s/\Q$START\E.*?\Q$END\E\n?//s;
	return $text;
}

sub merge_custom_js {
	my ($text) = @_;

	return remove_custom_js($text) . $BLOCK;
}

1;
