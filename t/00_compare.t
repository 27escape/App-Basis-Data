#!/usr/bin/env perl
# PODNAME: app-basis-data-compare test
# ABSTRACT: Test the App::Basis::Data::Compare module

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
use Test::More tests => 40;

BEGIN { use_ok('App::Basis::Data::Compare'); }

# -----------------------------------------------------------------------------

my $data = {} ;
my $rules = { fred => { eq => 'fred'}} ;

# empty data
ok( compare( {}, { fred => { eq => 'fred'}}) == 0 , 'no field in data - fails' );
ok( compare( {}, { fred => { eq => 'fred'}}, 1) == 0 , 'no field in data - sloppy - fails' );

# basic strings
ok( compare( { fred => 'fred'}, { fred => { eq => 'fred'}}) == 1 , 'string: eq' );
ok( compare( { fred => 'fred'}, { fred => { ne => 'bill'}}) == 1 , 'string: ne' );
ok( compare( { fred => 'zzz'}, { fred => { gt => 'aaa'}}) == 1 , 'string: gt' );
ok( compare( { fred => 'aaaa'}, { fred => { gte => 'aaa'}}) == 1 , 'string: gte' );
ok( compare( { fred => 'zzzz'}, { fred => { ge => 'zzza'}}) == 1 , 'string: gte v2' );
ok( compare( { fred => 'aaa'}, { fred => { lt => 'zzz'}}) == 1 , 'string: lt' );
ok( compare( { fred => 'aa'}, { fred => { lte => 'aaa'}}) == 1 , 'string: lte' );
ok( compare( { fred => 'aa1'}, { fred => { le => 'aaz'}}) == 1 , 'string: lte v2' );
ok( compare( { fred => 'fred'}, { fred => { '~' => 're'}}) == 1 , 'string: ~ regexp v2' );
ok( compare( { fred => 'fred'}, { fred => { '~' => '^f'}}) == 1 , 'string: ~ regexp' );
ok( compare( { fred => 'fred'}, { fred => { '~' => 'red'}}) == 1 , 'string: ~ regexp v2' );
ok( compare( { fred => 'fred'}, { fred => { '!~' => 'a|z'}}) == 1 , 'string: !~ regexp v3' );

# basic numbers
ok( compare( { fred => 10}, { fred => { '=' => 10}}) == 1 , 'number: =' );
ok( compare( { fred => 10}, { fred => { '!=' => 20}}) == 1 , 'number: !=' );
ok( compare( { fred => 10}, { fred => { '>' => 5}}) == 1 , 'number: >' );
ok( compare( { fred => 10}, { fred => { '>=' => 5}}) == 1 , 'number: >=' );
ok( compare( { fred => 10}, { fred => { '=>' => 10}}) == 1 , 'number: >= v2' );
ok( compare( { fred => 10}, { fred => { '<' => 20}}) == 1 , 'number: <' );
ok( compare( { fred => 10}, { fred => { '<=' => 20}}) == 1 , 'number: <=' );
ok( compare( { fred => 10}, { fred => { '=<' => 10}}) == 1 , 'number: <= v2' );

# date
ok( compare( { fred => '2014-06-02 12:34:56'}, { fred => { 'date:gte' => '2001-01-01 00:00:00'}}) == 1 , 'date:after ' );
ok( compare( { fred => '2014-06-02 12:34:56'}, { fred => { 'date:lte' => '2038-01-19 03:14:07'}}) == 1 , 'date:before' );
ok( compare( { fred => '2014-06-02 12:34:56'}, { fred => { 'date:lte' => '2038-01-19 03:14'}}) == 1 , 'date:lte' );
ok( compare( { fred => '2014-06-02 12:34:56'}, { fred => { 'date:eq' => '2014-06-02 12:34:56'}}) == 1 , 'date:eq' );
ok( compare( { fred => '2014-06-02'}, { fred => { 'date:lte' => '2014-06-02 00:00'}}) == 1 , 'date:eq' );
ok( compare( { fred => '2014-06-02'}, { fred => { 'date:lte' => '2014-06-02 00:00:00'}}) == 1 , 'date:eq' );

# time
ok( compare( { fred => '12:34:56'}, { fred => { 'time:gte' => '00:00:00'}}) == 1 , 'time:gte ' );
ok( compare( { fred => '12:34:56'}, { fred => { 'time:ge' => '00:00:00'}}) == 1 , 'time:gte v2 ' );
ok( compare( { fred => '12:34:56'}, { fred => { 'time:gte' => '12:34:56'}}) == 1 , 'time:eq ' );
ok( compare( { fred => '12:34:56'}, { fred => { 'time:eq' => '12:34'}}) == 1 , 'time:eq v2' );
ok( compare( { fred => '12:34:56'}, { fred => { 'time:lte' => '21:22:27'}}) == 1 , 'time:lte' );
ok( compare( { fred => '12:34:56'}, { fred => { 'time:le' => '21:22:27'}}) == 1 , 'time:lte v2' );

# complex
ok( compare( { fred => 'fred'}, { fred => { eq => 'fred'}, bill => {'eq' => '1'}}, 1) == 1 , 'complex: missing field in data - sloppy - passes' );
ok( compare( { fred => 'fred'}, { fred => { eq => 'fred'}, bill => {'eq' => '1'}}, 0) == 0 , 'complex: missing field in data - fails' );
ok( compare( { fred => 'fred', bill => 1}, { fred => { eq => 'fred'}, bill => {'eq' => '1'}}, 1) == 1 , 'complex: multiple fields - passes' );

ok( compare( { timestamp => '2013-02-01 12:00:00', extra => 'fred'}, { timestamp => { 'date:gte' => '2013-01-01 12:00:00', 'date:lte' => '2013-03-30 12:00:00' }} ) == 1, 'complex: dates between') ;

# compare against actual unix timestamp
ok( compare( { timestamp => time(), extra => 'fred'}, { timestamp => { 'date:gte' => '1980-01-01 12:00:00', 'date:lte' => '2038-01-01 12:00:00' }} ) == 1, 'complex: timestamp dates between') ;

# -----------------------------------------------------------------------------
# all done
