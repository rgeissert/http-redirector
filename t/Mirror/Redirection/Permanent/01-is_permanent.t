#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 5;

use Mirror::Redirection::Permanent;

can_ok('Mirror::Redirection::Permanent', 'is_permanent');

eval {
    is_permanent('', '');
    1;
} or fail($@);
pass('is_permanent is exported');

# Permanent
ok(is_permanent('pool/main/d/dpkg/dpkg_1.16.9_i386.deb', 'archive'),
    "a response for a deb file in pool is permanent");

ok(is_permanent('debian/dists/woody/main/binary-i386/Packages.gz', 'old'),
    "a response for any file in the 'old' archive is permanent");

# Non-permanent
ok(!is_permanent('debian/dists/sid/main/binary-i386/Packages.gz', 'archive'),
    "a response for a dists file in the main archive is NON permanent");
