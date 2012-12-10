#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 6;

use Mirror::RateLimiter;

my $rtltr_store;

{
    my $rtltr = Mirror::RateLimiter->load(\$rtltr_store);

    is($rtltr->attempts, 0, 'No attempt has been recorded');
    ok(!$rtltr->should_skip, 'Therefore, we should not skip');
    is($rtltr->attempts, 1, 'One attempt has been recorded');
    $rtltr->record_failure;
    # implicit save
}

{
    my $rtltr = Mirror::RateLimiter->load(\$rtltr_store);
    is($rtltr->attempts, 1, 'One attempt has been recorded');
    ok(!$rtltr->should_skip, 'Should not skip this time');
    # auto success if we don't call record_failure
    # auto save when the object is destroyed
}

{
    my $rtltr = Mirror::RateLimiter->load(\$rtltr_store);
    is($rtltr->attempts, 0, 'The object is reset upon success');
}
