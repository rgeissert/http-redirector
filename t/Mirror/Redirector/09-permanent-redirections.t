#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2;
use Plack::Test;
use HTTP::Request::Common;

use Mirror::Redirector;

my $app = Mirror::Redirector->new;

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res;

    $res = $cb->(GET "/?url=pool/main/d/dpkg/dpkg_1.16.9_i386.deb");
    is($res->code, 301, "The request was a permanent redirection");

    $res = $cb->(GET "/?url=dists/sid/main/binary-i386/Packages.gz");
    like($res->code, qr/^30[27]$/, "The request was a temporary redirection");
};
