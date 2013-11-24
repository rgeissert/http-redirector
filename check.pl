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
use Storable qw(retrieve);
use HTTP::Date qw();

use lib '.';
use Mirror::DB;
use Mirror::Trace;
use Mirror::RateLimiter;

use AnyEvent;
use AnyEvent::HTTP;

sub head_url($$$);
sub test_arch($$$$);
sub test_source($$$);
sub test_areas($$$);
sub test_stages($$$$);
sub check_mirror($$);
sub check_mirror_post_master($$$$$);
sub log_message($$$);
sub mirror_is_good($$);
sub archs_by_mirror($$);
sub parse_disable_file($);
sub fatal_connection_error($);
sub disable_mirrors($$@);
sub mark_bad_subset($$@);
sub mirror_provides_arch($$$);
sub mirror_types_to_check($);
sub store_not_too_much($$$);
sub disabled_this_session($$);

my $db_store = 'db';
my $db_output = $db_store;
my $store_traces = 0;
my $check_archs = '';
my $check_trace_archs = 1;
my $check_areas = '';
my $check_2stages = 1;
my $check_everything = 0;
my $incoming_db = '';
my $disable_sites = 'sites.disabled';
my $threads = -1;
my $verbose = 0;
my @ids;
my $ipv = 4;

GetOptions('check-architectures!' => \$check_archs,
	    'check-areas!' => \$check_areas,
	    'check-2stages!' => \$check_2stages,
	    'check-trace-architectures!' => \$check_trace_archs,
	    'check-everything' => \$check_everything,
	    'j|threads=i' => \$threads,
	    'db-store=s' => \$db_store,
	    'db-output=s' => \$db_output,
	    'id|mirror-id=s' => \@ids,
	    'incoming-db=s' => \$incoming_db,
	    'store-traces!' => \$store_traces,
	    'disable-sites=s' => \$disable_sites,
	    'ipv=i' => \$ipv,
	    'verbose!' => \$verbose) or exit 1;

# Avoid picking up db.in when working on db.wip, for example
$incoming_db ||= $db_store.'.in';

my %max_age = (
    'default' => 13*3600,
);

if ($check_everything) {
    $check_archs = 1 unless ($check_archs ne '');
    $check_areas = 1 unless ($check_areas ne '');
    $check_trace_archs = 1 unless ($check_trace_archs ne '');
    $check_2stages = 1 unless ($check_2stages ne '');
}

if ($ipv != 4 && $ipv != 6) {
    die("error: unknown IP family '$ipv'\n");
}

$| = 1;

our %traces;
our %just_disabled;

$AnyEvent::HTTP::MAX_RECURSE = 0;
$AnyEvent::HTTP::TIMEOUT = 10;
$AnyEvent::HTTP::MAX_PER_HOST = 1;
$AnyEvent::HTTP::USERAGENT = "MirrorChecker/0.2 ";

our $cv = AnyEvent::condvar;
our $db;
my $full_db = undef;
our %sites_to_disable;

if (-f $disable_sites) {
    eval {
    %sites_to_disable = %{parse_disable_file($disable_sites)};
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
    eval { $full_db = retrieve($incoming_db); };
    if ($@) {
	$full_db = undef;
	$incoming_db = '';
    }
}
$full_db = retrieve($db_store)
    unless (defined($full_db));

# Modify AE's PROTOCOL to force one or the other family
if ($ipv == 4) {
    $db = $full_db->{'ipv4'};
    $AnyEvent::PROTOCOL{ipv4} = 1;
    $AnyEvent::PROTOCOL{ipv6} = 0;
} elsif ($ipv == 6) {
    $db = $full_db->{'ipv6'};
    $AnyEvent::PROTOCOL{ipv4} = 0;
    $AnyEvent::PROTOCOL{ipv6} = 1;
}

print "{db:",($incoming_db||$db_store),"}\n";

our $process_stamps = 0;
unless (scalar(@ids)) {
    @ids = keys %{$db->{'all'}};
    $process_stamps = 1;
} elsif ($incoming_db) {
    die("error: passed --id but there's an incoming db: $incoming_db\n");
}

$cv->begin;
for my $id (@ids) {
    for my $type (mirror_types_to_check($id)) {
	check_mirror($id, $type);
    }
}
$cv->end;
$cv->recv;

for my $type (keys %traces) {
    my @stamps = sort { $b <=> $a } keys %{$traces{$type}};

    next unless ($process_stamps);

    my %master_stamps;
    my $global_master_stamp;

    for my $stamp (@stamps) {
	my $is_type_ref = has_type_reference($type, @{$traces{$type}{$stamp}});

	if (scalar(@{$traces{$type}{$stamp}}) <= 2 && !$is_type_ref) {
	    mark_bad_subset($type, "old or not popular master stamp '$stamp'", @{$traces{$type}{$stamp}});
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
			if (mirror_provides_arch($id, $type, $arch) || mirror_provides_arch($id, $type, 'any'));
		}

		push @per_continent, $id;
	    }

	    # Criteria: at least one mirror
	    # Criteria: at least one that is "good"
	    unless (scalar(@per_continent) && $good_mirrors) {
		mark_bad_subset($type, "Not enough good mirrors in its $continent subset", @per_continent);
		next;
	    }
	    # Criteria: at least %archs_required can be served
	    if ($type eq 'archive' && scalar(keys %archs_required)) {
		mark_bad_subset($type, "Required archs not present in its $continent subset", @per_continent);
		next;
	    }

	    if (!exists($master_stamps{$continent})) {
		# Do not let subsets become too old
		if (defined($global_master_stamp) &&
		    (($global_master_stamp - $stamp) > ($max_age{$type} || $max_age{'default'}) ||
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
		mark_bad_subset($type, "old master trace re $continent", @per_continent);
	    } else {
		if (exists($db->{$type}{'serial'})) {
		    $db->{$type}{'serial'}{$continent} = 0
			unless (exists($db->{$type}{'serial'}{$continent}));

		    print "Regression detected in $continent/$type\n"
			if ($db->{$type}{'serial'}{$continent} > $stamp);

		    $db->{$type}{'serial'}{$continent} = $stamp;
		}
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
Mirror::DB::store($full_db);

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

sub head_url($$$) {
    my ($url, $allow_html, $cb) = @_;

    $cv->begin;
    http_head $url, sub {
	my ($data, $headers) = @_;
	my $content_type = $headers->{'content-type'} || '';

	if ($headers->{'Status'} == 200 && (
	    $content_type ne 'text/html' || $allow_html)) {
	    &$cb(1);
	} else {
	    &$cb(0);
	}
	$cv->end;
    };
}

sub test_arch($$$$) {
    my ($base_url, $type, $arch, $cb) = @_;
    my $format;

    return test_source($base_url, $type, $cb) if ($arch eq 'source');

    if ($type eq 'archive') {
	$format = 'indices/files/arch-%s.files';
    } elsif ($type eq 'backports') {
	$format = 'dists/oldstable-backports/main/binary-%s/Release';
    } elsif ($type eq 'ports') {
	$format = 'dists/sid/main/binary-%s/Release';
    } elsif ($type eq 'security') {
	$format = 'dists/stable/updates/main/binary-%s/Packages.gz';
    } else {
	# unknown/unsupported type
	return;
    }

    # FIXME: we should really check more than just the standard
    $arch = 'i386' if ($arch eq 'any');

    my $url = $base_url;
    $url .= sprintf($format, $arch);

    head_url($url, 0, $cb);
}

sub test_source($$$) {
    my ($base_url, $type, $cb) = @_;
    my $format;

    if ($type eq 'archive') {
	$format = 'dists/sid/main/source/Release';
    } elsif ($type eq 'backports') {
	$format = 'dists/oldstable-backports/main/source/Release';
    } elsif ($type eq 'ports') {
	# no sources for ports
	return 1;
    } elsif ($type eq 'security') {
	$format = 'dists/stable/updates/main/source/Sources.gz';
    } else {
	# unknown/unsupported type
	return;
    }

    my $url = $base_url . $format;

    head_url($url, 0, $cb);
}

sub test_areas($$$) {
    my ($base_url, $type, $cb) = @_;
    my $format;
    my @areas = qw(main contrib non-free);

    if ($type eq 'archive') {
	$format = 'dists/sid/%s/';
    } elsif ($type eq 'backports') {
	$format = 'dists/oldstable-backports/%s/';
    } elsif ($type eq 'ports') {
	# only main for ports
	@areas = qw(main);
	$format = 'dists/sid/%s/';
    } elsif ($type eq 'security') {
	$format = 'dists/stable/updates/%s/';
    } else {
	# unknown/unsupported type
	return;
    }

    my $remaining_areas = scalar(@areas);
    for my $area (@areas) {
	my $url = $base_url;
	$url .= sprintf($format, $area);

	$cv->begin;
	head_url($url, 1, sub {
	    my $success = shift;

	    # Used to only call the cb once
	    if ($remaining_areas < 0) {
		$cv->end;
		return;
	    }
	    if (!$success) {
		&$cb(0);
		$remaining_areas = -1;
	    }
	    if (--$remaining_areas == 0) {
		&$cb(1);
	    }
	    $cv->end;
	});
    }
}

sub test_stages($$$$) {
    my ($base_url, $type, $master_trace, $cb) = @_;
    my $format;

    if ($type eq 'archive') {
	$format = 'dists/sid/Release';
    } elsif ($type eq 'backports') {
	$format = 'dists/oldstable-backports/Release';
    } elsif ($type eq 'ports') {
	$format = 'dists/sid/Release';
    } elsif ($type eq 'security') {
	$format = 'dists/stable/updates/Release';
    } else {
	# unknown/unsupported type, say we succeeded
	return 1;
    }

    my $url = $base_url . $format;
    my $trace_date = HTTP::Date::time2str($master_trace->date);

    $cv->begin;
    http_head $url,
	headers => ('if-unmodified-since' => $trace_date),
	sub {
	    my ($data, $headers) = @_;
	    # The last-modified date of $url should never be newer than the one
	    # in the trace file. Use if-unmodified-since so that a 412 code is
	    # returned on failure, and a 200 if successful (or if the server
	    # ignored the if-unmodified-since)
	    &$cb($headers->{'Status'} == 200 || $headers->{'Status'} == 500);
	    $cv->end;
	}
    ;
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

sub mirror_types_to_check($) {
    my $id = shift;
    my $mirror = $db->{'all'}{$id};
    my @mirror_types;
    my @types_to_check;

    for my $k (keys %$mirror) {
	next unless ($k =~ m/^(.+)-http$/);
	push @mirror_types, $1;
    }

    for my $type (@mirror_types) {
	next if (exists($mirror->{$type.'-tracearchcheck-disabled'}) && !$check_trace_archs);
	next if (exists($mirror->{$type.'-archcheck-disabled'}) && !$check_archs);
	next if (exists($mirror->{$type.'-areascheck-disabled'}) && !$check_areas);
	next if (exists($mirror->{$type.'-file-disabled'}) && !$disable_sites);
	# There's no way back for this one:
	next if (exists($mirror->{$type.'-stages-disabled'}));

	if ($disable_sites) {
	    my $todisable = $sites_to_disable{$mirror->{'site'}};
	    my $disabled = exists($mirror->{$type.'-file-disabled'});

	    if (exists($todisable->{$type}) || exists($todisable->{'any'})) {
		disable_mirrors($type, $disabled? '' : "blacklisted", $id);
		$mirror->{$type.'-file-disabled'} = undef;
		next;
	    } else {
		log_message($id, $type, "no longer blacklisted")
		    if ($disabled);
		delete $mirror->{$type.'-file-disabled'};
	    }
	}
	push @types_to_check, $type;
    }

    return @types_to_check;
}

sub check_mirror($$) {
    my $id = shift;
    my $type = shift;

    my $mtrace_content = '';
    my $mirror = $db->{'all'}{$id};
    my $master_trace;
    my $base_url = 'http://'.$mirror->{'site'}.$mirror->{$type.'-http'};

    $mirror->{$type.'-rtltr'} = undef
	unless (exists($mirror->{$type.'-rtltr'}));
    my $rtltr = Mirror::RateLimiter->load(\$mirror->{$type.'-rtltr'});

    return if ($rtltr->should_skip);
    $master_trace = Mirror::Trace->new($base_url);

    delete $mirror->{$type.'-badmaster'};
    delete $mirror->{$type.'-badsubset'};

    $cv->begin;
    http_get $master_trace->get_url($db->{$type}{'master'}),
	on_body => sub {store_not_too_much(shift, \$mtrace_content, shift->{'Status'})},
	sub {
	    my ($empty, $headers) = @_;
	    if ($headers->{'Status'} != 200 || !$master_trace->from_string($mtrace_content)) {
		my $error = ($headers->{'Status'} != 200)? $headers->{'Reason'} : 'parse error';
		disable_mirrors($type, "bad master trace ($error)", $id);
		$mirror->{$type.'-badmaster'} = undef;
		$rtltr->record_failure;
		#if (fatal_connection_error($error)) { abort remaining connections }
	    } else {
		my $site_trace = Mirror::Trace->new($base_url);
		my $strace_content = '';

		delete $mirror->{$type.'-badsite'};
		delete $mirror->{$type.'-oldftpsync'};
		delete $mirror->{$type.'-oldsite'};
		delete $mirror->{$type.'-notinrelease'};
		delete $mirror->{$type.'-noti18n'};

		$cv->begin;
		http_get $site_trace->get_url($mirror->{'trace-file'} || $mirror->{'site'}),
		    on_body => sub {store_not_too_much(shift, \$strace_content, shift->{'Status'})},
		    sub {
			my ($empty, $headers) = @_;
			if ($headers->{'Status'} != 200 || !$site_trace->from_string($strace_content)) {
			    my $error = ($headers->{'Status'} != 200)? $headers->{'Reason'} : 'parse error';
			    $mirror->{$type.'-badsite'} = undef;
			    disable_mirrors($type, "bad site trace ($error)", $id);
			    $rtltr->record_failure;
			    #if (fatal_connection_error($error)) { abort remaining connections }
			} else {
			    my %httpd_features = ('keep-alive' => 0, 'ranges' => 0);
			    if ($headers->{'connection'}) {
				$httpd_features{'keep-alive'} = ($headers->{'connection'} eq 'keep-alive');
			    } else {
				$httpd_features{'keep-alive'} = ($headers->{'HTTPVersion'} eq '1.1');
			    }
			    if ($headers->{'accept-ranges'}) {
				$httpd_features{'ranges'} = ($headers->{'accept-ranges'} eq 'bytes');
			    }

			    while (my ($k, $v) = each %httpd_features) {
				next if (exists($mirror->{$type.'-'.$k}) eq $v);

				if (exists($mirror->{$type.'-'.$k})) {
				    log_message($id, $type, "No more http/$k");
				    delete $mirror->{$type.'-'.$k};
				} else {
				    log_message($id, $type, "http/$k support seen");
				    $mirror->{$type.'-'.$k} = undef;
				}
			    }
			    check_mirror_post_master($id, $type, $rtltr, $master_trace, $site_trace);
			}
			$cv->end;
		    }
		;

		if ($check_2stages) {
		    test_stages($base_url, $type, $master_trace, sub {
			my $success = shift;
			if (!$success) {
			    disable_mirrors($type, "doesn't perform 2stages sync", $id);
			    $mirror->{$type.'-stages-disabled'} = undef;
			    $rtltr->record_failure;
			}
		    });
		}
	    }
	    $cv->end;
	}
    ;

    if ($check_areas) {
	delete $mirror->{$type.'-areascheck-disabled'};
	test_areas($base_url, $type, sub {
	    my $success = shift;
	    if (!$success) {
		disable_mirrors($type, "missing areas", $id);
		$mirror->{$type.'-areascheck-disabled'} = undef;
		$rtltr->record_failure;
	    }
	});
    }
}

sub check_mirror_post_master($$$$$) {
    my $id = shift;
    my $type = shift;
    my $rtltr = shift;
    my $mirror = $db->{'all'}{$id};
    my $base_url = 'http://'.$mirror->{'site'}.$mirror->{$type.'-http'};

    {
	my $master_trace = shift;
	my $site_trace = shift;
	my $disable_reason;
	my $ignore_master = 0;

	my $stored_site_date = $mirror->{$type.'-site'} || 0;
	my $stored_master_date = $mirror->{$type.'-master'} || 0;

	if ($site_trace->date < $master_trace->date) {
	    $ignore_master = 1;
	    $disable_reason = 'old site trace';
	    $mirror->{$type.'-oldsite'} = undef;
	} elsif (!$site_trace->uses_ftpsync) {
	    log_message($id, $type, "doesn't use ftpsync");
	} elsif (!$site_trace->good_ftpsync) {
	    $disable_reason = 'old ftpsync';
	    $mirror->{$type.'-oldftpsync'} = undef;
	    $rtltr->record_failure;
	}


	unless ($disable_reason) {
	    # Similar to the site->date < $master->date check above
	    # but stricter. Only accept a master bump if the site
	    # is also updated.
	    if ($master_trace->date > $stored_master_date &&
		$site_trace->date == $stored_site_date) {
		$ignore_master = 1;
		$disable_reason = 'new master but no new site';
		$mirror->{$type.'-oldsite'} = undef;
	    } else {
		# only update them when in an accepted state:
		$mirror->{$type.'-site'} = $site_trace->date;
		$mirror->{$type.'-master'} = $master_trace->date;
	    }

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
	    $traces{$type} = {}
		unless (exists($traces{$type}));
	    $traces{$type}{$master_trace->date} = []
		unless (exists($traces{$type}{$master_trace->date}));
	    push @{$traces{$type}{$master_trace->date}}, $id;
	}

	if ($disable_reason) {
	    disable_mirrors($type, $disable_reason, $id);
	} elsif (exists($mirror->{$type.'-disabled'}) && !disabled_this_session($type, $id)) {
	    log_message($id, $type, "re-considering, good traces");
	    delete $mirror->{$type.'-disabled'}
		if ($process_stamps);
	}
    }

    if ($check_archs) {
	my $sticky_archcheck_flag = 0;
	if (!exists($db->{$type}{'arch'}{'source'})) {
	    test_source($base_url, $type, sub {
		my $success = shift;
		if (!$success) {
		    disable_mirrors($type, "no sources", $id);
		    $mirror->{$type.'-archcheck-disabled'} = undef;
		    # Prevent any other callback (below) from dropping
		    # the flag
		    $sticky_archcheck_flag = 1;
		}
	    });
	}

	my @archs = archs_by_mirror($id, $type);
	# By default assume that all architectures are missing
	$mirror->{$type.'-archcheck-disabled'} = undef;
	for my $arch (@archs) {
	    # Don't even check it if it was disabled because the
	    # trace file says it is not included
	    next if (exists($mirror->{$type.'-'.$arch.'-trace-disabled'}));

	    test_arch($base_url, $type, $arch, sub {
		my $success = shift;
		if (!$success) {
		    $mirror->{$type.'-'.$arch.'-disabled'} = undef;
		    log_message($id, $type, "missing $arch");
		} else {
		    log_message($id, $type, "re-enabling $arch")
			if (exists($mirror->{$type.'-'.$arch.'-disabled'}));
		    delete $mirror->{$type.'-'.$arch.'-disabled'};
		    delete $mirror->{$type.'-archcheck-disabled'}
			unless ($sticky_archcheck_flag);
		}
	    });
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

    # 598: 'user aborted request via "on_header" or "on_body".'
    return ($error =~ m/^59/ && $error != 598);
}

sub disable_mirrors($$@) {
    my ($type, $reason) = (shift, shift);
    my @mirrors = @_;

    while (defined(my $id = pop @mirrors)) {
	$db->{'all'}{$id}{$type.'-disabled'} = undef;
	$just_disabled{"$id:$type"} = 1;
	log_message($id, $type, $reason) if ($reason);
    }
}

sub mark_bad_subset($$@) {
    my ($type, $reason) = (shift, shift);
    my @mirrors = @_;

    disable_mirrors($type, $reason, @mirrors);
    while (defined(my $id = pop @mirrors)) {
	$db->{'all'}{$id}{$type.'-badsubset'} = undef;
    }
}

sub mirror_provides_arch($$$) {
    my ($id, $type, $arch) = @_;

    my $mirror = $db->{'all'}{$id};

    if (exists($db->{$type}{'arch'}{$arch}) && exists($db->{$type}{'arch'}{$arch}{$id})
	&& !exists($mirror->{$type.'-'.$arch.'-disabled'})) {
	return 1;
    }
    return 0;
}

sub store_not_too_much($$$) {
    my ($data, $store, $status) = @_;

    if ($status != 200) {
	$$store = 0
	    if ($$store eq '');
	$$store += length($data);

	if ($$store > 1024*2) {
	    $$store = undef;
	    return 0;
	}
	return 1;
    }

    $$store .= $data;
    if (length($$store) > 1024) {
	$$store = undef;
	# abort the connection
	return 0;
    }
    return 1;
}

sub disabled_this_session($$) {
    my ($type, $id) = @_;
    return exists($just_disabled{"$id:$type"});
}
