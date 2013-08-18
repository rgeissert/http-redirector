#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 5;

use Mirror::Redirection::Blackhole;

can_ok('Mirror::Redirection::Blackhole', 'should_blackhole');

eval {
    should_blackhole('', '');
    1;
} or fail($@);
pass('should_blackhole is exported');

# Should blackhole
ok(should_blackhole('dists/wheezy/main/binary-i386/Packages.xz', 'archive'),
    "wheezy didn't include .xz versions of Packages files, so blackhole them");

ok(should_blackhole('dists/squeeze/InRelease', 'archive'),
    "squeeze didn't include InRelease files, so blackhole them");

# Should not blackhole
ok(!should_blackhole('dists/wheezy/main/binary-i386/Packages.bz2', 'archive'),
    "wheezy did include .bz2 versions of Packages files, so do NOT blackhole them");
