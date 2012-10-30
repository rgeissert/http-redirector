#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 4;

use Mirror::Trace;
use LWP::UserAgent;

my $trace = Mirror::Trace->new(LWP::UserAgent->new(), 'http://0.0.0.0/');

my $trace_data = <<EOF;
Tue Oct 30 03:25:38 GMT 2012
Used ftpsync version: 20120521
Running on host: mirror.switch.ch
Architectures: GUESSED:{ source amd64 armel i386 kfreebsd-amd64 kfreebsd-i386 sparc}
Upstream-mirror: ftp.ch.debian.org
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
is($trace->date, 1351567538, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');
