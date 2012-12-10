#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 7;

use Mirror::RateLimiter;

my ($rtltr, $rtltr_store);

#####
$rtltr = Mirror::RateLimiter->load(\$rtltr_store);
eval {
    $rtltr->record_failure;
};
isnt($@, '', "A failure can't be recorded without first calling should_skip");
#####


#####
$rtltr_store = undef;
$rtltr = Mirror::RateLimiter->load(\$rtltr_store);

ok(!$rtltr->should_skip, 'We should not skip, there has been no failure');
$rtltr->record_failure;
$rtltr->save;

# One-time failure tolerance
ok(!$rtltr->should_skip, 'We should not skip, there has been only one failure');
$rtltr->record_failure;
$rtltr->save;

ok($rtltr->should_skip, 'We should skip 1/1, there have been two failures');
eval {
    $rtltr->record_failure;
};
isnt($@, '', "A failure can't be recorded if it should have been skipped");
#####


#####
$rtltr_store = undef;
$rtltr = Mirror::RateLimiter->load(\$rtltr_store);

ok(!$rtltr->should_skip, 'We should not skip, there has been no failure');
$rtltr->record_failure;
$rtltr->save;

eval {
    $rtltr->record_failure;
};
isnt($@, '', "A failure can't be recorded without first calling should_skip");
#####
