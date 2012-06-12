#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 3;

use Mirror::AS;

is(Mirror::AS::convert(1), 1, 'AS 1 converts to 1');
is(Mirror::AS::convert(2.1005), 132077, 'AS 2.1005 converts to 132077');

is(Mirror::AS::convert("AS1"), 1, '"AS1" converts to 1');
