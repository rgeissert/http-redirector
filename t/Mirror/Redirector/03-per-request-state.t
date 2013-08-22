#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 6;
use Plack::Test;
use HTTP::Request::Common;

use Mirror::Redirector;

my $app = Mirror::Redirector->new;

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res;

    $res = $cb->(GET "/?mirror=archive.list&arch=foobar");
    ok($res->is_error, "Request for the 'foobar' architecture is an error");

    $res = $cb->(GET "/?url=pool/main/d/dpkg/dpkg_1.16.9_i386.deb");
    like($res->code, qr/^30[127]$/, "The request was a redirection");
};

# Reset the app
$app = Mirror::Redirector->new;

# FIXME: to reproduce the error the second request must not be
# satisfied by the mirror(s) in the first request.
test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res;

    $res = $cb->(GET "/?mirror=archive&url=pool/main/d/dpkg/dpkg_1.16.9_i386.deb");
    like($res->code, qr/^30[127]$/, "The request was a redirection");
    like($res->header('location'), qr</pool/>, "Pool path is correctly formed");

    $res = $cb->(GET "/?mirror=backports&url=pool/main/d/dpkg/dpkg_1.16.9_i386.deb");
    like($res->code, qr/^30[127]$/, "The request was a redirection");
    like($res->header('location'), qr</pool/>, "Pool path is correctly formed");
};
