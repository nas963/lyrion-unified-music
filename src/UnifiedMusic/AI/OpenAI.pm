package Plugins::UnifiedMusic::AI::OpenAI;

# Adapter za OpenAI Responses API. HTTP se ubacuje.

use strict;
use warnings;
use utf8;

use JSON::PP;
use Plugins::UnifiedMusic::AI::Common qw(parse_suggestions schema encode_body decode_body http_error MAX_OUTPUT_TOKENS);

sub new {
	my ($class, %args) = @_;
	return bless { http => $args{http} }, $class;
}

# Zahtev moze doneti svoju semu i parser; bez njih se traze predlozi pesama.
sub suggest {
	my ($self, $request, $done) = @_;

	my $key = $request->{api_key};
	my $schema = $request->{schema} // schema();
	my $parse = $request->{parse} // \&_suggestions;
	my $body = encode_body({
		model => $request->{model},
		max_output_tokens => MAX_OUTPUT_TOKENS,
		input => [
			{ role => 'system', content => $request->{prompt}{system} },
			{ role => 'user', content => $request->{prompt}{user} },
		],
		text => { format => { type => 'json_schema', name => $request->{schema_name} // 'suggestions', strict => JSON::PP::true, schema => $schema } },
	});

	$self->{http}->({
		url     => 'https://api.openai.com/v1/responses',
		headers => { Authorization => "Bearer $key", 'content-type' => 'application/json' },
		body    => $body,
	}, sub {
		my ($response) = @_;

		my $error = http_error($response, $key);
		return $done->($error) if $error;

		my $data = decode_body($response->{body});
		return $done->({ error => 'Invalid response.', retryable => 1 }) unless ref $data eq 'HASH';
		return $done->({ error => 'The response was cut off.', retryable => 1 }) if ($data->{status} // '') eq 'incomplete';

		my @parts = map { @{ $_->{content} || [] } } grep { ($_->{type} // '') eq 'message' } @{ $data->{output} || [] };
		return $done->({ error => 'The model declined the request.', retryable => 0 }) if grep { ($_->{type} // '') eq 'refusal' } @parts;

		my ($text) = map { $_->{text} } grep { ($_->{type} // '') eq 'output_text' } @parts;
		my $result = $parse->($text);
		return $done->({ error => 'The response was not valid JSON.', retryable => 1 }) unless $result;

		$done->($result);
	});
}

sub _suggestions {
	my $list = parse_suggestions($_[0]);
	return $list ? { suggestions => $list } : undef;
}

1;
