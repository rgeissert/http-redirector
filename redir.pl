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
use lib '.';

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
    print "Status: 405 Not Allowed\r\n";
    print "Allow: GET, HEAD\r\n\r\n";
    exit;
}

use Geo::IP;
use Storable qw(retrieve);
use Mirror::Math;
use Mirror::AS;

our $metric = ''; # alt: taxicab (default) | euclidean
my $stddev_set = 'iquartile'; # iquartile (default) | population
our $xtra_headers = 1;
my $add_links = 1;
my $random_sort = 1;
my $db_store = 'db';
my $peers_db_store = 'db.peers';
our $mirror_type = 'archive';
our %this_host = map { $_ => 1 } qw(); # this host's hostname
our $subrequest_method = ''; # alt: redirect (default) | sendfile | sendfile1.4 | accelredirect
our $subrequest_prefix = 'serve/';

my %nearby_continents = (
    'AF' => [ qw(EU NA AS SA OC) ],
    'SA' => [ qw(NA EU OC AS AF) ],
    'OC' => [ qw(NA AS EU SA AF) ],
    'AS' => [ qw(EU NA OC SA AF) ],
    'NA' => [ qw(EU AS OC SA AF) ],
    'EU' => [ qw(NA AS SA OC AF) ],
);

my %nearby_country = (
    'NA' => [ qw(US CA) ],
);

sub fullfils_request($$);
sub print_xtra($$);
sub find_arch($@);
sub clean_url($);
sub consider_mirror($);
sub check_arch_for_list(@);
sub url_for_mirror($);
sub do_redirect($$);
sub should_blackhole($);
sub mirror_is_in_continent($$$);

my @output;
our @archs;
my $action = 'redir';

unless ($request_method eq 'HEAD') {
    $xtra_headers = 0;
    $add_links = 0;
} else {
    print "Vary: x-web-demo\r\n";
}

$mirror_type = $q->param('mirror') || 'archive';

if ($mirror_type =~ s/\.list$//) {
    $action = 'list';
    $add_links = 0;
    push @archs, check_arch_for_list($q->param('arch'));
}

$action = 'demo' if (exists($ENV{'HTTP_X_WEB_DEMO'}));

our $db = retrieve($db_store);
# Make a shortcut
my $rdb = $db->{$mirror_type} or die("Invalid mirror type: $mirror_type");

####
my $IP = $q->remote_addr;
$IP = `wget -O- -q http://myip.dnsomatic.com/` if ($IP eq '127.0.0.1');
####

our $ipv6 = ($IP =~ m/:/);

# Handle IPv6 over IPv4 requests as if they originated from an IPv4
if ($ipv6 && $IP =~ m/^200(2|1(?=:0:)):/) {
    my $tunnel_type = $1;
    $ipv6 = 0;
    print_xtra('IPv6', $IP);

    if ($tunnel_type == 1) { # teredo
	$IP =~ m/:(\w{0,2}?)(\w{1,2}):(\w{0,2}?)(\w{1,2})$/ or die;
	$IP = join('.', hex($1)^0xff, hex($2)^0xff, hex($3)^0xff, hex($4)^0xff);
    } elsif ($tunnel_type == 2) { # 6to4
	$IP =~ m/^2002:(\w{0,2}?)(\w{1,2}):(\w{0,2}?)(\w{1,2}):/ or die;
	$IP = join('.', hex($1), hex($2), hex($3), hex($4));
    }
}

my ($g_city, $g_as);
my ($geo_rec, $as);
our ($lat, $lon);

if (!$ipv6) {
    $g_city = Geo::IP->open('geoip/GeoLiteCity.dat', GEOIP_MMAP_CACHE);
    $g_as = Geo::IP->open('geoip/GeoIPASNum.dat', GEOIP_MMAP_CACHE);

    $geo_rec = $g_city->record_by_addr($IP);
    ($as) = split /\s+/, ($g_as->org_by_addr($IP) || ' ');
} else {
    $g_city = Geo::IP->open('geoip/GeoLiteCityv6.dat', GEOIP_MMAP_CACHE);
    $g_as = Geo::IP->open('geoip/GeoIPASNumv6.dat', GEOIP_MMAP_CACHE);

    $geo_rec = $g_city->record_by_addr_v6($IP);
    ($as) = split /\s+/, ($g_as->org_by_addr_v6($IP) || ' ');
}

my $url = clean_url($q->param('url') || '');

if (should_blackhole($url)) {
    print "Status: 404 Not Found\r\n\r\n";
    exit;
}

if (!defined($geo_rec)) {
    # request can be handled locally. So, do it
    if ($action eq 'redir' && scalar(keys %this_host)) {
	do_redirect('', $url);
	exit;
    }
    # sadly, we really depend on it. throw an error for now
    print "Status: 501 Not Implemented\r\n\r\n";
    exit;
}
$as = Mirror::AS::convert($as);

$lat = $geo_rec->latitude;
$lon = $geo_rec->longitude;

# Do not send Link headers on directory requests
$add_links = 0 if ($add_links && $url =~ m,/$,);

# Even-numbered list: '[default]' => qr/regex/
# Whenever regex matches but there's no value in the capture #1 then
# the default value is used.
my @ARCHITECTURES_REGEX = (
    '' => qr'^dists/(?:[^/]+/){2,3}binary-([^/]+)/',
    '' => qr'^pool/(?:[^/]+/){3,4}.+_([^.]+)\.u?deb$',
    '' => qr'^dists/(?:[^/]+/){1,2}Contents-(?:udeb-(?!nf))?(?!udeb)([^.]+)\.(?:gz$|diff/)',
    '' => qr'^indices/files(?:/components)?/arch-([^.]+).*$',
    '' => qr'^dists/(?:[^/]+/){2}installer-([^/]+)/',
    '' => qr'^dists/(?:[^/]+/){2,3}(source)/',
    'source' => qr'^pool/(?:[^/]+/){3,4}.+\.(?:dsc|(?:diff|tar)\.(?:xz|gz|bz2))$',
);

@archs or @archs = find_arch($url, @ARCHITECTURES_REGEX);
# @archs may only have more than one element iff $action eq 'list'
# 'all' is not part of the archs that may be passed when running under
# $action eq 'list', so it should be safe to assume the size of the
# array
$archs[0] = '' if ($archs[0] eq 'all');

# If no mirror provides the 'source' "architecture" assume it is
# included by all mirrors. Apply the restriction otherwise.
if ($archs[0] eq 'source' && !exists($rdb->{'arch'}{'source'})) {
    $archs[0] = '';
}

if (exists($db->{'id'})) {
    $peers_db_store .= '-'.$db->{'id'} if ($peers_db_store);
}

our ($require_inrelease, $require_i18n) = (0, 0);
if ($mirror_type ne 'old') {
    $require_inrelease = ($url =~ m,/InRelease$,);
    $require_i18n = ($url =~ m,^dists/.+/i18n/,);
}

Mirror::Math::set_metric($metric);

my $continent = $geo_rec->continent_code;
$continent = 'EU' if ($continent eq '--');

print_xtra('IP', $IP);
print_xtra('AS', $as);
print_xtra('URL', $url);
print_xtra('Arch', join(', ', @archs));
print_xtra('Country', $geo_rec->country_code);
print_xtra('Continent', $continent);

our %hosts;
my $match_type = '';

# match by AS
foreach my $match (@{$rdb->{'AS'}{$as}}) {
    next unless (mirror_is_in_continent($rdb, $match, $continent));

    $match_type = 'AS' if (consider_mirror ($match));
}

# match by AS peer
if (!$match_type && $as && $peers_db_store && !$ipv6 && -f $peers_db_store) {
    my $peers_db = retrieve($peers_db_store);

    foreach my $match (keys %{$peers_db->{$as}}) {
	next unless (exists($db->{'all'}{$match}{$mirror_type.'-http'}));
	next unless (mirror_is_in_continent($rdb, $match, $continent));

	$match_type = 'AS-peer' if (consider_mirror ($match));
    }
}

# match by country
if (!$match_type) {
    foreach my $match (keys %{$rdb->{'country'}{$geo_rec->country_code}}) {
	$match_type = 'country' if (consider_mirror ($match));
    }
}

# match by nearby-country
if (!$match_type && exists($nearby_country{$continent})) {
    for my $country (@{$nearby_country{$continent}}) {
	foreach my $match (keys %{$rdb->{'country'}{$country}}) {
	    $match_type = 'nearby-country' if (consider_mirror ($match));
	}
    }
}

# match by continent
if (!$match_type) {
    my @continents = ($continent, @{$nearby_continents{$continent}});

    for my $mirror_continent (@continents) {
	last if ($match_type);

	my $mtype;
	if ($mirror_continent eq $continent) {
	    $mtype = 'continent';
	} else {
	    $mtype = 'nearby-continent';
	}

	foreach my $match (keys %{$rdb->{'continent'}{$mirror_continent}}) {
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
my $dev;

if ($stddev_set eq 'population') {
    $dev = Mirror::Math::stddevp(values %hosts);
} else {
    my @iq_dists = map { $hosts{$_} } Mirror::Math::iquartile(@sorted_hosts);
    $dev = Mirror::Math::stddev(@iq_dists);
}

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

if ($random_sort) {
    my $n = int(rand scalar(@close_hosts));
    $host = $close_hosts[$n];
}
print_xtra('Distance', $hosts{$host});
print_xtra('Match-Type', $match_type);

if ($action eq 'redir') {
    do_redirect($host, $url);
} elsif ($action eq 'demo') {
    print "Status: 200 OK\r\n";
    print "Cache-control: no-cache\r\n";
    print "Pragma: no-cache\r\n";
} elsif ($action eq 'list') {
    print "Content-type: text/plain\r\n";
    print "Status: 200 OK\r\n";
    for my $host (@close_hosts) {
	push @output, url_for_mirror($host)."\n";
    }
} else {
    die("FIXME: unknown action '$action'");
}

if ($add_links && (scalar(@close_hosts) > 1 || $action eq 'demo')) {
    # RFC6249-like link rels
    # A client strictly adhering to the RFC would ignore these since we
    # don't provide a digest, and we wont.
    for my $host (@close_hosts) {
	my $depth = 0;
	my $priority = $hosts{$host};

	$priority *= 100;
	$priority = 1 if ($priority == 0);
	$priority = sprintf("%.0f", $priority);

	if ($url =~ m,^dists/[^/]+/(?:main|contrib|non-free)/Contents-[^.]+\.diff(/.*)$, ||
	    $url =~ m,^dists/[^/]+/(?:main|contrib|non-free)/binary-[^/]+(/.*)$, ||
	    $url =~ m,^dists/[^/]+/(?:main|contrib|non-free)/i18n(/.*)$, ||
	    $url =~ m,^project(/.*)$, ||
	    $url =~ m,^tools(/.*)$,) {
	    $depth = $1 =~ tr[/][/];
	}

	print "Link: <".url_for_mirror($host).$url.">; rel=duplicate; pri=$priority; depth=$depth\r\n";
    }
}

print "\r\n";

for my $line (@output) {
    print $line;
}

exit;

sub fullfils_request($$) {
    my ($rdb, $id) = @_;

    my $mirror = $db->{'all'}{$id};

    return 0 if (exists($mirror->{$mirror_type.'-disabled'}));

    return 0 if ($ipv6 && !exists($mirror->{'ipv6'}));

    return 0 if ($require_inrelease && exists($mirror->{$mirror_type.'-notinrelease'}));

    return 0 if ($require_i18n && exists($mirror->{$mirror_type.'-noti18n'}));

    for my $arch (@archs) {
	next if ($arch eq '');

	return 0 if (!exists($rdb->{'arch'}{$arch}{$id}) && !exists($rdb->{'arch'}{'any'}{$id}));

	return 0 if (exists($mirror->{$mirror_type.'-'.$arch.'-disabled'}));
    }

    return 1;
}

sub print_xtra($$) {
    print "X-$_[0]: $_[1]\r\n"
	if ($xtra_headers);
}

sub find_arch($@) {
    my $url = shift;

    do {
	my ($default, $rx) = (shift, shift);
	if ($url =~ m/$rx/) {
	    my $arch = $1 || $default;
	    return $arch;
	}
    } while (@_);
    return '';
}

sub clean_url($) {
    my $url = shift;
    $url =~ s,//,/,g;
    $url =~ s,^/,,;
    $url =~ s,^\.\.?/,,g;
    $url =~ s,(?<=/)\.\.?(?:/|$),,g;
    $url = CGI::Simple->url_encode($url);
    $url =~ s,%2F,/,g;
    return $url;
}

sub consider_mirror($) {
    my ($id) = @_;

    my $mirror = $db->{'all'}{$id};

    return 0 unless fullfils_request($db->{$mirror_type}, $id);

    $hosts{$id} = Mirror::Math::calculate_distance($mirror->{'lon'}, $mirror->{'lat'},
				    $lon, $lat);
    return 1;
}

sub check_arch_for_list(@) {
    my @archs = @_;;

    if (scalar(@archs) == 0) {
	print "Status: 400 Bad Request";
    } else {
	return @archs;
    }

    print "\r\n\r\n";
    exit;
}

sub url_for_mirror($) {
    my $id = shift;
    return '' unless (length($id));
    my $mirror = $db->{'all'}{$id};
    return "http://".$mirror->{'site'}.$mirror->{$mirror_type.'-http'};
}

sub do_redirect($$) {
    my ($host, $real_url) = @_;

    if (scalar(keys %this_host)) {
	if ($host eq '' || exists($this_host{$db->{'all'}{$host}{'site'}})) {
	    my $internal_subreq = 0;
	    $real_url = $subrequest_prefix.$real_url;

	    if ($subrequest_method eq 'sendfile') {
		print "X-Sendfile: $real_url\r\n";
		$internal_subreq = 1;
	    } elsif ($subrequest_method eq 'sendfile1.4') {
		print "X-LIGHTTPD-send-file: $real_url\r\n";
		$internal_subreq = 1;
	    } elsif ($subrequest_method eq 'accelredirect') {
		print "X-Accel-Redirect: $real_url\r\n";
		$internal_subreq = 1;
	    } else {
		# do nothing special, will redirect
	    }

	    if ($internal_subreq) {
		print "Content-Location: $real_url\r\n";
		print "\r\n";
		exit;
	    }
	}
    }

    print "Content-type: text/plain\r\n";
    print "Status: 302 Moved Temporarily\r\n";
    print "Location: ".url_for_mirror($host).$real_url."\r\n";
}

sub should_blackhole($) {
    my $url = shift;

    if ($mirror_type eq 'archive') {
	return 1 if ($url =~ m,^dists/wheezy, && (
	    $url =~ m,/(?:main|contrib|non-free)/binary-[^/]+/Packages\.(?:lzma|xz)$, ||
	    $url =~ m,/(?:main|contrib|non-free)/i18n/Translation[^/]+\.(?:lzma|xz|gz)$,
	    ));
	return 1 if ($url =~ m,^dists/(?:squeeze|wheezy)-updates/(?:main|contrib|non-free)/i18n/,);
	return 1 if ($url =~ m,^dists/squeeze, && (
	    $url eq 'dists/squeeze/InRelease' ||
	    $url =~ m,/(?:main|contrib|non-free)/binary-[^/]+/Packages\.(?:lzma|xz)$, ||
	    $url =~ m,/(?:main|contrib|non-free)/i18n/Translation[^/]+\.(?:lzma|xz|gz)$, ||
	    $url =~ m,/(?:main|contrib|non-free)/i18n/Translation-en_(?:US|GB),
	    ));
	return 1 if ($url =~ m,^dists/lenny,);
    } elsif ($mirror_type eq 'backports') {
	return 1 if ($url =~ m,^dists/squeeze-backports/(?:main|contrib|non-free)/i18n/,
	    );
    } elsif ($mirror_type eq 'security') {
	return 1 if ($url =~ m,^dists/[^/]+/updates/(?:main|contrib|non-free)/i18n/,
	    );
    }
    return 0;
}

sub mirror_is_in_continent($$$) {
    my ($rdb, $id, $continent) = @_;

    return (exists($rdb->{'continent'}{$continent}{$id}));
}
