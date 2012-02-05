#!/usr/bin/perl -w

####################
#    Copyright (C) 2012 by Raphael Geissert <geissert@debian.org>
#
#    This file is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This file is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this file  If not, see <http://www.gnu.org/licenses/>.
#
#    On Debian systems, the complete text of the GNU General
#    Public License 3 can be found in '/usr/share/common-licenses/GPL-3'.
####################

use strict;
use warnings;

use Getopt::Long;
use threads;
use threads::shared;
use Thread::Queue;
use Storable qw(retrieve store);

sub test_arch($$$);
sub create_agent();
sub check_mirror($);

my $db_store = 'db';
my $db_output = $db_store;
my $check_archs = 0;
my $threads = 4;
my @ids;

GetOptions('check-architectures!' => \$check_archs,
	    'j|threads=i' => \$threads,
	    'db-store=s' => \$db_store,
	    'db-output=s' => \$db_output,
	    'id|mirror-id=s' => \@ids);

our %traces :shared;
our $ua;
my $q = Thread::Queue->new();
our $db :shared = shared_clone(retrieve($db_store));

unless (scalar(@ids)) {
    @ids = keys %{$db->{'all'}};
}

$q->enqueue(@ids);

while ($threads--) {
    threads->create(
	    sub {
		use LWP::UserAgent;
		use LWP::ConnCache;

		$ua = create_agent();

		while (my $id = $q->dequeue_nb()) {
		    check_mirror($id);
		}
	    }
	);
}

for my $thr (threads->list()) {
    $thr->join();
}

for my $type (keys %traces) {
    my @stamps = sort { $b <=> $a } keys %{$traces{$type}};
    my $master_stamp = 0;

    for my $stamp (@stamps) {
	my $disable = 0;

	if ($master_stamp == 0) {
	    if (scalar(@{$traces{$type}{$stamp}}) > 2) {
		$master_stamp = $stamp;
		print "Master stamp for $type: $stamp\n";
	    } else {
		print "Found stamp '$stamp' for $type, but ignored it (only ".
		    join(', ', @{$traces{$type}{$stamp}})." have it)\n";
	    }
	}

	# TODO: determine better ways to decide whether a mirror should
	# be disabled
	$disable = 1
	    if (($master_stamp - $stamp) > 3600*12);

	if ($disable) {
	    while (my $id = pop @{$traces{$type}{$stamp}}) {
		$db->{'all'}{$id}{$type.'-disabled'} = undef;
		print "Disabling $id/$type: old master trace\n";
	    }
	}
    }
}

{
    # Storable doesn't clone the tied hash as needed
    # so we have do it the ugly way:
    my $VAR1;
    {
	use Data::Dumper;
	$Data::Dumper::Purity = 1;
	$Data::Dumper::Indent = 0;

	my $clone = Dumper($db);
	eval $clone;
    }

    store ($VAR1, $db_output.'.new')
	or die ("failed to store to $db_output.new: $!");
    rename ($db_output.'.new', $db_output)
	or die("failed to rename $db_output.new: $!");
}

sub test_arch($$$) {
    my ($base_url, $type, $arch) = @_;
    my $format;

    if ($type eq 'archive') {
	$format = 'indices/files/arch-%s.files';
    } elsif ($type eq 'cdimage') {
	$format = 'current/%s/';
    } elsif ($type eq 'backports') {
	$format = 'dists/stable-backports/main/binary-%s/Release';
    } elsif ($type eq 'security') {
	$format = 'dists/stable/updates/main/binary-%s/Release';
    } else {
	# unknown/unsupported type, say we succeeded
	return 1;
    }

    # FIXME: we should really check more than just the standard
    $arch = 'i386' if ($arch eq 'any');

    my $url = $base_url;
    $url .= sprintf($format, $arch);

    my $response = $ua->head($url);
    my $content_type = $response->header('Content-Type') || '';

    return 0 if (!$response->is_success);
    return ($content_type ne 'text/html' || $type eq 'cdimage');
}

sub create_agent() {
    my $ua = LWP::UserAgent->new();

    $ua->timeout(10);
    $ua->agent("MirrorChecker/0.1 ");
    $ua->conn_cache(LWP::ConnCache->new());
    $ua->max_redirect(1);
    $ua->max_size(1024);

    return $ua;
}

sub check_mirror($) {
    my $id = shift;
    my $mirror = $db->{'all'}{$id};
    my @mirror_types;

    for my $k (keys %$mirror) {
	next unless ($k =~ m/^(.+)-http$/);
	push @mirror_types, $1;
    }

    for my $type (@mirror_types) {
	my $base_url = 'http://'.$mirror->{'site'}.$mirror->{$type.'-http'};
	my $master_trace = Mirror::Trace->new($ua, $base_url);

	if (!$master_trace->fetch($db->{$type}{'master'})) {
	    $mirror->{$type.'-disabled'} = undef;
	    print "Disabling $id/$type: bad master trace\n";
	    next;
	}

	{
	    lock(%traces);
	    $traces{$type} = shared_clone({})
		unless (exists($traces{$type}));
	    $traces{$type}{$master_trace->date} = shared_clone([])
		unless (exists($traces{$type}{$master_trace->date}));
	    push @{$traces{$type}{$master_trace->date}}, shared_clone($id);
	}

	my $site_trace = Mirror::Trace->new($ua, $base_url);
	my $disable_reason;

	if (!$site_trace->fetch($mirror->{'site'})) {
	    $disable_reason = 'bad site trace';
	} elsif ($site_trace->date < $master_trace->date) {
	    $disable_reason = 'old site trace';
	} elsif (!$site_trace->good_ftpsync) {
	    $disable_reason = 'old ftpsync';
	}

	if ($disable_reason) {
	    $mirror->{$type.'-disabled'} = undef;
	    print "Disabling $id/$type: $disable_reason\n";
	    next;
	}

	if (exists($mirror->{$type.'-disabled'})) {
	    print "Re-enabling $id/$type\n";
	    delete $mirror->{$type.'-disabled'};
	}

	if ($check_archs) {
	    # Find the list of architectures supposedly included by the
	    # given mirror. There's no index for it, so the search is a bit
	    # more expensive
	    my @archs = keys %{$db->{$type}{'arch'}};
	    my $all_failed = 1;
	    for my $arch (@archs) {
		next unless (exists($db->{$type}{'arch'}{$arch}{$id}));
		if (!test_arch($base_url, $type, $arch)) {
		    $mirror->{$type.'-'.$arch.'-disabled'} = undef;
		    print "Disabling $id/$type/$arch\n";
		} else {
		    print "Re-enabling $id/$type/$arch\n"
			if (exists($mirror->{$type.'-'.$arch.'-disabled'}));
		    delete $mirror->{$type.'-'.$arch.'-disabled'};
		    $all_failed = 0;
		}
	    }

	    if ($all_failed) {
		$mirror->{$type.'-disabled'} = undef;
		print "Disabling $id/$type: all archs failed\n";
	    }
	}
    }
}

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
    my ($date, $software) = split /\n/,$trace,3;

    return 0
	unless ($date =~ m/^\w{3} \s+ \w{3} \s+ \d{1,2} \s+ (?:\d{2}:){2}\d{2} \s+ UTC \s+ \d{4}$/x);

    $self->{'software'} = $software;
    $self->{'date'} = str2time($date);
    return 1;
}

sub date {
    my $self = shift;
    return $self->{'date'};
}

sub good_ftpsync {
    my $self = shift;

    return 1
        unless ($self->{'software'} =~ m/^Used ftpsync version: ([0-9]+)$/);
    return 0
        if ($1 < $MIN_FTPSYNC_VERSION);
    return 1;
}

1;
