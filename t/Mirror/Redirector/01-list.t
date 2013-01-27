#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 3;
use Plack::Test;
use HTTP::Request::Common;

use Mirror::Redirector;

my $app = Mirror::Redirector->new;

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res;

    $res = $cb->(GET "/?mirror=archive.list&arch=i386");
    is($res->code, 200, "The request was 200/successful");

    $res = $cb->(GET "/?mirror=archive.list");
    is($res->code, 400, "The request was 400/bad request");

    $res = $cb->(GET "/?mirror=archive.list&arch=foobar");
    ok($res->is_error, "Request for the 'foobar' architecture is an error");
};
