package Mirror::FallbackGeoLocation;

use strict;
use warnings;

use Mirror::CountryCoords;

use vars qw(%fake_records);

sub get_record;
sub get_continents_by_mirror_type;
sub get_countries_by_mirror_type;
sub get_continents_index;
sub get_countries_index;
sub is_enabled;

sub get_record {
    my ($db, $type) = @_;

    return $fake_records{$type}
	if (defined($fake_records{$type}));

    my $chosen_continent;
    {
	my $max_mirrors = 0;
	my %continents;
	for my $continent (get_continents_by_mirror_type($db, $type)) {
	    $continents{$continent} = scalar(keys %{get_continents_index($db, $type, $continent)});
	}
	for my $continent (sort { $continents{$b} <=> $continents{$a} } keys %continents) {
	    my @mirrors = keys %{get_continents_index($db, $type, $continent)};

	    next if (scalar(@mirrors) < $max_mirrors);

	    my $c = 0;
	    for my $id (@mirrors) {
		$c++ if (is_enabled($db, $type, $id));
	    }
	    if ($c > $max_mirrors) {
		$max_mirrors = $c;
		$chosen_continent = $continent;
	    }
	}
    }

    my $chosen_country;
    {
	my $max_mirrors = 0;
	my %countries;
	my $continent_index = get_continents_index($db, $type, $chosen_continent);
	for my $country (get_countries_by_mirror_type($db, $type)) {
	    $countries{$country} = scalar(keys %{get_countries_index($db, $type, $country)});
	}
	for my $country (sort { $countries{$b} <=> $countries{$a} } keys %countries) {
	    my @mirrors = keys %{get_countries_index($db, $type, $country)};

	    next unless (defined($mirrors[0]) && exists($continent_index->{$mirrors[0]}));
	    next if (scalar(@mirrors) < $max_mirrors);

	    my $c = 0;
	    for my $id (@mirrors) {
		$c++ if (is_enabled($db, $type, $id));
	    }
	    if ($c > $max_mirrors) {
		$max_mirrors = $c;
		$chosen_country = $country;
	    }
	}
    }

    my $ltln = Mirror::CountryCoords::country($chosen_country);
    $fake_records{$type} = {
	country => $chosen_country,
	continent => $chosen_continent,
	lat => $ltln->{'lat'},
	lon => $ltln->{'lon'},
	city => '',
	region => '',
    };
    return $fake_records{$type};
}

sub get_continents_by_mirror_type {
    my ($db, $type) = @_;

    return keys %{$db->{$type}{'continent'}};
}

sub get_countries_by_mirror_type {
    my ($db, $type) = @_;

    return keys %{$db->{$type}{'country'}};
}

sub get_continents_index {
    my ($db, $type, $continent) = @_;
    return $db->{$type}{'continent'}{$continent};
}

sub get_countries_index {
    my ($db, $type, $country) = @_;
    return $db->{$type}{'country'}{$country};
}

sub is_enabled {
    my ($db, $type, $id) = @_;
    return !exists($db->{'all'}{$id}{$type.'-disabled'});
}

1;
