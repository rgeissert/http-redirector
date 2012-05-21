#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 4;

use Mirror::Trace;
use LWP::UserAgent;

my $trace = Mirror::Trace->new(LWP::UserAgent->new(), 'http://0.0.0.0/');

my $trace_data = <<EOF;
Mon May 21 15:24:37 UTC 2012
Used ftpsync version: 80486
Running on host: ftp.halifax.RWTH-Aachen.DE
Architectures: GUESSED:{ source amd64 armel armhf hurd-i386 i386 ia64 kfreebsd-amd64 kfreebsd-i386 mips mipsel powerpc s390 s390x sparc}
Upstream-mirror: syncproxy2.eu.debian.org
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1337613877, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync trace');
ok(!$trace->good_ftpsync, 'broken ftpsync');
