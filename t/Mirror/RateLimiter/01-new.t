#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 2;

use Mirror::RateLimiter;

my ($rtltr, $rtltr_store);

eval {
    $rtltr = Mirror::RateLimiter->load(\$rtltr_store);
} or fail($@);
pass('Can create a new Mirror::RateLimiter');

isa_ok($rtltr, 'Mirror::RateLimiter');
