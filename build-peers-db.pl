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

use Storable qw(retrieve);
use Mirror::AS;
use Mirror::DB;

use Getopt::Long;

my $mirrors_db_file = 'db';
my $print_progress = 0;
my $max_distance = -1;
my $db_out = 'db.peers';

GetOptions('mirrors-db=s' => \$mirrors_db_file,
	    'progress!' => \$print_progress,
	    'distance=i' => \$max_distance,
	    'store-db=s' => \$db_out);

our $mirrors_db = retrieve($mirrors_db_file);

my %mirror_ASes;

for my $type (keys %{$mirrors_db}) {
    next if ($type eq 'all');

    for my $AS (keys %{$mirrors_db->{$type}{'AS'}}) {
	$mirror_ASes{$AS} = 1;
    }
}

my %as_routes;
my $count = -1;
my %sites_index;

sub build_sites_index;

$count = 0 if ($print_progress);

while (<>) {
    # allow comments and empty lines
    next if ($_ eq '' || m/^\s*#/);

    my @parts = split;
    die "malformed input" unless (scalar(@parts) >= 2);

    my @clientsASN = shift @parts;
    my $dest = shift @parts;
    my $dist = int(shift @parts || 0);

    last unless ($max_distance == -1 || $dist < $max_distance);

    if ($clientsASN[0] =~ s/^\{// && $clientsASN[0] =~ s/\}$//) {
	@clientsASN = split (/,/, $clientsASN[0]);
    }

    # allow the destination to be specified as the domain name of the
    # mirror
    if ($dest !~ m/^(?:AS)?\d+$/) {
	%sites_index or %sites_index = build_sites_index;
	if (!exists($sites_index{$dest})) {
	    die "Unknown site $dest";
	}
	$dest = $sites_index{$dest};
    }
    $dest = Mirror::AS::convert($dest);

    next unless (exists($mirror_ASes{$dest}));

    for my $client (@clientsASN) {
	$client = Mirror::AS::convert($client);

	next if ($client eq $dest);

	$as_routes{$client} = {}
	    unless (exists($as_routes{$client}));

	my $min_dist = $dist;
	$min_dist = $as_routes{$client}->{$dest}
	    if (exists($as_routes{$client}->{$dest}) && $as_routes{$client}->{$dest} < $min_dist);
	$as_routes{$client}->{$dest} = $min_dist;
    }

    if ($count != -1 && ($count++)%1000 == 0) {
	print STDERR "Processed: $count...\r";
    }
}

Mirror::DB::set($db_out);
Mirror::DB::store(\%as_routes);

# Build a map[site]=>ASN
# Perhaps a new attribute could be added to every site so that theere's
# no need to traverse multiple indexes.
sub build_sites_index {
    my %id2site;
    my %site2ASN;
    for my $id (keys %{$mirrors_db->{'all'}}) {
	$id2site{$id} = $mirrors_db->{'all'}{$id}{'site'};
    }
    for my $type (keys %{$mirrors_db}) {
	next if ($type eq 'all');
	for my $ASN (keys %{$mirrors_db->{$type}{'AS'}}) {
	    for my $id (@{$mirrors_db->{$type}{'AS'}{$ASN}}) {
		$site2ASN{$id2site{$id}} = $ASN;
	    }
	}
    }
    return %site2ASN;
}
