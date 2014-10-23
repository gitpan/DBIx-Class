package # hide from PAUSE
    SQL::Translator::Parser::DBIx::Class;

# AUTHOR: Jess Robinson

# Some mistakes the fault of Matt S Trout

use strict;
use warnings;
use vars qw($DEBUG $VERSION @EXPORT_OK);
$DEBUG = 0 unless defined $DEBUG;
$VERSION = sprintf "%d.%02d", q$Revision 1.0$ =~ /(\d+)\.(\d+)/;

use Exporter;
use Data::Dumper;
use SQL::Translator::Utils qw(debug normalize_name);

use base qw(Exporter);

@EXPORT_OK = qw(parse);

# -------------------------------------------------------------------
# parse($tr, $data)
#
# Note that $data, in the case of this parser, is not useful.
# We're working with DBIx::Class Schemas, not data streams.
# -------------------------------------------------------------------
sub parse {
    my ($tr, $data) = @_;
    my $args        = $tr->parser_args;
    my $dbixschema  = $args->{'DBIx::Schema'} || $data;
    $dbixschema   ||= $args->{'package'};
    
    die 'No DBIx::Schema' unless ($dbixschema);
    if (!ref $dbixschema) {
      eval "use $dbixschema;";
      die "Can't load $dbixschema ($@)" if($@);
    }

    my $schema      = $tr->schema;
    my $table_no    = 0;

#    print Dumper($dbixschema->registered_classes);

    #foreach my $tableclass ($dbixschema->registered_classes)
    foreach my $moniker ($dbixschema->sources)
    {
        #eval "use $tableclass";
        #print("Can't load $tableclass"), next if($@);
        my $source = $dbixschema->source($moniker);

        my $table = $schema->add_table(
                                       name => $source->name,
                                       type => 'TABLE',
                                       ) || die $schema->error;
        my $colcount = 0;
        foreach my $col ($source->columns)
        {
            # assuming column_info in dbix is the same as DBI (?)
            # data_type is a number, column_type is text?
            my %colinfo = (
              name => $col,
              size => 0,
              is_auto_increment => 0,
              is_foreign_key => 0,
              is_nullable => 0,
              %{$source->column_info($col)}
            );
            if ($colinfo{is_nullable}) {
              $colinfo{default} = '' unless exists $colinfo{default};
            }
            my $f = $table->add_field(%colinfo) || die $table->error;
        }
        $table->primary_key($source->primary_columns);

        my @rels = $source->relationships();
        foreach my $rel (@rels)
        {
            my $rel_info = $source->relationship_info($rel);

            my $rel_table = $source->related_source($rel)->name;

            # Ignore any rel cond that isn't a straight hash
            next unless ref $rel_info->{cond} eq 'HASH';

            # Get the key information, mapping off the foreign/self markers
            my @cond = keys(%{$rel_info->{cond}});
            my @refkeys = map {/^\w+\.(\w+)$/} @cond;
            my @keys = map {$rel_info->{cond}->{$_} =~ /^\w+\.(\w+)$/} @cond;

            if($rel_table)
            {

                #Decide if this is a foreign key based on whether the self
                #items are our primary columns.

                # Make sure every self key is in the primary key list
                my $found;
                foreach my $key (@keys) {
                    $found = 0;
                    foreach my $prim ($source->primary_columns) {
                        if ($prim eq $key) {
                            $found = 1;
                            last;
                        }
                    }
                    last unless $found;
                }

                # Make sure every primary key column is in the self keys
                if ($found) {
                    foreach my $prim ($source->primary_columns) {
                        $found = 0;
                        foreach my $key (@keys) {
                            if ($prim eq $key) {
                                $found = 1;
                                last;
                            }
                        }
                        last unless $found;
                    }
                }

                # if $found then the two sets are equal.

                # If the sets are different, then we assume it's a foreign key from
                # us to another table.
                if (!$found) {
                    $table->add_constraint(
                                type             => 'foreign_key',
                                name             => "fk_$keys[0]",
                                fields           => \@keys,
                                reference_fields => \@refkeys,
                                reference_table  => $rel_table,
                    );
                }
            }
        }
    }
    return 1;
}

1;
