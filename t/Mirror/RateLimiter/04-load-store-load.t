#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 14;

use Mirror::RateLimiter;

my ($rtltr, $rtltr_store);

$rtltr = Mirror::RateLimiter->load(\$rtltr_store);

can_ok($rtltr, 'record_failure');
can_ok($rtltr, 'attempts');

is($rtltr->attempts, 0, 'No attempt has been recorded');
ok(!$rtltr->should_skip, 'Therefore, we should not skip');
is($rtltr->attempts, 1, 'Now one attempt has been recorded');

$rtltr->record_failure;


# Explicit save before re-loading state
$rtltr->save;
$rtltr = Mirror::RateLimiter->load(\$rtltr_store);
is($rtltr->attempts, 1, 'One attempt has been recorded');
ok(!$rtltr->should_skip, 'We should not skip, this is the second attempt');
is($rtltr->attempts, 2, 'Two attempts have been recorded');

$rtltr->record_failure;


# [again] Explicit save before re-loading state
$rtltr->save;
$rtltr = Mirror::RateLimiter->load(\$rtltr_store);
is($rtltr->attempts, 2, 'Two attempts have been recorded');
ok($rtltr->should_skip, 'We should skip, this is the third attempt');
is($rtltr->attempts, 3, 'Three attempts have been recorded');


# [again] Explicit save before re-loading state
$rtltr->save;
$rtltr = Mirror::RateLimiter->load(\$rtltr_store);
is($rtltr->attempts, 3, 'Three attempts have been recorded');
ok(!$rtltr->should_skip, 'We should not skip, this is the fourth attempt');
is($rtltr->attempts, 4, 'Four attempts have been recorded');
