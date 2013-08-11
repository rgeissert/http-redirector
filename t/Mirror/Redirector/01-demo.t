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
    my $res = $cb->(GET "/?action=demo");
    is($res->code, 200, "The request was 200/successful");
    like($res->header('pragma'), qr/no-cache/i, "Pragma: no-cache");
};
