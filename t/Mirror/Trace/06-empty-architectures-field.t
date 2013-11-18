#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 10;

use Mirror::Trace;

my $trace = Mirror::Trace->new('http://0.0.0.0/');

my $trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 80286
Running on host: my.host.tld
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
# can't check if a given arch is included without an archs field
# so the right way to determine this is with:
ok(!$trace->features('architectures'), "Trace doesn't have architectures field");

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: i386 amd64
Upstream-mirror: my.upstream.tld
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
# This trace does list the architectures, so we can reliably tell
# what is included
ok($trace->features('architectures'), "Trace does have architectures field");
ok($trace->arch('i386'));

# It can also happen that it is missing
$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Upstream-mirror: my.upstream.tld
EOF

ok($trace->from_string($trace_data), 'Missing architectures field');
ok(!$trace->features('architectures'), "Trace doesn't have architectures field");

# Or empty
$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: 
Upstream-mirror: my.upstream.tld
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
ok($trace->features('architectures'), "Trace does have architectures field");
ok(!$trace->arch('i386'));
