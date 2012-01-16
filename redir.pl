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

# Usage: redir.pl?mirror=(archive|backports|...)&url=/debian/dists/sid/...
# Test (make sure -debug1 is set below):
#   ./redir.pl mirror=...
#   REMOTE_ADDR=1.2.3.4 ./redir.pl mirror=...
use CGI::Simple qw(-debug1);
my $q = new CGI::Simple;

use Geo::IP;
use Storable qw(retrieve);

my $db_store = 'db';
my $mirror_type = 'archive';
my %mirror_prefixes = (
    'archive' => '',
    'security' => '-security',
    'cdimage' => '-cd',
    'volatile' => '-volatile',
    'backports' => '-backports',
);

my $g_city = Geo::IP->open('geoip/GeoLiteCity.dat', GEOIP_MMAP_CACHE);
my $g_as = Geo::IP->open('geoip/GeoIPASNum.dat', GEOIP_MMAP_CACHE);

# TODO: support IPv6. Basic implementation is to lookup the country in
# the geoipv6 db and wish the user our best

sub fullfils_request($$$$);

my @ARCHITECTURES_REGEX = (
    qr'^dists/(?:[^/]+/){2,3}binary-([^/]+)/',
    qr'^pool/(?:[^/]+/){3,4}.+_([^.]+)\.deb$',
    qr'^dists/(?:[^/]+/){1,2}Contents-([^.]+)\.gz$',
);

our $db = retrieve($db_store);

####
my $IP = $ENV{'REMOTE_ADDR'} || '127.0.0.1';
# for testing purposes
$IP = '8.8.8.8' if ($IP eq '127.0.1.1');
$IP = `wget -O- -q http://myip.dnsomatic.com/` if ($IP eq '127.0.0.1');
####

$mirror_type = $q->param('mirror') || 'archive';

# Make a shortcut
my $rdb = $db->{$mirror_type} or die("Invalid mirror type: $mirror_type");

my $ipv6 = ($IP =~ m/::/);
my $r = $g_city->record_by_addr($IP);
my ($as) = split /\s+/, ($g_as->org_by_addr($IP) || '');
my $arch = '';

print "X-IP: $IP\r\n";
if (!defined($r) || !defined($as)) {
    # TODO: handle error
    $as = '';
    $r = undef;
}

print "X-AS: ".$as."\r\n";

my $url = $q->param('url') || '';
if (defined($mirror_prefixes{$mirror_type})) {
    # FIXME: ugly
    $url =~ s,^debian$mirror_prefixes{$mirror_type}/,,;
}
$url =~ s,//,/,g;

print "X-URL: $url\r\n";

foreach my $r (@ARCHITECTURES_REGEX) {
    if ($url =~ m/$r/) {
	$arch = $1;
	last;
    }
}
print "X-Arch: ".$arch."\r\n";

my $host = '';

# TODO:
# a list of mirrors that fullfil the request should be generated
# and then a weight calculated, to finally decide what mirror will be
# used (mirrors with equal weight should be chosen at random, at least)

# match by AS
foreach my $match (@{$rdb->{'AS'}{$as}}) {
    my $mirror = $db->{'all'}{$match};

    next unless fullfils_request($rdb, $match, $arch, $ipv6);

    $host = $mirror->{'site'}.$mirror->{$mirror_type.'-http'};
    last;
}

print "X-Country: ".$r->country_code."\r\n";
# match by country
if ($host eq '') {
    foreach my $match (keys %{$rdb->{'country'}{$r->country_code}}) {
	my $mirror = $db->{'all'}{$match};

    	next unless fullfils_request($rdb, $match, $arch, $ipv6);

	$host = $mirror->{'site'}.$mirror->{$mirror_type.'-http'};
	last;
    }
}

print "X-Continent: ".$r->continent_code."\r\n";
# match by continent
if ($host eq '') {
    foreach my $match (keys %{$rdb->{'continent'}{$r->continent_code}}) {
	my $mirror = $db->{'all'}{$match};

    	next unless fullfils_request($rdb, $match, $arch, $ipv6);

	$host = $mirror->{'site'}.$mirror->{$mirror_type.'-http'};
	last;
    }
}

# something went awry, we don't know how to handle this user, we failed
# let's make another attempt:
if ($host eq '' && $mirror_type eq 'archive') {
    $host = 'cdn.debian.net/debian/';
}

# TODO: if ($host eq '') { not a request for archive, but we don't know
#   where we should redirect the user to }

print "Location: http://".$host.$url."\r\n\r\n";

exit;

sub fullfils_request($$$$) {
    my ($rdb, $id, $arch, $ipv6) = @_;

    my $mirror = $db->{'all'}{$id};

    return 0 if ($ipv6 && !exists($rdb->{'ipv6'}{$id}));

    return 0 if ($arch ne '' && !exists($rdb->{'arch'}{$arch}{$id}) && !exists($rdb->{'arch'}{'any'}{$id}));

    return 1;
}
