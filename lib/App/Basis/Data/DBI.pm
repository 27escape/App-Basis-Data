# ABSTRACT: XXXXXX based data store access system

=head1 NAME

App::Basis::Data::Xxxxxx

=head1 SYNOPSIS

  use App::Basis::Data ;
 
  my $store = App::Basis::Data->new( sri => 'xxxxxx:///tmp/fred' ) ;

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

 
=head1 See Also


=head1 Todo


=cut

package App::Basis::Data::Xxxxxx;

use strict;
use warnings;
use Data::Printer;
use Try::Tiny;
use Moo;
use Path::Tiny;
use Sereal;
use namespace::clean;

# -----------------------------------------------------------------------------

=head1 Public Functions

=over 4

=cut

=item new

Create a file based instance of the data store

    my $store = App::Basis::Data->new( sri => 'Xxxxxx:///tmp/store') ;

B<Parameters>
  sri storage resource indicator, expected to have Xxxxxx:///
  
=cut

has sri => ( is => 'ro', required => 1 );

# -----------------------------------------------------------------------------

# this is where we will initialise _handler with the object that will perform the
# actual data storage functions

sub BUILD {
    my $self = shift;

    my ($mname) = ( __PACKAGE__ =~ /App::Basis::Data::(.*)/) ;
    # get the basename of this module, as this is the sri we accept
    $mname = lc( $mname) ;

    my ( $module, $dir ) = ( $self->sri =~ m|^($mname)://(.*)| );

    die "__PACKAGE__ expects a $mname:// sri" if ( !$module );


}

# -----------------------------------------------------------------------------
sub add {
    my $self = shift;
    my ($tag, $params) = @_;
}

# -----------------------------------------------------------------------------
#  only with uniq ID
sub delete {
    my $self = shift;
    my ($id) = @_ ;
}

# -----------------------------------------------------------------------------
# get the list of all the tags used
sub taglist {
    my $self = shift;
}

# -----------------------------------------------------------------------------
# search for entries matching a single tag

# tagname
# match 'regexp', '='. 'like', '>=' etc
# optional from/to timestamp
# optional count
sub tagsearch {
    my $self = shift;
    my ($tag, $params) = @_;
}

# -----------------------------------------------------------------------------
# search all entries to match some data

# match 'regexp', '='. 'like', '>=' etc
# optional from/to timestamp
# optional count
sub wildsearch {
    my $self = shift;
}

# -----------------------------------------------------------------------------
# Matches the tagsearch and wildsearch, but just returns the number of matching items
# not the items themselves
sub tagcount {
    my $self = shift;
    my ($tag, $params) = @_;
}

sub wildcount {
    my $self = shift;
}

# -----------------------------------------------------------------------------
# get data for a single uniq ID
sub data {
    my $self = shift;
}

# -----------------------------------------------------------------------------
# update the data referenced (will add if no uniq ID)
sub update {
    my $self = shift;
    my ($data) = @_ ;

    # error if no _id or _tag, would have to create new ertry

    my $path = $self->_build_path( $data->{_id}, $data->{_tag}) ;
    my $alt = $self->_find_path( $data->{id}) ;
    # alt and path should match
}
# -----------------------------------------------------------------------------
1;
