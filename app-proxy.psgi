# -*- perl -*-

use strict;
use warnings;

use lib '.';
use Mirror::Redirector;

my $app = Mirror::Redirector->new;
$app->set_local_ip(sub {
    my $req = shift;
    my $ip = '8.8.8.8';
    if ($req->header('x-forwarded-for')) {
	$ip = (split(/\s*,\s*/, $req->header('x-forwarded-for')))[-1];
    }
    return $ip;
});
sub { $app->run(@_); }
