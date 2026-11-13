package Plugins::UnifiedMusic::Import::Job;

# Uvoz liste iz teksta: model izvlaci stavke, pretraga nalazi pesme, pravi se plejlista.
# Model, pretraga i cuvanje plejliste se ubacuju.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Import::Prompt;

sub _name {
	my ($wanted, $suggested, $date) = @_;

	for my $name ($wanted, $suggested) {
		next unless defined $name;
		(my $clean = $name) =~ s/^\s+|\s+$//g;
		$clean =~ s/\s+/ /g;
		return $clean if length $clean;
	}
	return "Imported list $date";
}

sub _unique_urls {
	my ($results) = @_;

	my (%seen, @urls);
	for my $result (grep { $_->{found} } @$results) {
		push @urls, grep { !$seen{$_}++ } @{ $result->{found}{urls} };
	}
	return \@urls;
}

sub run {
	my ($args, $done) = @_;

	my ($adapter, $resolver, $save, $progress, $log) = @$args{qw(adapter resolver save progress log)};
	$progress ||= sub {};
	$log ||= sub {};

	my $text = $args->{text} // '';
	return $done->({ error => 'Paste the text with the list first.' }) unless $text =~ /\S/;

	my $request = {
		model       => $args->{model},
		api_key     => $args->{api_key},
		prompt      => Plugins::UnifiedMusic::Import::Prompt::build($text),
		schema      => Plugins::UnifiedMusic::Import::Prompt::schema(),
		schema_name => 'listening_list',
		parse       => \&Plugins::UnifiedMusic::Import::Prompt::parse,
	};

	my $on_list = sub {
		my ($answer) = @_;
		return $done->({ error => "The model could not read the list: $answer->{error}" }) if $answer->{error};

		my $list = $answer->{list};
		if (!@{ $list->{items} }) {
			$log->('UnifiedMusic: model nije prepoznao stavke; tekst ' . length($text) . ' znakova, odgovor: ' . ($answer->{raw} // ''));
			return $done->({ error => 'No albums or tracks were recognised in the text.' });
		}

		$progress->({ stage => 'searching', done => 0, total => scalar @{ $list->{items} } });
		$resolver->resolve($list->{items}, sub {
			my ($results) = @_;
			my $urls = _unique_urls($results);
			my $found = grep { $_->{found} } @$results;
			return $done->({ error => 'None of the ' . scalar(@$results) . ' items were found.', items => $results }) unless @$urls;

			my $name = _name($args->{name}, $list->{name}, $args->{date});
			$progress->({ stage => 'saving', done => scalar @$results, total => scalar @$results });
			$save->($name, $urls, sub {
				my ($saved) = @_;
				return $done->({ error => 'The playlist could not be saved.', items => $results }) if !$saved || $saved->{error};
				$done->({
					name        => $saved->{name},
					playlist_id => $saved->{id},
					date        => $args->{date},
					model       => $args->{model},
					found       => $found,
					total       => scalar @$results,
					tracks      => scalar @$urls,
					items       => $results,
				});
			});
		});
	};

	$progress->({ stage => 'reading' });
	$adapter->suggest($request, sub {
		my ($answer) = @_;
		# Privremena greska ili (retko) prazna lista: jos jedan pokusaj.
		my $empty = !$answer->{error} && !@{ $answer->{list}{items} || [] };
		return $on_list->($answer) unless $answer->{error} && $answer->{retryable} || $empty;
		$log->('UnifiedMusic: uvoz liste, ponovni pokusaj: ' . ($empty ? 'prazna lista; odgovor: ' . ($answer->{raw} // '') : $answer->{error}));
		$adapter->suggest($request, $on_list);
	});
}

1;
