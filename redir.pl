#!/usr/bin/perl -w

####################
#    Copyright (C) 2011, 2012 by Raphael Geissert <geissert@debian.org>
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

# Usage: redir.pl?mirror=(archive|backports|...)&url=/debian/dists/sid/...
# Test (make sure -debug1 is set below):
#   ./redir.pl mirror=...
#   REMOTE_ADDR=1.2.3.4 ./redir.pl mirror=...
use CGI::Simple qw(-debug1);
$CGI::Simple::POST_MAX = 0;
$CGI::Simple::DISABLE_UPLOADS = 1;
my $q = new CGI::Simple;

my $request_method = $q->request_method() || 'HEAD';
# abort POST and other requests ASAP
if ($request_method ne 'GET' && $request_method ne 'HEAD') {
    print "Status: 501 Not Implemented\r\n\r\n";
    exit;
}

use Geo::IP;
use Storable qw(retrieve);
use List::Util qw(shuffle);

our $metric = ''; # alt: taxicab (default) | euclidean
our $xtra_headers = 1;
my $add_links = 1;
my $random_sort = 1;
my $db_store = 'db';
our $mirror_type = 'archive';

my %nearby_continents = (
    'AF' => [ qw(EU AS) ],
    'SA' => [ qw(NA EU) ],
    'OC' => [ qw(NA AS) ],
    'AS' => [ qw(EU) ],
    'NA' => [ qw(EU) ],
    'EU' => [ qw(NA) ],
);

sub fullfils_request($$);
sub calculate_distance($$$$);
sub stddevp;
sub print_xtra($$);
sub find_arch($@);
sub clean_url($);
sub consider_mirror($);


our $arch = '';
my $action = 'redir';
$mirror_type = $q->param('mirror') || 'archive';
$mirror_type = 'cdimage' if ($mirror_type eq 'cd');

$action = 'list' if ($mirror_type =~ s/\.list$//);

if ($action eq 'list') {
    my @archs = $q->param('arch');
    my $abort = 0;

    if (scalar(@archs) == 0) {
	$abort = 1;
	print "Status: 400 Bad Request";
    } elsif (scalar(@archs) != 1) {
	$abort = 1;
	print "Status: 501 Not Implemented";
    } else {
	$arch = $archs[0];
    }

    if ($abort) {
	print "\r\n\r\n";
	exit;
    }
}

our $db = retrieve($db_store);
# Make a shortcut
my $rdb = $db->{$mirror_type} or die("Invalid mirror type: $mirror_type");

####
my $IP = $ENV{'REMOTE_ADDR'} || '127.0.0.1';
$IP = `wget -O- -q http://myip.dnsomatic.com/` if ($IP eq '127.0.0.1');
####

our $ipv6 = ($IP =~ m/::/);

my ($g_city, $g_as);

if (!$ipv6) {
    $g_city = Geo::IP->open('geoip/GeoLiteCity.dat', GEOIP_MMAP_CACHE);
    $g_as = Geo::IP->open('geoip/GeoIPASNum.dat', GEOIP_MMAP_CACHE);
} else {
    $g_city = Geo::IP->open('geoip/GeoLiteCityv6.dat', GEOIP_MMAP_CACHE);
    $g_as = Geo::IP->open('geoip/GeoIPASNumv6.dat', GEOIP_MMAP_CACHE);
}


our $geo_rec = $g_city->record_by_addr($IP);
my ($as) = split /\s+/, ($g_as->org_by_addr($IP) || '');

if (!defined($geo_rec)) {
    # sadly, we really depend on it. throw an error for now
    print "Status: 501 Not Implemented\r\n\r\n";
    exit;
}

my $url = clean_url($q->param('url') || '');

my @ARCHITECTURES_REGEX;
if ($mirror_type eq 'cdimage') {
    @ARCHITECTURES_REGEX = (
	qr'^(?:\d|current)[^/]*/([^/]+)/',
    );
} else {
    @ARCHITECTURES_REGEX = (
	qr'^dists/(?:[^/]+/){2,3}binary-([^/]+)/',
	qr'^pool/(?:[^/]+/){3,4}.+_([^.]+)\.u?deb$',
	qr'^dists/(?:[^/]+/){1,2}Contents-([^.]+)\.gz$',
	qr'^indices/files(?:/components)?/arch-([^.]+).*$',
	qr'^dists/(?:[^/]+/){2}installer-([^/]+)/',
    );
}

$arch ||= find_arch($url, @ARCHITECTURES_REGEX);
$arch = 'i386' if ($arch eq 'multi-arch');

print_xtra('IP', $IP);
print_xtra('AS', $as);
print_xtra('URL', $url);
print_xtra('Arch', $arch);
print_xtra('Country', $geo_rec->country_code);
print_xtra('Continent', $geo_rec->continent_code);

my %hosts;
my $match_type = '';

# match by AS
foreach my $match (@{$rdb->{'AS'}{$as}}) {
    $match_type = 'AS' if (consider_mirror ($match));
}

# match by country
if (!$match_type) {
    foreach my $match (keys %{$rdb->{'country'}{$geo_rec->country_code}}) {
	$match_type = 'country' if (consider_mirror ($match));
    }
}

# match by continent
if (!$match_type) {
    my @continents = ($geo_rec->continent_code, @{$nearby_continents{$geo_rec->continent_code}});

    for my $continent (@continents) {
	last if ($match_type);
	foreach my $match (keys %{$rdb->{'continent'}{$continent}}) {
	    my $mtype;
	    if ($continent eq $geo_rec->continent_code) {
		$mtype = 'continent';
	    } else {
		$mtype = 'nearby-continent';
	    }
	    $match_type = $mtype if (consider_mirror ($match));
	}
    }
}

# something went awry, we don't know how to handle this user, we failed
if (!$match_type) {
    print "Status: 503 Service Unavailable\r\n\r\n";
    exit;
}

my @sorted_hosts = sort { $hosts{$a} <=> $hosts{$b} } keys %hosts;
my @close_hosts;
my $dev = stddevp(values %hosts);

# Closest host (or one of many), to use as the base distance
my $host = $sorted_hosts[0];

print_xtra('Std-Dev', $dev);
print_xtra('Population', scalar(@sorted_hosts));
print_xtra('Closest-Distance', $hosts{$host});

for my $h (@sorted_hosts) {
    # NOTE: this might need some additional work, as we should probably
    # guarantee a certain amount of alt hosts to choose from
    if (($hosts{$h} - $hosts{$host}) <= $dev) {
	push @close_hosts, $h;
    } else {
	# the list is sorted, if we didn't accept this one won't accept
	# the next
	last;
    }
}

$host = (shuffle (@close_hosts))[0]
    if ($random_sort);
print_xtra('Distance', $hosts{$host});
print_xtra('Match-Type', $match_type);

if ($action eq 'redir') {
    print "Status: 307 Temporary Redirect\r\n";
    print "Location: http://".$host.$url."\r\n";
} elsif ($action eq 'list') {
    print "Status: 200 OK\r\n";
    # FIXME: we shouldn't need to end the headers here
    print "\r\n";
    for my $host (@close_hosts) {
	print "$host\n";
    }
    exit;
} else {
    die("FIXME: unknown action '$action'");
}

if ($add_links && scalar(@close_hosts) > 1) {
    # RFC6249-like link rels
    # A client strictly adhering to the RFC would ignore these since we
    # don't provide a digest, and we wont.
    for my $host (@close_hosts) {
	my $priority = $hosts{$host};

	$priority *= 100;
	$priority = 1 if ($priority == 0);
	$priority = sprintf("%.0f", $priority);

	print "Link: http://".$host.$url."; rel=duplicate; pri=$priority\r\n";
    }
}

print "\r\n";

exit;

sub fullfils_request($$) {
    my ($rdb, $id) = @_;

    my $mirror = $db->{'all'}{$id};

    return 0 if (exists($mirror->{$mirror_type.'-disabled'}));

    return 0 if ($ipv6 && !exists($rdb->{'ipv6'}{$id}));

    return 0 if ($arch ne '' && !exists($rdb->{'arch'}{$arch}{$id}) && !exists($rdb->{'arch'}{'any'}{$id}));

    return 0 if ($arch ne '' && exists($mirror->{$mirror_type.'-'.$arch.'-disabled'}));

    return 1;
}

sub calculate_distance($$$$) {
    my ($x1, $y1, $x2, $y2) = @_;

    if ($metric eq 'euclidean') {
	return sqrt(($x1-$x2)**2 + ($y1-$y2)**2);
    } else {
	return (abs($x1-$x2) + abs($y1-$y2));
    }
}

sub stddevp {
    my ($avg, $var, $stddev) = (0, 0, 0);
    local $_;

    for (@_) {
	$avg += $_;
    }
    $avg /= scalar(@_);

    for (@_) {
	$var += $_**2;
    }
    $var /= scalar(@_);
    $var -= $avg**2;

    $stddev = sqrt($var);
    return $stddev;
}

sub print_xtra($$) {
    print "X-$_[0]: $_[1]\r\n"
	if ($xtra_headers);
}

sub find_arch($@) {
    my $url = shift;
    local $_;

    foreach (@_) {
	return $1 if ($url =~ m/$_/);
    }
    return '';
}

sub clean_url($) {
    my $url = shift;
    $url =~ s,//,/,g;
    $url =~ s,^/,,;
    $url =~ s, ,+,g;
    return $url;
}

sub consider_mirror($) {
    my ($id) = @_;

    my $mirror = $db->{'all'}{$id};

    return 0 unless fullfils_request($db->{$mirror_type}, $id);

    my $host = $mirror->{'site'}.$mirror->{$mirror_type.'-http'};
    $hosts{$host} = calculate_distance($mirror->{'lon'}, $mirror->{'lat'},
				    $geo_rec->longitude, $geo_rec->latitude);
    return 1;
}
