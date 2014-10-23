package DBIx::Class::ResultSource;

use strict;
use warnings;

use DBIx::Class::ResultSet;
use Carp::Clan qw/^DBIx::Class/;
use Storable;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/_ordered_columns _columns _primaries _unique_constraints name resultset_attributes schema from _relationships/);
__PACKAGE__->mk_group_accessors('component_class' => qw/resultset_class result_class/);

=head1 NAME 

DBIx::Class::ResultSource - Result source object

=head1 SYNOPSIS

=head1 DESCRIPTION

A ResultSource is a component of a schema from which results can be directly
retrieved, most usually a table (see L<DBIx::Class::ResultSource::Table>)

=head1 METHODS

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;
  my $new = bless({ %{$attrs || {}}, _resultset => undef }, $class);
  $new->{resultset_class} ||= 'DBIx::Class::ResultSet';
  $new->{resultset_attributes} = { %{$new->{resultset_attributes} || {}} };
  $new->{_ordered_columns} = [ @{$new->{_ordered_columns}||[]}];
  $new->{_columns} = { %{$new->{_columns}||{}} };
  $new->{_relationships} = { %{$new->{_relationships}||{}} };
  $new->{name} ||= "!!NAME NOT SET!!";
  $new->{_columns_info_loaded} ||= 0;
  return $new;
}

=pod

=head2 add_columns

  $table->add_columns(qw/col1 col2 col3/);

  $table->add_columns('col1' => \%col1_info, 'col2' => \%col2_info, ...);

Adds columns to the result source. If supplied key => hashref pairs uses
the hashref as the column_info for that column.

Repeated calls of this method will add more columns, not replace them.

The contents of the column_info are not set in stone, the following
keys are currently recognised/used by DBIx::Class. 

=over 4

=item accessor 

Use this to set the name of the accessor for this column. If unset,
the name of the column will be used.

=item data_type

This contains the column type, it is automatically filled by the
L<SQL::Translator::Producer::DBIx::Class::File> producer, and the
L<DBIx::Class::Schema::Loader> module. If you do not enter the
data_type, DBIx::Class will attempt to retrieve it from the
database for you, using L<DBI>s column_info method. The values of this
key are typically upper-cased.

Currently there is no standard set of values for the data_type, use
whatever your database(s) support.

=item size

The length of your column, if it is a column type that can have a size
restriction. This is currently not used by DBIx::Class. 

=item is_nullable

If the column is allowed to contain NULL values, set a true value
(typically 1), here. This is currently not used by DBIx::Class.

=item is_auto_increment

Set this to a true value if this is a column that is somehow
automatically filled. This is currently not used by DBIx::Class.

=item is_foreign_key

Set this to a true value if this column represents a key from a
foreign table. This is currently not used by DBIx::Class.

=item default_value

Set this to the default value which will be inserted into this column
by the database. Can contain either values or functions. This is
currently not used by DBIx::Class. 

=item sequence

If your column is using a sequence to create it's values, set the name
of the sequence here, to allow the values to be retrieved
automatically by the L<DBIx::Class::PK::Auto> module. PK::Auto will
attempt to retrieve the sequence name from the database, if this value
is left unset.

=back

=head2 add_column

  $table->add_column('col' => \%info?);

Convenience alias to add_columns

=cut

sub add_columns {
  my ($self, @cols) = @_;
  $self->_ordered_columns(\@cols) unless $self->_ordered_columns;
  
  my @added;
  my $columns = $self->_columns;
  while (my $col = shift @cols) {
    # If next entry is { ... } use that for the column info, if not
    # use an empty hashref
    my $column_info = ref $cols[0] ? shift(@cols) : {};
    push(@added, $col) unless exists $columns->{$col};
    $columns->{$col} = $column_info;
  }
  push @{ $self->_ordered_columns }, @added;
  return $self;
}

*add_column = \&add_columns;

=head2 has_column

  if ($obj->has_column($col)) { ... }

Returns 1 if the source has a column of this name, 0 otherwise.

=cut

sub has_column {
  my ($self, $column) = @_;
  return exists $self->_columns->{$column};
}

=head2 column_info

  my $info = $obj->column_info($col);

Returns the column metadata hashref for a column. See the description
of add_column for information on the contents of the hashref.

=cut

sub column_info {
  my ($self, $column) = @_;
  $self->throw_exception("No such column $column") 
    unless exists $self->_columns->{$column};
  #warn $self->{_columns_info_loaded}, "\n";
  if ( ! $self->_columns->{$column}{data_type} 
       and ! $self->{_columns_info_loaded} 
       and $self->schema and $self->storage )
  {
    $self->{_columns_info_loaded}++;
    my $info;
    # eval for the case of storage without table 
    eval { $info = $self->storage->columns_info_for($self->from) };
    unless ($@) {
      foreach my $col ( keys %{$self->_columns} ) {
        foreach my $i ( keys %{$info->{$col}} ) {
            $self->_columns->{$col}{$i} = $info->{$col}{$i};
        }
      }
    }
  }
  return $self->_columns->{$column};
}

=head2 columns

  my @column_names = $obj->columns;

Returns all column names in the order they were declared to add_columns

=cut

sub columns {
  my $self = shift;
  $self->throw_exception("columns() is a read-only accessor, did you mean add_columns()?") if (@_ > 1);
  return @{$self->{_ordered_columns}||[]};
}

=head2 set_primary_key

=head3 Arguments: (@cols)

Defines one or more columns as primary key for this source. Should be
called after C<add_columns>.

Additionally, defines a unique constraint named C<primary>.

The primary key columns are used by L<DBIx::Class::PK::Auto> to
retrieve automatically created values from the database. 

=cut

sub set_primary_key {
  my ($self, @cols) = @_;
  # check if primary key columns are valid columns
  foreach my $col (@cols) {
    $self->throw_exception("No such column $col on table " . $self->name)
      unless $self->has_column($col);
  }
  $self->_primaries(\@cols);

  $self->add_unique_constraint(primary => \@cols);
}

=head2 primary_columns

Read-only accessor which returns the list of primary keys.

=cut

sub primary_columns {
  return @{shift->_primaries||[]};
}

=head2 add_unique_constraint

Declare a unique constraint on this source. Call once for each unique
constraint. Unique constraints are used when you call C<find> on a
L<DBIx::Class::ResultSet>, only columns in the constraint are searched,

  # For e.g. UNIQUE (column1, column2)
  __PACKAGE__->add_unique_constraint(constraint_name => [ qw/column1 column2/ ]);

=cut

sub add_unique_constraint {
  my ($self, $name, $cols) = @_;

  foreach my $col (@$cols) {
    $self->throw_exception("No such column $col on table " . $self->name)
      unless $self->has_column($col);
  }

  my %unique_constraints = $self->unique_constraints;
  $unique_constraints{$name} = $cols;
  $self->_unique_constraints(\%unique_constraints);
}

=head2 unique_constraints

Read-only accessor which returns the list of unique constraints on this source.

=cut

sub unique_constraints {
  return %{shift->_unique_constraints||{}};
}

=head2 from

Returns an expression of the source to be supplied to storage to specify
retrieval from this source; in the case of a database the required FROM clause
contents.

=cut

=head2 storage

Returns the storage handle for the current schema. 

See also: L<DBIx::Class::Storage>

=cut

sub storage { shift->schema->storage; }

=head2 add_relationship

  $source->add_relationship('relname', 'related_source', $cond, $attrs);

The relation name can be arbitrary, but must be unique for each relationship
attached to this result source. 'related_source' should be the name with
which the related result source was registered with the current schema
(for simple schemas this is usally either Some::Namespace::Foo or just Foo)

The condition needs to be an SQL::Abstract-style representation of the join
between the tables. For example, if you're creating a rel from Author to Book,

  { 'foreign.author_id' => 'self.id' }

will result in the JOIN clause

  author me JOIN book foreign ON foreign.author_id = me.id

You can specify as many foreign => self mappings as necessary.

Valid attributes are as follows:

=over 4

=item join_type

Explicitly specifies the type of join to use in the relationship. Any
SQL join type is valid, e.g. C<LEFT> or C<RIGHT>. It will be placed in
the SQL command immediately before C<JOIN>.

=item proxy

An arrayref containing a list of accessors in the foreign class to
proxy in the main class. If, for example, you do the following: 

  __PACKAGE__->might_have(bar => 'Bar', undef, { proxy => [ qw/margle/] }); 

Then, assuming Bar has an accessor named margle, you can do:

  my $obj = Foo->find(1);
  $obj->margle(10); # set margle; Bar object is created if it doesn't exist

=item accessor

Specifies the type of accessor that should be created for the
relationship. Valid values are C<single> (for when there is only a single 
related object), C<multi> (when there can be many), and C<filter> (for 
when there is a single related object, but you also want the relationship 
accessor to double as a column accessor). For C<multi> accessors, an 
add_to_* method is also created, which calls C<create_related> for the 
relationship.

=back

=cut

sub add_relationship {
  my ($self, $rel, $f_source_name, $cond, $attrs) = @_;
  $self->throw_exception("Can't create relationship without join condition") unless $cond;
  $attrs ||= {};

  my %rels = %{ $self->_relationships };
  $rels{$rel} = { class => $f_source_name,
                  source => $f_source_name,
                  cond  => $cond,
                  attrs => $attrs };
  $self->_relationships(\%rels);

  return $self;

  # XXX disabled. doesn't work properly currently. skip in tests.

  my $f_source = $self->schema->source($f_source_name);
  unless ($f_source) {
    eval "require $f_source_name;";
    if ($@) {
      die $@ unless $@ =~ /Can't locate/;
    }
    $f_source = $f_source_name->result_source;
    #my $s_class = ref($self->schema);
    #$f_source_name =~ m/^${s_class}::(.*)$/;
    #$self->schema->register_class(($1 || $f_source_name), $f_source_name);
    #$f_source = $self->schema->source($f_source_name);
  }
  return unless $f_source; # Can't test rel without f_source

  eval { $self->resolve_join($rel, 'me') };

  if ($@) { # If the resolve failed, back out and re-throw the error
    delete $rels{$rel}; # 
    $self->_relationships(\%rels);
    $self->throw_exception("Error creating relationship $rel: $@");
  }
  1;
}

=head2 relationships

Returns all valid relationship names for this source

=cut

sub relationships {
  return keys %{shift->_relationships};
}

=head2 relationship_info

=head3 Arguments: ($relname)

Returns the relationship information for the specified relationship name

=cut

sub relationship_info {
  my ($self, $rel) = @_;
  return $self->_relationships->{$rel};
} 

=head2 has_relationship

=head3 Arguments: ($rel)

Returns 1 if the source has a relationship of this name, 0 otherwise.

=cut

sub has_relationship {
  my ($self, $rel) = @_;
  return exists $self->_relationships->{$rel};
}

=head2 resolve_join

=head3 Arguments: ($relation)

Returns the join structure required for the related result source

=cut

sub resolve_join {
  my ($self, $join, $alias, $seen) = @_;
  $seen ||= {};
  if (ref $join eq 'ARRAY') {
    return map { $self->resolve_join($_, $alias, $seen) } @$join;
  } elsif (ref $join eq 'HASH') {
    return
      map {
        my $as = ($seen->{$_} ? $_.'_'.($seen->{$_}+1) : $_);
        ($self->resolve_join($_, $alias, $seen),
          $self->related_source($_)->resolve_join($join->{$_}, $as, $seen));
      } keys %$join;
  } elsif (ref $join) {
    $self->throw_exception("No idea how to resolve join reftype ".ref $join);
  } else {
    my $count = ++$seen->{$join};
    #use Data::Dumper; warn Dumper($seen);
    my $as = ($count > 1 ? "${join}_${count}" : $join);
    my $rel_info = $self->relationship_info($join);
    $self->throw_exception("No such relationship ${join}") unless $rel_info;
    my $type = $rel_info->{attrs}{join_type} || '';
    return [ { $as => $self->related_source($join)->from,
               -join_type => $type },
             $self->resolve_condition($rel_info->{cond}, $as, $alias) ];
  }
}

=head2 resolve_condition

=head3 Arguments: ($cond, $as, $alias|$object)

Resolves the passed condition to a concrete query fragment. If given an alias,
returns a join condition; if given an object, inverts that object to produce
a related conditional from that object.

=cut

sub resolve_condition {
  my ($self, $cond, $as, $for) = @_;
  #warn %$cond;
  if (ref $cond eq 'HASH') {
    my %ret;
    while (my ($k, $v) = each %{$cond}) {
      # XXX should probably check these are valid columns
      $k =~ s/^foreign\.// || $self->throw_exception("Invalid rel cond key ${k}");
      $v =~ s/^self\.// || $self->throw_exception("Invalid rel cond val ${v}");
      if (ref $for) { # Object
        #warn "$self $k $for $v";
        $ret{$k} = $for->get_column($v);
        #warn %ret;
      } elsif (ref $as) { # reverse object
        $ret{$v} = $as->get_column($k);
      } else {
        $ret{"${as}.${k}"} = "${for}.${v}";
      }
    }
    return \%ret;
  } elsif (ref $cond eq 'ARRAY') {
    return [ map { $self->resolve_condition($_, $as, $for) } @$cond ];
  } else {
   die("Can't handle this yet :(");
  }
}

=head2 resolve_prefetch

=head3 Arguments: (hashref/arrayref/scalar)

Accepts one or more relationships for the current source and returns an
array of column names for each of those relationships. Column names are
prefixed relative to the current source, in accordance with where they appear
in the supplied relationships. Examples:

  my $source = $schema->resultset('Tag')->source;
  @columns = $source->resolve_prefetch( { cd => 'artist' } );

  # @columns =
  #(
  #  'cd.cdid',
  #  'cd.artist',
  #  'cd.title',
  #  'cd.year',
  #  'cd.artist.artistid',
  #  'cd.artist.name'
  #)

  @columns = $source->resolve_prefetch( qw[/ cd /] );

  # @columns =
  #(
  #   'cd.cdid',
  #   'cd.artist',
  #   'cd.title',
  #   'cd.year'
  #)

  $source = $schema->resultset('CD')->source;
  @columns = $source->resolve_prefetch( qw[/ artist producer /] );

  # @columns =
  #(
  #  'artist.artistid',
  #  'artist.name',
  #  'producer.producerid',
  #  'producer.name'
  #)  

=cut

sub resolve_prefetch {
  my ($self, $pre, $alias, $seen, $order, $collapse) = @_;
  $seen ||= {};
  #$alias ||= $self->name;
  #warn $alias, Dumper $pre;
  if( ref $pre eq 'ARRAY' ) {
    return
      map { $self->resolve_prefetch( $_, $alias, $seen, $order, $collapse ) }
        @$pre;
  }
  elsif( ref $pre eq 'HASH' ) {
    my @ret =
    map {
      $self->resolve_prefetch($_, $alias, $seen, $order, $collapse),
      $self->related_source($_)->resolve_prefetch(
               $pre->{$_}, "${alias}.$_", $seen, $order, $collapse)
    } keys %$pre;
    #die Dumper \@ret;
    return @ret;
  }
  elsif( ref $pre ) {
    $self->throw_exception(
      "don't know how to resolve prefetch reftype ".ref($pre));
  }
  else {
    my $count = ++$seen->{$pre};
    my $as = ($count > 1 ? "${pre}_${count}" : $pre);
    my $rel_info = $self->relationship_info( $pre );
    $self->throw_exception( $self->name . " has no such relationship '$pre'" )
      unless $rel_info;
    my $as_prefix = ($alias =~ /^.*?\.(.+)$/ ? $1.'.' : '');
    my $rel_source = $self->related_source($pre);

    if (exists $rel_info->{attrs}{accessor}
         && $rel_info->{attrs}{accessor} eq 'multi') {
      $self->throw_exception(
        "Can't prefetch has_many ${pre} (join cond too complex)")
        unless ref($rel_info->{cond}) eq 'HASH';
      my @key = map { (/^foreign\.(.+)$/ ? ($1) : ()); }
                    keys %{$rel_info->{cond}};
      $collapse->{"${as_prefix}${pre}"} = \@key;
      my @ord = (ref($rel_info->{attrs}{order_by}) eq 'ARRAY'
                   ? @{$rel_info->{attrs}{order_by}}
                   : (defined $rel_info->{attrs}{order_by}
                       ? ($rel_info->{attrs}{order_by})
                       : ()));
      push(@$order, map { "${as}.$_" } (@key, @ord));
    }

    return map { [ "${as}.$_", "${as_prefix}${pre}.$_", ] }
      $rel_source->columns;
    #warn $alias, Dumper (\@ret);
    #return @ret;
  }
}

=head2 related_source

=head3 Arguments: ($relname)

Returns the result source object for the given relationship

=cut

sub related_source {
  my ($self, $rel) = @_;
  if( !$self->has_relationship( $rel ) ) {
    $self->throw_exception("No such relationship '$rel'");
  }
  return $self->schema->source($self->relationship_info($rel)->{source});
}

=head2 resultset

Returns a resultset for the given source, by calling:

  $self->resultset_class->new($self, $self->resultset_attributes)

=head2 resultset_class

Set the class of the resultset, this is useful if you want to create your
own resultset methods. Create your own class derived from
L<DBIx::Class::ResultSet>, and set it here.

=head2 resultset_attributes

Specify here any attributes you wish to pass to your specialised resultset.

=cut

sub resultset {
  my $self = shift;
  $self->throw_exception('resultset does not take any arguments. If you want another resultset, call it on the schema instead.') if scalar @_;
  return $self->{_resultset} if ref $self->{_resultset} eq $self->resultset_class;
  return $self->{_resultset} = $self->resultset_class->new($self, $self->{resultset_attributes});
}

=head2 throw_exception

See throw_exception in L<DBIx::Class::Schema>.

=cut

sub throw_exception {
  my $self = shift;
  if (defined $self->schema) { 
    $self->schema->throw_exception(@_);
  } else {
    croak(@_);
  }
}


=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

