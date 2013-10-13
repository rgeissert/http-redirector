package Mirror::Request;

use strict;
use warnings;

# Even-numbered list: '[default]' => qr/regex/
# Whenever regex matches but there's no value in the capture #1 then
# the default value is used.
our @ARCHITECTURES_REGEX = (
    '' => qr'^dists/(?:[^/]+/){2,3}binary-([^/]+)/',
    '' => qr'^pool/(?:[^/]+/){3,4}.+_([^.]+)\.u?deb$',
    '' => qr'^dists/(?:[^/]+/){1,2}Contents-(?:udeb-(?!nf))?(?!udeb)([^.]+)\.(?:gz$|diff/)',
    '' => qr'^indices/files(?:/components)?/arch-([^.]+).*$',
    '' => qr'^dists/(?:[^/]+/){2}installer-([^/]+)/',
    '' => qr'^dists/(?:[^/]+/){2,3}(source)/',
    'source' => qr'^pool/(?:[^/]+/){3,4}.+\.(?:dsc|(?:diff|tar)\.(?:xz|gz|bz2))$',
);

sub get_arch {
    my $url = shift;

    my $i = 0;
    while ($i + 1 < scalar(@ARCHITECTURES_REGEX)) {
	my ($default, $rx) = @ARCHITECTURES_REGEX[$i++ .. $i++];

	if ($url =~ m/$rx/) {
	    my $arch = $1 || $default;
	    return $arch;
	}
    }
    return '';
}

1;
