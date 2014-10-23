use strict;
use warnings;
use Test::More;
use Test::Warn;

use lib qw(t/lib);
use DBICTest ':DiffSQL';
use DBIx::Class::_Util 'UNRESOLVABLE_CONDITION';

use Data::Dumper;
BEGIN {
  if ( eval { require Test::Differences } ) {
    no warnings 'redefine';
    *is_deeply = \&Test::Differences::eq_or_diff;
  }
}

my $schema = DBICTest->init_schema( no_deploy => 1);
my $sm = $schema->storage->sql_maker;

{
  package # hideee
    DBICTest::SillyInt;

  use overload
    fallback => 1,
    '0+' => sub { ${$_[0]} },
  ;
}
my $num = bless( \do { my $foo = 69 }, 'DBICTest::SillyInt' );

is($num, 69, 'test overloaded object is "sane"');
is("$num", 69, 'test overloaded object is "sane"');

for my $t (
  {
    where => { artistid => 1, charfield => undef },
    cc_result => { artistid => 1, charfield => undef },
    sql => 'WHERE artistid = ? AND charfield IS NULL',
    efcc_result => { artistid => 1 },
    efcc_n_result => { artistid => 1, charfield => undef },
  },
  {
    where => { -and => [ artistid => 1, charfield => undef, { rank => 13 } ] },
    cc_result => { artistid => 1, charfield => undef, rank => 13 },
    sql => 'WHERE artistid = ?  AND charfield IS NULL AND rank = ?',
    efcc_result => { artistid => 1, rank => 13 },
    efcc_n_result => { artistid => 1, charfield => undef, rank => 13 },
  },
  {
    where => { -and => [ { artistid => 1, charfield => undef}, { rank => 13 } ] },
    cc_result => { artistid => 1, charfield => undef, rank => 13 },
    sql => 'WHERE artistid = ?  AND charfield IS NULL AND rank = ?',
    efcc_result => { artistid => 1, rank => 13 },
    efcc_n_result => { artistid => 1, charfield => undef, rank => 13 },
  },
  {
    where => { -and => [ -or => { name => 'Caterwauler McCrae' }, 'rank' ] },
    cc_result => { name => 'Caterwauler McCrae', rank => undef },
    sql => 'WHERE name = ? AND rank IS NULL',
    efcc_result => { name => 'Caterwauler McCrae' },
    efcc_n_result => { name => 'Caterwauler McCrae', rank => undef },
  },
  {
    where => { -and => [ [ [ artist => {'=' => \'foo' } ] ], { name => \[ '= ?', 'bar' ] } ] },
    cc_result => { artist => {'=' => \'foo' }, name => \[ '= ?', 'bar' ] },
    sql => 'WHERE artist = foo AND name = ?',
    efcc_result => { artist => \'foo' },
  },
  {
    where => { -and => [ -or => { name => 'Caterwauler McCrae', artistid => 2 } ] },
    cc_result => { -or => [ artistid => 2, name => 'Caterwauler McCrae' ] },
    sql => 'WHERE artistid = ? OR name = ?',
    efcc_result => {},
  },
  {
    where => { -or => { name => 'Caterwauler McCrae', artistid => 2 } },
    cc_result => { -or => [ artistid => 2, name => 'Caterwauler McCrae' ] },
    sql => 'WHERE artistid = ? OR name = ?',
    efcc_result => {},
  },
  {
    where => { -and => [ \'foo=bar',  [ { artistid => { '=', $num } } ], { name => 'Caterwauler McCrae'} ] },
    cc_result => { '' => \'foo=bar', name => 'Caterwauler McCrae', artistid => $num },
    sql => 'WHERE foo=bar AND artistid = ? AND name = ?',
    efcc_result => { name => 'Caterwauler McCrae', artistid => $num },
  },
  {
    where => { artistid => [ $num ], rank => [ 13, 2, 3 ], charfield => [ undef ] },
    cc_result => { artistid => $num, charfield => undef, rank => [13, 2, 3] },
    sql => 'WHERE artistid = ? AND charfield IS NULL AND ( rank = ? OR rank = ? OR rank = ? )',
    efcc_result => { artistid => $num },
    efcc_n_result => { artistid => $num, charfield => undef },
  },
  {
    where => { artistid => { '=' => 1 }, rank => { '>' => 12 }, charfield => { '=' => undef } },
    cc_result => { artistid => 1, charfield => undef, rank => { '>' => 12 } },
    sql => 'WHERE artistid = ? AND charfield IS NULL AND rank > ?',
    efcc_result => { artistid => 1 },
    efcc_n_result => { artistid => 1, charfield => undef },
  },
  {
    where => { artistid => { '=' => [ 1 ], }, charfield => { '=' => [ -AND => \'1', \['?',2] ] }, rank => { '=' => [ -OR => $num, $num ] } },
    cc_result => { artistid => 1, charfield => [-and => { '=' => \['?',2] }, { '=' => \'1' } ], rank => { '=' => [$num, $num] } },
    sql => 'WHERE artistid = ? AND charfield = 1 AND charfield = ? AND ( rank = ? OR rank = ? )',
    collapsed_sql => 'WHERE artistid = ? AND charfield = ? AND charfield = 1 AND ( rank = ? OR rank = ? )',
    efcc_result => { artistid => 1, charfield => UNRESOLVABLE_CONDITION },
  },
  {
    where => { -and => [ artistid => 1, artistid => 2 ], name => [ -and => { '!=', 1 }, 2 ], charfield => [ -or => { '=', 2 } ], rank => [-and => undef, { '=', undef }, { '!=', 2 } ] },
    cc_result => { artistid => [ -and => 1, 2 ], name => [ -and => { '!=', 1 }, 2 ], charfield => 2, rank => [ -and => { '!=', 2 }, undef ] },
    sql => 'WHERE artistid = ? AND artistid = ? AND charfield = ? AND name != ? AND name = ? AND rank IS NULL AND rank IS NULL AND rank != ?',
    collapsed_sql => 'WHERE artistid = ? AND artistid = ? AND charfield = ? AND name != ? AND name = ? AND rank != ? AND rank IS NULL',
    efcc_result => {
      artistid => UNRESOLVABLE_CONDITION,
      name => 2,
      charfield => 2,
    },
    efcc_n_result => {
      artistid => UNRESOLVABLE_CONDITION,
      name => 2,
      charfield => 2,
      rank => undef,
    },
  },
  (map { {
    where => $_,
    sql => 'WHERE (rank = 13 OR charfield IS NULL OR artistid = ?) AND (artistid = ? OR charfield IS NULL OR rank != 42)',
    collapsed_sql => 'WHERE (artistid = ? OR charfield IS NULL OR rank = 13) AND (artistid = ? OR charfield IS NULL OR rank != 42)',
    cc_result => { -and => [
      { -or => [ artistid => 1, charfield => undef, rank => { '=' => \13 } ] },
      { -or => [ artistid => 1, charfield => undef, rank => { '!=' => \42 } ] },
    ] },
    efcc_result => {},
    efcc_n_result => {},
  } } (

    { -and => [
      -or => [ rank => { '=' => \13 }, charfield => { '=' => undef }, artistid => 1 ],
      -or => { artistid => { '=' => 1 }, charfield => undef, rank => { '!=' => \42 } },
    ] },

    {
      -OR => [ rank => { '=' => \13 }, charfield => { '=' => undef }, artistid => 1 ],
      -or => { artistid => { '=' => 1 }, charfield => undef, rank => { '!=' => \42 } },
    },

  ) ),
  {
    where => { -or => [
      -and => [ foo => { '!=', { -value => undef } }, bar => { -in => [ 69, 42 ] } ],
      foo => { '=', { -value => undef } },
      baz => { '!=' => { -ident => 'bozz' } },
      baz => { -ident => 'buzz' },
    ] },
    sql => 'WHERE ( foo IS NOT NULL AND bar IN ( ?, ? ) ) OR foo IS NULL OR baz != bozz OR baz = buzz',
    collapsed_sql => 'WHERE baz != bozz OR baz = buzz OR foo IS NULL OR ( bar IN ( ?, ? ) AND foo IS NOT NULL )',
    cc_result => { -or => [
      baz => { '!=' => { -ident => 'bozz' } },
      baz => { '=' => { -ident => 'buzz' } },
      foo => undef,
      { bar => { -in => [ 69, 42 ] }, foo => { '!=', undef } }
    ] },
    efcc_result => {},
  },
  {
    where => { -or => [ rank => { '=' => \13 }, charfield => { '=' => undef }, artistid => { '=' => 1 }, genreid => { '=' => \['?', 2] } ] },
    sql => 'WHERE rank = 13 OR charfield IS NULL OR artistid = ? OR genreid = ?',
    collapsed_sql => 'WHERE artistid = ? OR charfield IS NULL OR genreid = ? OR rank = 13',
    cc_result => { -or => [ artistid => 1, charfield => undef, genreid => { '=' => \['?', 2] }, rank => { '=' => \13 } ] },
    efcc_result => {},
    efcc_n_result => {},
  },
  {
    where => { -and => [
      -or => [ rank => { '=' => \13 }, charfield => { '=' => undef }, artistid => 1 ],
      -or => { artistid => { '=' => 1 }, charfield => undef, rank => { '=' => \13 } },
    ] },
    cc_result => { -and => [
      { -or => [ artistid => 1, charfield => undef, rank => { '=' => \13 } ] },
      { -or => [ artistid => 1, charfield => undef, rank => { '=' => \13 } ] },
    ] },
    sql => 'WHERE (rank = 13 OR charfield IS NULL OR artistid = ?) AND (artistid = ? OR charfield IS NULL OR rank = 13)',
    collapsed_sql => 'WHERE (artistid = ? OR charfield IS NULL OR rank = 13) AND (artistid = ? OR charfield IS NULL OR rank = 13)',
    efcc_result => {},
    efcc_n_result => {},
  },
  {
    where => { -and => [
      -or => [ rank => { '=' => \13 }, charfield => { '=' => undef }, artistid => 1 ],
      -or => { artistid => { '=' => 1 }, charfield => undef, rank => { '!=' => \42 } },
      -and => [ foo => { '=' => \1 }, bar => 2 ],
      -and => [ foo => 3, bar => { '=' => \4 } ],
      -exists => \'(SELECT 1)',
      -exists => \'(SELECT 2)',
      -not => { foo => 69 },
      -not => { foo => 42 },
    ]},
    sql => 'WHERE
          ( rank = 13 OR charfield IS NULL OR artistid = ? )
      AND ( artistid = ? OR charfield IS NULL OR rank != 42 )
      AND foo = 1
      AND bar = ?
      AND foo = ?
      AND bar = 4
      AND (EXISTS (SELECT 1))
      AND (EXISTS (SELECT 2))
      AND NOT foo = ?
      AND NOT foo = ?
    ',
    collapsed_sql => 'WHERE
          ( artistid = ? OR charfield IS NULL OR rank = 13 )
      AND ( artistid = ? OR charfield IS NULL OR rank != 42 )
      AND (EXISTS (SELECT 1))
      AND (EXISTS (SELECT 2))
      AND NOT foo = ?
      AND NOT foo = ?
      AND bar = 4
      AND bar = ?
      AND foo = 1
      AND foo = ?
    ',
    cc_result => {
      -and => [
        { -or => [ artistid => 1, charfield => undef, rank => { '=' => \13 } ] },
        { -or => [ artistid => 1, charfield => undef, rank => { '!=' => \42 } ] },
        { -exists => \'(SELECT 1)' },
        { -exists => \'(SELECT 2)' },
        { -not => { foo => 69 } },
        { -not => { foo => 42 } },
      ],
      foo => [ -and => { '=' => \1 }, 3 ],
      bar => [ -and => { '=' => \4 }, 2 ],
    },
    efcc_result => {
      foo => UNRESOLVABLE_CONDITION,
      bar => UNRESOLVABLE_CONDITION,
    },
    efcc_n_result => {
      foo => UNRESOLVABLE_CONDITION,
      bar => UNRESOLVABLE_CONDITION,
    },
  },
  {
    where => { -and => [
      [ '_macro.to' => { -like => '%correct%' }, '_wc_macros.to' => { -like => '%correct%' } ],
      { -and => [ { 'group.is_active' => 1 }, { 'me.is_active' => 1 } ] }
    ] },
    cc_result => {
      'group.is_active' => 1,
      'me.is_active' => 1,
      -or => [
        '_macro.to' => { -like => '%correct%' },
        '_wc_macros.to' => { -like => '%correct%' },
      ],
    },
    sql => 'WHERE ( _macro.to LIKE ? OR _wc_macros.to LIKE ? ) AND group.is_active = ? AND me.is_active = ?',
    efcc_result => { 'group.is_active' => 1, 'me.is_active' => 1 },
  },

  {
    where => { -and => [
      artistid => { -value => [1] },
      charfield => { -ident => 'foo' },
      name => { '=' => { -value => undef } },
      rank => { '=' => { -ident => 'bar' } },
    ] },
    sql => 'WHERE artistid = ? AND charfield = foo AND name IS NULL AND rank = bar',
    cc_result => {
      artistid => { -value => [1] },
      name => undef,
      charfield => { '=', { -ident => 'foo' } },
      rank => { '=' => { -ident => 'bar' } },
    },
    efcc_result => {
      artistid => [1],
      charfield => { -ident => 'foo' },
      rank => { -ident => 'bar' },
    },
    efcc_n_result => {
      artistid => [1],
      name => undef,
      charfield => { -ident => 'foo' },
      rank => { -ident => 'bar' },
    },
  },

  {
    where => { artistid => [] },
    cc_result => { artistid => [] },
    efcc_result => {},
  },
  (map {
    {
      where => { -and => $_ },
      cc_result => undef,
      efcc_result => {},
      sql => '',
    },
    {
      where => { -or => $_ },
      cc_result => undef,
      efcc_result => {},
      sql => '',
    },
    {
      where => { -or => [ foo => 1, $_ ] },
      cc_result => { foo => 1 },
      efcc_result => { foo => 1 },
      sql => 'WHERE foo = ?',
    },
    {
      where => { -or => [ $_, foo => 1 ] },
      cc_result => { foo => 1 },
      efcc_result => { foo => 1 },
      sql => 'WHERE foo = ?',
    },
    {
      where => { -and => [ fuu => 2, $_, foo => 1 ] },
      sql => 'WHERE fuu = ? AND foo = ?',
      collapsed_sql => 'WHERE foo = ? AND fuu = ?',
      cc_result => { foo => 1, fuu => 2 },
      efcc_result => { foo => 1, fuu => 2 },
    },
  } (
    # bare
    [], {},
    # singles
    [ {} ], [ [] ],
    # doubles
    [ [], [] ], [ {}, {} ], [ [], {} ], [ {}, [] ],
    # tripples
    [ {}, [], {} ], [ [], {}, [] ]
  )),

  # FIXME legacy compat crap, possibly worth undef/dieing in SQLMaker
  { where => { artistid => {} }, sql => '', cc_result => undef, efcc_result => {}, efcc_n_result => {} },

  # batshit insanity, just to be thorough
  {
    where => { -and => [ [ 'artistid' ], [ -and => [ artistid => { '!=', 69 }, artistid => undef, artistid => { '=' => 200 } ]], artistid => [], { -or => [] }, { -and => [] }, [ 'charfield' ], { name => [] }, 'rank' ] },
    cc_result => { artistid => [ -and => [], { '!=', 69 }, undef, 200  ], charfield => undef, name => [], rank => undef },
    sql => 'WHERE artistid IS NULL AND artistid != ? AND artistid IS NULL AND artistid = ? AND 0=1 AND charfield IS NULL AND 0=1 AND rank IS NULL',
    collapsed_sql => 'WHERE 0=1 AND artistid != ? AND artistid IS NULL AND artistid = ? AND charfield IS NULL AND 0=1 AND rank IS NULL',
    efcc_result => { artistid => UNRESOLVABLE_CONDITION },
    efcc_n_result => { artistid => UNRESOLVABLE_CONDITION, charfield => undef, rank => undef },
  },

  # original test from RT#93244
  {
    where => {
      -and => [
        \[
          "LOWER(me.title) LIKE ?",
          '%spoon%',
        ],
        [ { 'me.title' => 'Spoonful of bees' } ],
    ]},
    cc_result => {
      '' => \[
        "LOWER(me.title) LIKE ?",
        '%spoon%',
      ],
      'me.title' => 'Spoonful of bees',
    },
    sql => 'WHERE LOWER(me.title) LIKE ? AND me.title = ?',
    efcc_result => { 'me.title' => 'Spoonful of bees' },
  }
) {

  for my $w (
    $t->{where},
    $t->{where},  # do it twice, make sure we didn't destory the condition
    [ -and => $t->{where} ],
    [ -AND => $t->{where} ],
    { -OR => [ -AND => $t->{where} ] },
    ( keys %{$t->{where}} <= 1 ? [ %{$t->{where}} ] : () ),
    ( (keys %{$t->{where}} == 1 and $t->{where}{-or})
      ? ( ref $t->{where}{-or} eq 'HASH'
        ? [ map { $_ => $t->{where}{-or}{$_} } sort keys %{$t->{where}{-or}} ]
        : $t->{where}{-or}
      )
      : ()
    ),
  ) {
    my $name = do { local ($Data::Dumper::Indent, $Data::Dumper::Terse, $Data::Dumper::Sortkeys) = (0, 1, 1); Dumper $w };

    my ($generated_sql) = $sm->where($w);

    is_same_sql ( $generated_sql, $t->{sql}, "Expected SQL from $name" )
      if exists $t->{sql};

    my $collapsed_cond = $schema->storage->_collapse_cond($w);

    is_same_sql(
      ($sm->where($collapsed_cond))[0],
      ( $t->{collapsed_sql} || $t->{sql} || $generated_sql ),
      "Collapse did not alter *the semantics* of the final SQL based on $name",
    );

    is_deeply(
      $collapsed_cond,
      $t->{cc_result},
      "Expected collapsed condition produced on $name",
    );

    is_deeply(
      $schema->storage->_extract_fixed_condition_columns($w),
      $t->{efcc_result},
      "Expected fixed_condition produced on $name",
    );

    is_deeply(
      $schema->storage->_extract_fixed_condition_columns($w, 'consider_nulls'),
      $t->{efcc_n_result},
      "Expected fixed_condition including NULLs produced on $name",
    ) if $t->{efcc_n_result};

    die unless Test::Builder->new->is_passing;
  }
}

done_testing;
