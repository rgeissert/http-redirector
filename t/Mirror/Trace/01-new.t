#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 2;

use Mirror::Trace;
use LWP::UserAgent;

my $trace;
eval {
    $trace = Mirror::Trace->new(LWP::UserAgent->new(), 'http://0.0.0.0/');
} or fail($@);
pass('Can create a new Mirror::Trace');

isa_ok($trace, 'Mirror::Trace');
