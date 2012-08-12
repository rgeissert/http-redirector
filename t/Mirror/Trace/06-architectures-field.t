#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 17;

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
ok($trace->arch('i386'), 'It includes i386');
ok($trace->arch('amd64'), 'It includes amd64');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: FULL
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->arch('i386'), 'It includes i386');
ok($trace->arch('foo'), 'It includes "foo" (all of them)');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: COMMON:{i386 amd64} s390
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->arch('i386'), 'It includes i386');
ok($trace->arch('amd64'), 'It includes amd64');
ok($trace->arch('s390'), 'It includes s390');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: GUESSED:{ i386 amd64 source}
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->arch('i386'), 'It includes i386');
ok($trace->arch('amd64'), 'It includes amd64');
ok($trace->arch('source'), 'It includes source');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: i386 s390x
Upstream-mirror: my.upstream.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok(!$trace->arch('amd64'), 'It does not include amd64');
ok(!$trace->arch('s390'), 'It does not include s390');
