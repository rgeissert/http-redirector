#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Plack::Test;
use HTTP::Request::Common;

use Mirror::Redirector;

my @requests = (
    'project/trace/ftp-master.debian.org' => 'project/trace/ftp-master.debian.org',
    '/project/trace/ftp-master.debian.org' => 'project/trace/ftp-master.debian.org',
    'project/trace//ftp-master.debian.org' => 'project/trace/ftp-master.debian.org',
    'project%2Ftrace%2Fftp-master.debian.org' => 'project/trace/ftp-master.debian.org',
    # TODO:
#    'project/trace/../trace/ftp-master.debian.org' => 'project/trace/ftp-master.debian.org',
    # Current behaviour:
    'project/trace/../ftp-master.debian.org' => 'project/trace/ftp-master.debian.org',
    'project/trace/.//../ftp-master.debian.org' => 'project/trace/ftp-master.debian.org',
    'project/trace/%2C' => 'project/trace/%2C',
    'project/%0D%0AAnother-header:foo' => 'project/%0D%0AAnother-header%3Afoo',
    '../foo' => 'foo',
);

plan tests => scalar(@requests);

my $app = Mirror::Redirector->new;

test_psgi app => sub { $app->run(@_) }, client => sub {
    my $cb  = shift;
    my $res;

    while (@requests) {
	my ($url_sent, $url_expected) = (shift @requests, shift @requests);

	$res = $cb->(GET "/?action=demo&url=$url_sent");
	is($res->code, 200, 'The request was successful');
	is($res->header('X-URL'), $url_expected, 'The url parameter is correctly escaped');
    }
};
