#!/usr/bin/perl

use strict;
use warnings;

use Plack::Test;
use HTTP::Request::Common;

use Mirror::Redirector;

my $app = Mirror::Redirector->new;

my $params = $ARGV[0] || '';

$app->set_local_ip($ENV{'REMOTE_ADDR'})
    if (defined($ENV{'REMOTE_ADDR'}));

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res = $cb->(HEAD "/?$params");
    print $res->as_string;
};
