#!/usr/bin/perl -w

####################
#    Copyright (C) 2011 by Raphael Geissert <geissert@debian.org>
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
use File::stat qw(stat);
use Storable qw(store dclone);
use Socket;

# DNS lookups are slow
use threads;
use threads::shared;
use Thread::Semaphore;
use Thread::Queue;

my $current_list = 'Mirrors.masterlist';
my $db_store = 'db';
my @mirror_types = qw(www volatile archive old nonus
			backports security cdimage);
my %exclude_mirror_types = map { $_ => 1 } qw(nonus www volatile);

# Options:
my ($update_list, $threads, $leave_new) = (1, 4, 0);

sub parse_list($$);
sub process_entry($);
sub fancy_get_host($);

GetOptions('update-list!' => \$update_list,
	    'j|threads=i' => \$threads,
	    'leave-new' => \$leave_new);

if ($update_list) {
    # TODO: use LWP
    system('wget',
	    '-OMirrors.masterlist.new',
	    'http://anonscm.debian.org/viewvc/webwml/webwml/english/mirror/Mirrors.masterlist?view=co'
	) and die ("wget Mirrors.masterlist failed: $?");

    rename('Mirrors.masterlist.new', $current_list)
	or die ("mv Mirrors.masterlist{.new,} failed: $?");

=foo
    # Before enabling this code we need to find a place where we can
    # download the latest Mirrors list from, while preserving mtime
    if (-f $current_list) {
	my ($current, $new);
	$current = stat($current_list);
	$new = stat('Mirrors.masterlist');
	
	if ($current->mtime() >= $new->mtime()) {
	    exit 0;
	}
    }
=cut
}

my %all_sites;
my @data = parse_list($current_list, \%all_sites);

my %db :shared;
my %semaphore;
my $q = Thread::Queue->new(@data);
my $i :shared = 0;

foreach my $mirror_type (@mirror_types) {
    next if ($exclude_mirror_types{$mirror_type});

    $db{$mirror_type} = shared_clone({
	'country' => {}, 'ipv6' => {}, 'arch' => {},
	'all' => {}, 'AS' => {}, 'continent' => {},
	'master' => ''
    });
    $semaphore{$mirror_type} = Thread::Semaphore->new();
}
$db{'all'} = shared_clone({});
$semaphore{'main'} = Thread::Semaphore->new();

my ($g_city, $g_as);

while ($threads--) {
    threads->create(
	    sub {
		# Geo::IP (at least the XS version) is not thread-safe
		# it appears as if it tried to close the db handle as
		# many times as threads. Workaround it by importing it
		# on each individual thread.
		# (even in this case, *_by_name fail; don't know why)
		use Geo::IP;
		$g_city = Geo::IP->open('geoip/GeoLiteCity.dat', GEOIP_MMAP_CACHE);
		$g_as = Geo::IP->open('geoip/GeoIPASNum.dat', GEOIP_MMAP_CACHE);

		# we wait until all threads are done processing the queue
		# and since the queue is filled and no new items are added
		# later, it is safe to use dequeue_nb to check if it
		# should exit
		while (my $entry = $q->dequeue_nb()) {
		    process_entry($entry);
		}
	    }
	);
}

for my $thr (threads->list()) {
    $thr->join();
}

if (scalar(keys %{$db{'archive'}{'all'}}) < 10) {
    print STDERR "error: not even 10 mirrors found on the archive list, not saving\n";
} else {

    # Storable doesn't clone the tied hash as needed
    # so we have do it the ugly way:
    my $VAR1;
    {
	use Data::Dumper;
	$Data::Dumper::Purity = 1;
	$Data::Dumper::Indent = 0;
    
	my $clone = Dumper(\%db);
	eval $clone;
    }

    store ($VAR1, $db_store.'.new')
	or die ("failed to store to $db_store.new: $!");
    unless ($leave_new) {
	rename ($db_store.'.new', $db_store)
	    or die("failed to rename $db_store.new: $!");
    }
}

exit;

sub parse_list($$) {
    my ($file, $sites_ref) = @_;

    my @data;
    my $group;
    my $field;

    open(MLIST, '<', $file)
	or die ("could not open $file for reading: $!");

    local $_;
    while (<MLIST>) {
	chomp;

	if (m/^\s*$/) {
	    $group = undef;
	    next;
	}
	elsif (m/^(\S+):\s*(.*?)\s*$/) {
	    # skip commented-out lines:
	    next if (substr($1, 0, 2) eq 'X-');

	    unless (defined $group) {
		$group = {};
		push @data, $group;
	    }

	    $field = lc $1;
	    my $value = $2;

	    $group->{$field} = $value;
	    # We need this list before we process the sites themselves
	    # so we can't build it as we process them.
	    # Purists might prefer to add another iteration to build
	    # it, but I don't mind doing this only one extra thing here:
	    $sites_ref->{$value} = undef
		if ($field eq 'site');
	    next;
	}
	elsif (m/^\s+(.*?)\s*$/) {

	    if (!defined($group)) {
		warn ("syntax error: found lone field continuation");
		next;
	    }
	    my $value = $1;
	    $group->{$field} .= "\n" . $value;
	    next;
	}
	else {
	    warn ("syntax error: found lone data");
	    next;
	}
    }
    close(MLIST);

    return @data;
}

sub process_entry($) {
    my $entry = shift;

    $entry->{'type'} = lc $entry->{'type'} || 'unknown';

    return if ($entry->{'type'} =~ m/^(?:unknown|geodns)$/);
    if ($entry->{'type'} eq 'origin') {
	foreach my $type (@mirror_types) {
	    next unless (exists($entry->{$type.'-rsync'}));
	    next if ($exclude_mirror_types{$type});

	    $db{$type}{'master'} = $entry->{'site'};
	}
	return;
    }

    if (!defined($entry->{'site'})) {
	print STDERR "warning: mirror without site:\n";
	require Data::Dumper;
	print STDERR Data::Dumper::Dumper($entry);
	return;
    }

    if (defined ($entry->{'ipv6'}) && $entry->{'ipv6'} eq 'only') {
	print STDERR "warning: unsupported IPv6-only $entry->{'site'}\n";
	return;
    }

    if (defined ($entry->{'includes'})) {
	my @includes = split /\s+/ , $entry->{'includes'};
	my $missing = 0;
	foreach my $include (@includes) {
	    next if (exists ($all_sites{$include}));

	    print "info: $entry->{'site'} includes $include\n";
	    print "\tbut it doesn't have its own entry, not cloning\n";
	    $missing = 1;

=foo
	    # I don't know for sure if the included mirrors can be
	    # accessed with $include as Host (instead of $entry->{'site'}
	    my %new_site;
	    while (my ($k, $v) = each %$entry) {
		next if ($k eq 'includes');
		$v = $include if ($k eq 'site');
		$new_site{$k} = $v;
	    }
	    $q->enqueue(shared_clone(\%new_site));
=cut
	}
	if (!$missing) {
	    print "info: $entry->{'site'} has Includes, all with their own entry, skipping\n";
	    return;
	}
    }

    my ($r, $as) = (undef, '');

    my @ips = fancy_get_host($entry->{'site'});

    if (!@ips || scalar(@ips) == 0) {
	print STDERR "warning: host lookup for $entry->{'site'} failed\n";
	return;
    }

    # Consider: lookup all possible IPs and try to match them to a unique host
    # However: we can't control what IP the client will connect to, and
    #	we can't guarantee that accessing the mirror with a different
    #	Host will actually work. Meh.
    for my $ip (@ips) {
	my $m_record = $g_city->record_by_addr($ip);
	# Split result, original format is: "AS123 Foo Bar corp"
	my ($m_as) = split /\s+/, ($g_as->org_by_addr($ip) || '');

	if (!defined($r)) {
	    $r = $m_record;
	} elsif ($r->city ne $m_record->city) {
	    print STDERR "warning: ".$entry->{'site'}." resolves to IPs in different".
			" cities (".$r->city." != ".$m_record->city.")\n";
	}
	if (!$as) {
	    $as = $m_as;
	} elsif ($as ne $m_as) {
	    print STDERR "warning: ".$entry->{'site'}." resolves to multiple different".
			" AS' ($as != $m_as)\n";
	}
    }

    if (!defined($r) || !$as) {
	print STDERR "warning: GeoIP/AS db lookup failed for $entry->{'site'}\n";
	return;
    }
    my $country = $r->country_code || 'A1';
    my ($listed_country) = split /\s+/, $entry->{'country'};
    my $continent = $r->continent_code || 'XX';
    my ($lat, $lon) = ($r->latitude, $r->longitude);

    # A1: Anonymous proxies
    # A2: Satellite providers
    # EU: Europe
    # AP: Asia/Pacific region
    if ($country =~ m/^(?:A1|A2|EU|AP)$/) {
	print STDERR "warning: non-definitive country ($country) entry in GeoIP db for $entry->{'site'}\n";
	$country = $listed_country;
	print STDERR "\tusing listed country ($listed_country), will need fix in redir.pl\n";
    } elsif ($listed_country ne $country) {
	print STDERR "warning: listed country for $entry->{'site'} doesn't match GeoIP db\n";
	print STDERR "\t$listed_country (listed) vs $country (db), ";
	print STDERR "using geoip db's entry\n";
    }

    # Generate a unique id for this site
    my $id;
    {
	lock($i);
	$id = $i++;
    }
    # When used as hash key, it is converted to a string.
    # Better store it as a string everywhere:
    $id = sprintf('%x', $id);

    $entry->{'lat'} = $lat;
    $entry->{'lon'} = $lon;

    if (defined($entry->{'bandwidth'})) {
	my $bw = 0;
	if ($entry->{'bandwidth'} =~ m/([\d.]+)\s*([tgm])/i) {
	    my ($quantity, $unit) = ($1, $2);
	    $unit = lc $unit;
	    while ($unit ne 'm') {
		if ($unit eq 't') {
		    $quantity *= 1000;
		    $unit = 'g';
		}
		if ($unit eq 'g') {
		    $quantity *= 1000;
		    $unit = 'm';
		}
	    }
	    $bw = $quantity;
	} else {
	    print STDERR "warning: unknown bandwidth format ($entry->{'bandwidth'}) for $entry->{'site'}\n";
	}
	$entry->{'bandwidth'} = $bw;
    }

    foreach my $type (@mirror_types) {
	delete $entry->{$type.'-ftp'};
	delete $entry->{$type.'-rsync'};
	delete $entry->{$type.'-nfs'};
	delete $entry->{$type.'-upstream'};
	delete $entry->{$type.'-method'};

	if ($exclude_mirror_types{$type}) {
	    delete $entry->{$type.'-http'};
	    delete $entry->{$type.'-architecture'};
	    next;
	}

	next unless (defined($entry->{$type.'-http'}));

	if (!defined($entry->{$type.'-architecture'}) && $type eq 'archive') {
	    print STDERR "warning: no $type-architecture list for $entry->{'site'}\n";
	    next;
	}

	if (!defined($entry->{$type.'-architecture'})) {
	    $entry->{$type.'-architecture'} = 'ANY';
	}

	my %archs = map { lc $_ => 1 }
	    split(/\s+/, $entry->{$type.'-architecture'});

	# Now store the results
	$semaphore{'main'}->down();
	$db{'all'}{$id} = $entry;
	$semaphore{'main'}->up();

	$semaphore{$type}->down();
	# Create skeleton, if missing:
	$db{$type}{'AS'}{$as} = shared_clone([])
	    unless (exists ($db{$type}{'AS'}{$as}));
	$db{$type}{'country'}{$country} = shared_clone({})
	    unless (exists ($db{$type}{'country'}{$country}));
	$db{$type}{'continent'}{$continent} = shared_clone({})
	    unless (exists ($db{$type}{'continent'}{$continent}));

	$db{$type}{'all'}{$id} = undef;
	$db{$type}{'ipv6'}{$id} = undef
	    if (defined ($entry->{'ipv6'}) && $entry->{'ipv6'} eq 'yes');
	$db{$type}{'country'}{$country}{$id} = undef;
	$db{$type}{'continent'}{$continent}{$id} = undef;
	push @{$db{$type}{'AS'}{$as}}, $id;

	foreach my $arch (keys %archs) {
	    # more skeletons...
	    $db{$type}{'arch'}{$arch} = shared_clone({})
		unless (exists ($db{$type}{'arch'}{$arch}));

	    $db{$type}{'arch'}{$arch}{$id} = undef;
	}

	$semaphore{$type}->up();
	# end: now store the results

	# cleanup
	delete $entry->{$type.'-architecture'};
    }

    # remove unused fields
    delete $entry->{'sponsor'};
    delete $entry->{'country'};
    delete $entry->{'maintainer'};
    delete $entry->{'ipv6'};
    delete $entry->{'location'};
    delete $entry->{'alias'};
    delete $entry->{'aliases'};
    delete $entry->{'comment'};
    delete $entry->{'comments'};
    delete $entry->{'type'};
}

sub fancy_get_host($) {
    my $name = shift;

    my @addresses = gethostbyname($name)
	or return;
    return map { inet_ntoa($_) } @addresses[4..$#addresses];
}
