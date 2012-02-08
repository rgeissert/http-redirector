#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 3;

use threads;
use threads::shared;
use Mirror::DB;
use Storable qw(retrieve);

Mirror::DB::set('db.test');

my $db :shared = shared_clone([]);

ok(Mirror::DB::store($db), 'store shared');

is_deeply($db, [], 'db is (a ref to) an empty array');

my $sdb = retrieve('db.test');

eval { is_deeply($db, $sdb, 'db and its stored version are equal'); }
    or fail('could not compare db to its stored version');

unlink('db.test');
