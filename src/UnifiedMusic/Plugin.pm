package Plugins::UnifiedMusic::Plugin;

# CLI komande pretrage i dnevnih miksova, i veza modula sa Lyrion-om.

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use Encode ();
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
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::PluginManager;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use Plugins::UnifiedMusic::AI::Anthropic;
use Plugins::UnifiedMusic::AI::Common;
use Plugins::UnifiedMusic::AI::OpenAI;
use Plugins::UnifiedMusic::Import::Album;
use Plugins::UnifiedMusic::Import::History;
use Plugins::UnifiedMusic::Import::Job;
use Plugins::UnifiedMusic::Import::Resolver;
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

my ($store, $scheduler, $history);
my %import = (running => 0);

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
	$history = Plugins::UnifiedMusic::Import::History->new(file => catdir(Slim::Utils::Prefs::dir(), 'unifiedmusic', 'imports.json'));
	eval { $history->compact; 1 } or $log->error("UnifiedMusic: spajanje uvoza nije uspelo: $@");

	Slim::Control::Request::addDispatch(['unifiedmusic', 'search'], [0, 1, 1, \&_cliSearch]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mixes', 'items'], [0, 1, 1, \&_cliMixes]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'items'], [0, 1, 1, \&_cliMixItems]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'play'], [1, 0, 1, \&_cliMixPlay]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'save'], [0, 0, 1, \&_cliMixSave]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'append'], [0, 0, 1, \&_cliMixAppend]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'run'], [0, 0, 1, \&_cliMixRun]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'status'], [0, 1, 1, \&_cliMixStatus]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'mix', 'rename'], [0, 0, 1, \&_cliMixRename]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'import', 'run'], [0, 0, 1, \&_cliImportRun]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'import', 'continue'], [0, 0, 1, \&_cliImportContinue]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'import', 'cancel'], [0, 0, 1, \&_cliImportCancel]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'import', 'status'], [0, 1, 1, \&_cliImportStatus]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'import', 'items'], [0, 1, 1, \&_cliImportItems]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'import', 'play'], [1, 0, 1, \&_cliImportPlay]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'import', 'delete'], [0, 0, 1, \&_cliImportDelete]);
	Slim::Control::Request::addDispatch(['unifiedmusic', 'import', 'rename'], [0, 0, 1, \&_cliImportRename]);

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

# --- Uvoz liste iz teksta ---

sub _import_resolver {
	my ($client) = @_;

	my $warn = sub { $log->warn($_[0]) };
	my $run = sub {
		my ($target, $command, $done) = @_;
		_run($target ? $client : undef, $command, $done);
	};
	my $services = installed_services();
	my %sources;
	for my $type (qw(track album)) {
		$sources{$type}{local} = Plugins::UnifiedMusic::Source::Local->new(run => $run, only => $type);
		$sources{$type}{$_} = Plugins::UnifiedMusic::Source::Service->new(service => $_, run => $run, log => $warn, only => $type) for @$services;
	}
	my %present = map { $_ => 1 } 'local', @$services;

	return Plugins::UnifiedMusic::Import::Resolver->new(
		order    => [grep { $present{$_} } @{ Plugins::UnifiedMusic::Search::source_order_for_primary($prefs->get('primarySource')) }],
		search   => sub {
			my ($type, $source, $term, $done) = @_;
			$sources{$type}{$source}->search($term, { client => $client ? $client->id : undef }, sub { $done->($_[0]{items}) });
		},
		expand   => sub { _expand_album($client, @_) },
		delay    => sub { _set_timer($SERVICE_PAUSE, $_[0]) },
		defer    => sub { _set_timer(0, $_[0]) },
		progress => sub {
			my ($index, $total, $entry) = @_;
			@import{qw(stage done total current)} = ('searching', $index - 1, $total, "$entry->{artist} - $entry->{title}");
		},
	);
}

# Album u adrese pesama: lokalno kroz titles, servis kroz meni albuma, na kraju explodePlaylist.
sub _expand_album {
	my ($client, $item, $done) = @_;

	my $play = $item->{play} || {};
	if (defined $play->{album_id}) {
		return _run(undef, ['titles', 0, 999, "album_id:$play->{album_id}", 'tags:u', 'sort:tracknum'], sub {
			my ($result) = @_;
			$done->([map { $_->{url} } @{ $result && $result->{titles_loop} || [] }]);
		});
	}

	my $explode = sub {
		my $url = $play->{url};
		my $handler = defined $url ? Slim::Player::ProtocolHandlers->handlerForURL($url) : undef;
		return $done->([]) unless $client && $handler && $handler->can('explodePlaylist');
		eval { $handler->explodePlaylist($client, $url, sub { $done->(Plugins::UnifiedMusic::Import::Album::only_tracks($_[0])) }); 1 }
			or do { $log->warn("UnifiedMusic: album $url nije razvijen: $@"); $done->([]) };
	};

	return $explode->() unless defined $item->{browse} && $client;

	my $browse = sub {
		my ($id, $callback) = @_;
		_run($client, ['globalsearch', 'items', 0, 999, 'menu:1', "item_id:$id"], $callback);
	};
	$browse->($item->{browse}, sub {
		my ($menu) = @_;
		my $urls = Plugins::UnifiedMusic::Import::Album::track_urls($menu);
		return $done->($urls) if @$urls;

		my @discs = @{ Plugins::UnifiedMusic::Import::Album::disc_ids($menu) };
		return $explode->() unless @discs;
		my @all;
		my $next;
		$next = sub {
			my $disc = shift @discs;
			if (!defined $disc) {
				undef $next;
				return @all ? $done->(\@all) : $explode->();
			}
			$browse->($disc, sub { push @all, @{ Plugins::UnifiedMusic::Import::Album::track_urls($_[0]) }; $next->() });
		};
		$next->();
	});
}

# Nova plejlista; ako naziv postoji, dodaje se " (2)", " (3)"...
sub _save_import_playlist {
	my ($name, $urls, $done) = @_;

	my $attempt = 1;
	my $try;
	$try = sub {
		my $candidate = $attempt == 1 ? $name : "$name ($attempt)";
		_run(undef, ['playlists', 'new', "name:$candidate"], sub {
			my $created = Plugins::UnifiedMusic::Mix::Cli::new_playlist_id($_[0]);
			if ($created->{exists} && ++$attempt <= 50) {
				return $try->();
			}
			undef $try;
			return $done->({ error => 1 }) unless $created->{id};
			_run_all(undef, [map { ['playlists', 'edit', 'cmd:add', "playlist_id:$created->{id}", "url:$_"] } @$urls], sub {
				$done->({ id => $created->{id}, name => $candidate });
			});
		});
	};
	$try->();
}

sub _append_import_playlist {
	my ($id, $urls, $done) = @_;

	_run_all(undef, [map { ['playlists', 'edit', 'cmd:add', "playlist_id:$id", "url:$_"] } @$urls], sub { $done->({ id => $id }) });
}

sub _import_summary {
	my ($entry) = @_;
	return undef unless $entry;
	return { map { $_ => $entry->{$_} } grep { defined $entry->{$_} } qw(id name date found total tracks error playlist_id appended) };
}

# Lyrion cita vrednost parametra samo do kraja reda, pa Material salje tekst URI-kodiran.
sub _import_param {
	my ($request, $name) = @_;

	my $value = $request->getParam($name);
	return $value unless defined $value && ($request->getParam('encoding') // '') eq 'uri';
	$value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
	return Encode::decode('UTF-8', $value);
}

sub _import_ai {
	my $config = _stored_config();
	my $provider = Plugins::UnifiedMusic::Mix::Config::provider_for_model($config->{model} // '');
	my $key = Plugins::UnifiedMusic::Mix::Config::key_for_model($config);
	return undef unless $provider && length($key // '');
	my $class = $provider eq 'openai' ? 'Plugins::UnifiedMusic::AI::OpenAI' : 'Plugins::UnifiedMusic::AI::Anthropic';
	return { adapter => $class->new(http => \&_http), model => $config->{model}, api_key => $key };
}

# Prvi korak: model cita tekst; rezultat ceka u stanju "review" da ga korisnik potvrdi.
sub _cliImportRun {
	my ($request) = @_;

	if ($import{running}) {
		$request->addResult('running', 1);
		return $request->setStatusDone;
	}

	my $ai = _import_ai();
	if (!$ai) {
		$request->addResult('error', 'Choose a model and enter its API key in the Unified Music settings.');
		return $request->setStatusDone;
	}

	my $date = _now()->{date};
	%import = (running => 1, stage => 'reading', started => time(), last => $import{last});

	my $finish = sub {
		my ($result) = @_;
		if ($result->{error}) {
			$log->warn("UnifiedMusic: uvoz liste nije uspeo: $result->{error}");
			%import = (running => 0, last => { error => $result->{error}, date => $date });
			return;
		}
		%import = (running => 0, stage => 'review', review => { list => $result->{list}, date => $date, model => $ai->{model} }, last => $import{last});
	};

	eval {
		Plugins::UnifiedMusic::Import::Job::extract({
			%$ai,
			text => _import_param($request, 'text'),
			date => $date,
			log  => sub { $log->warn($_[0]) },
		}, $finish);
		1;
	} or $finish->({ error => "Import failed: $@" });

	$request->addResult('started', 1);
	$request->setStatusDone;
}

# Drugi korak: pretraga i nova ili postojeca plejlista.
sub _cliImportContinue {
	my ($request) = @_;

	my $review = $import{review};
	if ($import{running} || !$review) {
		$request->addResult('error', $import{running} ? 'An import is already running.' : 'There is no recognised list to import. Analyze the text again.');
		return $request->setStatusDone;
	}

	my $playlist_id = $request->getParam('playlist_id');
	my $target = defined $playlist_id && length $playlist_id
		? { id => $playlist_id, name => _import_param($request, 'playlist_name') // '' }
		: { name => _import_param($request, 'name') };

	my $client = $request->client || _any_client();
	my $date = $review->{date};
	%import = (running => 1, stage => 'searching', started => time(), last => $import{last});

	my $finish = sub {
		my ($result) = @_;
		my $entry = { %$result, id => sprintf('%d-%04d', time(), int(rand(10000))), date => $date, created => time() };
		my $last = _import_summary($entry);
		if ($result->{items}) {
			eval {
				# Dopuna ide u zapis plejliste; poruka i dalje govori samo o ovom uvozu.
				my $saved = $result->{appended} ? $history->add_to_playlist($entry) : $history->add($entry);
				$last->{id} = $saved->{id};
				1;
			} or $log->error("UnifiedMusic: uvoz nije zapisan: $@");
		}
		$log->warn("UnifiedMusic: uvoz liste nije uspeo: $result->{error}") if $result->{error};
		%import = (running => 0, last => $last);
	};

	eval {
		Plugins::UnifiedMusic::Import::Job::build({
			list     => $review->{list},
			target   => $target,
			date     => $date,
			model    => $review->{model},
			resolver => _import_resolver($client),
			create   => \&_save_import_playlist,
			append   => \&_append_import_playlist,
			progress => sub { my ($state) = @_; $import{$_} = $state->{$_} for keys %$state },
		}, $finish);
		1;
	} or $finish->({ error => "Import failed: $@" });

	$request->addResult('started', 1);
	$request->setStatusDone;
}

sub _cliImportCancel {
	my ($request) = @_;

	if (!$import{running}) {
		delete $import{review};
		delete $import{stage};
	}
	$request->setStatusDone;
}

sub _cliImportStatus {
	my ($request) = @_;

	$request->addResult('running', $import{running} ? 1 : 0);
	for my $field (qw(stage done total current)) {
		$request->addResult($field, $import{$field}) if ($import{running} || $import{review}) && defined $import{$field};
	}
	if (!$import{running} && $import{review}) {
		my $list = $import{review}{list};
		$request->addResult('review', {
			name  => $list->{name},
			items => [map { my $item = $_; +{ map { $_ => $item->{$_} } grep { defined $item->{$_} } qw(type artist title composer artist_only whole_work) } } @{ $list->{items} }],
		});
	}
	$request->addResult('last', $import{last}) if $import{last};
	$request->setStatusDone;
}

sub _cliImportItems {
	my ($request) = @_;

	my $id = $request->getParam('id');
	if (!defined $id) {
		$request->addResult('imports', [map {
			my $entry = $_;
			my $summary = _import_summary($entry);
			# Za filter u Material-u: izvodjaci i naslovi iz liste.
			$summary->{terms} = join ' ', map { ($_->{artist} // '') . ' ' . ($_->{title} // '') . ' ' . ($_->{found} ? ($_->{found}{title} // '') : '') } @{ $entry->{items} || [] };
			$summary;
		} @{ $history->list }]);
		$request->addResult('running', $import{running} ? 1 : 0);
		return $request->setStatusDone;
	}

	my $entry = $history->get($id);
	if ($entry) {
		$request->addResult('import', _import_summary($entry));
		$request->addResult('items', [map {
			my %row = %$_;
			if ($row{found}) {
				my %found = %{ $row{found} };
				$found{count} = scalar @{ delete $found{urls} || [] };
				$row{found} = \%found;
			}
			\%row;
		} @{ $entry->{items} || [] }]);
	}
	$request->setStatusDone;
}

sub _cliImportPlay {
	my ($request) = @_;

	my $entry = $history->get($request->getParam('id'));
	my $index = $request->getParam('item');
	my @rows = grep { $_->{found} } $entry ? (defined $index ? ($entry->{items}[$index] // ()) : @{ $entry->{items} || [] }) : ();
	my (%seen, @urls);
	push @urls, grep { !$seen{$_}++ } @{ $_->{found}{urls} || [] } for @rows;

	my $commands = Plugins::UnifiedMusic::Mix::Cli::queue_commands($request->getParam('cmd') // 'play', \@urls);
	$request->setStatusProcessing;
	_run_all($request->client, $commands, sub { $request->setStatusDone });
}

sub _cliImportDelete {
	my ($request) = @_;

	$request->addResult('deleted', $history->remove($request->getParam('id')));
	$request->setStatusDone;
}

# Novi naziv uvezene liste i njene plejliste; plejlista sa istim nazivom se ne prepisuje.
sub _cliImportRename {
	my ($request) = @_;

	my $id = $request->getParam('id');
	my $entry = $history->get($id);
	my $name = Plugins::UnifiedMusic::Import::Job::clean_name(_import_param($request, 'name'));
	my $fail = sub {
		$request->addResult('error', $_[0]);
		$request->setStatusDone;
	};
	return $fail->('This imported list no longer exists.') unless $entry;
	return $fail->('Enter a name.') unless length $name;

	my $save = sub {
		$history->set_name($id, $name);
		$request->addResult('name', $name);
		$request->setStatusDone;
	};
	my $playlist = $entry->{playlist_id};
	return $save->() unless defined $playlist;

	$request->setStatusProcessing;
	_run(undef, ['playlists', 'rename', "playlist_id:$playlist", "newname:$name", 'dry_run:1'], sub {
		my ($check) = @_;
		return $fail->('The playlist was not found; it may have been deleted.') unless $check;
		my $other = $check->{overwritten_playlist_id};
		return $fail->(qq{A playlist named "$name" already exists.}) if defined $other && $other ne $playlist;
		_run(undef, ['playlists', 'rename', "playlist_id:$playlist", "newname:$name"], sub {
			return $fail->('The playlist could not be renamed.') unless $_[0];
			$save->();
		});
	});
}

1;
