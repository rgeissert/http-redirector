#!/usr/bin/perl -w

use strict;
use warnings;
use Storable qw(retrieve);
use Data::Dumper;

$Data::Dumper::Purity = 1;

my $db = 'db';

$db = $ARGV[0] if (defined($ARGV[0]));

print Dumper(retrieve($db));
