package Mirror::Redirection::Blackhole;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(should_blackhole);

sub should_blackhole {
    my $url = shift;
    my $mirror_type = shift;

    if ($mirror_type eq 'archive') {
	return 1 if ($url =~ m,^dists/jessie, && (
	    $url =~ m,/(?:main|contrib|non-free)/binary-[^/]+/Packages\.(?:lzma)$, ||
	    $url =~ m,/(?:main|contrib|non-free)/i18n/Translation[^/]+\.(?:lzma|gz)$,
	    ));
	return 1 if ($url =~ m,^dists/wheezy, && (
	    $url =~ m,/(?:main|contrib|non-free)/binary-[^/]+/Packages\.(?:lzma|xz)$, ||
	    $url =~ m,/(?:main|contrib|non-free)/i18n/Translation[^/]+\.(?:lzma|xz|gz)$,
	    ));
	return 1 if ($url =~ m,^dists/(?:squeeze|wheezy)-updates/(?:main|contrib|non-free)/i18n/,);
	return 1 if ($url =~ m,^dists/squeeze, && (
	    $url eq 'dists/squeeze/InRelease' ||
	    $url =~ m,/(?:main|contrib|non-free)/binary-[^/]+/Packages\.(?:lzma|xz)$, ||
	    $url =~ m,/(?:main|contrib|non-free)/i18n/Translation[^/]+\.(?:lzma|xz|gz)$, ||
	    $url =~ m,/(?:main|contrib|non-free)/i18n/Translation-en_(?:US|GB),
	    ));
	return 1 if ($url =~ m,^dists/lenny,);
    } elsif ($mirror_type eq 'backports') {
	return 1 if ($url =~ m,^dists/squeeze-backports/(?:main|contrib|non-free)/i18n/,
	    );
    } elsif ($mirror_type eq 'security') {
	return 1 if ($url =~ m,^dists/[^/]+/updates/(?:main|contrib|non-free)/i18n/,
	    );
    }
    return 0;
}

1;
