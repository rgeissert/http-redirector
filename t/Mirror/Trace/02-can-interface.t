#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 1;

use Mirror::Trace;

can_ok('Mirror::Trace', qw(get_url from_string date uses_ftpsync good_ftpsync));
