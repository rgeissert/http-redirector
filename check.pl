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
use LWP::UserAgent;
use LWP::ConnCache;
use Date::Parse;
use Storable qw(retrieve store);

sub get_trace($$);
sub test_arch($$$);

my $db_store = 'db';
my $check_archs = 0;

GetOptions('check-architectures!' => \$check_archs);

my %traces;
our $ua = LWP::UserAgent->new();

$ua->timeout();
$ua->agent("MirrorChecker/0.1 ");
$ua->conn_cache(LWP::ConnCache->new());
$ua->max_redirect(1);
$ua->max_size(1024);

our $db = retrieve($db_store);

for my $id (keys %{$db->{'all'}}) {
    my $mirror = $db->{'all'}{$id};
    my @mirror_types;

    for my $k (keys %$mirror) {
	next unless ($k =~ m/^(.+)-http$/);
	push @mirror_types, $1;
    }

    for my $type (@mirror_types) {
	my $base_url = 'http://'.$mirror->{'site'}.$mirror->{$type.'-http'};
	my $trace = get_trace($base_url, $db->{$type}{'master'});

	if (!$trace) {
	    $mirror->{$type.'-disabled'} = undef;
	    print "Disabling $id/$type: bad trace\n";
	    next;
	} else {
	    print "Re-enabling $id/$type\n"
		if (exists($mirror->{$type.'-disabled'}));
	     delete $mirror->{$type.'-disabled'};
	}

	$traces{$type} = {}
	    unless (exists($traces{$type}));
	$traces{$type}{$trace} = []
	    unless (exists($traces{$type}{$trace}));
	push @{$traces{$type}{$trace}}, $id;

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

store ($db, $db_store.'.new')
    or die ("failed to store to $db_store.new: $!");
rename ($db_store.'.new', $db_store)
    or die("failed to rename $db_store.new: $!");

sub get_trace($$) {
    my ($base_url, $master) = @_;
    my $req_url = $base_url.'project/trace/'.$master;

    my $response = $ua->get($req_url);
    return unless ($response->is_success);

    my $trace = $response->decoded_content;
    my ($date) = split /\n/,$trace,2;

    return
	unless ($date =~ m/^\w{3} \w{3} \d{2} (?:\d{2}:){2}\d{2} UTC \d{4}$/);
    
    return str2time($date);
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

    return 0 if (!$response->is_success);
    return ($response->header('Content-Type') ne 'text/html');
}
