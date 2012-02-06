#!/usr/bin/perl -w

use strict;
use warnings;
use Storable qw(store);

my $db_output = 'db';
my $file = $ARGV[0];

my $db;
my $VAR1;

die ("failed to import '$file'") unless ($db = do $file);

store ($db, $db_output.'.new')
    or die ("failed to store to $db_output.new: $!");
rename ($db_output.'.new', $db_output)
    or die("failed to rename $db_output.new: $!");

