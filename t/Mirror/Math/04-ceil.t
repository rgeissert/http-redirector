#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 4;

use Mirror::Math;

is(Mirror::Math::ceil(0), 0, 'ceil of 0');
is(Mirror::Math::ceil(0.6), 1, 'ceil of 0.6');
is(Mirror::Math::ceil(0.1), 1, 'ceil of 0.1');
is(Mirror::Math::ceil(2), 2, 'ceil of 2');
