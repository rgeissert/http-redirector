#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 4;
use Test::Trap;

use Mirror::Trace;

my $trace = Mirror::Trace->new('http://0.0.0.0/');

my ($trace_data, $res);

$trace_data = '';

$res = trap { $trace->from_string($trace_data) };
is($res, 0, 'Empty trace data');
is($trap->stderr, '', 'No errors parsing data');


$trace_data = '
';

$res = trap { $trace->from_string($trace_data) };
is($res, 0, 'Empty trace data w/new line');
is($trap->stderr, '', 'No errors parsing data');
