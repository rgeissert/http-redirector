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
use Socket;
use Geo::IP;
use Storable qw(dclone);

use Mirror::AS;
use Mirror::DB;

use AE;
use AnyEvent::DNS;

my $input_dir = 'mirrors.lst.d';
my $db_store = 'db';
my $db_output = $db_store;
my @mirror_types = qw(www volatile archive old nonus
			backports security cdimage ports);
my %exclude_mirror_types = map { $_ => 1 } qw(nonus www volatile cdimage);

# Options:
my ($update_list, $threads) = (1, -1);
our $verbose = 0;

sub get_lists($);
sub parse_list($$);
sub process_entry4($@);
sub process_entry6($@);
sub process_entry_common($$$$@);
sub query_dns_for_entry($);
sub bandwidth_to_mb($);

GetOptions('update-list!' => \$update_list,
	    'list-directory=s' => \$input_dir,
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
	"$input_dir/Mirrors.masterlist.new");
    if ($res->is_error) {
	die("error: failed to fetch Mirrors.masterlist: ",$res->status_line,"\n");
    }
    rename("$input_dir/Mirrors.masterlist.new", "$input_dir/Mirrors.masterlist")
	or die ("mv Mirrors.masterlist{.new,} failed: $?");
}

my %all_sites;
my @data;
my @input_files;

@input_files = get_lists($input_dir);

for my $list (sort @input_files) {
    @data = (@data, parse_list($list, \%all_sites));
}

my $cv = AE::cv;
my %full_db = ('ipv4' => {}, 'ipv6' => {});
my $db4 = $full_db{'ipv4'};
my $db6 = $full_db{'ipv6'};
my $i = 0;

foreach my $mirror_type (@mirror_types) {
    next if ($exclude_mirror_types{$mirror_type});

    $db4->{$mirror_type} = {
	'country' => {}, 'arch' => {},
	'AS' => {}, 'continent' => {},
	'master' => '', 'serial' => {}
    };
    $full_db{$mirror_type} = $db4->{$mirror_type};
    $db6->{$mirror_type} = {
	'country' => {}, 'arch' => {},
	'AS' => {}, 'continent' => {},
	'master' => '', 'serial' => {}
    };
}
$db4->{'all'} = {};
$db6->{'all'} = {};
$full_db{'all'} = $db4->{'all'};

$full_db{'id'} = time;

my ($g_city4, $g_as4, $g_city6, $g_as6);
$g_city4 = Geo::IP->open('geoip/GeoLiteCity.dat', GEOIP_MMAP_CACHE)
    or die;
$g_as4 = Geo::IP->open('geoip/GeoIPASNum.dat', GEOIP_MMAP_CACHE)
    or die;
$g_city6 = Geo::IP->open('geoip/GeoLiteCityv6.dat', GEOIP_MMAP_CACHE)
    or die;
$g_as6 = Geo::IP->open('geoip/GeoIPASNumv6.dat', GEOIP_MMAP_CACHE)
    or die;

my $remaining_entries = scalar(@data);
for my $entry (@data) {
    if (query_dns_for_entry($entry)) {
	if (exists($entry->{'ipv4'})) {
	    delete $entry->{'ipv4'};
	    AnyEvent::DNS::a $entry->{'site'}, sub {
		process_entry4(dclone($entry), @_);
		$cv->send if (--$remaining_entries == 0);
	    };
	}
	if (exists($entry->{'ipv6'})) {
	    # we now only use it as a flag here
	    delete $entry->{'ipv6'};
	    $remaining_entries++;
	    AnyEvent::DNS::aaaa $entry->{'site'}, sub {
		process_entry6(dclone($entry), @_);
		$cv->send if (--$remaining_entries == 0);
	    };
	}
    } else {
	$cv->send if (--$remaining_entries == 0);
    }
}

$cv->recv;

if (!exists($db4->{'archive'}{'arch'}{'i386'}) || scalar(keys %{$db4->{'archive'}{'arch'}{'i386'}}) < 10) {
    print STDERR "error: not even 10 mirrors with i386 found on the archive list, not saving\n";
} else {
    Mirror::DB::set($db_output);
    Mirror::DB::store(\%full_db);
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

sub query_dns_for_entry($) {
    my $entry = shift;

    $entry->{'type'} = lc ($entry->{'type'} || 'unknown');

    return 0 if ($entry->{'type'} =~ m/^(?:unknown|geodns)$/ && $entry->{'site'} ne 'security.debian.org');

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

	    $db4->{$type}{'master'} = $entry->{'site'};
	    $db6->{$type}{'master'} = $entry->{'site'};
	}
	return 0;
    }

    if (!defined($entry->{'site'})) {
	print STDERR "warning: mirror without site:\n";
	require Data::Dumper;
	print STDERR Data::Dumper::Dumper($entry);
	return 0;
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
	return 0;
    }

    # By default consider all mirrors to have v4 connectivity
    $entry->{'ipv4'} = undef;
    if (defined ($entry->{'ipv6'})) {
	if ($entry->{'ipv6'} eq 'only') {
	    $entry->{'ipv6'} = undef;
	    delete $entry->{'ipv4'};
	} elsif ($entry->{'ipv6'} eq 'yes') {
	    $entry->{'ipv6'} = undef;
	} elsif ($entry->{'ipv6'} eq 'no') {
	    delete $entry->{'ipv6'};
	} else {
	    print STDERR "warning: unknown ipv6 value: '$entry->{'ipv6'}'\n";
	    return 0;
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
	    return 0;
	}
    }

    if (defined ($entry->{'restricted-to'})) {
	print STDERR "warning: skipping $entry->{'site'}, Restricted-To support is buggy\n";
	return 0;
	if ($entry->{'restricted-to'} =~ m/^(?:strict-country|subnet)$/) {
	    print STDERR "warning: unsupported Restricted-To $entry->{'restricted-to'}\n";
	    return 0;
	}
	if ($entry->{'restricted-to'} !~ m/^(?:AS|country)$/) {
	    print STDERR "warning: unknown Restricted-To value: '$entry->{'restricted-to'}'\n";
	    return 0;
	}
    } else {
	$entry->{'restricted-to'} = '';
    }

    return 1;
}

sub process_entry6($@) {
    my $entry = shift;
    my @ips = @_;

    return process_entry_common($db6, $entry,
	    sub { return $g_as6->org_by_addr_v6(shift)},
	    sub { return $g_city6->record_by_addr_v6(shift)},
	    @_);
}

sub process_entry4($@) {
    my $entry = shift;
    my @ips = @_;

    return process_entry_common($db4, $entry,
	    sub { return $g_as4->org_by_addr(shift)},
	    sub { return $g_city4->record_by_addr(shift)},
	    @_);
}

sub process_entry_common($$$$@) {
    my $db = shift;
    my $entry = shift;
    my $as_of_ip = shift;
    my $grec_of_ip = shift;
    my @ips = @_;

    if (!@ips || scalar(@ips) == 0) {
	print STDERR "warning: host lookup for $entry->{'site'} failed\n";
	return;
    }

    my ($r, $as) = (undef, '');
    $as = $entry->{'as'} if (defined($entry->{'as'}));
    # Consider: lookup all possible IPs and try to match them to a unique host
    # However: we can't control what IP the client will connect to, and
    #	we can't guarantee that accessing the mirror with a different
    #	Host will actually work. Meh.
    my %as_seen;
    for my $ip (@ips) {
	my $m_record = &$grec_of_ip($ip);
	# Split result, original format is: "AS123 Foo Bar corp"
	my ($m_as) = split /\s+/, (&$as_of_ip($ip) || '');

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
			" AS' ($as != $m_as)\n" unless (exists($as_seen{$m_as}));
	    $as_seen{$m_as} = 1;
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
    if ($country =~ m/^(?:A1|A2|EU|AP)$/ || defined($entry->{'geoip-override'})) {
	if (!defined($entry->{'geoip-override'})) {
	    print STDERR "warning: non-definitive country ($country) entry in GeoIP db for $entry->{'site'}\n";
	    print STDERR "\tusing listed country ($listed_country)";
	} else {
	    print STDERR "warning: overriding country of $entry->{'site'}";
	}
	$country = $listed_country;
	$continent = $g_city4->continent_code_by_country_code($country);

	print STDERR ", fixing continent to '$continent'";

	require Mirror::CountryCoords;
	my $coords = Mirror::CountryCoords::country($country);
	if ($coords) {
	    $lat = $coords->{'lat'};
	    $lon = $coords->{'lon'};
	    print STDERR " and country coordinates\n";
	} else {
	    print STDERR ", but country coordinates could not be found\n";
	}

	# If provided, fix the latitude and longitude
	if (defined($entry->{'lat'})) {
	    $lat = $entry->{'lat'};
	}
	if (defined($entry->{'lon'})) {
	    $lon = $entry->{'lon'};
	}

    } elsif ($listed_country ne $country) {
	print STDERR "warning: listed country for $entry->{'site'} doesn't match GeoIP db\n";
	print STDERR "\t$listed_country (listed) vs $country (db), ";
	print STDERR "using geoip db's entry\n";
    }

    # Generate a unique id for this site
    my $id = $i++;
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
	eval {
	    $entry->{'bandwidth'} = bandwidth_to_mb($entry->{'bandwidth'});
	};
	if ($@) {
	    print STDERR "warning: $@ for $entry->{'site'}\n";
	    delete $entry->{'bandwidth'};
	}
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

	# Now store the results
	unless ($mirror_recorded) {
	    $db->{'all'}{$id} = $entry;
	    $mirror_recorded = 1;
	}

	# Create skeleton, if missing:
	$db->{$type}{'AS'}{$as} = []
	    unless (exists ($db->{$type}{'AS'}{$as}));
	push @{$db->{$type}{'AS'}{$as}}, $id;

	unless ($entry->{'restricted-to'} eq 'AS') {
	    $db->{$type}{'country'}{$country} = {}
		unless (exists ($db->{$type}{'country'}{$country}));
	    $db->{$type}{'country'}{$country}{$id} = undef;

	    unless ($entry->{'restricted-to'} eq 'country') {
		$db->{$type}{'continent'}{$continent} = {}
		    unless (exists ($db->{$type}{'continent'}{$continent}));
		$db->{$type}{'continent'}{$continent}{$id} = undef;
	    }
	}

	foreach my $arch (keys %archs) {
	    # more skeletons...
	    $db->{$type}{'arch'}{$arch} = {}
		unless (exists ($db->{$type}{'arch'}{$arch}));

	    $db->{$type}{'arch'}{$arch}{$id} = undef;
	}
	# end: now store the results
    }

    # remove any remaining fields we don't use
    my %wanted_fields = map { $_ => 1 } qw(
	bandwidth
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

sub bandwidth_to_mb($) {
    my $bw_str = shift;
    my $bw = 0;

    if ($bw_str =~ m/([\d.]+)\s*([tgm])/i) {
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
	die "unknown bandwidth format ($bw_str)\n";
    }
    return $bw;
}

sub get_lists($) {
    my $input_dir = shift;
    my @lists;
    my $dh;

    opendir($dh, $input_dir)
	or die("error: could not open '$input_dir' directory: $!\n");
    @lists = grep { m/\.masterlist$/ && s,^,$input_dir/, } readdir($dh);
    closedir($dh);

    return @lists;
}
