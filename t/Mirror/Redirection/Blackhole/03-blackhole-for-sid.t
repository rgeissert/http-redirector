#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 4;

use Mirror::Redirection::Blackhole;

ok(should_blackhole('dists/sid/main/binary-amd64/Packages.bz2', 'archive'),
    "bz2-compressed indexes are not provided for sid");

ok(should_blackhole('dists/sid/main/binary-amd64/Packages.lzma', 'archive'),
    "lzma-compressed indexes are not provided for sid");

ok(!should_blackhole('dists/sid/main/binary-amd64/Packages.gz', 'archive'),
    "gz-compressed indexes are still provided for sid");

ok(!should_blackhole('dists/sid/main/binary-amd64/Packages.xz', 'archive'),
    "xz-compressed indexes are provided for sid");
