#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;
use Plack::Test;
use HTTP::Request::Common;

use Mirror::Redirector;

my $app = Mirror::Redirector->new;

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res;
    my $pdbs;

    $res = $cb->(GET '/');
    $pdbs = $Mirror::Redirector::peers_db_store;

    $res = $cb->(GET '/');
    is($Mirror::Redirector::peers_db_store, $pdbs, "The global peers_db_store is not modified");
};
