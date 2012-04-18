#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 4;
use Test::Trap;

use Mirror::Trace;
use LWP::UserAgent;

my $trace = Mirror::Trace->new(LWP::UserAgent->new(), 'http://0.0.0.0/');

my ($trace_data, $res);

$trace_data = '';

$res = trap { $trace->_parse_trace($trace_data) };
is($res, 0, 'Empty trace data');
is($trap->stderr, '', 'No errors parsing data');


$trace_data = '
';

$res = trap { $trace->_parse_trace($trace_data) };
is($res, 0, 'Empty trace data w/new line');
is($trap->stderr, '', 'No errors parsing data');
