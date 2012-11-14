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
use Storable qw(retrieve);

my $db_store = 'db';

GetOptions('db-store=s' => \$db_store);

my $db = retrieve($db_store);

print "Mirrors db report\n";
print "=================\n";

for my $id (sort keys %{$db->{'all'}}) {
    my $mirror = $db->{'all'}{$id};
    my @mirror_types;

    print "\nMirror: $mirror->{site}\n";

    for my $k (keys %$mirror) {
	next unless ($k =~ m/^(.+)-http$/);
	push @mirror_types, $1;
    }
    for my $type (@mirror_types) {
	print "Type: $type\n";
	print "Status: ",(exists($mirror->{"$type-disabled"})?"disabled":"enabled"),"\n";
	print "Path: ",$mirror->{"$type-http"},"\n";
	print "\tBad master trace\n"
	    if (exists($mirror->{$type.'-badmaster'}));
	print "\tBad site trace\n"
	    if (exists($mirror->{$type.'-badsite'}));
	print "\tMissing all architectures, or source packages\n"
	    if (exists($mirror->{$type.'-archcheck-disabled'}));
	print "\tMissing archive areas (main, contrib, or non-free)\n"
	    if (exists($mirror->{$type.'-areascheck-disabled'}));
	print "\tNot reliable for serving InRelease files\n"
	    if (exists($mirror->{$type.'-notinrelease'}));
	print "\tNot reliable for serving i18n/ files\n"
	    if (exists($mirror->{$type.'-noti18n'}));
	print "\tToo old ftpsync\n"
	    if (exists($mirror->{$type.'-oldftpsync'}));
	for my $key (keys %{$mirror}) {
	    next unless ($key =~ m/^\Q$type-\E/);
	    if ($key =~ m/^\Q$type-\E(.+?)(-trace)?-disabled$/) {
		my $arch = $1;
		next unless (exists($db->{$type}{'arch'}{$arch}));

		# If disabled by trace file:
		if (defined($2)) {
		    print "\tDropped architecture: $arch, but listed\n";
		# Don't report it twice:
		} elsif (!exists($mirror->{"$type-$arch-trace-disabled"})) {
		    print "\tMissing architecture: $arch, but listed\n";
		}
	    }
	}
    }
}
