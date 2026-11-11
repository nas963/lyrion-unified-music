use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Mix::Scheduler;

sub setup {
	my (%o) = @_;
	my %s = (
		now => { date => $o{date} // '2026-11-11', hhmm => $o{hhmm} // '03:59' },
		last => $o{last} // '2026-11-10', runs => 0, timers => [], cancelled => 0,
		player => $o{player} // 1, runTime => '04:00', hold => $o{hold},
	);
	$s{obj} = Plugins::UnifiedMusic::Mix::Scheduler->new(
		now => sub { $s{now} },
		set_timer => sub { push @{ $s{timers} }, { seconds => $_[0], cb => $_[1] }; return scalar @{ $s{timers} } },
		cancel_timer => sub { $s{cancelled}++ },
		run_job => sub { $s{runs}++; my $cb = shift; if ($s{hold}) { $s{pending} = $cb } else { $cb->({ ok => [], failed => [] }) } },
		has_player => sub { $s{player} },
		last_run => sub { $s{last} },
		set_last_run => sub { $s{last} = $_[0] },
		config => sub { { runTime => $s{runTime} } },
	);
	return \%s;
}

sub fire { my ($s) = @_; my $t = pop @{ $s->{timers} }; $t->{cb}->() }

{
	my $s = setup(hhmm => '03:59');
	$s->{obj}->start;
	is $s->{runs}, 0, 'pre vremena se ne pokrece';
	is $s->{timers}[-1]{seconds}, 60, 'planirano za minut';
	$s->{now}{hhmm} = '04:00';
	fire($s);
	is $s->{runs}, 1, 'pokrece se u zadato vreme';
	is $s->{last}, '2026-11-11', 'zapisan dan';
	is $s->{timers}[-1]{seconds}, 86400, 'sledeci dan';
}

{
	my $s = setup(hhmm => '09:00', last => '2026-11-10');
	$s->{obj}->start;
	is $s->{runs}, 1, 'nadoknada pri startu';
	my $d = setup(hhmm => '09:00', last => '2026-11-11');
	$d->{obj}->start;
	is $d->{runs}, 0, 'bez nadoknade ako je danas uradjeno';
	is $d->{timers}[-1]{seconds}, 19 * 3600, 'planirano za sutra';
}

{
	my $s = setup(hhmm => '09:00', player => 0);
	$s->{obj}->start;
	is $s->{runs}, 0, 'bez plejera nema posla';
	for my $try (1 .. 6) {
		is $s->{timers}[-1]{seconds}, 3600, "pokusaj $try posle sata";
		fire($s);
	}
	is $s->{runs}, 0, 'i dalje bez plejera';
	is $s->{last}, '2026-11-11', 'odustaje do sutra';
	isnt $s->{timers}[-1]{seconds}, 3600, 'nema novih ponavljanja';
}

{
	my $s = setup(hhmm => '09:00', last => '2026-11-11', hold => 1);
	$s->{obj}->start;
	my @out;
	$s->{obj}->run_now(sub { push @out, $_[0] });
	is $s->{runs}, 1, 'run_now pokrece';
	$s->{obj}->run_now(sub { push @out, $_[0] });
	is $s->{runs}, 1, 'drugi se ne pokrece';
	is_deeply $out[0], { running => 1 }, 'javlja da traje';
	$s->{pending}->({ ok => ['J'], failed => [] });
	is_deeply $out[1], { ok => ['J'], failed => [] }, 'ishod';
}

{
	my $s = setup(hhmm => '09:00', last => '2026-11-11', hold => 1);
	$s->{obj}->start;
	ok !$s->{obj}->is_running, 'ne radi pre pokretanja';
	$s->{obj}->run_now(sub {});
	ok $s->{obj}->is_running, 'radi dok traje';
	$s->{pending}->({ ok => [], failed => [] });
	ok !$s->{obj}->is_running, 'ne radi posle zavrsetka';
}

{
	my $s = setup(hhmm => '04:00', last => '2026-11-10', hold => 1);
	$s->{obj}->start;
	is $s->{runs}, 1, 'zakazani posao traje';
	my @out;
	$s->{obj}->run_now(sub { push @out, $_[0] });
	is $s->{runs}, 1, 'pokreni sada ne pravi drugi';
	is_deeply $out[0], { running => 1 }, 'javlja da traje';
}

{
	my $s = setup(hhmm => '09:00', last => '2026-11-11', player => 0);
	$s->{obj}->start;
	my @out;
	$s->{obj}->run_now(sub { push @out, $_[0] });
	is $s->{runs}, 0, 'run_now bez plejera ne pokrece';
	is_deeply $out[0], { no_player => 1 }, 'run_now javlja da nema plejera';
}

{
	my $s = setup(hhmm => '09:00', last => '2026-11-11');
	$s->{obj}->{run_job} = sub { die "kvar\n" };
	$s->{obj}->start;
	my @out;
	$s->{obj}->run_now(sub { push @out, $_[0] });
	ok !$s->{obj}->is_running, 'izuzetak oslobadja posao';
	is $out[0]{failed}[0]{error}, "kvar\n", 'izuzetak je u ishodu';
}

{
	my $s = setup(hhmm => '01:00', last => '2026-11-10', hold => 1);
	$s->{obj}->start;
	$s->{obj}->run_now(sub {});
	$s->{pending}->({ ok => [], failed => [{ name => 'J', error => 'x' }] });
	is $s->{last}, '2026-11-10', 'neuspeo rucni posao ne oznacava dan';
	$s->{obj}->run_now(sub {});
	$s->{pending}->({ ok => ['J'], failed => [] });
	is $s->{last}, '2026-11-11', 'uspeo rucni posao oznacava dan';
}

{
	my $s = setup(hhmm => '09:00', last => '2026-11-10', hold => 1);
	$s->{obj}->start;
	is $s->{runs}, 1, 'posao traje';
	$s->{now} = { date => '2026-11-12', hhmm => '00:10' };
	$s->{obj}->_fire;
	is $s->{timers}[-1]{seconds}, 60, 'dok posao traje, ponovna provera uskoro';
}

{
	my $s = setup(hhmm => '03:00', last => '2026-11-11');
	$s->{obj}->start;
	$s->{runTime} = '03:30';
	$s->{obj}->_plan;
	is $s->{cancelled}, 1, 'novi tajmer otkazuje stari';
}

{
	my $s = setup(hhmm => '09:00', player => 0);
	$s->{obj}->start;
	my $before = $s->{timers}[-1]{seconds};
	$s->{obj}->reschedule;
	is $s->{timers}[-1]{seconds}, $before, 'cuvanje ne prekida ponovne pokusaje';
}

{
	my $s = setup(hhmm => '03:00', last => '2026-11-11');
	$s->{obj}->start;
	$s->{runTime} = '03:30';
	$s->{obj}->reschedule;
	is $s->{cancelled}, 1, 'stari tajmer otkazan';
	is $s->{timers}[-1]{seconds}, 1800, 'novo vreme vazi';
}

done_testing;
