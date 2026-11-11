package Plugins::UnifiedMusic::Mix::Job;

# Jedan prolaz kroz sve kategorije: model, trazenje pesama, upis.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Mix::Config;
use Plugins::UnifiedMusic::Mix::Prompt;

use constant KEEP_DAYS => 7;

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

		my $request = {
			model   => $config->{model},
			api_key => Plugins::UnifiedMusic::Mix::Config::key_for_model($config),
			prompt  => Plugins::UnifiedMusic::Mix::Prompt::build({ category => $category, count => $config->{trackCount}, rng => $rng }),
		};
		my $name = $category->{name};

		my $on_answer = sub {
			my ($answer) = @_;
			if ($answer->{error}) {
				$fail->($name, $answer->{error});
				return $next->();
			}
			$resolver->resolve($answer->{suggestions}, $config->{trackCount}, sub {
				my ($tracks) = @_;
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

		$adapter->suggest($request, sub {
			my ($answer) = @_;
			return $on_answer->($answer) unless $answer->{error} && $answer->{retryable};
			$adapter->suggest($request, $on_answer);
		});
	};
	$next->();
}

1;
