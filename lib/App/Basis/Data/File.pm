# ABSTRACT: File based data store access system

=head1 NAME

App::Basis::Data::File

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

You should not use this class directly, it should be called via L<App::Basis::Data>
 
=head1 Todo


=cut

package App::Basis::Data::File;

use strict;
use warnings;
use Data::Printer;
use Try::Tiny;
use Moo;
use Path::Tiny;
use Sereal;
use JSON;
use namespace::clean;

# -----------------------------------------------------------------------------

=head1 Public Functions

=over 4

=cut

=item new

Create a file based instance of the data store

    my $store = App::Basis::Data->new( sri => 'file:///tmp/store') ;

B<Parameters>
  sri storage resource indicator, expected to have file:///
  
=cut

has sri       => ( is => 'ro', required => 1 );
has _dir      => ( is => 'ro', init_arg => undef, default => sub { } );
has _settings => ( is => 'ro', init_arg => undef, default => sub { } );

# has _encoder  => ( is => 'ro', init_arg => undef, default => sub { Sereal::Encoder->new(); } );
# has _decoder  => ( is => 'ro', init_arg => undef, default => sub { Sereal::Decoder->new(); } );
has _encoder => ( is => 'ro', init_arg => undef, default => sub { JSON->new->allow_nonref; } );
has _decoder => ( is => 'ro', init_arg => undef, default => sub { JSON->new->allow_nonref; } );

# -----------------------------------------------------------------------------

# this is where we will initialise _handler with the object that will perform the
# actual data storage functions

sub BUILD {
    my $self = shift;

    my ($mname) = ( __PACKAGE__ =~ /App::Basis::Data::(.*)/ );

    # get the basename of this module, as this is the sri we accept
    $mname = lc($mname);

    my ( $module, $dir ) = ( $self->sri =~ m|^($mname)://(.*)| );

    die "__PACKAGE__ expects a $mname:// sri" if ( !$module );

    die "Cannot build a datastore as sri points to a file" if ( -f $dir );

    try {
        path($dir)->mkpath;    # will die if any issues
    }
    catch {
        die "Cannot build a datastore as issues with sri ";
    };

    # set the directory for the store, remove trailing dir markers
    $dir =~ s|/$||;
    $self->{_dir} = $dir;
    $self->_get_settings();
}

# -----------------------------------------------------------------------------
# load in and decode the settings
sub _get_settings {
    my $self = shift;
    my $path = $self->{_dir} . '/settings';

    try {
        $self->{_settings} = $self->{_decoder}->decode( path($path)->slurp );
    }
    catch {
        # store the defaults
        $self->_store_settings(undef);
    };
}

# -----------------------------------------------------------------------------
# encode and store the settings
sub _store_settings {
    my $self = shift;

    # set defaults if needed
    $self->{_settings} ||= { next_id => '0' };
    say STDERR "dir " . $self->{_dir};
    path( $self->{_dir} . '/settings' )->spew( $self->{_encoder}->encode( $self->{_settings} ) );
}

# -----------------------------------------------------------------------------
# next_id is stored in the settings, this means that settings will be
# reloaded the next_id value updated and saved again
sub _next_id {
    my $self = shift;

    # reload settings and adjust, not quite atomic but fine for simple use
    $self->_get_settings();
    $self->{_settings}->{next_id}++;
    $self->_store_settings();
    return $self->{_settings}->{next_id};
}

# -----------------------------------------------------------------------------
# build a path to access a data item
# we keep things in directories with up to 100 (00..99) items per directory, with 4 levels
# of directory, should allow us to have 100^4 entries in the store!
# we will make
sub _build_path {
    my $self = shift;
    my ( $id, $tag ) = @_;
    $tag ||= 'default';

    # up to 7 leading 0's
    my $fred = sprintf( "%08d", $id );
    my (@b) = ( $fred =~ /(\d{2})/g );
    my $path = $self->{_dir} . "/$tag/data/" . join( '/', @b );

    return $path;
}

# -----------------------------------------------------------------------------
# find the path for a given ID
sub _find_path {
    my $self = shift;
    my ($id) = @_;
    my $path;

    foreach my $tag ( $self->taglist() ) {
        $path = $self->_build_path( $id, $tag );
        last if ( -f $path );
    }

    return $path;
}

# -----------------------------------------------------------------------------
# add and update both use this
sub _store {
    my $self = shift;
    my ( $path, $data ) = @_;

    # make the directory for the file to live in
    path( path($path)->dirname )->mkpath;    # will die if any issues
    path($path)->spew( $self->{_encoder}->encode($data) );
    return -f $path;
}

# -----------------------------------------------------------------------------
# store the passed data as is
sub add {
    my $self = shift;
    my ( $tag, $params ) = @_;
    my $id;
    my $path;

    # lets give ourselves a few chances to create the ID if another process
    # has created it just before use
    while (1) {
        $id = $self->_next_id();
        $path = $self->_build_path( $id, $tag );
        if ( !-f $path ) {
            last;
        }
    }

    if ( !$path ) {
        warn "could not create path";
        return 0;
    }

    # add the ID into the data
    $params->{_id} = $id;
    return $self->_store( $path, $params ) ? $id : undef;
}

# -----------------------------------------------------------------------------
# get the list of all the tags used
sub taglist {
    my $self = shift;
    my @dirs;

    foreach my $dir ( path( $self->{_dir} )->children() ) {
        push @dirs, path($dir)->basename if ( -d $dir );
    }

    return @dirs;
}

# -----------------------------------------------------------------------------
#  only with uniq ID
sub delete {
    my $self = shift;
    my ($id) = @_;

    my $path = $self->_find_path($id);
    if ($path) {
        unlink $path;
    }
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
    my ( $tag, $params ) = @_;
}

sub wildcount {
    my $self = shift;

}

# -----------------------------------------------------------------------------
# get data for a single uniq ID
sub data {
    my $self = shift;
    my ($id) = @_;

    return undef if( !$id) ;
    my $path = $self->_find_path($id);

    return $self->{_decoder}->decode( path($path)->slurp );
}

# -----------------------------------------------------------------------------
# update the data referenced (will add if no uniq ID)
sub update {
    my $self = shift;
    my ($params) = @_;

    # error if no _id or _tag, would have to create new ertry

    my $path = $self->_build_path( $params->{_id}, $params->{_tag} );

    return 0 if ( !$path );

    return $self->_store( $path, $params );
}

# -----------------------------------------------------------------------------
1;