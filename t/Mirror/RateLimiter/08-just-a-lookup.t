#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 5;

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
    # Now just look up the number of attempts
    my $rtltr = Mirror::RateLimiter->load(\$rtltr_store);
    is($rtltr->attempts, 1, 'One attempt has been recorded');
    $rtltr->save;
}

{
    my $rtltr = Mirror::RateLimiter->load(\$rtltr_store);
    is($rtltr->attempts, 1, 'Still only one attempt has been recorded');
}
