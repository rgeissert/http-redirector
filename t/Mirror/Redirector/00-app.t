#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok('Mirror::Redirector'); }

my $app;

eval {
$app = Mirror::Redirector->new;
};
is ($@, '', 'Failed to instantiate a new Mirror::Redirector');

can_ok($app, 'run');
