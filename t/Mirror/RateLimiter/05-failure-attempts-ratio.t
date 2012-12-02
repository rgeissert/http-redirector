#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 7;

use Mirror::RateLimiter;

my ($rtltr, $rtltr_store);

$rtltr = Mirror::RateLimiter->load(\$rtltr_store);

ok(!$rtltr->should_skip, 'We should not skip, there has been no failure');
$rtltr->record_failure;
$rtltr->save;

# Allow a one-time failure tolerance
ok(!$rtltr->should_skip, 'We should not skip, there has been only one failure');
$rtltr->record_failure;
$rtltr->save;

ok($rtltr->should_skip, 'We should skip 1/1, there have been two failures');
$rtltr->save;

ok(!$rtltr->should_skip, 'We should no longer skip, we skipped once already');
$rtltr->record_failure;
$rtltr->save;

ok($rtltr->should_skip, 'We should skip 1/2, again');
$rtltr->save;

ok($rtltr->should_skip, 'We should skip 2/2, again');
$rtltr->save;

ok(!$rtltr->should_skip, 'We should no longer skip');
$rtltr->record_failure;
$rtltr->save;
