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
use Mirror::DB;

use Getopt::Long;

my $mirrors_db_file = 'db';
my $print_progress = 0;
my $max_distance = 1;
my $db_out = 'db.peers';

GetOptions('mirrors-db=s' => \$mirrors_db_file,
	    'progress!' => \$print_progress,
	    'distance=i' => \$max_distance,
	    'store-db=s' => \$db_out);

my $mirrors_db = retrieve($mirrors_db_file);

my %mirror_ASes;

for my $type (keys %{$mirrors_db}) {
    next if ($type eq 'all');

    for my $AS (keys %{$mirrors_db->{$type}{'AS'}}) {
	$AS =~ s/^AS//;
	$mirror_ASes{$AS} = 1;
    }
}

my %as_routes;
my $count = -1;

$count = 0 if ($print_progress);

while (<>) {
    my @parts = split;
    next unless (scalar(@parts) >= 3);

    my @dests = pop @parts;
    # get rid of the network mask
    shift @parts;

    if ($dests[0] =~ s/^\{// && $dests[0] =~ s/\}$//) {
	@dests = split (/,/, $dests[0]);
    }

    for my $dest (@dests) {
	next unless (exists($mirror_ASes{$dest}));
	my $distance = 0;

	my @path = @parts;
	while (my $peer = pop @path) {
	    last unless ($distance < $max_distance);
	    next if ($dest eq $peer);
	    $distance++;

	    $as_routes{$peer} = {}
		unless (exists($as_routes{$peer}));
	    $as_routes{$peer}->{$dest} = $distance;
	}
    }

    if ($count != -1 && ($count++)%1000 == 0) {
	print STDERR "Processed: $count...\r";
    }
}

Mirror::DB::set($db_out);
Mirror::DB::store(\%as_routes);
