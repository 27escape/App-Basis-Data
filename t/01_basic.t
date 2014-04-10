#!/usr/bin/env perl
# PODNAME: app-basis-data test
# ABSTRACT: Test the App::Basis::Data module

# (c) kevin Mulholland 2014, moodfarm@cpan.org
# this code is released under the Perl Artistic License
# extra info at http://support.torch.sh/help/kb/graylog2-server/using-the-gelf-http-input

use 5.10.0;
use strict;
use warnings;
use POSIX qw( strftime);
use Data::Printer;
use App::Basis;
use Try::Tiny;
use Path::Tiny ;
use Test::More tests => 10;

BEGIN { use_ok('App::Basis::Data'); }

# -----------------------------------------------------------------------------
# we test the basic file store mechanism for everyone
# there are specific test of DBI/redis/mongo, even though the actual test mechanism
# will be the same

# my $id = $store->add( tag => 'test', message => 'testing', level => 'debug', counter => 20) ;
# my $test_data = $store->tagsearch( tag => 'test', from => '2014-01-01') ;
# my $large_count_data = $store->wildsearch( counter => { 'gte' => 100} ) ; # or '>='
# my $test_count = $store->tagcount(tag => 'test') ;
# my $data = $store->data( $id) ;
# $data->{counter} = 50 ;
# my $new_id = $store->replace( id=> $id, $data) ;
# say ( $id == $new_id) ? "Data replaced" : "data ccreated" ;
# $store->delete( $id) ;

# first test should be to find out if we fail with a bad sri

my $bad;

try {
    $bad = App::Basis::Data->new( sri => 'blergh://abc123' );
}
catch {};
ok( !$bad, 'Cannot instance a silly sri' );

try {
    $bad = App::Basis::Data->new( sri => 'file:///bc123' );
}
catch {};
ok( !$bad, 'Cannot instance a bad directory' );

my $store_dir =  "/tmp/abds.$$" ;
$store_dir = "/tmp/datastore" ;
my $store = App::Basis::Data->new( sri => "file://$store_dir" );
ok( $store, 'We have a store') ;

my $data = {
    pid => $$, 
    time => time,
    field2 => 12345,
} ;

my $id = $store->add( 'fred', $data) ;
note( "id is $id") ;
ok( $id, 'Added data to the store') ;
my $data2 = $store->data( $id) ;
# this is fine as it seems to ignore the fields prefixed '_'
is_deeply( $data, $data2, 'added data is correct') ;

$data2->{number} = 100 ;
my $update_id = $store->update( $data2) ;
ok( $update_id == $id, "Updated without adding") ;
my $data3 = $store->data( $id) ;
ok($data3->{_modified}, 'there is a modified field');
# this is fine as it seems to ignore the fields prefixed '_'
is_deeply( $data2, $data3, 'updated data is correct') ;

# alter the id to mess with things, should add new record
delete $data3->{_id} ;
$update_id = $store->update( $data3) ;
ok( $update_id != $id, "Update added new record") ;

diag( p( $data3)) ;





# path( $store_dir)->remove_tree ;

# -----------------------------------------------------------------------------
# all done
