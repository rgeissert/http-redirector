#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 3;

use Mirror::Trace;

my $trace = Mirror::Trace->new('http://0.0.0.0/');

TODO: {

local $TODO = "No real parsing is done yet";

my $trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: FULL i386
Upstream-mirror: my.upstream.tld
EOF

ok(!$trace->from_string($trace_data), 'FULL mirror but lists an arch');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: GUESSED:{foo} bar
Upstream-mirror: my.upstream.tld
EOF

ok(!$trace->from_string($trace_data), 'GUESSED archs lists with an especific arch');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
Architectures: COMMON{foo}
Upstream-mirror: my.upstream.tld
EOF

ok(!$trace->from_string($trace_data), 'Missing : after archs token');
}
