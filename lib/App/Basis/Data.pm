# ABSTRACT: Generalised data store access system

=head1 NAME

App::Basis::Data

=head1 SYNOPSIS

  use App::Basis::Data ;
 
  my $store = App::Basis::Data->new( sri => 'file:///tmp/fred' ) ;

  my $id = $store->add( tag => 'test', message => 'testing', level => 'debug', counter => 20) ;
  my $test_data = $store->tagsearch( tag => 'test', from => '2014-01-01') ;
  my $large_count_data = $store->wildsearch( counter => { 'gte' => 100} ) ; # or '>='
  my $test_count = $store->tagcount(tag => 'test') ;
  my $data = $store->data( $id) ;
  $data->{counter} = 50 ;
  my $new_id = $store->replace( id=> $id, $data) ;
  say ( $id == $new_id) ? "Data replaced" : "data ccreated" ;
  $store->delete( $id) ;

=head1 DESCRIPTION
 

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
    # so lets als split out any component parts

    my %params = ( sri => $self->sri);
    foreach my $s (split( ';', $self->sri)) {
        my ($k,$v) = ( $c =~ /^(.*)=(.*)/) ;
        $k = _trim( $k) ;
        $params{$k} = _trim( $v) ;
     }


    # and create the required class instance
    $self->{_handler} = $class->new( %params );
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
  timestamp will override automatic timestamp
  source 
  
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
# get the list of all the tags used
sub taglist {
    my $self = shift;
    my ( $tag, $params ) = @_;
    $self->{_handler}->taglist( $tag, $params );
}

# -----------------------------------------------------------------------------
#  only with uniq ID
sub delete {
    my $self   = shift;
    my $params = @_;
    $self->{_handler}->delete($params);
}

# -----------------------------------------------------------------------------
# search for entries matching a single tag

# tagname
# match 'regexp', '='. 'like', '>=' etc
# optional from/to timestamp
# optional count
sub tagsearch {
    my $self = shift;
    my ( $tag, $params ) = @_;
    $params->{from} = $self->_as_timestamp( $params->{from} );
    $params->{to}   = $self->_as_timestamp( $params->{to} );

    $self->{_handler}->tagsearch( $tag, $params );
}

# -----------------------------------------------------------------------------
# search all entries to match some data

# match 'regexp', '='. 'like', '>=' etc
# optional from/to timestamp
# optional count
sub wildsearch {
    my $self   = shift;
    my $params = @_;
    $params->{from} = $self->_as_timestamp( $params->{from} );
    $params->{to}   = $self->_as_timestamp( $params->{to} );

    $self->{_handler}->wildsearch($params);
}

# -----------------------------------------------------------------------------
# Matches the tagsearch and wildsearch, but just returns the number of matching items
# not the items themselves
# optional from/to timestamp
sub tagcount {
    my $self = shift;
    my ( $tag, $params ) = @_;
    $params->{from} = $self->_as_timestamp( $params->{from} );
    $params->{to}   = $self->_as_timestamp( $params->{to} );

    $self->{_handler}->tagcount( $tag, $params );
}

# -----------------------------------------------------------------------------
# optional from/to timestamp
sub wildcount {
    my $self   = shift;
    my $params = @_;
    $params->{from} = $self->_as_timestamp( $params->{from} );
    $params->{to}   = $self->_as_timestamp( $params->{to} );

    $self->{_handler}->wildcount($params);
}

# -----------------------------------------------------------------------------

sub data {
    my $self = shift;
    my ($id) = @_;

    $self->{_handler}->data($id);
}

# -----------------------------------------------------------------------------
# get data for a single uniq ID
sub update {
    my $self = shift;
    my ($params) = @_;
    my $id       = $params->{_id};
    my $current  = $self->data($id);

    if ($current) {
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

=back 

=cut

# -----------------------------------------------------------------------------
1;
