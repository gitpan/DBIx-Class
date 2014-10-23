package DBIx::Class::DB;

use base qw/DBIx::Class/;
use DBIx::Class::Schema;
use DBIx::Class::Storage::DBI;
use DBIx::Class::ClassResolver::PassThrough;
use DBI;

__PACKAGE__->load_components(qw/ResultSetProxy/);

*dbi_commit = \&txn_commit;
*dbi_rollback = \&txn_rollback;

sub storage { shift->schema_instance(@_)->storage; }

sub resultset_instance {
  my $class = shift;
  my $source = $class->result_source_instance;
  if ($source->result_class ne $class) {
    $source = $source->new($source);
    $source->result_class($class);
  }
  return $source->resultset;
}

=head1 NAME 

DBIx::Class::DB - Non-recommended classdata schema component

=head1 SYNOPSIS

  package MyDB;

  use base qw/DBIx::Class/;
  __PACKAGE__->load_components('DB');

  __PACKAGE__->connection('dbi:...', 'user', 'pass', \%attrs);

  package MyDB::MyTable;

  use base qw/MyDB/;
  __PACKAGE__->load_components('Core'); # just load this in MyDB if it will always be there

  ...

=head1 DESCRIPTION

This class is designed to support the Class::DBI connection-as-classdata style
for DBIx::Class. You are *strongly* recommended to use a DBIx::Class::Schema
instead; DBIx::Class::DB will continue to be supported but new development
will be focused on Schema-based DBIx::Class setups.

=head1 METHODS

=head2 storage

Sets or gets the storage backend. Defaults to L<DBIx::Class::Storage::DBI>.

=head2 class_resolver

****DEPRECATED****

Sets or gets the class to use for resolving a class. Defaults to 
L<DBIx::Class::ClassResolver::Passthrough>, which returns whatever you give
it. See resolve_class below.

=cut

__PACKAGE__->mk_classdata('class_resolver' =>
                            'DBIx::Class::ClassResolver::PassThrough');

=head2 connection

  __PACKAGE__->connection($dsn, $user, $pass, $attrs);

Specifies the arguments that will be passed to DBI->connect(...) to
instantiate the class dbh when required.

=cut

sub connection {
  my ($class, @info) = @_;
  $class->setup_schema_instance unless $class->can('schema_instance');
  $class->schema_instance->connection(@info);
}

=head2 setup_schema_instance

Creates a class method ->schema_instance which contains a DBIx::Class::Schema;
all class-method operations are proxies through to this object. If you don't
call ->connection in your DBIx::Class::DB subclass at load time you *must*
call ->setup_schema_instance in order for subclasses to find the schema and
register themselves with it.

=cut

sub setup_schema_instance {
  my $class = shift;
  my $schema = bless({}, 'DBIx::Class::Schema');
  $class->mk_classdata('schema_instance' => $schema);
}

=head2 txn_begin

Begins a transaction (does nothing if AutoCommit is off).

=cut

sub txn_begin { $_[0]->schema_instance->txn_begin }

=head2 txn_commit

Commits the current transaction.

=cut

sub txn_commit { $_[0]->schema_instance->txn_commit }

=head2 txn_rollback

Rolls back the current transaction.

=cut

sub txn_rollback { $_[0]->schema_instance->txn_rollback }

{
  my $warn;

  sub resolve_class {
    warn "resolve_class deprecated as of 0.04999_02" unless $warn++;
    return shift->class_resolver->class(@_);
  }
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

