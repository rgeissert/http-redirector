#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 2;

use Mirror::RateLimiter;

my ($rtltr, $rtltr_store);

$rtltr = Mirror::RateLimiter->load(\$rtltr_store);

can_ok($rtltr, 'should_skip');
ok(!$rtltr->should_skip, 'We should not skip, there has been no failure');
