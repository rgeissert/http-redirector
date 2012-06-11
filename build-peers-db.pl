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
my $store_distance = 0;
my $db_out = 'db.peers';

GetOptions('mirrors-db=s' => \$mirrors_db_file,
	    'progress!' => \$print_progress,
	    'distance=i' => \$max_distance,
	    'store-distance!' => \$store_distance,
	    's|store-db=s' => \$db_out);

our $mirrors_db = retrieve($mirrors_db_file);

my %peers_db;
my $count = -1;
my %site2id;
my %AS2ids;

sub build_site2id_index;
sub build_AS2ids_index;


$count = 0 if ($print_progress);

while (<>) {
    # allow comments and empty lines
    next if ($_ eq '' || m/^\s*#/);

    my @parts = split;
    die "malformed input" unless (scalar(@parts) >= 2);

    my @clientsASN = shift @parts;
    my @dests = shift @parts;
    my $dist = int(shift @parts || 0);

    last unless ($max_distance == -1 || $dist < $max_distance);

    if ($clientsASN[0] =~ s/^\{// && $clientsASN[0] =~ s/\}$//) {
	@clientsASN = split (/,/, $clientsASN[0]);
    }

    # allow the destination to be specified as the domain name of the
    # mirror
    if ($dests[0] !~ m/^(?:AS)?\d+$/) {
	%site2id or %site2id = build_site2id_index;
	if (!exists($site2id{$dests[0]})) {
	    die "Unknown site ".$dests[0];
	}
	$dests[0] = $site2id{$dests[0]};
    } else {
	%AS2ids or %AS2ids = build_AS2ids_index;
	$dests[0] = Mirror::AS::convert($dests[0]);

	next unless (exists($AS2ids{$dests[0]}));
	@dests = @{$AS2ids{$dests[0]}};
    }

    for my $client (@clientsASN) {
	$client = Mirror::AS::convert($client);

	$peers_db{$client} = {}
	    unless (exists($peers_db{$client}));

	for my $dest (@dests) {
	    my $min_dist = undef;

	    if ($store_distance) {
		$min_dist = $dist;
		$min_dist = $peers_db{$client}->{$dest}
		    if (exists($peers_db{$client}->{$dest}) && $peers_db{$client}->{$dest} < $min_dist);
	    }
	    $peers_db{$client}->{$dest} = $min_dist;
	}
    }

    if ($count != -1 && ($count++)%1000 == 0) {
	print STDERR "Processed: $count...\r";
    }
}

Mirror::DB::set($db_out);
Mirror::DB::store(\%peers_db);

sub build_site2id_index {
    my %site2id;
    for my $id (keys %{$mirrors_db->{'all'}}) {
	$site2id{$mirrors_db->{'all'}{$id}{'site'}} = $id;
    }
    return %site2id;
}

# Build a map[AS]=>site_id
sub build_AS2ids_index {
    my %AS2site;
    for my $type (keys %{$mirrors_db}) {
	next if ($type eq 'all');
	for my $AS (keys %{$mirrors_db->{$type}{'AS'}}) {
	    for my $id (@{$mirrors_db->{$type}{'AS'}{$AS}}) {
		$AS2site{$AS} = {}
		    unless exists($AS2site{$AS});
		$AS2site{$AS}{$id} = undef;
	    }

	}
    }
    for my $AS (keys %AS2site) {
	my @ids = keys %{$AS2site{$AS}};
	$AS2site{$AS} = \@ids;
    }
    return %AS2site;
}
