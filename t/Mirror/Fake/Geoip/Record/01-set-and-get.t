#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 7;

use Mirror::Fake::Geoip::Record;

can_ok('Mirror::Fake::Geoip::Record', 'new');

my $geoip_rec;
eval {
$geoip_rec = Mirror::Fake::Geoip::Record->new(
    latitude => '52.5',
    longitude => '5.75',
    country_code => 'NL',
    continent_code => 'EU',
);
}; is($@, '', 'Creating a fake geoip record failed');

can_ok($geoip_rec, qw(latitude longitude country_code continent_code));
is($geoip_rec->latitude, '52.5', 'Can get the lat back');
is($geoip_rec->longitude, '5.75', 'Can get the lon back');
is($geoip_rec->country_code, 'NL', 'Can get the country back');
is($geoip_rec->continent_code, 'EU', 'Can get the continent back');
