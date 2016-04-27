#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 10;

use Mirror::Trace;

my $trace = Mirror::Trace->new('http://0.0.0.0/');

my $trace_data = <<EOF;
Wed Apr 27 15:39:01 UTC 2016
Using dak v1
Running on host: franck.debian.org
Archive serial: 2016042703
Date: Wed, 27 Apr 2016 15:39:01 +0000
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
is($trace->date, 1461771541, 'Parsed date is correct');

$trace_data = <<EOF;
Wed Apr 27 15:56:37 UTC 2016
Date: Wed, 27 Apr 2016 15:56:37 +0000
Date-Started: Wed, 27 Apr 2016 15:50:51 +0000
Archive serial: 2016042703
Used ftpsync version: 20150425
Running on host: arrakis.carnet.hr
Architectures: GUESSED:{ source amd64 arm64 armel armhf hurd-i386 i386 ia64 kfreebsd-amd64 kfreebsd-i386 mips mipsel powerpc ppc64el s390 s390x sparc}
Upstream-mirror: syncproxy2.eu.debian.org
Total bytes received in rsync: 5116226559
Total time spent in stage1 rsync: 258
Total time spent in stage2 rsync: 88
Total time spent in rsync: 346
Average rate: 14786781 B/s
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
is($trace->date, 1461772597, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');

$trace_data = <<EOF;
Wed Apr 27 15:50:50 UTC 2016
Date: Wed, 27 Apr 2016 15:50:50 +0000
Date-Started: Wed, 27 Apr 2016 15:42:08 +0000
Archive serial: 2016042703
Used ftpsync version: 20160306
Running on host: klecker.debian.org
Architectures: all amd64 arm64 armel armhf hurd-i386 i386 ia64 kfreebsd-amd64 kfreebsd-i386 mips mips64el mipsel powerpc ppc64el s390 s390x source sparc 
Architectures-Configuration: ALL
Upstream-mirror: ftp-master.debian.org
SSL: true
Total bytes received in rsync: 5129219495
Total time spent in stage1 rsync: 473
Total time spent in stage2 rsync: 49
Total time spent in rsync: 522
Average rate: 9826090 B/s
EOF

ok($trace->from_string($trace_data), 'Parse trace data');
is($trace->date, 1461772250, 'Parsed date is correct');
ok($trace->uses_ftpsync, 'ftpync-generated trace');
ok($trace->good_ftpsync, 'Good version of ftpync is used');
