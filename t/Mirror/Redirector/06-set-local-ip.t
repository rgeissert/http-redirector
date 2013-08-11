#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 9;
use Plack::Test;
use HTTP::Request::Common;

use Mirror::Redirector;

my $app = Mirror::Redirector->new;

can_ok($app, qw'set_local_ip get_local_ip');

# Requests from 127.0.0.1 are translated as if they'd come from 8.8.8.8
$app->set_local_ip('8.8.8.8');
is($app->get_local_ip('127.0.0.1'), '8.8.8.8', '127.0.0.1 is now translated to 8.8.8.8');

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res = $cb->(GET '/?action=demo');
    is($res->code, 200, 'The request was successful');
    is($res->header('X-IP'), '8.8.8.8', 'The local IP was translated to 8.8.8.8');
};

# Now as if they'd come from 8.8.4.4
$app->set_local_ip('8.8.4.4');
is($app->get_local_ip('127.0.0.1'), '8.8.4.4', '127.0.0.1 is now translated to 8.8.4.4');

# Now using a user-defined function
# This is mainly for use in tests and locally-run instances (where one
# can modify the application), as M::Redirector only calls get_local_ip
# on 127.0.0.1. It can, for example, be used to respect x-forwarded-for
$app->set_local_ip(sub {
    my $req = shift;
    if ($req->header('x-forwarded-for')) {
	return $req->header('x-forwarded-for');
    }
    return '8.8.8.8';
});

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res = $cb->(GET '/?action=demo');
    is($res->code, 200, 'The request was successful');
    is($res->header('X-IP'), '8.8.8.8', 'The local IP was translated to 8.8.8.8');
};

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res = $cb->(GET '/?action=demo', x_forwarded_for => '8.8.4.4');
    is($res->code, 200, 'The request was successful');
    is($res->header('X-IP'), '8.8.4.4', 'The local IP was translated to 8.8.4.4');
};
