# ABSTRACT: Generalised data store access system

=head1 NAME

App::Basis::Data

=head1 SYNOPSIS

  use App::Basis::Data ;
 
  my $store = App::Basis::Data->new( sri => 'file:///tmp/fred' ) ;

  my $id = $store->add( 'test', {message => 'testing', level => 'debug', counter => 20}) ;
  my $large_count_data = $store->wildsearch( counter => { 'gte' => 100} ) ; # or '>=' for numbers
  my $test_count = $store->count( {_tag => { 'eq' => 'test'}) ;
  my $data = $store->data( $id) ;
  $data->{counter} = 50 ;
  my $new_id = $store->update( $data) ;
  say ( $id == $new_id) ? "Data replaced" : "data created" ;
  $store->delete( $id) ;

=head1 DESCRIPTION

I needed a way to store semi-structured data to a number of systems, DB, redis, file.
This module scratches this itch, it is not intended to be fast or efficient, just useful to me.

With this I can store and search for data in a consistent way irrespective of the system
that the data is store to. Document based stores can just store the data

I do not expect (at the moment) that the data is multi-level, for me a data item is a group of
key-values

    item
    fred    => 'bill' ,
    counter => 12,
    source  => 'localhost'

This will not work 

    fred    => 'bill' ,
    counter => 12,
    source  => 'localhost',
    array   => [ 1,2,3,4],
    hash    => { alf => 'alien', friend => 'mork'}

well it will, it can be stored/retrieved, but we can only search scalar keys and values.

=head1 Todo

DBI, Redis, Mongo datastore modules still need to be written

Consider adding L<Net::Graylog::Client> as a datastore

=head1 AUTHOR

 kevin mulholland

=head1 VERSIONS

v0.1  2014/04/08, initial work

=head1 Notes

DBI does not make use of any particular autoincrementing fields for the
id as the different databases do this in different ways, so we are stuck with 
implementing a settings table and a data table 
 
=head1 See Also


=head1 Todo


=cut

package App::Basis::Data;

use 5.10.0;
use strict;
use warnings;
use POSIX qw(strftime);
use Data::Printer;
use Sys::Hostname;
use Data::UUID;
use App::Basis;
use Try::Tiny;
use Moo;
use Date::Manip;
use namespace::clean;

# -----------------------------------------------------------------------------

=head1 Public Functions

=over 4

=cut

=item new

Create a new instance of the data store

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;

B<Parameters>
  sri storage resource indicator, expected to have file:///, dbi:, redis: and mongo:
  
=cut

has sri       => ( is => 'ro', required => 1 );
has _uuid     => ( is => 'ro', init_arg => undef, default => sub { Data::UUID->new() }, );
has _hostname => ( is => 'ro', init_arg => undef, default => sub { hostname(); } );
has _handler  => ( is => 'ro', init_arg => undef, default => sub { } );
has _module   => ( is => 'ro', init_arg => undef, default => sub { } );

# create a date::manip object so we don't have to keep doing it, useful in long running
# situations
has _datemanip => ( is => 'ro', init_arg => undef, default => sub { Date::Manip::Date->new() } );

# -----------------------------------------------------------------------------
# remove leading and trailing spaces
sub _trim {
    my ($str) = @_;
    return if ( !$str );

    $str =~ s/^\s+//gsm;
    $str =~ s/\s+$//gsm;

    return $str;
}

# -----------------------------------------------------------------------------

# this is where we will initialise _handler with the object that will perform the
# actual data storage functions

sub BUILD {
    my $self = shift;

    my ($module) = ( $self->sri =~ /^(\w+):/ );
    my $class = "App::Basis::Data::" . ucfirst($module);

    $self->{_module} = $module;
    try {
        eval "require $class";
    }
    catch {
        say STDERR "$class vs $_";
        die "No handler for $module";
    };

    # while each SQL DB understands its DBI format, this is not true of the redis/mongo DBs
    # so lets also split out any component parts

    my %params = ( sri => $self->sri );
    foreach my $s (split( ';', $self->sri )) {
        my ( $k, $v ) = ( $s =~ /^(.*?)=(.*)/ );
        if ( $k ) {
            $k = _trim($k);
            $params{$k} = _trim($v);
        }
    }

    # and create the required class instance
    $self->{_handler} = $class->new(%params);
}

# -----------------------------------------------------------------------------
sub _as_timestamp {
    my $self = shift;
    my ($datestr) = @_;
    my $timestamp;
    my $date = $self->{_datemanip}->new();

    # we may have to convert the timestamp
    if ( $datestr && $datestr !~ /^\d+$/ ) {

        # reuse the date::manip object
        $date->parse($datestr);
        {
            # if we get a warning about converting the date to a day, there
            # must be a problem with parsing the input date string
            local $SIG{__WARN__} = sub {
                die "Invalid date";
            };
            my $day = $date->printf("%a");
        }

        # update timestamp with unix epoch
        $timestamp = $date->secs_since_1970_GMT;
    }
    else {
        $timestamp = $datestr;
    }

    return $timestamp;
}

# -----------------------------------------------------------------------------

=item add 

Add a new data item to the store

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;
    my $id = $store->add( thing1 => 123, thing2 => 'abc') ;

B<Parameters>
  hash of data to store
  timestamp will override automatic timestamp, timestamp only valid from 1970
  
=cut

sub add {
    my $self = shift;
    my ( $tag, $params ) = @_;

    # we don't add empty data
    return 0 if ( !$params );

    die "add requires a hashref" if ( ref($params) ne 'HASH' );

    # remove any parameters that are prefixed '_'
    foreach my $key ( keys %$params ) {
        delete $params->{key} if ( $key =~ /^_/ );
    }

    $params->{_timestamp} = $self->_as_timestamp( $params->{timestamp} || time() );
    $params->{_created}   = time();
    $params->{_source}    = $self->_hostname;
    $params->{_uuid}      = $self->_uuid->create_str();
    $params->{_tag}       = $tag;

    return $self->{_handler}->add( $tag, $params );
}

# -----------------------------------------------------------------------------

=item taglist

list all the tags that have been used to tag data

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;
    my $@tags = $store->taglist() ;
  
=cut

sub taglist {
    my $self = shift;
    my ($tag) = @_;
    $self->{_handler}->taglist($tag);
}

# -----------------------------------------------------------------------------

=item delete

Remove a data item from the store

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;
    my $id = $store->add( thing1 => 123, thing2 => 'abc') ;
    $store->delete( $id) ;
    # alternatively
    my $data = $store->($id) ;
    $store->delete( $data) ;

B<Parameters>
    id or data item

=cut

sub delete {
    my $self = shift;
    my ($id) = @_;
    # we may get passed the full data item
    $id = $id->{_id} if ( ref($id) eq 'HASH' );
    $self->{_handler}->delete($id);
}

# -----------------------------------------------------------------------------

=item data

Get a data item from the store

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;
    my $id = $store->add( thing1 => 123, thing2 => 'abc') ;
    my $data = $store->data( $id) ;

B<Parameters>
  id   valid data item id

B<Returns>
  hashref of data

=cut

sub data {
    my $self = shift;
    my ($id) = @_;

    # we may get passed the full data item
    $id = $id->{_id} if ( ref($id) eq 'HASH' );

    $self->{_handler}->data($id);
}

# -----------------------------------------------------------------------------

=item update

Update a data item

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;
    my $id = $store->add( thing1 => 123, thing2 => 'abc') ;
    my $data = $store->data( $id) ;
    $data->{fred} = 'wilma' ;
    delete $data->{thing2} ;
    my $s = $store->update( $data) ;
    say ($s == $id ? "updated" : "new record added")  ;

B<Parameters>
  hashref of data to update

B<Returns>
  id of updated item
  
=cut

sub update {
    my $self = shift;
    my ($params) = @_;
    die "update requires a hashref" if ( ref($params) ne 'HASH' );
    my $id      = $params->{_id};
    my $current = $self->data($id);

    # basic check to see if its the same
    if ( $current && $current->{_uuid} eq $params->{_uuid} ) {
        $params->{_modified} = time();

        # remove any parameters that are prefixed '_'
        foreach my $key ( keys %$params ) {
            delete $params->{key} if ( $key =~ /^_/ );
        }

        # add in the entries from the current record
        foreach my $key ( keys %$current ) {
            $params->{key} = $current->{key} if ( $key =~ /^_/ );
        }
        $id = $self->{_handler}->update($params) ? $id : undef;
    }
    else {
        $id = $self->add( $params->{_tag}, $params );
    }
    return $id;
}

# -----------------------------------------------------------------------------

=item search

search for matching items
This is the general purpose search

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;
    my $data = $store->search( 
        match => { 
            _tag => { 'eq' => 'fred'},
            _timestamp = { '>=' => '2013-01-01 12:00:00', '<=' => 'yesterday'},
            thing2 => { '~' => 'a'},
        }
        fields => [ qw( timestamp id source message)],
        count => 0,   # default
    ) ;

Fields is a list of matching fields to be returned, if a matching data item does not
have this field, then this will be undef/missing
Can return count of matching items if count is non-zero, in whch case fields is ignored

valid comparisons are 
    numbers: >= > = != =<     (=> same as <=, <= same as =<)
    strings: gte gt eq ne lt lte      (ge same as gte, le same as lte)
    time: prefix string compare with 'time:', i.e. time:eq, 
    date: prefix string compare with 'date:', i.e. date:eq (date:after same as date:gt, date:before same as date:lt)
    there are no :ne comparisons for date or time
    regular expressions: ~ and !~ 
    see L<App::Basis::Data::Compare> for more infomation.

B<Parameters>
  hashref of things to search against

B<Returns>
  arrayref of matching items
  
=cut

# implementation note: the handler version of this method should only grab the matching tag items
# and match against any underscore prefixed item, then return the items here so that the more
# complex search can be done in one place and consistently

sub search {
    my $self = shift;
    my ($params) = @_;
    die "search requires a hashref" if ( ref($params) ne 'HASH' );

    my $items = $self->{_handler}->search($params);
}

# -----------------------------------------------------------------------------

=item count

Count the number of items that match a search

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;
    my $items = $store->count( {  
         _tag       => { 'eq'       => 'bill' },
        _timestamp => { 'date:gte' => '2013-01-01 00:00:00', 'date:lte' => '2013-12-31 23:59:59' },
    }) ;

B<Parameters>
  search terms to find items to count
  
=cut

sub count {
    my $self = shift;
    my ($rules) = @_;
    die "count requires a hashref" if ( $rules && ref($rules) ne 'HASH' );

    $self->{_handler}->count($rules);
}

# -----------------------------------------------------------------------------

=item purge items that match a search

Count the number of items with the tag, parameters are optional

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;
    my $items = $store->purge( {  
         _tag       => { 'eq'       => 'bill' },
        _timestamp => { 'date:gte' => '2013-01-01 00:00:00', 'date:lte' => '2013-12-31 23:59:59' },
    }) ;

B<Parameters>
    search terms to find items to purge
  
B<Returns>
    Number of items deleted

=cut

sub purge {
    my $self = shift;
    my ($rules) = @_;
    die "purge requires a hashref" if ( $rules && ref($rules) ne 'HASH' );

    $self->{_handler}->purge($rules);
}

# -----------------------------------------------------------------------------

=back 

=cut

# -----------------------------------------------------------------------------
1;
