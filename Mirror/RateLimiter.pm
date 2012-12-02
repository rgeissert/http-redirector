package Mirror::RateLimiter;

use strict;
use warnings;

use Carp qw(croak);

sub load {
    my ($class, $storeref) = @_;
    my $self = {};
    bless($self, $class);

    $self->{'store'} = $storeref;
    if (defined($$storeref)) {
	my @i = split (/:/, $$storeref, 3);
	$self->{'attempts'} = shift @i;
	$self->{'wait_til'} = shift @i;
	$self->{'increment'} = shift @i;
	$self->_initialize_run;
    } else {
	$self->_initialize;
    }

    return $self;
}

sub _initialize {
    my $self = shift;
    $self->{'attempts'} = 0;
    $self->{'wait_til'} = 3;
    $self->{'increment'} = 2;
    $self->_initialize_run;
}

sub _initialize_run {
    my $self = shift;
    $self->{'skip_tested'} = 0;
    $self->{'result'} = '';
}

sub should_skip {
    my $self = shift;
    my $attempts = $self->{'attempts'};
    $self->{'attempts'}++;

    $self->{'skip_tested'} = 1;

    return 0 if ($attempts <= 1);
    return 0 if ($self->{'wait_til'} == $attempts);

    $self->{'result'} = 'skip';
    return 1;
}

sub record_failure {
    my $self = shift;

    croak "Forgot to check if you should_skip?"
	unless ($self->{'skip_tested'});
    croak "Forgot to actually skip? or save?"
	if ($self->{'result'} && $self->{'result'} ne 'fail');

    $self->{'result'} = 'fail';

    if ($self->{'attempts'} <= 1) {
	$self->{'wait_til'} = 3;
    } elsif ($self->{'wait_til'} < $self->{'attempts'}) {
	$self->{'wait_til'} = $self->{'attempts'} + $self->{'increment'};
	$self->{'increment'}++;
    }
}

sub attempts {
    my $self = shift;
    return $self->{'attempts'};
}

sub save {
    my $self = shift;

    # If the state was not modified, there's nothing to save
    return unless ($self->{'skip_tested'});

    # A non-declared result implies success
    if ($self->{'result'}) {
	$self->_initialize_run;
    } else {
	$self->_initialize;
    }
    $self->_save_state;
}

sub _save_state {
    my $self = shift;
    ${$self->{'store'}} = join(':',
	$self->{'attempts'},
	$self->{'wait_til'},
	$self->{'increment'},
	);
}

sub DESTROY {
    my $self = shift;
    $self->save;
}

1;
