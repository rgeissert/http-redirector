#!/usr/bin/perl -w

use strict;
use warnings;

use lib '.';
use Mirror::DB;

my $db_output = 'db';
my $file = $ARGV[0];

my $db;
my $VAR1;

die ("failed to import '$file'") unless ($db = do $file);

Mirror::DB::set($db_output);
Mirror::DB::store($db);
