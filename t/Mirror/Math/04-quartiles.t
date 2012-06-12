#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 1;

use Mirror::Math;

my @inter_iquartile = Mirror::Math::iquartile(qw(3 3 6 7 7 10 10 10 11 13 30));

is(join (',', @inter_iquartile), '6,7,7,10,10,10,11', 'inter quartile values');
