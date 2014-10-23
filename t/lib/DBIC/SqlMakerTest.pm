package DBIC::SqlMakerTest;

use strict;
use warnings;

use base qw/Test::Builder::Module Exporter/;

our @EXPORT = qw/
  &is_same_sql_bind
  &is_same_sql
  &is_same_bind
  &eq_sql
  &eq_bind
  &eq_sql_bind
/;


{
  package DBIC::SqlMakerTest::SQLATest;

  # replacement for SQL::Abstract::Test if not available

  use strict;
  use warnings;

  use base qw/Test::Builder::Module Exporter/;

  use Scalar::Util qw(looks_like_number blessed reftype);
  use Data::Dumper;
  use Test::Builder;
  use Test::Deep qw(eq_deeply);

  our $tb = __PACKAGE__->builder;

  sub is_same_sql_bind
  {
    my ($sql1, $bind_ref1, $sql2, $bind_ref2, $msg) = @_;

    my $same_sql = eq_sql($sql1, $sql2);
    my $same_bind = eq_bind($bind_ref1, $bind_ref2);

    $tb->ok($same_sql && $same_bind, $msg);

    if (!$same_sql) {
      _sql_differ_diag($sql1, $sql2);
    }
    if (!$same_bind) {
      _bind_differ_diag($bind_ref1, $bind_ref2);
    }
  }

  sub is_same_sql
  {
    my ($sql1, $sql2, $msg) = @_;

    my $same_sql = eq_sql($sql1, $sql2);

    $tb->ok($same_sql, $msg);

    if (!$same_sql) {
      _sql_differ_diag($sql1, $sql2);
    }
  }

  sub is_same_bind
  {
    my ($bind_ref1, $bind_ref2, $msg) = @_;

    my $same_bind = eq_bind($bind_ref1, $bind_ref2);

    $tb->ok($same_bind, $msg);

    if (!$same_bind) {
      _bind_differ_diag($bind_ref1, $bind_ref2);
    }
  }

  sub _sql_differ_diag
  {
    my ($sql1, $sql2) = @_;

    $tb->diag("SQL expressions differ\n"
      . "     got: $sql1\n"
      . "expected: $sql2\n"
    );
  }

  sub _bind_differ_diag
  {
    my ($bind_ref1, $bind_ref2) = @_;

    $tb->diag("BIND values differ\n"
      . "     got: " . Dumper($bind_ref1)
      . "expected: " . Dumper($bind_ref2)
    );
  }

  sub eq_sql
  {
    my ($left, $right) = @_;

    $left =~ s/\s+//g;
    $right =~ s/\s+//g;

    return $left eq $right;
  }

  sub eq_bind
  {
    my ($bind_ref1, $bind_ref2) = @_;

    return eq_deeply($bind_ref1, $bind_ref2);
  }

  sub eq_sql_bind
  {
    my ($sql1, $bind_ref1, $sql2, $bind_ref2) = @_;

    return eq_sql($sql1, $sql2) && eq_bind($bind_ref1, $bind_ref2);
  }
}

eval "use SQL::Abstract::Test;";
if ($@ eq '') {
  # SQL::Abstract::Test available

  *is_same_sql_bind = \&SQL::Abstract::Test::is_same_sql_bind;
  *is_same_sql = \&SQL::Abstract::Test::is_same_sql;
  *is_same_bind = \&SQL::Abstract::Test::is_same_bind;
  *eq_sql = \&SQL::Abstract::Test::eq_sql;
  *eq_bind = \&SQL::Abstract::Test::eq_bind;
  *eq_sql_bind = \&SQL::Abstract::Test::eq_sql_bind;
} else {
  # old SQL::Abstract

  *is_same_sql_bind = \&DBIC::SqlMakerTest::SQLATest::is_same_sql_bind;
  *is_same_sql = \&DBIC::SqlMakerTest::SQLATest::is_same_sql;
  *is_same_bind = \&DBIC::SqlMakerTest::SQLATest::is_same_bind;
  *eq_sql = \&DBIC::SqlMakerTest::SQLATest::eq_sql;
  *eq_bind = \&DBIC::SqlMakerTest::SQLATest::eq_bind;
  *eq_sql_bind = \&DBIC::SqlMakerTest::SQLATest::eq_sql_bind;
}


1;

__END__


=head1 NAME

DBIC::SqlMakerTest - Helper package for testing sql_maker component of DBIC

=head1 SYNOPSIS

  use Test::More;
  use DBIC::SqlMakerTest;
  
  my ($sql, @bind) = $schema->storage->sql_maker->select(%args);
  is_same_sql_bind(
    $sql, \@bind, 
    $expected_sql, \@expected_bind,
    'foo bar works'
  );

=head1 DESCRIPTION

Exports functions that can be used to compare generated SQL and bind values.

If L<SQL::Abstract::Test> (packaged in L<SQL::Abstract> versions 1.50 and
above) is available, then it is used to perform the comparisons (all functions
are delegated to id). Otherwise uses simple string comparison for the SQL
statements and simple L<Data::Dumper>-like recursive stringification for
comparison of bind values.


=head1 FUNCTIONS

=head2 is_same_sql_bind

  is_same_sql_bind(
    $given_sql, \@given_bind, 
    $expected_sql, \@expected_bind,
    $test_msg
  );

Compares given and expected pairs of C<($sql, \@bind)>, and calls
L<Test::Builder/ok> on the result, with C<$test_msg> as message.

=head2 is_same_sql

  is_same_sql(
    $given_sql,
    $expected_sql,
    $test_msg
  );

Compares given and expected SQL statement, and calls L<Test::Builder/ok> on the
result, with C<$test_msg> as message.

=head2 is_same_bind

  is_same_bind(
    \@given_bind, 
    \@expected_bind,
    $test_msg
  );

Compares given and expected bind value lists, and calls L<Test::Builder/ok> on
the result, with C<$test_msg> as message.

=head2 eq_sql

  my $is_same = eq_sql($given_sql, $expected_sql);

Compares the two SQL statements. Returns true IFF they are equivalent.

=head2 eq_bind

  my $is_same = eq_sql(\@given_bind, \@expected_bind);

Compares two lists of bind values. Returns true IFF their values are the same.

=head2 eq_sql_bind

  my $is_same = eq_sql_bind(
    $given_sql, \@given_bind,
    $expected_sql, \@expected_bind
  );

Compares the two SQL statements and the two lists of bind values. Returns true
IFF they are equivalent and the bind values are the same.


=head1 SEE ALSO

L<SQL::Abstract::Test>, L<Test::More>, L<Test::Builder>.

=head1 AUTHOR

Norbert Buchmuller, <norbi@nix.hu>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Norbert Buchmuller.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 
