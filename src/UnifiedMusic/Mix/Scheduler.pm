package Plugins::UnifiedMusic::Mix::Scheduler;

# Noćni tajmer, nadoknada, jedan posao u isto vreme. Vreme i tajmer se ubacuju.

use strict;
use warnings;
use utf8;

use constant RETRY_SECONDS => 3600;
use constant MAX_RETRIES   => 6;
use constant BUSY_RECHECK_SECONDS => 60;

sub new {
	my ($class, %args) = @_;
	return bless { %args, attempts => 0, running => 0 }, $class;
}

sub _minutes {
	my ($hhmm) = @_;
	my ($hour, $minute) = split /:/, $hhmm;
	return $hour * 60 + $minute;
}

sub _set {
	my ($self, $seconds, $callback) = @_;
	$self->{cancel_timer}->($self->{handle}) if defined $self->{handle};
	$self->{handle} = $self->{set_timer}->($seconds, $callback);
}

sub _plan {
	my ($self) = @_;

	my $diff = _minutes($self->{config}->()->{runTime}) - _minutes($self->{now}->()->{hhmm});
	$diff += 1440 if $diff <= 0;
	$self->_set($diff * 60, sub { $self->_fire });
}

sub reschedule {
	my ($self) = @_;

	return if $self->{attempts};
	$self->_plan;
}

sub start {
	my ($self) = @_;

	my $now = $self->{now}->();
	my $due = _minutes($now->{hhmm}) >= _minutes($self->{config}->()->{runTime});
	my $done_today = ($self->{last_run}->() // '') eq $now->{date};

	return $self->_fire if $due && !$done_today;
	$self->_plan;
}

sub _fire {
	my ($self) = @_;

	my $date = $self->{now}->()->{date};
	return $self->_set(BUSY_RECHECK_SECONDS, sub { $self->_fire }) if $self->{running};
	return $self->_plan if ($self->{last_run}->() // '') eq $date;

	if (!$self->{has_player}->()) {
		$self->{attempts}++;
		if ($self->{attempts} <= MAX_RETRIES) {
			return $self->_set(RETRY_SECONDS, sub { $self->_fire });
		}
		$self->{attempts} = 0;
		$self->{set_last_run}->($date);
		return $self->_plan;
	}

	$self->{attempts} = 0;
	$self->_start_job(sub { $self->_plan });
}

sub _start_job {
	my ($self, $finished, $manual) = @_;

	$self->{running} = 1;
	my $date = $self->{now}->()->{date};
	my $finish = sub {
		my ($result) = @_;
		$self->{running} = 0;
		$self->{set_last_run}->($date) if !$manual || @{ $result->{ok} };
		$finished->($result);
	};

	eval { $self->{run_job}->($finish); 1 }
		or $finish->({ ok => [], failed => [{ name => 'job', error => $@ }] });
}

sub is_running {
	my ($self) = @_;
	return $self->{running} ? 1 : 0;
}

sub run_now {
	my ($self, $callback) = @_;

	return $callback->({ running => 1 }) if $self->{running};
	return $callback->({ no_player => 1 }) unless $self->{has_player}->();
	$self->_start_job($callback, 1);
}

1;
