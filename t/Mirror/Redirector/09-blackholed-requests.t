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

    $res = $cb->(GET "/?url=dists/squeeze/InRelease");
    is($res->code, 404, "The request was blackholed");

    $res = $cb->(GET "/?url=dists/sid/InRelease");
    like($res->code, qr/^30\d$/, "The request was a redirection");
};
