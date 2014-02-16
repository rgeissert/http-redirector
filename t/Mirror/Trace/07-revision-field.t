#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 10;

use Mirror::Trace;

my $trace = Mirror::Trace->new('http://0.0.0.0/');

my $trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: i386 amd64
Upstream-mirror: my.upstream.tld
Revision: i18n
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
ok($trace->features('i18n'), 'Revised for i18n issue');
# Trust the revision field, not the version:
ok(!$trace->features('inrelease'), 'Revised for InRelease issue');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used my own script
Running on host: my.host.tld
Architectures: FULL
Upstream-mirror: my.upstream.tld
Revision: i18n
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
ok($trace->features('i18n'), 'Custom script revised for i18n issue');
ok(!$trace->features('inrelease'), 'Custom script not revised for InRelease issue');

$trace_data = <<EOF;
Tue Aug 14 02:56:48 UTC 2012
Used rsmir version 1
Running on host: debian.c3sl.ufpr.br
Architectures: FULL
Upstream-mirror: [2001:610:1908:b000::148:10]
Revision: i18n InRelease AUIP
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
ok($trace->features('i18n'), 'Custom script revised for i18n issue');
ok($trace->features('inrelease'), 'Custom script revised for InRelease issue');
ok($trace->features('auip'), 'Custom script revised for AUIP check');
