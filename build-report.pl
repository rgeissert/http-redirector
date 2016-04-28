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

sub print_note;

our $print_note_block;
my $db_store = 'db';

GetOptions('db-store=s' => \$db_store);

my $db = retrieve($db_store);

my %tags_bad = (
	"badmaster"		=> "Bad master trace",
	"badsite"		=> "Bad site trace",
	"badsubset"		=> "In a too old, new, or incomplete subset",
	"stages-disabled"	=> "Doesn't perform two-stages sync",
	"archcheck-disabled"	=> "Missing all architectures, or source packages",
	"areascheck-disabled"	=> "Missing archive areas (main, contrib, or non-free)",
	"file-disabled"		=> "Blacklisted",
	"notinrelease"		=> "Not reliable for serving InRelease files",
	"noti18n"		=> "Not reliable for serving i18n/ files",
	"oldftpsync"		=> "Too old ftpsync",
	"oldsite"		=> "Site trace older than master, possibly syncing",
);

my %tags_good = (
	"ranges"		=> "Doesn't seem to support Range requests",
	"keep-alive"		=> "Doesn't seem to support Keep-Alive connections",
);

print "Mirrors db report\n";
print "=================\n";

for my $ipv (sort keys %{$db}) {
    next unless (ref($db->{$ipv}) && exists($db->{$ipv}{'all'}));

    my $ldb = $db->{$ipv};
    my $postfix = '';
    $postfix = "-$ipv" if ($ipv ne 'ipv4');

    for my $id (sort keys %{$ldb->{'all'}}) {
	my $mirror = $ldb->{'all'}{$id};
	my @mirror_types;

	print "\nMirror: $mirror->{site}$postfix\n";

	for my $k (keys %$mirror) {
	    next unless ($k =~ m/^(.+)-http$/);
	    push @mirror_types, $1;
	}
	for my $type (sort @mirror_types) {
	    $print_note_block = 1;
	    print "- Type: $type\n";
	    print "  Status: ",(exists($mirror->{"$type-disabled"})?"disabled":"enabled"),"\n";
	    print "  State: ",(($mirror->{"$type-state"} eq "syncing")?"syncing":"synced"),"\n"
		if (defined($mirror->{"$type-state"}));
	    print "  Path: ",$mirror->{"$type-http"},"\n";

	    foreach my $k (sort keys (%tags_bad)) {
		    print_note $tags_bad{$k}
			    if (exists($mirror->{$type.'-'.$k}));
	    }

	    foreach my $k (sort keys (%tags_good)) {
		    print_note $tags_good{$k}
			    if (!exists($mirror->{$type.'-'.$k}));
	    }

	    if (defined($mirror->{"$type-master"}) and defined($mirror->{"$type-site"})) {
		my $delay = int(($mirror->{"$type-site"} - $mirror->{"$type-master"})/60);
		my $last_update = localtime($mirror->{"$type-site"});
		print_note "Last update: $last_update";
		print_note "Sync delay: $delay min";
	    }

	    for my $key (keys %{$mirror}) {
		next unless ($key =~ m/^\Q$type-\E/);
		if ($key =~ m/^\Q$type-\E(.+?)(-trace)?-disabled$/) {
		    my $arch = $1;
		    next if (exists($mirror->{$type.'-archcheck-disabled'}));
		    next unless (exists($ldb->{$type}{'arch'}{$arch}));

		    # If disabled by trace file:
		    if (defined($2)) {
			print_note "Dropped architecture: $arch, but listed";
		    # Don't report it twice:
		    } elsif (!exists($mirror->{"$type-$arch-trace-disabled"})) {
			print_note "Missing architecture: $arch, but listed";
		    }
		}
	    }
	}
    }
}

sub print_note {
    my $note = shift;
    if ($print_note_block) {
	print "  Notes:\n";
	$print_note_block = 0;
    }
    print "   $note\n";
}
