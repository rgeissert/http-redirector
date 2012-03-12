package Mirror::Math;

use strict;
use warnings;

use vars qw($METRIC);

BEGIN {
    $METRIC = 'taxicab';
}

sub set_metric($) {
    $METRIC = shift;  
}

sub calculate_distance($$$$) {
    my ($x1, $y1, $x2, $y2) = @_;

    if ($METRIC eq 'euclidean') {
	return sqrt(($x1-$x2)**2 + ($y1-$y2)**2);
    } else {
	return (abs($x1-$x2) + abs($y1-$y2));
    }
}

sub stddevp {
    my ($avg, $var, $stddev) = (0, 0, 0);
    local $_;

    for (@_) {
	$avg += $_;
    }
    $avg /= scalar(@_);

    for (@_) {
	$var += $_**2;
    }
    $var /= scalar(@_);

    # Reduce precision
    $var = sprintf('%f', $var);

    my $sq_avg = $avg**2;
    # Reduce precision again
    $sq_avg = sprintf('%f', $sq_avg);

    $var -= $sq_avg;

    $stddev = sqrt($var);
    return $stddev;
}

1;
