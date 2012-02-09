#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 6;

use Mirror::Math;

is($Mirror::Math::METRIC, 'taxicab', 'default metric is taxicab');
is(Mirror::Math::calculate_distance(0, 0, 0, 0), 0, 'distance from (0,0) is (0,0)');
is(Mirror::Math::calculate_distance(0, 1, 1, 0), 2, '(0, 1) to (1, 0) in taxicab is 2');

ok(Mirror::Math::set_metric('euclidean'), 'can set metric to euclidean');
is(Mirror::Math::calculate_distance(0, 0, 0, 0), 0, 'distance from (0,0) is (0,0)');
is(Mirror::Math::calculate_distance(0, 0, 3, 0), 3, '(0, 0) to (3, 0) in euclidean is 3');
