#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

eval 'use LWPx::Record::DataSection';
plan skip_all => "LWPx::Record::DataSection is required to run this test"
    if $@;

plan tests => 2;

use Mirror::Trace;
use LWP::UserAgent;

my $trace = Mirror::Trace->new(LWP::UserAgent->new(), 'http://http.debian.net/debian/');

ok(!$trace->fetch('http.debian.net'), 'Trace can not be parsed if the fetch failed');
is($trace->fetch_error, '404 Not Found', 'Error with which the fetch failed');

__DATA__
@@ GET http://http.debian.net/debian/project/trace/http.debian.net
HTTP/1.1 404 Not Found
Connection: close
Date: Thu, 01 Nov 2012 00:08:13 GMT
Server: Apache
Content-Length: 239
Content-Type: text/html; charset=iso-8859-1

<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html><head>
<title>404 Not Found</title>
</head><body>
<h1>Not Found</h1>
<p>The requested URL /debian/project/trace/http.debian.net was not found on this server.</p>
<hr>
</body></html>

