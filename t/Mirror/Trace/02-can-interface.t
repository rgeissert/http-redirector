#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 1;

use Mirror::Trace;

can_ok('Mirror::Trace', qw(fetch date uses_ftpsync good_ftpsync));
