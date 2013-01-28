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
    my $res = $cb->(HEAD '/', x_web_demo => 'yeah');
    is($res->code, 200, 'The request was successful');
    is($res->header('X-IP'), '4.4.4.4', 'The default IP for tests is 4.4.4.4');
};
