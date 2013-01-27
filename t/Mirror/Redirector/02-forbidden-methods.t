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

    $res = $cb->(POST "/foo", content => 'foo');
    is($res->code, 405, "POST is not an allowed method");

    $res = $cb->(PUT "/foo");
    is($res->code, 405, "PUT is not an allowed method");
};
