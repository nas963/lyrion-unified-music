package Plugins::UnifiedMusic::AI::Anthropic;

# Adapter za Anthropic Messages API. HTTP se ubacuje.

use strict;
use warnings;
use utf8;

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
		model      => $request->{model},
		max_tokens => MAX_OUTPUT_TOKENS,
		system     => $request->{prompt}{system},
		messages   => [{ role => 'user', content => $request->{prompt}{user} }],
		output_config => { effort => 'low', format => { type => 'json_schema', schema => $schema } },
	});

	$self->{http}->({
		url     => 'https://api.anthropic.com/v1/messages',
		headers => { 'x-api-key' => $key, 'anthropic-version' => '2026-10-21', 'content-type' => 'application/json' },
		body    => $body,
	}, sub {
		my ($response) = @_;

		my $error = http_error($response, $key);
		return $done->($error) if $error;

		my $data = decode_body($response->{body});
		return $done->({ error => 'Invalid response.', retryable => 1 }) unless ref $data eq 'HASH';

		my $stop = $data->{stop_reason} // '';
		return $done->({ error => 'The model declined the request.', retryable => 0 }) if $stop eq 'refusal';
		return $done->({ error => 'The response was cut off.', retryable => 1 }) if $stop eq 'max_tokens';

		my ($text) = map { $_->{text} } grep { ($_->{type} // '') eq 'text' } @{ $data->{content} || [] };
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
