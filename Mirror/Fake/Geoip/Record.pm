package Mirror::Fake::Geoip::Record;

use strict;
use warnings;

sub new {
    my $class = shift;
    my $self = {};

    my %data;
    {
	my $even = 1;
	my $key = '';

	foreach my $elem (@_) {
	    if ($even) {
		$even = 0;
		$key = $elem;
	    } else {
		$even = 1;
		$data{$key} = $elem;
	    }
	}
    }
    $self->{'data'} = \%data;

    bless ($self, $class);
    return $self;
}

sub latitude {
    my $self = shift;
    return $self->{'data'}->{'latitude'};
}

sub longitude {
    my $self = shift;
    return $self->{'data'}->{'longitude'};
}

sub country_code {
    my $self = shift;
    return $self->{'data'}->{'country_code'};
}

sub continent_code {
    my $self = shift;
    return $self->{'data'}->{'continent_code'};
}

sub city {
    my $self = shift;
    return $self->{'data'}->{'city'} || '';
}

sub region {
    my $self = shift;
    return $self->{'data'}->{'region'} || '';
}

1;
