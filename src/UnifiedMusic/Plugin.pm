package Plugins::UnifiedMusic::Plugin;

# CLI komande pretrage i dnevnih miksova, i veza modula sa Lyrion-om.

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec::Functions qw(catdir);
use POSIX ();
use Scalar::Util qw(blessed);
use Time::HiRes;

use Slim::Control::Request;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::Client;
use Slim::Utils::Log;
use Slim::Utils::PluginManager;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use Plugins::UnifiedMusic::AI::Anthropic;
use Plugins::UnifiedMusic::AI::Common;
use Plugins::UnifiedMusic::AI::OpenAI;
use Plugins::UnifiedMusic::MaterialBridge;
use Plugins::UnifiedMusic::Mix::Cli;
use Plugins::UnifiedMusic::Mix::Config;
use Plugins::UnifiedMusic::Mix::Job;
use Plugins::UnifiedMusic::Mix::OrderedSearch;
use Plugins::UnifiedMusic::Mix::Resolver;
use Plugins::UnifiedMusic::Mix::Scheduler;
use Plugins::UnifiedMusic::Mix::Store;
use Plugins::UnifiedMusic::Search;
use Plugins::UnifiedMusic::Source::Local;
use Plugins::UnifiedMusic::Source::Service;

my $TIMEOUT = 5;
my $AI_TIMEOUT = 120;
my $START_DELAY = 60;
my $SERVICE_PAUSE = 1;

my $prefs = preferences('plugin.unifiedmusic');
my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.unifiedmusic',
	defaultLevel => 'WARN',
	description  => 'PLUGIN_UNIFIEDMUSIC',
});

my ($store, $scheduler);

sub getDisplayName { 'PLUGIN_UNIFIEDMUSIC' }

sub initPlugin {
	my ($class, @args) = @_;

	$class->SUPER::initPlugin(@args);

	if (!defined $prefs->get('primarySource')) {
		$prefs->set('primarySource', Plugins::UnifiedMusic::Search::primary_from_order($prefs->get('sourceOrder')));
	}
	$prefs->init({ categories => [], trackCount => 30, runTime => '04:00', timeZone => 'Europe/Belgrade', model => 'claude-haiku-5-5' });

	_install_material_bridge();

	$store = Plugins::UnifiedMusic::Mix::Store->new(dir => catdir(Slim::Utils::Prefs::dir(), 'unifiedmusic', 'mixes'));

	Slim::Control::Request::addDispatch(['unifiedmusic', 'search'], [0, 1, 1, \&_cliSearch]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mixes', 'items'], [0, 1, 1, \&_cliMixes]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'items'], [0, 1, 1, \&_cliMixItems]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'play'], [1, 0, 1, \&_cliMixPlay]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'save'], [0, 0, 1, \&_cliMixSave]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'append'], [0, 0, 1, \&_cliMixAppend]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'run'], [0, 0, 1, \&_cliMixRun]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'status'], [0, 1, 1, \&_cliMixStatus]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'rename'], [0, 0, 1, \&_cliMixRename]);

	if (main::WEBUI) {
		require Plugins::UnifiedMusic::Settings;
		Plugins::UnifiedMusic::Settings->new;
		Slim::Web::Pages->addPageLinks('plugins', { PLUGIN_UNIFIEDMUSIC => 'plugins/UnifiedMusic/settings/basic.html' });
	}

	$scheduler = Plugins::UnifiedMusic::Mix::Scheduler->new(
		now          => \&_now,
		set_timer    => \&_set_timer,
		cancel_timer => sub { Slim::Utils::Timers::killSpecific($_[0]) },
		run_job      => \&_run_job,
		has_player   => sub { _any_client() ? 1 : 0 },
		last_run     => sub { $prefs->get('lastRun') },
		set_last_run => sub { $prefs->set('lastRun', $_[0]) },
		config       => \&_stored_config,
	);
	# Plejeri se javljaju tek posle starta servera.
	_set_timer($START_DELAY, sub { $scheduler->start });
}

# Postavlja nas blok u custom.js i ikonicu u Material-ove korisnicke foldere.
sub _install_material_bridge {
	my $folder = catdir(Slim::Utils::Prefs::dir(), 'material-skin');
	my $images = catdir($folder, 'images');
	my $custom = catdir($folder, 'custom.js');

	eval {
		make_path($images);

		my $current = '';
		if (open my $in, '<:raw', $custom) {
			local $/;
			$current = <$in>;
		}
		my $merged = Plugins::UnifiedMusic::MaterialBridge::merge_custom_js($current);
		if ($merged ne $current) {
			open my $out, '>:raw', $custom or die "$custom: $!";
			print {$out} $merged;
			close $out or die "$custom: $!";
		}

		copy(catdir(dirname(__FILE__), 'HTML', 'EN', 'plugins', 'UnifiedMusic', 'material', 'folder-local.svg'),
			catdir($images, 'folder-local.svg')) or die "folder-local.svg: $!";
		1;
	} or $log->error("Material Skin dodaci nisu postavljeni: $@");
}

sub rename_category {
	my ($old, $new) = @_;
	return $store->rename_category($old, $new);
}

sub reschedule {
	$scheduler->reschedule if $scheduler;
}

sub _set_timer {
	my ($seconds, $callback) = @_;
	return Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + $seconds, sub { $callback->() });
}

sub stored_config {
	return _stored_config();
}

sub _stored_config {
	return {
		map { $_ => $prefs->get($_) } qw(primarySource categories trackCount model anthropicKey openaiKey runTime timeZone)
	};
}

sub _now {
	my $result;
	{
		local $ENV{TZ} = _stored_config()->{timeZone};
		POSIX::tzset();
		my @time = localtime();
		$result = { date => POSIX::strftime('%Y-%m-%d', @time), hhmm => POSIX::strftime('%H:%M', @time), epoch => time() };
	}
	POSIX::tzset();
	return $result;
}

sub _any_client {
	my ($client) = grep { $_->connected } Slim::Player::Client::clients();
	return $client;
}

# Izvrsava Lyrion komandu; $done dobija rezultat ili undef, tacno jednom.
sub _run {
	my ($client, $command, $done) = @_;

	my $called;
	my $finish = sub {
		return if $called++;
		$done->(@_) if $done;
	};

	my $request = eval {
		Slim::Control::Request::executeRequest($client, $command, sub {
			my ($finished) = @_;
			$finish->($finished->isStatusError ? undef : $finished->getResults);
		});
	};

	if ($@ || !blessed($request) || $request->isStatusError) {
		$log->warn('Komanda nije izvrsena: ' . join(' ', @$command) . ($@ ? " ($@)" : ''));
		$finish->(undef);
	}
}

sub installed_services {
	return Plugins::UnifiedMusic::Search::available_services(sub { Slim::Utils::PluginManager->isEnabled($_[0]) });
}

sub _make_search {
	my ($client) = @_;

	my $warn = sub { $log->warn($_[0]) };
	my $run = sub {
		my ($target, $command, $done) = @_;
		_run($target ? $client : undef, $command, $done);
	};

	my %sources = (local => Plugins::UnifiedMusic::Source::Local->new(run => $run));
	$sources{$_} = Plugins::UnifiedMusic::Source::Service->new(service => $_, run => $run, log => $warn) for @{ installed_services() };

	return Plugins::UnifiedMusic::Search->new(
		sources => \%sources,
		source_order => Plugins::UnifiedMusic::Search::source_order_for_primary($prefs->get('primarySource')),
		timeout      => $TIMEOUT,
		set_timer    => \&_set_timer,
		cancel_timer => sub { Slim::Utils::Timers::killSpecific($_[0]) },
	);
}

# Za noćni posao: samo pesme, izvor po izvor, uz pauzu posle servisa.
sub _make_ordered_search {
	my ($client, $config) = @_;

	my $warn = sub { $log->warn($_[0]) };
	my $run = sub {
		my ($target, $command, $done) = @_;
		_run($target ? $client : undef, $command, $done);
	};

	my %sources = (local => Plugins::UnifiedMusic::Source::Local->new(run => $run, only => 'track'));
	$sources{$_} = Plugins::UnifiedMusic::Source::Service->new(service => $_, run => $run, log => $warn, only => 'track') for @{ installed_services() };

	return Plugins::UnifiedMusic::Mix::OrderedSearch->new(
		sources => \%sources,
		order  => Plugins::UnifiedMusic::Search::source_order_for_primary($config->{primarySource}),
		client => $client ? $client->id : undef,
		delay  => sub { _set_timer($SERVICE_PAUSE, $_[0]) },
	);
}

sub _cliSearch {
	my ($request) = @_;

	my $client = $request->client;
	my $search = _make_search($client);

	$request->setStatusProcessing;
	$search->run($request->getParam('term'), { client => $client ? $client->id : undef, library_id => $request->getParam('library_id') }, sub {
		my ($response) = @_;
		$request->addResult($_, $response->{$_}) for keys %$response;
		$request->setStatusDone;
	});
}

sub _http {
	my ($call, $callback) = @_;

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my ($http) = @_;
			$callback->(Plugins::UnifiedMusic::AI::Common::http_response($http->code, $http->content));
		},
		sub {
			my ($http, $error, $response) = @_;
			$callback->(Plugins::UnifiedMusic::AI::Common::http_response(
				$response ? $response->code : undef, $response ? $response->content : undef, $error,
			));
		},
		{ timeout => $AI_TIMEOUT },
	)->post($call->{url}, %{ $call->{headers} }, $call->{body});
}

sub _run_job {
	my ($done) = @_;

	my $checked = Plugins::UnifiedMusic::Mix::Config::validate(_stored_config());
	if (!$checked->{ok}) {
		my $result = { ok => [], failed => [{ name => 'settings', error => join(' ', @{ $checked->{errors} }) }] };
		$prefs->set('lastResult', $result);
		return $done->($result);
	}

	my $config = $checked->{config};
	my $client = _any_client();
	my $ordered = _make_ordered_search($client, $config);
	my $adapter_class = Plugins::UnifiedMusic::Mix::Config::provider_for_model($config->{model}) eq 'openai'
		? 'Plugins::UnifiedMusic::AI::OpenAI' : 'Plugins::UnifiedMusic::AI::Anthropic';

	Plugins::UnifiedMusic::Mix::Job::run({
		config   => $config,
		adapter  => $adapter_class->new(http => \&_http),
		resolver => Plugins::UnifiedMusic::Mix::Resolver->new(search => sub {
			my ($term, $callback, $key) = @_;
			$ordered->search($term, $callback, $key);
		}, defer => sub { _set_timer(0, $_[0]) }),
		store    => $store,
		rng      => sub { int(rand($_[0])) },
		date     => _now()->{date},
		log      => sub { $log->warn($_[0]) },
	}, sub {
		my ($result) = @_;
		$prefs->set('lastResult', $result);
		$done->($result);
	});
}

sub run_now {
	my ($callback) = @_;
	$scheduler->run_now($callback);
}

sub _cliMixes {
	my ($request) = @_;

	my $rows = Plugins::UnifiedMusic::Mix::Cli::categories($store, _stored_config(), _now()->{date});
	$request->addResult('categories', $rows);
	$request->setStatusDone;
}

sub _cliMixItems {
	my ($request) = @_;

	my $resp = Plugins::UnifiedMusic::Mix::Cli::mix_items($store, $request->getParam('category'), $request->getParam('date'), _now()->{date});
	$request->addResult($_, $resp->{$_}) for keys %$resp;
	$request->setStatusDone;
}

sub _mix_urls {
	my ($request) = @_;

	my $resp = Plugins::UnifiedMusic::Mix::Cli::mix_items($store, $request->getParam('category'), $request->getParam('date'), _now()->{date});
	return [map { $_->{url} } @{ $resp->{tracks} }];
}

sub _run_all {
	my ($client, $commands, $done) = @_;

	my @queue = @$commands;
	my $next;
	$next = sub {
		my $command = shift @queue;
		if (!$command) {
			undef $next;
			return $done->();
		}
		_run($client, $command, sub { $next->() });
	};
	$next->();
}

sub _cliMixPlay {
	my ($request) = @_;

	my $commands = Plugins::UnifiedMusic::Mix::Cli::queue_commands($request->getParam('cmd') // 'play', _mix_urls($request));
	$request->setStatusProcessing;
	_run_all($request->client, $commands, sub { $request->setStatusDone });
}

sub _add_to_playlist {
	my ($request, $playlist_id, $urls) = @_;

	$request->setStatusProcessing;
	_run_all(undef, [map { ['playlists', 'edit', 'cmd:add', "playlist_id:$playlist_id", "url:$_"] } @$urls], sub {
		$request->addResult('playlist_id', $playlist_id);
		$request->setStatusDone;
	});
}

sub _cliMixSave {
	my ($request) = @_;

	my $urls = _mix_urls($request);
	$request->setStatusProcessing;
	_run(undef, ['playlists', 'new', 'name:' . $request->getParam('name')], sub {
		my ($result) = @_;
		my $created = Plugins::UnifiedMusic::Mix::Cli::new_playlist_id($result);
		if ($created->{exists}) {
			$request->addResult('exists', 1);
			$request->setStatusDone;
			return;
		}
		if ($created->{error}) {
			$request->addResult('failed', 1);
			$request->setStatusDone;
			return;
		}
		_add_to_playlist($request, $created->{id}, $urls);
	});
}

sub _cliMixAppend {
	my ($request) = @_;

	_add_to_playlist($request, $request->getParam('playlist_id'), _mix_urls($request));
}

sub _cliMixStatus {
	my ($request) = @_;

	$request->addResult('running', $scheduler->is_running);
	$request->addResult('last', $prefs->get('lastResult'));
	$request->setStatusDone;
}

sub _cliMixRename {
	my ($request) = @_;

	$request->addResult('moved', rename_category($request->getParam('from'), $request->getParam('to')));
	$request->setStatusDone;
}

sub _cliMixRun {
	my ($request) = @_;

	$scheduler->run_now(sub {
		my ($result) = @_;
		if ($result->{no_player}) {
			$request->addResult('no_player', 1);
		}
		elsif (!$result->{running}) {
			$prefs->set('lastResult', $result);
		}
	});
	$request->setStatusDone;
}

1;
