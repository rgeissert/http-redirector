package Mirror::AS;

use strict;
use warnings;

sub convert {
    my $as = shift;

    $as =~ s/^AS//;

    if ($as =~ m/(\d+)\.(\d+)/) {
	$as = unpack('N', pack('nn', $1, $2));
    }

    return $as;
}

1;
