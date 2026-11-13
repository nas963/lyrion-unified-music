package Plugins::UnifiedMusic::Import::Job;

# Uvoz liste iz teksta u dva koraka:
#   extract: model izvlaci stavke i predlaze naziv (korisnik ih zatim pregleda i menja naziv),
#   build:   pretraga nalazi pesme i pravi novu plejlistu ili dopunjuje postojecu.
# Model, pretraga i cuvanje plejliste se ubacuju.

use strict;
use warnings;
use utf8;

use Plugins::UnifiedMusic::Import::Prompt;

sub clean_name {
	my ($name) = @_;

	return '' unless defined $name;
	(my $clean = $name) =~ s/^\s+|\s+$//g;
	$clean =~ s/\s+/ /g;
	return $clean;
}

sub _name {
	my ($wanted, $suggested, $date) = @_;

	for my $name ($wanted, $suggested) {
		my $clean = clean_name($name);
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

# Prvi korak: { list => { name, items } } ili { error }.
sub extract {
	my ($args, $done) = @_;

	my ($adapter, $log) = @$args{qw(adapter log)};
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
		$list->{name} = _name(undef, $list->{name}, $args->{date});
		$done->({ list => $list });
	};

	$adapter->suggest($request, sub {
		my ($answer) = @_;
		# Privremena greska ili (retko) prazna lista: jos jedan pokusaj.
		my $empty = !$answer->{error} && !@{ $answer->{list}{items} || [] };
		return $on_list->($answer) unless $answer->{error} && $answer->{retryable} || $empty;
		$log->('UnifiedMusic: uvoz liste, ponovni pokusaj: ' . ($empty ? 'prazna lista; odgovor: ' . ($answer->{raw} // '') : $answer->{error}));
		$adapter->suggest($request, $on_list);
	});
}

# Drugi korak. $args->{target}: { name } za novu plejlistu ili { id, name } za postojecu.
sub build {
	my ($args, $done) = @_;

	my ($list, $resolver, $create, $append, $progress) = @$args{qw(list resolver create append progress)};
	$progress ||= sub {};
	my $target = $args->{target} || {};
	my $existing = defined $target->{id} && length $target->{id};

	$progress->({ stage => 'searching', done => 0, total => scalar @{ $list->{items} } });
	$resolver->resolve($list->{items}, sub {
		my ($results) = @_;
		my $urls = _unique_urls($results);
		my $found = grep { $_->{found} } @$results;
		return $done->({ error => 'None of the ' . scalar(@$results) . ' items were found.', name => $list->{name}, items => $results }) unless @$urls;

		my $name = $existing ? clean_name($target->{name}) : _name($target->{name}, $list->{name}, $args->{date});
		$progress->({ stage => 'saving', done => scalar @$results, total => scalar @$results });

		my $saved = sub {
			my ($saved) = @_;
			return $done->({ error => 'The playlist could not be saved.', name => $name, items => $results }) if !$saved || $saved->{error};
			my %result = (
				name        => $saved->{name} // $name,
				playlist_id => $saved->{id},
				date        => $args->{date},
				model       => $args->{model},
				found       => $found,
				total       => scalar @$results,
				tracks      => scalar @$urls,
				items       => $results,
			);
			$result{appended} = 1 if $existing;
			$done->(\%result);
		};

		return $append->($target->{id}, $urls, sub { $saved->($_[0] && !$_[0]{error} ? { id => $target->{id}, name => $name } : $_[0]) }) if $existing;
		$create->($name, $urls, $saved);
	});
}

1;
