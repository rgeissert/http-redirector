#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 9;

use Mirror::RateLimiter;

my ($rtltr, $rtltr_store);

$rtltr = Mirror::RateLimiter->load(\$rtltr_store);

is($rtltr->attempts, 0, '0 attempts so far');
ok(!$rtltr->should_skip, 'We should not skip, there has been no failure');

$rtltr->record_failure;

# Save the status, to allow the object to be reused
can_ok($rtltr, 'save');
$rtltr->save;

# Allow a one-time failure tolerance
is($rtltr->attempts, 1, '1 attempt');
ok(!$rtltr->should_skip, 'We should not skip, there has been only one failure');

$rtltr->record_failure;
$rtltr->save;

is($rtltr->attempts, 2, '2 attempts');
ok($rtltr->should_skip, 'We should skip, there have been two failures');
$rtltr->save;

is($rtltr->attempts, 3, '3 attempts');
ok(!$rtltr->should_skip, 'We should no longer skip, we skipped once already');
