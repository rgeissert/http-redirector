#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 6;

use Mirror::CountryCoords;

can_ok('Mirror::CountryCoords', 'country');

ok(Mirror::CountryCoords::country('FR'), 'Can lookup coords of FR');
is_deeply(Mirror::CountryCoords::country('FR'),
	    {'lat' => '46.0000', 'lon' => '2.0000'}, 'Coords of FR');

ok(Mirror::CountryCoords::country('DE'), 'Can lookup coords of DE');
is_deeply(Mirror::CountryCoords::country('DE'),
	    {'lat' => '51.0000', 'lon' => '9.0000'}, 'Coords of DE');

is(Mirror::CountryCoords::country('XX'), undef, 'No known country results in undef');
