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

my $print_progress = 0;
my $max_distance = 1;
my $output_file = 'peers.lst.d/routing-table.lst';

GetOptions('progress!' => \$print_progress,
	    'distance=i' => \$max_distance,
	    'output-file=s' => \$output_file) or exit 1;

my $count = -1;

$count = 0 if ($print_progress);

sub seen;

my $out;

if ($output_file eq '-') {
    $out = \*STDOUT;
} else {
    open($out, '>', $output_file)
	or die("error: could not open '$output_file' for writing: $!\n");
}

print $out "# AS peering table\n";
print $out "# Using a maximum distance of $max_distance\n";

while (<>) {
    my @parts = split;
    next unless (scalar(@parts) >= 3);

    my @dests = pop @parts;
    # get rid of the network mask
    my $address = shift @parts;
    my $ipv = ($address =~ m/:/)? 'v6' : 'v4';

    if ($dests[0] =~ s/^\{// && $dests[0] =~ s/\}$//) {
	@dests = split (/,/, $dests[0]);
    }

    for my $dest (@dests) {
	my $distance = 0;

	my @path = @parts;
	while (my $peer = pop @path) {
	    last unless ($distance < $max_distance);
	    next if ($dest eq $peer);
	    $distance++;

	    my $output = "$dest $peer $distance $ipv";

	    print $out "$output\n" if (not seen($output));
	}
    }

    if ($count != -1 && ($count++)%1000 == 0) {
	print STDERR "Processed: $count...\r";
    }
}

my %seen_cache_index;
my @seen_cache;
sub seen {
    my $entry = shift;

    return 1 if (exists($seen_cache_index{$entry}));

    # cache up to 3 items
    if (scalar(@seen_cache) == 3) {
	delete $seen_cache_index{shift @seen_cache};
    }

    push @seen_cache, $entry;
    $seen_cache_index{$entry} = undef;
    return 0;
}
