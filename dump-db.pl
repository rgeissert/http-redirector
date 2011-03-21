#!/usr/bin/perl -w

use strict;
use warnings;
use Storable qw(retrieve);
use Data::Dumper;

print Dumper(retrieve('db'));
