package Plugins::UnifiedMusic::Settings;

use strict;
use warnings;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

use Plugins::UnifiedMusic::Mix::Config;
use Plugins::UnifiedMusic::Search;

my $prefs = preferences('plugin.unifiedmusic');
my $EXTRA_ROWS = 3;

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_UNIFIEDMUSIC');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/UnifiedMusic/settings/basic.html');
}

sub prefs {
	return ($prefs);
}

sub _save {
	my ($params) = @_;

	my %input = (
		primarySource => $params->{umPrimarySource},
		categories    => Plugins::UnifiedMusic::Mix::Config::categories_from_form($params),
		trackCount    => $params->{umTrackCount},
		model         => $params->{umModel},
		runTime       => $params->{umRunTime},
		timeZone      => $params->{umTimeZone},
		anthropicKey  => length($params->{umAnthropicKey} // '') ? $params->{umAnthropicKey} : $prefs->get('anthropicKey'),
		openaiKey     => length($params->{umOpenaiKey} // '') ? $params->{umOpenaiKey} : $prefs->get('openaiKey'),
	);

	my $checked = Plugins::UnifiedMusic::Mix::Config::validate(\%input);
	if (!$checked->{ok}) {
		$params->{warning} = join(' ', @{ $checked->{errors} });
		return;
	}

	$prefs->set($_, $checked->{config}{$_}) for qw(primarySource categories trackCount model runTime timeZone anthropicKey openaiKey);
	require Plugins::UnifiedMusic::Plugin;
	Plugins::UnifiedMusic::Plugin::rename_category(@$_) for @{ Plugins::UnifiedMusic::Mix::Config::category_renames($params) };
	Plugins::UnifiedMusic::Plugin::reschedule();
}

sub handler {
	my ($class, $client, $params, @rest) = @_;

	if ($params->{saveSettings}) {
		_save($params);
	}

	my $stored = { map { $_ => $prefs->get($_) } qw(primarySource trackCount model runTime timeZone anthropicKey openaiKey) };
	my $categories = [map { { %$_, original => $_->{name} } } @{ $prefs->get('categories') || [] }];

	# Posle neuspelog cuvanja prikazuje se ono sto je korisnik uneo.
	if ($params->{saveSettings} && $params->{warning}) {
		$stored->{primarySource} = $params->{umPrimarySource};
		$stored->{trackCount} = $params->{umTrackCount};
		$stored->{model} = $params->{umModel};
		$stored->{runTime} = $params->{umRunTime};
		$stored->{timeZone} = $params->{umTimeZone};
		$categories = Plugins::UnifiedMusic::Mix::Config::categories_from_form($params);
	}

	$params->{um} = $stored;
	$params->{umSources} = Plugins::UnifiedMusic::Search::source_options(Plugins::UnifiedMusic::Plugin::installed_services(), $stored->{primarySource});
	$params->{umHasAnthropic} = length($stored->{anthropicKey} // '') ? 1 : 0;
	$params->{umHasOpenai} = length($stored->{openaiKey} // '') ? 1 : 0;
	$params->{umModels} = Plugins::UnifiedMusic::Mix::Config::available_models($stored);
	$params->{umCategories} = [
		(map { { name => $_->{name}, genres => join("\n", @{ $_->{genres} }), active => ($_->{active} // 1) ? 1 : 0, original => $_->{original} // '' } } @$categories),
		(map { { name => '', genres => '', active => 1, original => '' } } 1 .. $EXTRA_ROWS),
	];
	$params->{umCategoryRows} = $#{ $params->{umCategories} };
	delete $stored->{$_} for qw(anthropicKey openaiKey);

	return $class->SUPER::handler($client, $params, @rest);
}

1;
