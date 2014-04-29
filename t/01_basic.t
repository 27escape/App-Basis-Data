#!/usr/bin/env perl
# PODNAME: app-basis-data test
# ABSTRACT: Test the App::Basis::Data module

# (c) kevin Mulholland 2014, moodfarm@cpan.org
# this code is released under the Perl Artistic License

use 5.10.0;
use strict;
use warnings;
use POSIX qw( strftime);
use Data::Printer;
use App::Basis;
use Try::Tiny;
use Path::Tiny;
use Test::More tests => 30;

BEGIN { use_ok('App::Basis::Data'); }

# -----------------------------------------------------------------------------
# we test the basic file store mechanism for everyone
# there are specific test of DBI/redis/mongo, even though the actual test mechanism
# will be the same

# first test should be to find out if we fail with a bad sri

my $bad;

try {
    $bad = App::Basis::Data->new( sri => 'blergh://abc123' );
}
catch {};
ok( !$bad, 'Cannot instance with a silly sri' );

try {
    $bad = App::Basis::Data->new( sri => 'file:///bc123' );
}
catch {};
ok( !$bad, 'Cannot instance a bad directory' );

my $store_dir = "/tmp/abds.$$";

# temp use consistent storename so we can check contents, clean before we start
$store_dir = "/tmp/datastore";
path($store_dir)->remove_tree if ( -d $store_dir );

my $store = App::Basis::Data->new( sri => "file://$store_dir" );
ok( $store, 'We have a store' );

my $data = {
    pid    => $$,
    time   => time,
    field2 => 12345,
};

my $id;
try {
    $id = $store->add( 'fred', 123 );
}
catch {};
ok( !$id, 'cannot add a scalar' );    # this covers arrays and hashes too
try {
    $id = $store->add( 'fred', [123] );
}
catch {};
ok( !$id, 'cannot add an arrayref' );

$id = $store->add( 'fred', $data );

# note("id is $id");
ok( $id, 'Added data to the store' );
my @f = $store->taglist;
ok( scalar(@f) == 1 && $f[0] eq 'fred', 'Taglist is good for 1 item' );
my $data2 = $store->data($id);

# this is fine as it seems to ignore the fields prefixed '_'
is_deeply( $data, $data2, 'added data is correct' );

$data2->{number} = 100;
my $update_id = $store->update($data2);
ok( $update_id == $id, "Updated without adding" );

my $data3 = $store->data($id);
ok( $data3->{_modified}, 'there is a modified field' );

# this is fine as it seems to ignore the fields prefixed '_'
is_deeply( $data2, $data3, 'updated data is correct' );

# alter the id to mess with things, should add new record
delete $data3->{_id};
$update_id = $store->update($data3);
ok( $update_id != $id, "Update added new record" );

$store->add( 'bill', $data );

@f = sort $store->taglist;
ok( scalar(@f) == 2 && $f[0] eq 'bill' && $f[1] eq 'fred', 'Taglist is good for 2 items' );

# give the data a timestamp
$data->{timestamp} = '2013-01-01 12:00:00';
$store->add( 'bill', $data );

# we now have 2 things in 'bill' one in 2013 and one this year

# next up tagcount, count everything
my $count = $store->count( { _tag => { 'eq' => 'bill' } } );
ok( $count == 2, '2 bill items' );

# count all in 2013
$count = $store->count(
    {   _tag       => { 'eq'       => 'bill' },
        _timestamp => { 'date:gte' => '2013-01-01', 'date:lte' => '2013-12-31' },
    }
);
ok( $count == 1, '1 bill in 2013' );

# we need to add some data that we can search for, change the date to 2000, to ensure we do not clash
# with previous data

$store->add( 'test_search',  { timestamp => '2000-02-01 12:00:00', message => 'testing 123',          counter => 100 } );
$store->add( 'test_search',  { timestamp => '2000-03-01 12:00:00', message => 'Testing, testing 123', counter => 120 } );
$store->add( 'test_search2', { timestamp => '2000-04-01 12:00:00', message => 'hello world',          counter => 140 } );

$data = $store->search( { _tag => { 'eq' => 'test_search' }, } );
ok( scalar(@$data) == 2, 'search on tags only' );

$data = $store->search( { _timestamp => { 'date:gte' => '2000-01-01 12:00:00', 'date:lte' => '2000-03-30 12:00:00' }, } );
ok( scalar(@$data) == 2, 'search on dates only' );

$data = $store->search( { message => { '~' => '^hello' } } );
ok( scalar(@$data) == 1, 'regexp search only hello' );

$data = $store->search( { message => { '!~' => 'hello' } } );
ok( scalar(@$data) == 2, 'regexp search not hello' );

$count = $store->count();
ok( $count > 0, 'raw count' );

my $del = $store->purge( {counter => { '=' => 140}}) ;
ok( $del == 1, 'purge deleted a single item' );

my $left = $store->count();
ok( ($left + 1) == $count, 'double check single delete' );

$del = $store->purge( ) ;
ok( $del == 6, 'purge deleted 6 items' );
$count = $store->count();
ok( $count == 0, 'purge emptied the datastore' );

$data = {
    pid    => $$,
    time   => time,
    field2 => 12345,
    array  => [ 1, 2, 3, 4],
    hash   => { alf => 'alien', friend => 'mork'},
};

$id = $store->add( 'complex', $data) ;
ok( $id, 'stored complex' );
$data2 = $store->data($id);
# this is fine as it seems to ignore the fields prefixed '_'
is_deeply( $data, $data2, 'retrieved complex data is correct' );

$data = $store->search( { _tag => { 'eq' => 'complex' } } );
ok( scalar(@$data) == 1, 'found complex' );

$data = $store->search( { _tag => { 'eq' => 'complex' }, array => 1 } );
ok( scalar(@$data) == 0, 'cannot search on complex key' );

$data = $store->search( { _tag => { 'eq' => 'complex' }, array => 1 }, 1 );
ok( scalar(@$data) == 0, 'cannot sloppy search on complex key' );

# clean up things
path($store_dir)->remove_tree;

# -----------------------------------------------------------------------------
# all done
