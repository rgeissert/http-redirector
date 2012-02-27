#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 11;

use Mirror::Trace;
use LWP::UserAgent;

my $trace = Mirror::Trace->new(LWP::UserAgent->new(), 'http://0.0.0.0/');

my $trace_data = <<EOF;
Mon Feb 27 16:13:04 UTC 2012
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1330359184, 'Parsed date is correct');
ok(!$trace->uses_ftpsync, 'Not an ftpync trace');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 80387
Running on host: my.host.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1330334034, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');

$trace_data = <<EOF;
Mon Feb 27 15:26:15 UTC 2012
Used ftpsync-pushrsync from: rietz.debian.org
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1330356375, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-pushrsync is ftpsync');
ok($trace->good_ftpsync, 'ftpync-pushrsync is always good');
