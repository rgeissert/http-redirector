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
use Storable qw(retrieve);

use lib '.';
use Mirror::DB;
use Mirror::Trace;
use Mirror::RateLimiter;

sub head_url($$);
sub test_arch($$$);
sub test_source($$);
sub test_areas($$);
sub create_agent();
sub check_mirror($);
sub log_message($$$);
sub mirror_is_good($$);
sub archs_by_mirror($$);
sub parse_disable_file($);
sub fatal_connection_error($);

my $db_store = 'db';
my $db_output = $db_store;
my $store_traces = 0;
my $check_archs = '';
my $check_trace_archs = 1;
my $check_areas = '';
my $check_everything = 0;
my $incoming_db = '';
my $disable_sites = 'sites.disabled';
my $threads = 4;
my $verbose = 0;
my @ids;

GetOptions('check-architectures!' => \$check_archs,
	    'check-areas!' => \$check_areas,
	    'check-trace-architectures!' => \$check_trace_archs,
	    'check-everything' => \$check_everything,
	    'j|threads=i' => \$threads,
	    'db-store=s' => \$db_store,
	    'db-output=s' => \$db_output,
	    'id|mirror-id=s' => \@ids,
	    'incoming-db=s' => \$incoming_db,
	    'store-traces!' => \$store_traces,
	    'disable-sites=s' => \$disable_sites,
	    'verbose!' => \$verbose) or exit 1;

# Avoid picking up db.in when working on db.wip, for example
$incoming_db ||= $db_store.'.in';

if ($check_everything) {
    $check_archs = 1 unless ($check_archs ne '');
    $check_areas = 1 unless ($check_areas ne '');
    $check_trace_archs = 1 unless ($check_trace_archs ne '');
}

$| = 1;

our %traces :shared;
our $ua;
my $q = Thread::Queue->new();
our $db :shared = undef;
our %sites_to_disable :shared;

if (-f $disable_sites) {
    eval {
    %sites_to_disable = %{shared_clone(parse_disable_file($disable_sites))};
    };
    # If there was an exception take it as if we hadn't been requested to
    # process the file
    if ($@) {
	warn $@;
	$disable_sites = '';
    }
}

if ($incoming_db) {
    # The db might be gone or not exist at all
    eval { $db = shared_clone(retrieve($incoming_db)); };
    if ($@) {
	$db = undef;
	$incoming_db = '';
    }
}
$db = shared_clone(retrieve($db_store))
    unless (defined($db));

print "{db:",($incoming_db||$db_store),"}\n";

unless (scalar(@ids)) {
    @ids = keys %{$db->{'all'}};
} elsif ($incoming_db) {
    die("error: passed --id but there's an incoming db: $incoming_db\n");
}

$q->enqueue(@ids);

while ($threads--) {
    threads->create(
	    sub {
		use LWP::UserAgent;
		use LWP::ConnCache;

		$ua = create_agent();

		while (defined(my $id = $q->dequeue_nb())) {
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

    next if (scalar(@stamps) <= 2);

    my %master_stamps;
    my $global_master_stamp;

    for my $stamp (@stamps) {
	my $is_type_ref = has_type_reference($type, @{$traces{$type}{$stamp}});

	if (scalar(@{$traces{$type}{$stamp}}) <= 2 && !$is_type_ref) {
	    while (defined(my $id = pop @{$traces{$type}{$stamp}})) {
		$db->{'all'}{$id}{$type.'-disabled'} = undef;
		log_message($id, $type, "old or not popular master stamp '$stamp'");
	    }
	    next;
	}

	for my $continent (keys %{$db->{$type}{'continent'}}) {
	    my @per_continent;
	    my $good_mirrors = 0;
	    my %archs_required = map { $_ => 1 } qw(amd64 i386);

	    for my $id (@{$traces{$type}{$stamp}}) {
		next unless (exists($db->{$type}{'continent'}{$continent}{$id}));

		my $mirror = $db->{'all'}{$id};

		$good_mirrors++ if (mirror_is_good($mirror, $type));

		for my $arch (keys %archs_required) {
		    delete $archs_required{$arch}
			if (exists($db->{$type}{'arch'}{$arch}{$id}) && !exists($mirror->{$type.'-'.$arch.'-disabled'}));
		}

		push @per_continent, $id;
	    }

	    # Criteria: at least one mirror
	    # Criteria: at least one that is "good"
	    next unless (scalar(@per_continent) && $good_mirrors);
	    # Criteria: at least %archs_required can be served
	    next if (scalar(keys %archs_required));

	    if (!exists($master_stamps{$continent})) {
		# Do not let subsets become too old
		if (defined($global_master_stamp) &&
		    (($global_master_stamp - $stamp) > 12*3600 ||
		     $type eq 'security' || $is_type_ref)) {
		    print "Overriding the master stamp of $type/$continent (from $stamp to $global_master_stamp)\n";
		    $master_stamps{$continent} = $global_master_stamp;
		} elsif (!defined($global_master_stamp)) {
		    $global_master_stamp = $stamp;
		}
	    }

	    if (exists($master_stamps{$continent})) {
		# if a master stamp has been recorded already it means
		# there are more up to date mirrors
		while (defined(my $id = pop @per_continent)) {
		    $db->{'all'}{$id}{$type.'-disabled'} = undef;
		    log_message($id, $type, "old master trace re $continent");
		}
	    } else {
		$master_stamps{$continent} = $stamp;
		print "Master stamp for $continent/$type: $stamp\n";
	    }
	}
    }

    my @continents_by_stamp = sort {$master_stamps{$a} <=> $master_stamps{$b}}
				keys %master_stamps;

    if (scalar(@continents_by_stamp)) {
	my $recent_stamp = $master_stamps{$continents_by_stamp[-1]};

	while (my $continent = pop @continents_by_stamp) {
	    my $diff = ($recent_stamp - $master_stamps{$continent})/3600;

	    if ($diff == 0) {
		print "Subset $continent/$type is up to date\n";
	    } else {
		print "Subset $continent/$type is $diff hour(s) behind\n";
	    }
	}
    }
}

Mirror::DB::set($db_output);
Mirror::DB::store($db);

# If we used an 'incoming' db, delete it after storing it as the normal
# db. If any other process picked the incoming db too, well, they will
# be using the same data we used, so it's okay.
# This assumes that any other process will have been started after us,
# or finished before use otherwise
if ($incoming_db) {
    unlink($incoming_db);
}

if ($store_traces) {
    Mirror::DB::set('traces.db');
    Mirror::DB::store(\%traces);
}

sub mirror_is_good($$) {
    my ($mirror, $type) = @_;

    return 0 if (exists($mirror->{$type.'-disabled'}));

    return 1 if ($type eq 'old');

    return 0 if (exists($mirror->{$type.'-notinrelease'}));
    return 0 if (exists($mirror->{$type.'-noti18n'}));

    return 1;
}

sub has_type_reference {
    my $type = shift;

    for my $id (@_) {
	return 1 if (exists($db->{'all'}{$id}{$type.'-reference'}));
    }
    return 0;
}

sub head_url($$) {
    my ($url, $allow_html) = @_;

    my $response = $ua->head($url);
    my $content_type = $response->header('Content-Type') || '';

    return 0 if (!$response->is_success);
    return ($content_type ne 'text/html' || $allow_html);
}

sub test_arch($$$) {
    my ($base_url, $type, $arch) = @_;
    my $format;

    return test_source($base_url, $type) if ($arch eq 'source');

    if ($type eq 'archive') {
	$format = 'indices/files/arch-%s.files';
    } elsif ($type eq 'backports') {
	$format = 'dists/oldstable-backports/main/binary-%s/Release';
    } elsif ($type eq 'security') {
	$format = 'dists/stable/updates/main/binary-%s/Packages.gz';
    } else {
	# unknown/unsupported type, say we succeeded
	return 1;
    }

    # FIXME: we should really check more than just the standard
    $arch = 'i386' if ($arch eq 'any');

    my $url = $base_url;
    $url .= sprintf($format, $arch);

    return head_url($url, 0);
}

sub test_source($$) {
    my ($base_url, $type) = @_;
    my $format;

    if ($type eq 'archive') {
	$format = 'dists/sid/main/source/Release';
    } elsif ($type eq 'backports') {
	$format = 'dists/oldstable-backports/main/source/Release';
    } elsif ($type eq 'security') {
	$format = 'dists/stable/updates/main/source/Sources.gz';
    } else {
	# unknown/unsupported type, say we succeeded
	return 1;
    }

    my $url = $base_url . $format;

    return head_url($url, 0);
}

sub test_areas($$) {
    my ($base_url, $type) = @_;
    my $format;
    my @areas = qw(main contrib non-free);

    if ($type eq 'archive') {
	$format = 'dists/sid/%s/';
    } elsif ($type eq 'backports') {
	$format = 'dists/oldstable-backports/%s/';
    } elsif ($type eq 'security') {
	$format = 'dists/stable/updates/%s/';
    } else {
	# unknown/unsupported type, say we succeeded
	return 1;
    }

    for my $area (@areas) {
	my $url = $base_url;
	$url .= sprintf($format, $area);

	return 0  unless(head_url($url, 1));
    }
    return 1;
}

sub create_agent() {
    my $ua = LWP::UserAgent->new();

    $ua->timeout(10);
    $ua->agent("MirrorChecker/0.1 ");
    $ua->conn_cache(LWP::ConnCache->new());
    $ua->max_redirect(0);
    $ua->max_size(1024);

    return $ua;
}

sub archs_by_mirror($$) {
    my ($id, $type) = @_;

    # Find the list of architectures supposedly included by the
    # given mirror. Traverse the inverted indexes to determine them
    my @all_archs = keys %{$db->{$type}{'arch'}};
    my @archs;
    for my $arch (@all_archs) {
	next unless (exists($db->{$type}{'arch'}{$arch}{$id}));
	push @archs, $arch;
    }
    return @archs;
}

sub check_mirror($) {
    my $id = shift;
    my $mirror = $db->{'all'}{$id};
    my @mirror_types;

    my $fatal_error = 0;

    for my $k (keys %$mirror) {
	next unless ($k =~ m/^(.+)-http$/);
	push @mirror_types, $1;
    }

    for my $type (@mirror_types) {
	next if (exists($mirror->{$type.'-tracearchcheck-disabled'}) && !$check_trace_archs);
	next if (exists($mirror->{$type.'-archcheck-disabled'}) && !$check_archs);
	next if (exists($mirror->{$type.'-areascheck-disabled'}) && !$check_areas);
	next if (exists($mirror->{$type.'-file-disabled'}) && !$disable_sites);

	if ($disable_sites) {
	    my $todisable = $sites_to_disable{$mirror->{'site'}};
	    my $disabled = exists($mirror->{$type.'-file-disabled'});

	    if (exists($todisable->{$type}) || exists($todisable->{'any'})) {
		log_message($id, $type, "blacklisted")
		    unless ($disabled);
		$mirror->{$type.'-disabled'} = undef;
		$mirror->{$type.'-file-disabled'} = undef;
		next;
	    } else {
		log_message($id, $type, "no longer blacklisted")
		    if ($disabled);
		delete $mirror->{$type.'-file-disabled'};
	    }
	}

	$mirror->{$type.'-rtltr'} = undef
	    unless (exists($mirror->{$type.'-rtltr'}));
	my $rtltr = Mirror::RateLimiter->load(\$mirror->{$type.'-rtltr'});

	next if ($rtltr->should_skip);

	my $base_url = 'http://'.$mirror->{'site'}.$mirror->{$type.'-http'};
	my $master_trace = Mirror::Trace->new($ua, $base_url);
	my $disable = 0;

	if (!$master_trace->fetch($db->{$type}{'master'})) {
	    my $error = $master_trace->fetch_error || 'parse error';
	    $mirror->{$type.'-disabled'} = undef;
	    log_message($id, $type, "bad master trace ($error)");
	    $rtltr->record_failure;
	    if (fatal_connection_error($error)) {
		$fatal_error = 1;
		last;
	    }
	    next unless ($check_archs || $check_areas);
	    $disable = 1;
	}

	if (!$disable) {
	    my $site_trace = Mirror::Trace->new($ua, $base_url);
	    my $disable_reason;
	    my $ignore_master = 0;

	    delete $mirror->{$type.'-notinrelease'};
	    delete $mirror->{$type.'-noti18n'};

	    if (!$site_trace->fetch($mirror->{'trace-file'} || $mirror->{'site'})) {
		my $error = $site_trace->fetch_error || 'parse error';
		$ignore_master = 1;
		$disable_reason = "bad site trace ($error)";
		$rtltr->record_failure;
		if (fatal_connection_error($error)) {
		    $fatal_error = 1;
		    last;
		}
	    } elsif ($site_trace->date < $master_trace->date) {
		$ignore_master = 1;
		$disable_reason = 'old site trace';
	    } elsif (!$site_trace->uses_ftpsync) {
		log_message($id, $type, "doesn't use ftpsync");
	    } elsif (!$site_trace->good_ftpsync) {
		$disable_reason = 'old ftpsync';
		$rtltr->record_failure;
	    }

	    unless ($disable_reason) {
		if (!$site_trace->features('inrelease')) {
		    log_message($id, $type, "doesn't handle InRelease files correctly")
			if ($verbose);
		    $mirror->{$type.'-notinrelease'} = undef;
		}
		if (!$site_trace->features('i18n')) {
		    log_message($id, $type, "doesn't handle i18n files correctly")
			if ($verbose);
		    $mirror->{$type.'-noti18n'} = undef;
		}
		if ($site_trace->features('architectures')) {
		    if ($check_trace_archs) {
			delete $mirror->{$type.'-tracearchcheck-disabled'};

			my @archs = archs_by_mirror($id, $type);
			for my $arch (@archs) {
			    if ($arch eq 'any' && $site_trace->arch('GUESSED')) {
				# not much can be done about it
				next;
			    }
			    if (!$site_trace->arch($arch)) {
				# Whenever disabling an arch because it
				# isn't listed in the site's trace file,
				# always require this check to be performed
				# before re-enabling the arch
				$mirror->{$type.'-'.$arch.'-trace-disabled'} = undef;
				$mirror->{$type.'-'.$arch.'-disabled'} = undef;
				log_message($id, $type, "missing $arch (det. from trace file)");
			    } elsif (exists($mirror->{$type.'-'.$arch.'-trace-disabled'})) {
				log_message($id, $type, "re-enabling $arch (det. from trace file)");
				delete $mirror->{$type.'-'.$arch.'-disabled'};
				delete $mirror->{$type.'-'.$arch.'-trace-disabled'};
			    }
			}

			if (!exists($db->{$type}{'arch'}{'source'}) && !$site_trace->arch('source')) {
			    $rtltr->record_failure;
			    $mirror->{$type.'-tracearchcheck-disabled'} = undef;
			    $disable_reason = "no sources (det. from trace file)";
			}
		    }
		} else {
		    log_message($id, $type, "doesn't list architectures");
		}
	    }

	    if (!$ignore_master) {
		lock(%traces);
		$traces{$type} = shared_clone({})
		    unless (exists($traces{$type}));
		$traces{$type}{$master_trace->date} = shared_clone([])
		    unless (exists($traces{$type}{$master_trace->date}));
		push @{$traces{$type}{$master_trace->date}}, shared_clone($id);
	    }

	    if ($disable_reason) {
		$mirror->{$type.'-disabled'} = undef;
		log_message($id, $type, $disable_reason);
		next unless ($check_archs || $check_areas);
		$disable = 1;
	    }

	    if (exists($mirror->{$type.'-disabled'}) && !$disable) {
		log_message($id, $type, "re-considering, good traces");
		delete $mirror->{$type.'-disabled'};
	    }
	}

	if ($check_areas) {
	    delete $mirror->{$type.'-disabled'} unless ($disable);
	    delete $mirror->{$type.'-areascheck-disabled'};
	    if (!test_areas($base_url, $type)) {
		$mirror->{$type.'-disabled'} = undef;
		$mirror->{$type.'-areascheck-disabled'} = undef;
		$rtltr->record_failure;
		log_message($id, $type, "missing areas");
		next unless ($check_archs);
		$disable = 1;
	    }
	}

	if ($check_archs) {
	    delete $mirror->{$type.'-disabled'} unless ($disable);
	    delete $mirror->{$type.'-archcheck-disabled'};

	    my @archs = archs_by_mirror($id, $type);
	    my $all_failed = 1;
	    for my $arch (@archs) {
		# Don't even check it if it was disabled because the
		# trace file says it is not included
		next if (exists($mirror->{$type.'-'.$arch.'-trace-disabled'}));

		if (!test_arch($base_url, $type, $arch)) {
		    $mirror->{$type.'-'.$arch.'-disabled'} = undef;
		    log_message($id, $type, "missing $arch");
		} else {
		    log_message($id, $type, "re-enabling $arch")
			if (exists($mirror->{$type.'-'.$arch.'-disabled'}));
		    delete $mirror->{$type.'-'.$arch.'-disabled'};
		    $all_failed = 0;
		}
	    }

	    if ($all_failed) {
		$mirror->{$type.'-disabled'} = undef;
		$mirror->{$type.'-archcheck-disabled'} = undef;
		$rtltr->record_failure;
		log_message($id, $type, "all archs failed");
		next;
	    }

	    if (!exists($db->{$type}{'arch'}{'source'}) && !test_source($base_url, $type)) {
		$mirror->{$type.'-disabled'} = undef;
		$mirror->{$type.'-archcheck-disabled'} = undef;
		$rtltr->record_failure;
		log_message($id, $type, "no sources");
		next;
	    }
	}
    }

    # The mirror couldn't be checked due to what's considered a "fatal error"
    # i.e. some kind of error from which it is unlikely to recover any time soon
    # As such, some checks might have been skipped. So mark it as
    # disabled by any check that would have otherwise been run.
    # It might be possible for the mirror to recover at a later time, however.
    if ($fatal_error) {
	for my $type (@mirror_types) {
	    log_message($id, $type, "disabling due to fatal error");
	    $mirror->{$type.'-disabled'} = undef;

	    $mirror->{$type.'-tracearchcheck-disabled'} = undef
		if ($check_trace_archs);
	    $mirror->{$type.'-archcheck-disabled'} = undef
		if ($check_archs);
	    $mirror->{$type.'-areascheck-disabled'} = undef
		if ($check_areas);
	    $mirror->{$type.'-file-disabled'} = undef
		if ($disable_sites);
	}
    }
}

sub log_message($$$) {
    my ($id, $type, $msg) = @_;

    print "[$id/$type] $msg\n";
}

sub parse_disable_file($) {
    my $disable_file = shift;
    my %disable_index;

    open(my $fh, '<', $disable_file) or
	die "warning: could not open '$disable_file' for reading\n";

    while (<$fh>) {
	next if (m/^\s*$/);
	next if (m/^\s*#/);
	chomp;

	my @parts = split(qr</>, $_, 3);
	if (scalar(@parts) == 3) {
	    warn "warning: malformed input (should be 'site[/type]')";
	    next;
	}

	unless (exists($disable_index{$parts[0]})) {
	    $disable_index{$parts[0]} = {};
	}
	if (defined($parts[1])) {
	    $disable_index{$parts[0]}{$parts[1]} = 1;
	} else {
	    $disable_index{$parts[0]}{'any'} = 1;
	}
    }
    close ($fh);
    return \%disable_index;
}

sub fatal_connection_error($) {
    my $error = shift;

    return 0 unless ($error =~ m/^500/);
    return ($error =~ m/Bad hostname/ || $error =~ m/Connection refused/
	    || $error =~ m/connect: timeout/);
}
