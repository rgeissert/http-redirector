package Mirror::Trace;

use strict;
use warnings;
use Date::Parse;

use vars qw($MIN_FTPSYNC_VERSION);

sub new {
    my ($class, $ua, $base_url) = @_;
    my $self = {};
    bless($self, $class);

    $MIN_FTPSYNC_VERSION = 80387;

    $self->{'ua'} = $ua if (defined($ua));
    $self->{'base_url'} = $base_url if (defined($base_url));

    return $self;
}

sub fetch {
    my $self = shift;
    my $file = shift;

    my $req_url = $self->{'base_url'}.'project/trace/'.$file;

    my $response = $self->{'ua'}->get($req_url);
    return 0 unless ($response->is_success);

    my $trace = $response->decoded_content;
    return $self->_parse_trace($trace);
}

sub _parse_trace {
    my $self = shift;
    my $trace = shift;

    my ($date, $software) = split /\n/,$trace,3;

    return 0
	unless ($date =~ m/^\w{3} \s+ \w{3} \s+ \d{1,2} \s+ (?:\d{2}:){2}\d{2} \s+ UTC \s+ \d{4}$/x);

    $self->{'software'} = $software;
    $self->{'date'} = str2time($date) or return 0;
    return 1;
}

sub date {
    my $self = shift;
    return $self->{'date'};
}

sub uses_ftpsync {
    my $self = shift;

    return 1
        if ($self->{'software'} =~ m/^Used ftpsync(?: version|-pushrsync from): /);
    return 0;
}

sub good_ftpsync {
    my $self = shift;

    return 1
        if ($self->{'software'} =~ m/^Used ftpsync-pushrsync/);
    return 1
        unless ($self->{'software'} =~ m/^Used ftpsync version: ([0-9]+)$/);
    return 0
        if ($1 < $MIN_FTPSYNC_VERSION);
    return 1;
}

1;
