#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 3;

use Mirror::Redirection::Blackhole;

ok(should_blackhole('dists/squeeze-lts/main/binary-armel/Packages.gz', 'archive'),
    "Squeeze lts is limited to amd64 and i386, so blackhole other archs");

ok(!should_blackhole('dists/squeeze-lts/main/binary-amd64/Packages.gz', 'archive'),
    "Squeeze lts has amd64");

ok(!should_blackhole('dists/squeeze-lts/main/binary-i386/Packages.gz', 'archive'),
    "Squeeze lts has i386");
