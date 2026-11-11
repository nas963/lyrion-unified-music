use strict;
use warnings;
use utf8;
use Test::More;
use JSON::PP;
use Plugins::UnifiedMusic::AI::Common;
use Plugins::UnifiedMusic::AI::Anthropic;
use Plugins::UnifiedMusic::AI::OpenAI;

*parse = \&Plugins::UnifiedMusic::AI::Common::parse_suggestions;
*redact = \&Plugins::UnifiedMusic::AI::Common::redact;

my $json = JSON::PP->new->utf8->canonical;
my $good = '{"suggestions":[{"artist":"Miles Davis","title":"So What"}]}';

is_deeply parse($good), [{ artist => 'Miles Davis', title => 'So What' }], 'ispravan JSON';
is_deeply parse("```json\n$good\n```"), [{ artist => 'Miles Davis', title => 'So What' }], 'Markdown blok';
is_deeply parse('{"suggestions":[{"artist":"A","title":"B","year":1959},{"artist":"","title":"C"},{"title":"D"}]}'),
	[{ artist => 'A', title => 'B' }], 'visak polja i prazne stavke';
is parse('nije json'), undef, 'neispravan JSON';
is parse('{"x":1}'), undef, 'bez liste';
is redact('greska sk-tajna kraj', 'sk-tajna', undef, ''), 'greska <key> kraj', 'kljuc se skriva';

{
	my $http_response = \&Plugins::UnifiedMusic::AI::Common::http_response;
	is_deeply $http_response->(401, 'no', 'Unauthorized'), { status => 401, body => 'no' }, 'status iz greske se cuva';
	is_deeply $http_response->(undef, undef, 'timeout'), { error => 'timeout' }, 'bez statusa je mrezna greska';
	is_deeply $http_response->(0, '', ''), { error => 'Network error.' }, 'bez teksta greske';
	my $long = ('x' x 295) . 'sk-tajna';
	unlike Plugins::UnifiedMusic::AI::Common::http_error({ status => 400, body => $long }, 'sk-tajna')->{error}, qr/sk-t/, 'kljuc na granici se skriva';
}

sub call {
	my ($class, $model, $response) = @_;
	my (@requests, @done);
	my $adapter = $class->new(http => sub { push @requests, $_[0]; $_[1]->($response) });
	$adapter->suggest({ model => $model, api_key => 'sk-tajna', prompt => { system => 'S', user => 'U' } }, sub { push @done, $_[0] });
	return (\@requests, \@done);
}

sub body { return JSON::PP->new->utf8->decode($_[0]{body}) }

my $a = 'Plugins::UnifiedMusic::AI::Anthropic';
{
	my $ok = { status => 200, body => $json->encode({ stop_reason => 'end_turn', content => [{ type => 'text', text => $good }] }) };
	my ($requests, $done) = call($a, 'claude-haiku-5-5', $ok);
	my $request = $requests->[0];
	is $request->{url}, 'https://api.anthropic.com/v1/messages', 'anthropic adresa';
	is $request->{headers}{'x-api-key'}, 'sk-tajna', 'anthropic kljuc u zaglavlju';
	is $request->{headers}{'anthropic-version'}, '2026-10-21', 'anthropic verzija';
	unlike $request->{body}, qr/sk-tajna/, 'kljuc nije u telu';
	my $body = body($request);
	is $body->{model}, 'claude-haiku-5-5', 'model';
	is $body->{max_tokens}, 16000, 'ogranicenje izlaza';
	ok !exists $body->{temperature}, 'bez temperature';
	is $body->{system}, 'S', 'system';
	is $body->{output_config}{effort}, 'low', 'trud';
	is $body->{output_config}{format}{type}, 'json_schema', 'sema';
	is scalar @$done, 1, 'done jednom';
	is $done->[0]{suggestions}[0]{title}, 'So What', 'predlozi';
}

my %cases = (
	'odbijanje'    => [{ status => 200, body => $json->encode({ stop_reason => 'refusal', content => [] }) }, 0],
	'max_tokens'   => [{ status => 200, body => $json->encode({ stop_reason => 'max_tokens', content => [{ type => 'text', text => '{' }] }) }, 1],
	'los JSON'     => [{ status => 200, body => $json->encode({ stop_reason => 'end_turn', content => [{ type => 'text', text => 'xx' }] }) }, 1],
	'401'          => [{ status => 401, body => '{"error":"sk-tajna"}' }, 0],
	'500'          => [{ status => 500, body => 'x' }, 1],
	'mreza'        => [{ error => 'timeout sk-tajna' }, 1],
);
for my $name (sort keys %cases) {
	my ($response, $retryable) = @{ $cases{$name} };
	my (undef, $done) = call($a, 'claude-haiku-5-5', $response);
	is scalar @$done, 1, "$name: done jednom";
	ok defined $done->[0]{error}, "$name: greska";
	is $done->[0]{retryable}, $retryable, "$name: ponovljivo";
	unlike $done->[0]{error}, qr/sk-tajna/, "$name: bez kljuca";
}

my $o = 'Plugins::UnifiedMusic::AI::OpenAI';
{
	my $ok = { status => 200, body => $json->encode({ status => 'completed', output => [{ type => 'message', content => [{ type => 'output_text', text => $good }] }] }) };
	my ($requests, $done) = call($o, 'gpt-6-luna', $ok);
	my $request = $requests->[0];
	is $request->{url}, 'https://api.openai.com/v1/responses', 'openai adresa';
	is $request->{headers}{Authorization}, 'Bearer sk-tajna', 'openai kljuc';
	my $body = body($request);
	is $body->{model}, 'gpt-6-luna', 'openai model';
	is $body->{max_output_tokens}, 16000, 'openai ogranicenje';
	ok !exists $body->{temperature}, 'openai bez temperature';
	is $body->{text}{format}{type}, 'json_schema', 'openai sema';
	ok $body->{text}{format}{strict}, 'openai strict';
	is $body->{input}[0]{role}, 'system', 'openai system';
	is $done->[0]{suggestions}[0]{artist}, 'Miles Davis', 'openai predlozi';

	my (undef, $incomplete) = call($o, 'gpt-6-luna', { status => 200, body => $json->encode({ status => 'incomplete', output => [] }) });
	is $incomplete->[0]{retryable}, 1, 'openai nepotpun odgovor';
	my (undef, $refused) = call($o, 'gpt-6-luna', { status => 200, body => $json->encode({ status => 'completed', output => [{ type => 'message', content => [{ type => 'refusal', refusal => 'ne' }] }] }) });
	is $refused->[0]{retryable}, 0, 'openai odbijanje';
}

done_testing;
