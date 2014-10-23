package DBIx::Class::Storage::DBI::Oracle::Generic;
# -*- mode: cperl; cperl-indent-level: 2 -*-

use strict;
use warnings;

=head1 NAME

DBIx::Class::Storage::DBI::Oracle::Generic - Automatic primary key class for Oracle

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->add_columns({ id => { sequence => 'mysequence', auto_nextval => 1 } });
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->sequence('mysequence');

=head1 DESCRIPTION

This class implements autoincrements for Oracle.

=head1 METHODS

=cut

use Carp::Clan qw/^DBIx::Class/;

use base qw/DBIx::Class::Storage::DBI::MultiDistinctEmulation/;

# __PACKAGE__->load_components(qw/PK::Auto/);

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, @columns) = @_;
  my @ids = ();
  foreach my $col (@columns) {
    my $seq = ($source->column_info($col)->{sequence} ||= $self->get_autoinc_seq($source,$col));
    my $id = $self->_sequence_fetch( 'currval', $seq );
    push @ids, $id;
  }
  return @ids;
}

sub _dbh_get_autoinc_seq {
  my ($self, $dbh, $source, $col) = @_;

  # look up the correct sequence automatically
  my $sql = q{
    SELECT trigger_body FROM ALL_TRIGGERS t
    WHERE t.table_name = ?
    AND t.triggering_event = 'INSERT'
    AND t.status = 'ENABLED'
  };

  # trigger_body is a LONG
  $dbh->{LongReadLen} = 64 * 1024 if ($dbh->{LongReadLen} < 64 * 1024);

  my $sth = $dbh->prepare($sql);
  $sth->execute( uc($source->name) );
  while (my ($insert_trigger) = $sth->fetchrow_array) {
    return uc($1) if $insert_trigger =~ m!(\w+)\.nextval!i; # col name goes here???
  }
  $self->throw_exception("Unable to find a sequence INSERT trigger on table '" . $source->name . "'.");
}

sub _sequence_fetch {
  my ( $self, $type, $seq ) = @_;
  my ($id) = $self->dbh->selectrow_array("SELECT ${seq}.${type} FROM DUAL");
  return $id;
}

=head2 get_autoinc_seq

Returns the sequence name for an autoincrement column

=cut

sub get_autoinc_seq {
  my ($self, $source, $col) = @_;
    
  $self->dbh_do('_dbh_get_autoinc_seq', $source, $col);
}

=head2 columns_info_for

This wraps the superclass version of this method to force table
names to uppercase

=cut

sub columns_info_for {
  my ($self, $table) = @_;

  $self->next::method(uc($table));
}

=head2 datetime_parser_type

This sets the proper DateTime::Format module for use with
L<DBIx::Class::InflateColumn::DateTime>.

=cut

sub datetime_parser_type { return "DateTime::Format::Oracle"; }

sub _svp_begin {
    my ($self, $name) = @_;
 
    $self->dbh->do("SAVEPOINT $name");
}

# Oracle automatically releases a savepoint when you start another one with the
# same name.
sub _svp_release { 1 }

sub _svp_rollback {
    my ($self, $name) = @_;

    $self->dbh->do("ROLLBACK TO SAVEPOINT $name")
}

=head1 AUTHORS

Andy Grundman <andy@hybridized.org>

Scott Connelly <scottsweep@yahoo.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
