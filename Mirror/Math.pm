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

sub stddev {
    my ($avg, $var, $stddev) = (0, 0, 0);
    local $_;

    return 0 if (scalar(@_) == 1);

    for (@_) {
	$avg += $_;
    }
    $avg /= scalar(@_);

    for (@_) {
	$var += ($_-$avg)**2;
    }
    $var /= scalar(@_)-1;

    # Reduce precision
    $var = sprintf('%f', $var);

    $stddev = sqrt($var);
    return $stddev;
}

sub ceil($) {
    my $n = shift;
    my $i  = int($n);

    return $n if ($i == $n);
    return $i+1;
}

sub iquartile(@) {
    my @elems = @_;
    my $count = scalar(@elems);
    my ($lower, $upper) = ($count*0.25, $count*0.75);

    $lower = ceil($lower);
    $upper = ceil($upper);

    return @elems[($lower-1)..($upper-1)];
}

1;
