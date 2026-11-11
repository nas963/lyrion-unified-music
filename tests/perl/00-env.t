use strict;
use warnings;
use Test::More;
use Unicode::Normalize;
use JSON::PP;

ok(-f 't/fixtures/qobuz_tracks.json', 'fixtures kopirani');
done_testing;
