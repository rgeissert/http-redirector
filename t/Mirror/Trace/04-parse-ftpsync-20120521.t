#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 20;

use Mirror::Trace;
use LWP::UserAgent;

my $trace = Mirror::Trace->new(LWP::UserAgent->new(), 'http://0.0.0.0/');

my $trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: i386 amd64
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1330334034, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: FULL
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1330334034, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: COMMON:{i386 amd64} s390
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1330334034, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: COMMON:{i386 amd64} s390
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1330334034, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: GUESSED:{ i386 amd64 source}
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1330334034, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');
