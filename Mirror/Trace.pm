package Mirror::Trace;

use strict;
use warnings;
use Date::Parse;

use vars qw($MIN_FTPSYNC_VERSION $MIN_DMSSYNC_VERSION);

sub new {
    my ($class, $ua, $base_url) = @_;
    my $self = {};
    bless($self, $class);

    $MIN_FTPSYNC_VERSION = 80387;
    $MIN_DMSSYNC_VERSION = '0.1';

    $self->{'ua'} = $ua if (defined($ua));
    $self->{'base_url'} = $base_url if (defined($base_url));

    return $self;
}

sub fetch {
    my $self = shift;
    my $file = shift;

    my $req_url = $self->{'base_url'}.'project/trace/'.$file;

    my $response = $self->{'ua'}->get($req_url);
    unless ($response->is_success) {
	$self->{'fetch_error'} = $response->status_line;
	return 0;
    }

    my $trace = $response->decoded_content;
    return $self->_parse_trace($trace);
}

sub fetch_error {
    my $self = shift;
    return $self->{'fetch_error'};
}

sub _parse_trace {
    my $self = shift;
    my $trace = shift;

    my ($date, $software, $archs, $revisions);

    my @trace_lines = split /\n/,$trace;
    ($date, $software) = (shift @trace_lines, shift @trace_lines);

    return 0 unless (defined($date));

    return 0
	unless ($date =~ m/^\w{3} \s+ \w{3} \s+ \d{1,2} \s+ (?:\d{2}:){2}\d{2} \s+ (?:UTC|GMT) \s+ \d{4}$/x);

    for my $line (@trace_lines) {
	return 0 unless ($line =~ m/^([\w -]+):(.*)\s*$/);
	my ($key, $val) = ($1, $2);

	$archs = $val if ($key eq 'Architectures');
	$revisions = $val if ($key eq 'Revision');
    }

    if (defined($revisions)) {
	my @revs = split /\s+/,$revisions;
	$revisions = { map { lc($_) => 1 } @revs };
    }

    $self->{'software'} = $software || '';
    $self->{'date'} = str2time($date) or return 0;
    $self->{'archs'} = $archs;
    $self->{'revision'} = $revisions;

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
    return 1
        if ($self->{'software'} =~ m/^DMS sync dms-/);
    return 0;
}

sub good_ftpsync {
    my $self = shift;

    return 1
        if ($self->{'software'} =~ m/^Used ftpsync-pushrsync/);

    if ($self->{'software'} =~ m/^Used ftpsync version: ([0-9]+)$/) {
	return ($1 >= $MIN_FTPSYNC_VERSION && $1 ne 80486);
    }
    if ($self->{'software'} =~ m/^DMS sync dms-([0-9.\w-]+)$/) {
	return ($1 ge $MIN_DMSSYNC_VERSION);
    }

    return 0;
}

sub features {
    my $self = shift;
    my $feature = shift;

    if ($feature eq 'architectures') {
	return defined($self->{'archs'});
    }

    return 1
	if ($feature eq 'revision' && defined($self->{'revision'}));
    if (defined($self->{'revision'})) {
	return (exists($self->{'revision'}{$feature}));
    }

    return 1
        if ($self->{'software'} =~ m/^Used ftpsync-pushrsync/);

    if ($self->{'software'} =~ m/^Used ftpsync version: ([0-9]+)$/) {
	my $version = $1;
	return 1 if ($feature eq 'inrelease' && $version >= 80387);
	return 1 if ($feature eq 'i18n' && $version >= 20120521);
	return 1 if ($feature eq 'auip' && $version >= 20130501);
    }
    if ($self->{'software'} =~ m/^DMS sync dms-([0-9.\w-]+)$/) {
	my $version = $1;
	return 1 if ($feature eq 'inrelease' && $version ge '0.1');
	return 1 if ($feature eq 'i18n' && $version ge '0.2');
    }

    return 0;
}

sub arch {
    my $self = shift;
    my $arch = shift;

    return ($self->{'archs'} =~ m/\b$arch\b/ || $self->{'archs'} =~ m/\bFULL\b/);
}

1;
