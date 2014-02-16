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

use Getopt::Long;

sub get_mirror($);

my $db_store = '';
my $translate_id = 1;
my $translate_type = 0;
my $generate_url = 0;

GetOptions('db|mirrors-db=s' => \$db_store,
	    'i|translate-id!' => \$translate_id,
	    't|translate-type!' => \$translate_type,
	    'u|generate-url!' => \$generate_url) or exit 1;

if ($generate_url) {
    $translate_id = 1;
    $translate_type = 1;
}

$| = 1;

our $db;

while (<>) {
    if ($. == 1) {
	if (m/^{db:([^}]+)}$/) {
	    $db_store = $1;
	    $_ = '';
	}
	$db = retrieve($db_store || 'db');
    }
    if (s,^\[(\w+)/(\w+)\],,) {
	my ($id, $type) = ($1, $2);
	my $replacement = $id;

	if ($translate_id) {
	    die "unknown site $id"
		unless (get_mirror($id));
	    $replacement = get_mirror($id)->{'site'};
	}
	if ($translate_type) {
	    die "unknown type $type"
		unless (exists(get_mirror($id)->{"$type-http"}));
	    $replacement .= get_mirror($id)->{"$type-http"};
	} else {
	    $replacement .= "/$type";
	}
	if ($generate_url) {
	    $replacement = 'http://'.$replacement;
	}
	print "[$replacement]";
	print;
    } else {
	print;
    }
}

sub get_mirror($) {
    my $id = shift;

    if (exists($db->{'ipv4'}{'all'}{$id})) {
	return $db->{'ipv4'}{'all'}{$id};
    } elsif (exists($db->{'ipv6'}{'all'}{$id})) {
	return $db->{'ipv6'}{'all'}{$id};
    } else {
	return;
    }
}
