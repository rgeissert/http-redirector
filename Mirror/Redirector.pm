package Mirror::Redirector;

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

use Geo::IP;
use Storable qw(retrieve);
use Mirror::Math;
use Mirror::AS;
use Mirror::Redirection::Permanent;
use Mirror::Redirection::Blackhole;
use Mirror::Request;
use URI::Escape qw(uri_escape);

use Plack::Request;

sub fullfils_request($$);
sub print_xtra($$);
sub clean_url($);
sub consider_mirror($);
sub url_for_mirror($);
sub do_redirect($$);
sub mirror_is_in_continent($$$);
sub mirror_supports_ranges($$$);

our %nearby_continents = (
    'AF' => [ qw(EU NA AS SA OC) ],
    'SA' => [ qw(NA EU OC AS AF) ],
    'OC' => [ qw(NA AS EU SA AF) ],
    'AS' => [ qw(EU NA OC SA AF) ],
    'NA' => [ qw(EU AS OC SA AF) ],
    'EU' => [ qw(NA AS SA OC AF) ],
);

our %nearby_country = (
    'NA' => [ qw(US CA) ],
);

our $metric = ''; # alt: taxicab (default) | euclidean
our $stddev_set = 'iquartile'; # iquartile (default) | population
our $random_sort = 1;
our $db_store = 'db';
our $peers_db_store = 'db.peers';
our %this_host = map { $_ => 1 } qw(); # this host's hostname
our $subrequest_method = ''; # alt: redirect (default) | sendfile | sendfile1.4 | accelredirect
our $subrequest_prefix = 'serve/';

my ($_db, $db, $peers_db);
my ($gdb4, $asdb4, $gdb6, $asdb6);

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    # $_db holds the full database, while $db holds only the
    # part specific to the requested IP-family
    $db = $_db = retrieve($db_store);

    return $self;
}

sub get_ipdb {
    my ($ip, $ipv6) = @_;
    my $geo_rec;

    if (!$ipv6) {
	$gdb4 ||= Geo::IP->open('geoip/GeoLiteCity.dat', GEOIP_MMAP_CACHE);
	$geo_rec = $gdb4->record_by_addr($ip);
    } else {
	$gdb6 ||= Geo::IP->open('geoip/GeoLiteCityv6.dat', GEOIP_MMAP_CACHE);
	$geo_rec = $gdb6->record_by_addr_v6($ip);
    }
    return $geo_rec;
}

sub get_asdb {
    my ($ip, $ipv6) = @_;
    my $as;

    if (!$ipv6) {
	$asdb4 ||= Geo::IP->open('geoip/GeoIPASNum.dat', GEOIP_MMAP_CACHE);
	($as) = split /\s+/, ($asdb4->org_by_addr($ip) || ' ');
    } else {
	my $asdb6 ||= Geo::IP->open('geoip/GeoIPASNumv6.dat', GEOIP_MMAP_CACHE);
	($as) = split /\s+/, ($asdb6->org_by_addr_v6($ip) || ' ');
    }
    return $as;
}

sub run {
    my $self = shift;
    my $env = shift;
    my $req = Plack::Request->new($env);
    our $res = $req->new_response;

    my $request_method = $req->method || 'HEAD';
    # abort POST and other requests ASAP
    if ($request_method ne 'GET' && $request_method ne 'HEAD') {
	$res->status(405);
	$res->header('Allow' => 'GET, HEAD');
	return $res->finalize;
    }

    our $xtra_headers = 1;
    our $add_links = 1;
    our $mirror_type = 'archive';
    our $permanent_redirect = 1;

    my @output;
    our @archs = ();
    my $action = 'redir';

    if ($req->param('action') && $req->param('action') eq 'demo') {
	$action = 'demo';
    } else {
	$xtra_headers = 0;
	$add_links = 0;
    }

    $mirror_type = $req->param('mirror') || 'archive';

    if ($mirror_type =~ s/\.list$//) {
	$action = 'list';
	$add_links = 0;

	@archs = $req->param('arch');

	if (scalar(@archs) == 0) {
	    $res->status(400);
	    return $res->finalize;
	}
    }

    ####
    my $IP = $req->address;
    $IP = $self->get_local_ip($req) if ($IP eq '127.0.0.1');
    ####

    our $ipv6 = ($IP =~ m/:/);

    $db = ($ipv6)? $_db->{'ipv6'} : $_db->{'ipv4'};
    # Make a shortcut
    my $rdb = $db->{$mirror_type} or die("Invalid mirror type: $mirror_type");

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

    my ($geo_rec, $as);
    our ($lat, $lon);

    $geo_rec = get_ipdb($IP, $ipv6);
    $as = get_asdb($IP, $ipv6);

    my $url = clean_url($req->param('url') || '');

    if (should_blackhole($url, $mirror_type)) {
	$res->status(404);
	return $res->finalize;
    }

    if (!defined($geo_rec)) {
	require Mirror::FallbackGeoLocation;
	$geo_rec = Mirror::FallbackGeoLocation::get_record($db, $mirror_type);
    }
    # this should be a no-op now:
    if (!defined($geo_rec)) {
	# request can be handled locally. So, do it
	if ($action eq 'redir' && scalar(keys %this_host)) {
	    do_redirect('', $url);
	    return $res->finalize;
	}
	# sadly, we really depend on it. throw an error for now
	$res->status(501);
	return $res->finalize;
    }
    $as = Mirror::AS::convert($as);

    $lat = $geo_rec->latitude;
    $lon = $geo_rec->longitude;

    # Do not send Link headers on directory requests
    $add_links = 0 if ($add_links && $url =~ m,/$,);

    @archs or @archs = Mirror::Request::get_arch($url);
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

    # Do not use .=, as it would be concatenating to the
    # scoped "my" variable rather than to the global variable
    my $peers_db_store = $peers_db_store.'-'.$db->{'id'}
	if (exists($db->{'id'}) && $peers_db_store);

    our ($require_inrelease, $require_i18n) = (0, 0);
    if ($mirror_type ne 'old') {
	$require_inrelease = ($url =~ m,/InRelease$,);
	$require_i18n = ($url =~ m,^dists/.+/i18n/,);
    }

    if ($permanent_redirect) {
	$permanent_redirect = is_permanent($url, $mirror_type);
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
    print_xtra('City', $geo_rec->city);
    print_xtra('Region', $geo_rec->region || '');

    our %hosts = ();
    my $match_type = '';

    # match by AS
    foreach my $match (@{$rdb->{'AS'}{$as}}) {
	next unless (mirror_is_in_continent($rdb, $match, $continent));

	$match_type = 'AS' if (consider_mirror ($match));
    }

    # match by AS peer
    if (!$match_type && $as && !$ipv6 && (defined($peers_db) || ($peers_db_store && -f $peers_db_store))) {
	$peers_db ||= retrieve($peers_db_store);

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
	$res->status(503);
	return $res->finalize;
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
	if (($hosts{$h} - $hosts{$host}) <= $dev &&
	    (scalar(@close_hosts) < 4 || $hosts{$h} == $hosts{$close_hosts[-1]})) {
	    push @close_hosts, $h;
	} else {
	    # the list is sorted, if we didn't accept this one won't accept
	    # the next
	    last;
	}
    }

    if (defined($req->header('Range')) && scalar(@close_hosts) > 1) {
	my @favorable_hosts;
	for my $id (@close_hosts) {
	    push @favorable_hosts, $id
		if (mirror_supports_ranges($db, $id, $mirror_type));
	}
	if (scalar(@favorable_hosts)) {
	    @close_hosts = @favorable_hosts;
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
	$res->status(200);
	$res->header('Cache-control', 'no-cache');
	$res->header('Pragma', 'no-cache');
    } elsif ($action eq 'list') {
	$res->status(200);
	$res->content_type('text/plain');
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
	my @link_headers;
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

	    push @link_headers, "<".url_for_mirror($host).$url.">; rel=duplicate; pri=$priority; depth=$depth";
	}
	my $link_header = join(', ', @link_headers);
	if ($action ne 'demo') {
	    # Pre-wheezy versions of APT break on header lines of >= 360
	    # bytes, so ensure we don't exceed that limit. This can be
	    # safely removed if/when those versions are not/no longer
	    # supported
	    while (length($link_header) > 355) {
		pop @link_headers;
		$link_header = join(', ', @link_headers);
	    }
	}
	$res->header('Link' => $link_header);
    }

    $res->body(\@output);
    return $res->finalize;

    sub fullfils_request($$) {
	my ($rdb, $id) = @_;

	my $mirror = $db->{'all'}{$id};

	return 0 if (exists($mirror->{$mirror_type.'-disabled'}));

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
	$res->header("X-$_[0]", $_[1])
	    if ($xtra_headers);
    }

    sub consider_mirror($) {
	my ($id) = @_;

	my $mirror = $db->{'all'}{$id};

	return 0 unless fullfils_request($db->{$mirror_type}, $id);

	$hosts{$id} = Mirror::Math::calculate_distance($mirror->{'lon'}, $mirror->{'lat'},
					$lon, $lat);
	return 1;
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
		    $res->header('X-Sendfile', $real_url);
		    $internal_subreq = 1;
		} elsif ($subrequest_method eq 'sendfile1.4') {
		    $res->header('X-LIGHTTPD-send-file', $real_url);
		    $internal_subreq = 1;
		} elsif ($subrequest_method eq 'accelredirect') {
		    $res->header('X-Accel-Redirect', $real_url);
		    $internal_subreq = 1;
		} else {
		    # do nothing special, will redirect
		}

		if ($internal_subreq) {
		    $res->header('Content-Location', $real_url);
		    return;
		}
	    }
	}

	$res->content_type('text/plain');
	my $rcode;
	if ($permanent_redirect) {
	    $rcode = 301;
	} else {
	    $rcode = 302;
	}
	$res->redirect(url_for_mirror($host).$real_url, $rcode);
	return;
    }

}

sub clean_url($) {
    my $url = shift;
    $url =~ s,//,/,g;
    $url =~ s,^/,,;
    $url =~ s,^\.\.?/,,g;
    $url =~ s,(?<=/)\.\.?(?:/|$),,g;
    $url = uri_escape($url);
    $url =~ s,%2F,/,g;
    $url =~ s,%20,+,g;
    return $url;
}

sub mirror_is_in_continent($$$) {
    my ($rdb, $id, $continent) = @_;

    return (exists($rdb->{'continent'}{$continent}{$id}));
}

sub mirror_supports_ranges($$$) {
    my ($db, $id, $type) = @_;

    return (exists($db->{'all'}{$id}{$type.'-ranges'}));
}

sub set_local_ip {
    my $self = shift;
    my $translation = shift;

    if (ref $translation ne 'CODE') {
	my $ip = $translation;
	$translation = sub { return $ip; };
    }

    $self->{'local_ip'} = $translation;
    return;
}

sub get_local_ip {
    my $self = shift;
    my $req = shift;

    if (defined($self->{'local_ip'})) {
	return $self->{'local_ip'}($req);
    } else {
	return $self->_query_remote_ip;
    }
}

sub _query_remote_ip {
    my $self = shift;
    my $ip;

    if (defined($ENV{'HARNESS_ACTIVE'})) {
	$ip = '4.4.4.4';
    } else {
	$ip = `wget -O- -q http://myip.dnsomatic.com/`;
    }

    $self->set_local_ip($ip) if ($ip);
    return $ip;
}

1;
