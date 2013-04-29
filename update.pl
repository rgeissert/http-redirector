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
use Socket;

use Mirror::AS;
use Mirror::DB;

# DNS lookups are slow
use threads;
use threads::shared;
use Thread::Semaphore;
use Thread::Queue;

my $current_list = 'Mirrors.masterlist';
my $db_store = 'db';
my $db_output = $db_store;
my @mirror_types = qw(www volatile archive old nonus
			backports security cdimage);
my %exclude_mirror_types = map { $_ => 1 } qw(nonus www volatile cdimage);

# Options:
my ($update_list, $threads) = (1, 4);
our $verbose = 0;

sub parse_list($$);
sub process_entry($);
sub fancy_get_host($);

GetOptions('update-list!' => \$update_list,
	    'j|threads=i' => \$threads,
	    'db-output=s' => \$db_output,
	    'verbose' => \$verbose) or exit 1;

if ($update_list) {
    use LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    $ua->timeout(20);
    $ua->protocols_allowed(['http', 'https']);

    my $res = $ua->mirror(
	'http://anonscm.debian.org/viewvc/webwml/webwml/english/mirror/Mirrors.masterlist?view=co',
	'Mirrors.masterlist.new');
    if ($res->is_error) {
	die("error: failed to fetch Mirrors.masterlist: ",$res->status_line,"\n");
    }
    rename('Mirrors.masterlist.new', $current_list)
	or die ("mv Mirrors.masterlist{.new,} failed: $?");
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
	'country' => {}, 'arch' => {},
	'AS' => {}, 'continent' => {},
	'master' => ''
    });
    $semaphore{$mirror_type} = Thread::Semaphore->new();
}
$db{'all'} = shared_clone({});
$db{'id'} = time;
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
		$g_city = Geo::IP->open('geoip/GeoLiteCity.dat', GEOIP_MMAP_CACHE)
		    or die;
		$g_as = Geo::IP->open('geoip/GeoIPASNum.dat', GEOIP_MMAP_CACHE)
		    or die;

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

if (!exists($db{'archive'}{'arch'}{'i386'}) || scalar(keys %{$db{'archive'}{'arch'}{'i386'}}) < 10) {
    print STDERR "error: not even 10 mirrors with i386 found on the archive list, not saving\n";
} else {
    Mirror::DB::set($db_output);
    Mirror::DB::store(\%db);
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

    return if ($entry->{'type'} =~ m/^(?:unknown|geodns)$/ && $entry->{'site'} ne 'security.debian.org');

    if ($entry->{'site'} eq 'security.debian.org') {
	# used to indicate that even if only this site has a newer
	# master trace, all other mirrors should be disabled
	$entry->{'security-reference'} = 'yes';

	# not really relevant, yet this is needed by the rest of the code
	$entry->{'country'} = 'US United States';
    }

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

    my $got_http = 0;
    foreach my $type (@mirror_types) {
	next unless (exists($entry->{$type.'-http'}));
	next if ($exclude_mirror_types{$type});

	$got_http = 1;
    }
    unless ($got_http) {
	print "info: $entry->{'site'} is not an HTTP mirror, skipping\n"
	    if ($verbose);
	return;
    }

    if (defined ($entry->{'ipv6'})) {
	if ($entry->{'ipv6'} eq 'only') {
	    print STDERR "warning: unsupported IPv6-only $entry->{'site'}\n";
	    return;
	} elsif ($entry->{'ipv6'} eq 'yes') {
	    $entry->{'ipv6'} = undef;
	} elsif ($entry->{'ipv6'} eq 'no') {
	    delete $entry->{'ipv6'};
	} else {
	    print STDERR "warning: unknown ipv6 value: '$entry->{'ipv6'}'\n";
	    return;
	}
    }

    if (defined ($entry->{'includes'})) {
	my @includes = split /\s+/ , $entry->{'includes'};
	my $missing = 0;
	foreach my $include (@includes) {
	    next if (exists ($all_sites{$include}));

	    print "info: $entry->{'site'} includes $include\n";
	    print "\tbut it doesn't have its own entry, not cloning\n";
	    $missing = 1;
	}
	if (!$missing) {
	    print "info: $entry->{'site'} has Includes, all with their own entry, skipping\n"
		if ($verbose);
	    return;
	}
    }

    if (defined ($entry->{'restricted-to'})) {
	print STDERR "warning: skipping $entry->{'site'}, Restricted-To support is buggy\n";
	return;
	if ($entry->{'restricted-to'} =~ m/^(?:strict-country|subnet)$/) {
	    print STDERR "warning: unsupported Restricted-To $entry->{'restricted-to'}\n";
	    return;
	}
	if ($entry->{'restricted-to'} !~ m/^(?:AS|country)$/) {
	    print STDERR "warning: unknown Restricted-To value: '$entry->{'restricted-to'}'\n";
	    return;
	}
    } else {
	$entry->{'restricted-to'} = '';
    }

    my ($r, $as) = (undef, '');

    $as = $entry->{'as'} if (defined($entry->{'as'}));

    my $attempts = 2;
    my @ips;
    while ($attempts--) {
	@ips = fancy_get_host($entry->{'site'});
	last if (@ips && scalar(@ips) > 0);
    }
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
	} elsif (defined($m_as) && $as ne $m_as) {
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
    $as = Mirror::AS::convert($as);

    # A1: Anonymous proxies
    # A2: Satellite providers
    # EU: Europe
    # AP: Asia/Pacific region
    if ($country =~ m/^(?:A1|A2|EU|AP)$/) {
	print STDERR "warning: non-definitive country ($country) entry in GeoIP db for $entry->{'site'}\n";
	print STDERR "\tusing listed country ($listed_country)";
	$country = $listed_country;

	require Mirror::CountryCoords;
	my $coords = Mirror::CountryCoords::country($country);
	if ($coords) {
	    $lat = $coords->{'lat'};
	    $lon = $coords->{'lon'};
	    print STDERR " and country coordinates\n";
	} else {
	    print STDERR ", but country coordinates could not be found\n";
	}
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

    # Remove trailing zeros
    for my $coord_type (qw(lat lon)) {
	next unless ($entry->{$coord_type} =~ m/\./);
	$entry->{$coord_type} =~ s/0+$//;
	$entry->{$coord_type} =~ s/\.$//;
    }

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

    my $mirror_recorded = 0;

    foreach my $type (@mirror_types) {
	if ($exclude_mirror_types{$type}) {
	    delete $entry->{$type.'-http'};
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

	unless ($mirror_recorded) {
	    # Now store the results
	    $semaphore{'main'}->down();
	    $db{'all'}{$id} = $entry;
	    $semaphore{'main'}->up();
	    $mirror_recorded = 1;
	}

	$semaphore{$type}->down();
	# Create skeleton, if missing:
	$db{$type}{'AS'}{$as} = shared_clone([])
	    unless (exists ($db{$type}{'AS'}{$as}));
	push @{$db{$type}{'AS'}{$as}}, $id;

	unless ($entry->{'restricted-to'} eq 'AS') {
	    $db{$type}{'country'}{$country} = shared_clone({})
		unless (exists ($db{$type}{'country'}{$country}));
	    $db{$type}{'country'}{$country}{$id} = undef;

	    unless ($entry->{'restricted-to'} eq 'country') {
		$db{$type}{'continent'}{$continent} = shared_clone({})
		    unless (exists ($db{$type}{'continent'}{$continent}));
		$db{$type}{'continent'}{$continent}{$id} = undef;
	    }
	}

	foreach my $arch (keys %archs) {
	    # more skeletons...
	    $db{$type}{'arch'}{$arch} = shared_clone({})
		unless (exists ($db{$type}{'arch'}{$arch}));

	    $db{$type}{'arch'}{$arch}{$id} = undef;
	}

	$semaphore{$type}->up();
	# end: now store the results
    }

    # remove any remaining fields we don't use
    my %wanted_fields = map { $_ => 1 } qw(
	bandwidth
	ipv6
	lat
	lon
	site
	restricted-to
	trace-file
    );
    for my $key (keys %{$entry}) {
	next if ($key =~ m/-http$/);
	next if ($key =~ m/-reference$/);

	if (defined($wanted_fields{$key})) {
	    # undef has a special meaning
	    next if (!defined($entry->{$key}));
	    # empty fields are not useful
	    next if (length($entry->{$key}));
	}
	delete $entry->{$key};
    }
}

sub fancy_get_host($) {
    my $name = shift;

    my @addresses = gethostbyname($name)
	or return;
    return map { inet_ntoa($_) } @addresses[4..$#addresses];
}
