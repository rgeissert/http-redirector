#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 2;

use Mirror::Trace;

my $trace = Mirror::Trace->new('http://0.0.0.0/');

my $trace_data = <<EOF;
Mon Feb 27 16:13:04 UTC 2012
Using dak v1
Running on host: franck.debian.org
Archive serial: 2012022703
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
is($trace->date, 1330359184, 'Parsed date is correct');
