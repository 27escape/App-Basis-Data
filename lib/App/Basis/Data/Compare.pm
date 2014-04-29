# ABSTRACT: Compare a data item against some rules

=head1 NAME

App::Basis::Data::Compare

=head1 DESCRIPTION

Compare top fields in a hashref against a set of rules
 
=head1 AUTHOR

 kevin mulholland

=head1 VERSIONS

v0.1  2014/04/26, initial work

=head1 About dates and time comparisons

Dates are converted using 

Time and date comparisons will be slow as both sides need to be converted into
numbers before the comparison can take place, to keep things simple the scale of the
check of date:eq or time:eq depends on the scale of the rule
 
    rule time:eq 12:00 will match 12:00 and 12:00:37
    rule date:eq 2014-12-02 will match "2014-12-02", "2014-12-02 03:45" and "2014-12-02 05:45:34"

For most things before and after will be enough, before is considered to be a less than or equal comparison
after is a greater than or equal comparison

    rule time:gte 12:00  will match 12:00:00 and values after 12:00:01 
    rule date:lte 2014-12-02 will match "2014-12-02 00:00:00" and values before "2014-12-01 23:59:59"

Dates for rules should alisoways use the iso 8601 form "YYYY-mm-dd HH:MM:SS" the time part is optional

Time comparisons will extract HH:MM[:SS] from any string

=head1 See Also

L<App::Basis::Data>

=cut

package App::Basis::Data::Compare;

use 5.10.0;
use strict;
use warnings;
use Data::Printer;
use Try::Tiny;
use Exporter;
use Date::Manip;
use namespace::clean;
use POSIX qw(strftime);
use feature 'state';
use vars qw( @EXPORT @ISA);

@ISA = qw(Exporter);

# this is the list of things that will get imported into the loading packages
# namespace
@EXPORT = qw( compare);

# -----------------------------------------------------------------------------

my $time_regexp = '(\d{2}:\d{2}(:\d{2})?)';
my $date_regexp = '(\d{4}-\d{2}-\d{2}([ T](\d{2}:\d{2}(:\d{2})?)?)?)';

# -----------------------------------------------------------------------------
sub _as_datestr {
    state $dm = Date::Manip::Date->new();

    my ($date) = @_;
    my $datestr;

    return if ( !defined $date );

    # we may have to convert the timestamp
    if ( !$date || $date =~ /^\d+$/ ) {
        $datestr = strftime( '%Y-%m-%d %H:%M:%S', gmtime($date) );
    }
    else {
        # reuse the date::manip object
        $dm->parse($date);
        {
            # if we get a warning about converting the date to a day, there
            # must be a problem with parsing the input date string
            local $SIG{__WARN__} = sub {
                die "Invalid date";
            };
            my $day = $dm->printf("%a");
            if ($day) {
                $datestr = strftime( '%Y-%m-%d %H:%M:%S', gmtime( $dm->secs_since_1970_GMT ) );
            }
        }
    }

    return $datestr;
}

# -----------------------------------------------------------------------------
# find some dates and put them into a format ready for comparisons
sub _process_dates {
    my ( $first, $second ) = @_;
    my ($a) = ( $first  =~ /$date_regexp/ );
    my ($b) = ( $second =~ /$date_regexp/ );

    # resort to Date::Manip if needed
    $a = _as_datestr($first)  if ( !$a );
    $b = _as_datestr($second) if ( !$b );

    # now we have datestrings, lets see how we need to limit them against the rules
    if ( $a && $b ) {

        # make sure we make the sizes the same
        if ( length($a) > length($b) ) {
            $a = substr( $a, 0, length($b) );
        }
        elsif ( length($a) == 18 && length($b) == 24 ) {
            $a = "$a:00";
        }
        elsif ( length($a) == 12 && length($b) == 24 ) {
            $a = "$a 00:00:00";
        }
    }

    # if either is bad set $a as bad, so its an easy compare
    $a = undef if ( !$a || !$b );

    return ( $a, $b );
}

# -----------------------------------------------------------------------------
# find some times and put them into a format ready for comparisons
sub _process_times {
    my ( $first, $second ) = @_;
    my ($a) = ( $first  =~ /$time_regexp/ );
    my ($b) = ( $second =~ /$time_regexp/ );
    if ( $a && $b ) {

        # make sure we make the sizes the same
        if ( length($b) == 5 ) {
            $a = substr( $a, 0, 5 );
        }
        elsif ( length($a) == 5 && length($b) == 8 ) {
            $a = "$a:00";
        }
    }

    # if either is bad set $a as bad, so its an easy compare
    $a = undef if ( !$a || !$b );

    return ( $a, $b );
}

# -----------------------------------------------------------------------------

=head1 Public Functions

=over 4

=cut

=item compare

Compare a data item against some rules, all rules must pass

    my $data = {
        tag => 'fred', thing2 => 'sample'
    } ;
    my $rules = { 
            tag => { 'eq' => 'fred'},
            thing2 => { '~' => 'a'},
        } ;

    say "matched" if( compare( $data, $rules)) ;

The rules have a field name that is expected to exist in the data, this holds
a number of ways to match the data item.
    
    eq, ne, gte|ge, gt, lt, lte|le   string based comparisons
    =, !=, =>, >, <, <=, number based comparisons
    ~|=~ match using regular expressions, caseless, becomes  =~ /$regexp/i
    !~   inverted match using regular expressions, caseless, becomes !~ /$regexp/i
    add 'date:' or 'time:' to string comparisons to convert to valid dates/times, no 'ne' 
    date or time comparisons though

if there is not a field in data for a rule field then we will assume that the
comparison fails unless the sloppy flag is used

B<Parameters>
  data      hashref of data items, single level
  rules     hashref of rules
  sloppy    optional flag to allow rule fields to be missing in the data
  
B<Returns>
    True if data matched all the rules, otherwise false

=cut

my %_bad_refs = ( ARRAY => 1, HASH => 1, CODE => 1, REF => 1, GLOB => 1, LVALUE => 1, FORMAT => 1, IO => 1, VSTRING => 1, Regexp => 1 );

sub compare {
    my ( $data, $rules, $sloppy ) = @_;
    my $result     = 1;
    my $matched    = 0;
    my $rule_count = 0;

    foreach my $field ( keys %{$rules} ) {
        $rule_count++;
        if ( !$data->{$field} ) {

            if ($sloppy) {
                next;
            }
            else {
                # no data for a field, then it must fail
                $result = 0;
                last;
            }
        }
        else {
            # if we are being sloppy we need to
            $data->{$field} //= "" if ($sloppy);

            # test against references we do not want to handle
            if ( $_bad_refs{ ref( $data->{$field} ) } ) {
                warn "Attempt to search using a complex data item ($field)";
                $result = 0;
                last;
            }

            foreach my $cmp ( keys %{ $rules->{$field} } ) {

                # we could do this as a function lookup, but as its simple, we
                # will just have lots of if statements
                # string comparisons use "" . to coerce into a string
                # numeric comparisons use 0 + to coerce into a number
                if ( $cmp eq '=' ) {
                    $result = ( 0 + $data->{$field} ) == ( 0 + $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq '!=' ) {
                    $result = ( 0 + $data->{$field} ) != ( 0 + $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq '>' ) {
                    $result = ( 0 + $data->{$field} ) > ( 0 + $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq '=>' || $cmp eq '>=' ) {
                    $result = 0 + ( $data->{$field} ) >= ( 0 + $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq '<' ) {
                    $result = ( 0 + $data->{$field} ) < ( 0 + $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq '<=' || $cmp eq '=<' ) {
                    $result = ( 0 + $data->{$field} ) <= ( 0 + $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq 'eq' ) {
                    $result = ( "" . $data->{$field} ) eq ( "" . $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq 'ne' ) {
                    $result = ( "" . $data->{$field} ) ne ( "" . $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq 'gt' ) {
                    $result = ( "" . $data->{$field} ) gt( "" . $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq 'gte' || $cmp eq 'ge' ) {
                    $result = ( "" . $data->{$field} ) ge( "" . $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq 'lt' ) {
                    $result = ( "" . $data->{$field} ) lt( "" . $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq 'lte' || $cmp eq 'le' ) {
                    $result = ( "" . $data->{$field} ) le( "" . $rules->{$field}->{$cmp} );
                }
                elsif ( $cmp eq '~' || $cmp eq '=~' ) {
                    $result = ( "" . $data->{$field} ) =~ /$rules->{$field}->{$cmp}/i;
                }
                elsif ( $cmp eq '!~' ) {
                    $result = ( "" . $data->{$field} ) !~ /$rules->{$field}->{$cmp}/i;
                }
                elsif ( $cmp eq 'date:lt' || $cmp eq 'date:before' ) {
                    my ( $a, $b ) = _process_dates( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a lt $b : 0;
                }
                elsif ( $cmp eq 'date:lte' || $cmp eq 'date:le' ) {
                    my ( $a, $b ) = _process_dates( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a le $b : 0;
                }
                elsif ( $cmp eq 'date:eq' ) {
                    my ( $a, $b ) = _process_dates( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a eq $b : 0;
                }
                elsif ( $cmp eq 'date:gt' || $cmp eq 'date:after' ) {
                    my ( $a, $b ) = _process_dates( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a gt $b : 0;
                }
                elsif ( $cmp eq 'date:gte' || $cmp eq 'date:ge' ) {
                    my ( $a, $b ) = _process_dates( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a ge $b : 0;
                }
                elsif ( $cmp eq 'time:lt' || $cmp eq 'time:before' ) {
                    my ( $a, $b ) = _process_times( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a lt $b : 0;
                }
                elsif ( $cmp eq 'time:lte' || $cmp eq 'time:le' ) {
                    my ( $a, $b ) = _process_times( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a le $b : 0;
                }
                elsif ( $cmp eq 'time:eq' ) {
                    my ( $a, $b ) = _process_times( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a eq $b : 0;
                }
                elsif ( $cmp eq 'time:gt' || $cmp eq 'time:after' ) {
                    my ( $a, $b ) = _process_times( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a gt $b : 0;
                }
                elsif ( $cmp eq 'time:gte' || $cmp eq 'time:ge' ) {
                    my ( $a, $b ) = _process_times( $data->{$field}, $rules->{$field}->{$cmp} );
                    $result = ( $a && $b ) ? $a ge $b : 0;
                }
                else {
                    die "Unknown comparison $cmp";
                }

                # string compares may return '' rather than 0
                $result = 0 if ( $result eq '' );
                last if ( !$result && !$sloppy );
            }

            $matched += $result;
        }

        # if any compare failed then we can drop out early
        last if ( !$result && !$sloppy );
    }

    # even if we are sloppy we need to match at least a single rule
    if ($sloppy) {
        $result = 0 if ( !$matched );
    }
    else {
        $result = 0 if ( $matched && $matched != $rule_count );
    }
    return $result;
}

# -----------------------------------------------------------------------------

=back 

=cut

# -----------------------------------------------------------------------------
1;
