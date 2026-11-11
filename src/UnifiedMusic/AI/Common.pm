package Plugins::UnifiedMusic::AI::Common;

# Zajednicki delovi AI adaptera. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

use Exporter qw(import);
use JSON::PP;

our @EXPORT_OK = qw(parse_suggestions redact schema encode_body decode_body http_error http_response MAX_OUTPUT_TOKENS);

use constant MAX_OUTPUT_TOKENS => 16000;

my $JSON = JSON::PP->new->utf8->canonical;

sub schema {
	return {
		type => 'object',
		additionalProperties => JSON::PP::false,
		required => ['suggestions'],
		properties => {
			suggestions => {
				type => 'array',
				items => {
					type => 'object',
					additionalProperties => JSON::PP::false,
					required => ['artist', 'title'],
					properties => { artist => { type => 'string' }, title => { type => 'string' } },
				},
			},
		},
	};
}

sub encode_body {
	return $JSON->encode($_[0]);
}

sub decode_body {
	my ($text) = @_;
	return undef unless defined $text;
	return eval { $JSON->decode($text) };
}

sub parse_suggestions {
	my ($text) = @_;

	return undef unless defined $text;
	$text =~ s/^\s*```(?:json)?\s*//i;
	$text =~ s/\s*```\s*$//;

	my $data = eval { JSON::PP->new->decode($text) };
	return undef unless ref $data eq 'HASH' && ref $data->{suggestions} eq 'ARRAY';

	my @list;
	for my $item (@{ $data->{suggestions} }) {
		next unless ref $item eq 'HASH';
		next unless defined $item->{artist} && $item->{artist} =~ /\S/ && defined $item->{title} && $item->{title} =~ /\S/;
		push @list, { artist => $item->{artist}, title => $item->{title} };
	}
	return \@list;
}

sub redact {
	my ($text, @keys) = @_;

	for my $key (grep { defined && length } @keys) {
		$text =~ s/\Q$key\E/<key>/g;
	}
	return $text;
}

# Pravi odgovor za adapter iz statusa, tela i teksta greske HTTP klijenta.
sub http_response {
	my ($code, $body, $error) = @_;

	return { status => $code, body => $body } if $code;
	return { error => length($error // '') ? $error : 'Network error.' };
}

# Vraca gresku za neuspeo HTTP odgovor ili undef ako je odgovor uspesan.
sub http_error {
	my ($response, $key) = @_;

	return { error => redact($response->{error}, $key), retryable => 1 } if defined $response->{error};

	my $status = $response->{status} // 0;
	return undef if $status >= 200 && $status < 300;

	my $retryable = ($status == 429 || $status >= 500) ? 1 : 0;
	return { error => substr(redact("HTTP $status: " . ($response->{body} // ''), $key), 0, 300), retryable => $retryable };
}

1;
