#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 1;

use Mirror::Math;

my $d = Mirror::Math::calculate_distance('2.0000', '46.0000', '1.4333', '43.6000');

eval {
    is(Mirror::Math::stddevp($d, $d, $d, $d, $d, $d), 0, 'stddev six times $d is 0');
} or fail($@);
