#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 2;

use Mirror::Math;

is(Mirror::Math::stddevp(1, 1, 1), 0, 'stddev of equals is 0');
is(Mirror::Math::stddevp(1, -1), 1, 'stddevp of 1 and -1 is 1');
