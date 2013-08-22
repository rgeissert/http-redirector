package Mirror::Redirection::Permanent;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(is_permanent);

sub is_permanent {
    my ($url, $type) = @_;
    return ($url =~ m,^pool/, ||
	    $url =~ m,\.diff/.+\.(?:gz|bz2|xz|lzma)$, ||
	    $url =~ m,/installer-[^/]+/\d[^/]+/, ||
	    $type eq 'old');
}

1;
