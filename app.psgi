# -*- perl -*-

use strict;
use warnings;

use lib '.';
use Mirror::Redirector;

my $app = Mirror::Redirector->new;
sub { $app->run(@_); }
