#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

use Mirror::Request;

my @tests = (
    'pool/main/d/dpkg/dpkg_1.15.8.13_i386.deb' => 'i386',
    'pool/main/d/dpkg/dpkg_1.15.8.13_amd64.deb' => 'amd64',
    'dists/sid/main/binary-ia64/Packages.gz' => 'ia64',
    'dists/sid/main/installer-powerpc/current/images/udeb.list' => 'powerpc',
    'indices/files/components/arch-i386.list.gz' => 'i386',
    'indices/files/arch-alpha.files' => 'alpha',
    'dists/sid/main/binary-i386/Packages.diff/Index' => 'i386',
    'dists/sid/main/Contents-armel.diff/Index' => 'armel',
    'dists/sid/main/Contents-armel.gz' => 'armel',
    'dists/sid/Contents-hurd-i386.gz' => 'hurd-i386',
    'dists/sid/main/Contents-udeb-ia64.gz' => 'ia64',
    'pool/main/d/dpkg/dpkg_1.15.8.13.dsc' => 'source',
    'pool/main/d/dpkg/dpkg_1.15.8.13.tar.bz2' => 'source',
    'pool/main/d/dpkg/dpkg_1.16.10.tar.xz' => 'source',
    'pool/main/d/dpkg/libdpkg-perl_1.15.8.13_all.deb' => 'all',
    'pool/main/l/le/le_1.14.3-1.diff.gz' => 'source',
    'pool/main/l/le/le_1.14.9-2.debian.tar.gz' => 'source',
    'pool/main/l/le/le_1.14.9.orig.tar.gz' => 'source',
);

plan tests => (scalar(@tests)/2 + 1);

can_ok('Mirror::Request', 'get_arch');

while (@tests) {
    my ($req, $arch) = (shift @tests, shift @tests);
    is(Mirror::Request::get_arch($req), $arch, "The architecture of the file is $arch");
}
