#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 1;

use Mirror::DB;

Mirror::DB::set('db.test');
ok(Mirror::DB::store(\'something'), 'store'); #'
unlink('db.test');
