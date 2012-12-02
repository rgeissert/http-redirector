#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 25;

use Mirror::RateLimiter;

my ($rtltr, $rtltr_store);

$rtltr = Mirror::RateLimiter->load(\$rtltr_store);

ok(!$rtltr->should_skip, 'We should not skip, there has been no failure');
$rtltr->record_failure;
$rtltr->save;

# One-time failure tolerance
ok(!$rtltr->should_skip, 'We should not skip, there has been only one failure');
$rtltr->record_failure;
$rtltr->save;

ok($rtltr->should_skip, 'We should skip 1/1, there have been two failures');
$rtltr->save;

ok(!$rtltr->should_skip, 'We should not skip, there have been two failures');
$rtltr->record_failure;
$rtltr->save;

ok($rtltr->should_skip, 'We should skip 1/2, there have been two failures');
$rtltr->save;
ok($rtltr->should_skip, 'We should skip 2/2, there have been two failures');
$rtltr->save;

ok(!$rtltr->should_skip, 'We should not skip, there have been two failures');
$rtltr->save;

is($rtltr->attempts, 0, "Last attempt was a success, rtltr should be reset");
ok(!$rtltr->should_skip, 'We should not skip, no failure was recorded in the last attempt');

# Simulate a bunch of successful attempts...
for my $i (1..10) {
    $rtltr->save;
    ok(!$rtltr->should_skip, 'We should not skip, no failure was recorded in the last attempt');
}
# With the last one actually failing:
$rtltr->record_failure;
$rtltr->save;

# One-time failure tolerance
ok(!$rtltr->should_skip, 'We should not skip, there has been only one failure');
$rtltr->record_failure;
$rtltr->save;

ok($rtltr->should_skip, 'We should skip 1/1, there have been two failures');
$rtltr->save;

ok(!$rtltr->should_skip, 'We should not skip, there have been two failures');
$rtltr->record_failure;
$rtltr->save;

ok($rtltr->should_skip, 'We should skip 1/2, there have been three failures');
$rtltr->save;
ok($rtltr->should_skip, 'We should skip 2/2, there have been three failures');
$rtltr->save;

ok(!$rtltr->should_skip, 'We should not skip, there have been three failures');
$rtltr->record_failure;
$rtltr->save;
