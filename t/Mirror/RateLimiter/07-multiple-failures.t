#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 3;

use Mirror::RateLimiter;

my ($rtltr, $rtltr_store);

$rtltr = Mirror::RateLimiter->load(\$rtltr_store);
$rtltr->should_skip;
eval {
    ok($rtltr->record_failure, 'record_failure can be called once');
    ok($rtltr->record_failure, 'record_failure can be called twice');
};
is($@, '', "record_failure can be called multiple times");
