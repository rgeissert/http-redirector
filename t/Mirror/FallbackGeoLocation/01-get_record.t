#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

use Storable qw(retrieve);
use Mirror::FallbackGeoLocation;

my $db;
eval {
    $db = retrieve('db');
    plan tests => 3;
};
if ($@) {
    plan skip_all => "Failed to retrieve db: $@";
    exit;
}

can_ok('Mirror::FallbackGeoLocation', 'get_record');

ok(Mirror::FallbackGeoLocation::get_record($db, 'archive'), 'Can get a record');
my $rec = Mirror::FallbackGeoLocation::get_record($db, 'archive');

can_ok($rec, qw(city continent_code country_code latitude longitude region));
