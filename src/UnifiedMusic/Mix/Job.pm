package Plugins::UnifiedMusic::Mix::Job;

# Jedan prolaz kroz sve kategorije: model, trazenje pesama, upis.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Mix::Config;
use Plugins::UnifiedMusic::Mix::Prompt;
use Plugins::UnifiedMusic::Mix::Resolver;

use constant KEEP_DAYS => 7;
# Model ponekad vrati mnogo manje predloga nego sto je trazeno; tada se pita jos najvise dva puta.
use constant TOP_UPS => 2;
use constant SUGGESTIONS_PER_TRACK => 2;

sub run {
	my ($args, $done) = @_;

	my ($config, $adapter, $resolver, $store, $rng, $date, $log) = @$args{qw(config adapter resolver store rng date log)};
	my @queue = grep { $_->{active} // 1 } @{ $config->{categories} };
	my (@ok, @failed);

	my $fail = sub {
		my ($name, $error) = @_;
		push @failed, { name => $name, error => $error };
		$log->("UnifiedMusic: kategorija '$name' nije napravljena: $error");
	};

	my $next;
	$next = sub {
		my $category = shift @queue;
		if (!$category) {
			undef $next;
			eval { $store->prune($date, KEEP_DAYS); 1 } or $log->("UnifiedMusic: brisanje starih miksova nije uspelo: $@");
			return $done->({ ok => \@ok, failed => \@failed });
		}

		my $name = $category->{name};
		my $count = $config->{trackCount};
		my $first = Plugins::UnifiedMusic::Mix::Prompt::build({ category => $category, count => $count, rng => $rng });
		my (@suggestions, %known);
		my $rounds = 0;

		my $resolve = sub {
			$resolver->resolve(\@suggestions, $count, sub {
				my ($tracks) = @_;
				$log->("UnifiedMusic: kategorija '$name': " . scalar(@suggestions) . ' predloga'
					. ($rounds > 1 ? ' (' . ($rounds - 1) . ' dopuna)' : '') . ', ' . scalar(@$tracks) . ' pesama');
				if (@$tracks) {
					if (eval { $store->save({ category => $name, date => $date, model => $config->{model}, tracks => $tracks }); 1 }) {
						push @ok, $name;
					}
					else {
						$fail->($name, "Could not save the mix: $@");
					}
				}
				else {
					$fail->($name, 'No tracks were found.');
				}
				$next->();
			});
		};

		my $ask;
		$ask = sub {
			my ($prompt) = @_;
			$rounds++;
			my $request = {
				model   => $config->{model},
				api_key => Plugins::UnifiedMusic::Mix::Config::key_for_model($config),
				prompt  => $prompt,
			};
			my $on_answer = sub {
				my ($answer) = @_;
				if ($answer->{error}) {
					# Neuspela dopuna ne kvari ono sto je vec stiglo.
					undef $ask;
					return $resolve->() if @suggestions;
					$fail->($name, $answer->{error});
					return $next->();
				}
				my $before = @suggestions;
				for my $suggestion (@{ $answer->{suggestions} }) {
					push @suggestions, $suggestion
						unless $known{ Plugins::UnifiedMusic::Mix::Resolver::suggestion_key($suggestion->{artist}, $suggestion->{title}) }++;
				}
				if (@suggestions < $count * SUGGESTIONS_PER_TRACK && $rounds <= TOP_UPS && @suggestions > $before) {
					return $ask->(Plugins::UnifiedMusic::Mix::Prompt::more($first, \@suggestions, $first->{requested} - @suggestions));
				}
				undef $ask;
				$resolve->();
			};
			$adapter->suggest($request, sub {
				my ($answer) = @_;
				return $on_answer->($answer) unless $answer->{error} && $answer->{retryable};
				$adapter->suggest($request, $on_answer);
			});
		};
		$ask->($first);
	};
	$next->();
}

1;
