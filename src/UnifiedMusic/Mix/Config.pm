package Plugins::UnifiedMusic::Mix::Config;

# Provera podesavanja dnevnih miksova. Bez zavisnosti od Lyrion-a.

use strict;
use warnings;
use utf8;

my @MODELS = (
	{ id => 'claude-haiku-5-5', provider => 'anthropic', key => 'anthropicKey' },
	{ id => 'gpt-6-luna',       provider => 'openai',    key => 'openaiKey' },
);
my %MODEL = map { $_->{id} => $_ } @MODELS;
my %PRIMARY = map { $_ => 1 } qw(local qobuz tidal);

sub _trim {
	my ($text) = @_;
	$text //= '';
	$text =~ s/^\s+|\s+$//g;
	return $text;
}

sub provider_for_model {
	my ($model) = @_;
	return $MODEL{$model} ? $MODEL{$model}{provider} : undef;
}

sub key_for_model {
	my ($config) = @_;
	my $model = $MODEL{ $config->{model} // '' } or return undef;
	return $config->{ $model->{key} };
}

sub available_models {
	my ($config) = @_;
	return [map { { id => $_->{id}, available => length(_trim($config->{ $_->{key} })) ? 1 : 0 } } @MODELS];
}

sub categories_from_form {
	my ($params) = @_;

	my @categories;
	for my $index (0 .. ($params->{umCategoryRows} // -1)) {
		my $name = _trim($params->{"umCategoryName$index"});
		next unless length $name;
		my $genres = $params->{"umCategoryGenres$index"} // '';
		push @categories, {
			name   => $name,
			genres => [grep { length } map { _trim($_) } split /\r?\n/, $genres],
			active => $params->{"umCategoryActive$index"} ? 1 : 0,
		};
		my $original = _trim($params->{"umCategoryOriginal$index"});
		$categories[-1]{original} = $original if length $original;
	}
	return \@categories;
}

sub category_renames {
	my ($params) = @_;

	return [map { [$_->{original}, $_->{name}] } grep { defined $_->{original} && $_->{original} ne $_->{name} } @{ categories_from_form($params) }];
}

sub validate {
	my ($input) = @_;

	my %config = (trackCount => 30, runTime => '04:00', timeZone => 'Europe/Belgrade', primarySource => 'local');
	for my $name (keys %$input) {
		$config{$name} = $input->{$name} if defined $input->{$name} && $input->{$name} ne '';
	}

	my @errors;

	push @errors, 'Unknown primary source.' unless $PRIMARY{ $config{primarySource} };
	push @errors, 'Track count must be a number from 5 to 100.'
		unless $config{trackCount} =~ /^\d+$/ && $config{trackCount} >= 5 && $config{trackCount} <= 100;
	push @errors, 'Run time must be HH:MM.'
		unless $config{runTime} =~ /^([01]\d|2[0-3]):[0-5]\d$/;
	push @errors, 'Time zone is required.' unless length _trim($config{timeZone});

	if (!$MODEL{ $config{model} // '' }) {
		push @errors, 'Choose a supported model.';
	}
	elsif (!length _trim(key_for_model(\%config))) {
		push @errors, "Model $config{model} needs its API key.";
	}

	my (@categories, %seen);
	for my $category (@{ $config{categories} || [] }) {
		my $name = _trim($category->{name});
		my @genres = grep { length } map { _trim($_) } @{ $category->{genres} || [] };
		if (!length $name) {
			push @errors, 'Category name is required.';
			next;
		}
		push @errors, "Category '$name' is listed twice." if $seen{ lc $name }++;
		push @errors, "Category '$name' needs at least one genre." unless @genres;
		push @categories, { name => $name, genres => \@genres, active => ($category->{active} // 1) ? 1 : 0 };
	}
	$config{categories} = \@categories;

	return @errors ? { ok => 0, errors => \@errors } : { ok => 1, config => \%config };
}

1;
