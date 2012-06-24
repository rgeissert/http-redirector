#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 24;

use Mirror::Trace;
use LWP::UserAgent;

my $trace = Mirror::Trace->new(LWP::UserAgent->new(), 'http://0.0.0.0/');

my $trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 80286
Running on host: my.host.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok(!$trace->features('inrelease'), '286 did not handle inrelease files');
ok(!$trace->features('i18n'), '286 did not handle i18n files');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 80387
Running on host: my.host.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->features('inrelease'), '386 handles inrelease files');
ok(!$trace->features('i18n'), '386 did not handle i18n files');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync version: 20120521
Running on host: my.host.tld
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->features('inrelease'), '20120521 handles inrelease files');
ok($trace->features('i18n'), '20120521 handles i18n files');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
Used ftpsync-pushrsync from: rietz.debian.org
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->features('inrelease'), 'pushrsync handles inrelease files');
ok($trace->features('i18n'), 'pushrsync handles i18n files');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
DMS sync dms-0.0.8-dev
Running on host: ftp.de.debian.org
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok(!$trace->features('inrelease'), 'dms 0.0.8 does not handle inrelease files');
ok(!$trace->features('i18n'), 'dms 0.0.8 does not handle i18n files');

$trace_data = <<EOF;
Mon Feb 27 09:13:54 UTC 2012
DMS sync dms-0.1
Running on host: ftp.de.debian.org
EOF

ok($trace->_parse_trace($trace_data), 'Parse trace data');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->features('inrelease'), 'dms handles inrelease files');
ok(!$trace->features('i18n'), 'dms 0.1 does not handle i18n files');
