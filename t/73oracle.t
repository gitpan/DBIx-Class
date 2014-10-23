{
  package    # hide from PAUSE
    DBICTest::Schema::ArtistFQN;

  use base 'DBIx::Class::Core';

  __PACKAGE__->table(
      defined $ENV{DBICTEST_ORA_USER}
      ? $ENV{DBICTEST_ORA_USER} . '.artist'
      : 'artist'
  );
  __PACKAGE__->add_columns(
      'artistid' => {
          data_type         => 'integer',
          is_auto_increment => 1,
      },
      'name' => {
          data_type   => 'varchar',
          size        => 100,
          is_nullable => 1,
      },
      'autoinc_col' => {
          data_type         => 'integer',
          is_auto_increment => 1,
      },
  );
  __PACKAGE__->set_primary_key('artistid');

  1;
}

use strict;
use warnings;

use Test::Exception;
use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;

my ($dsn,  $user,  $pass)  = @ENV{map { "DBICTEST_ORA_${_}" }  qw/DSN USER PASS/};

# optional:
my ($dsn2, $user2, $pass2) = @ENV{map { "DBICTEST_ORA_EXTRAUSER_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBICTEST_ORA_DSN}, _USER and _PASS to run this test. ' .
  'Warning: This test drops and creates tables called \'artist\', \'cd\', \'track\' and \'sequence_test\''.
  ' as well as following sequences: \'pkid1_seq\', \'pkid2_seq\' and \'nonpkid_seq\''
  unless ($dsn && $user && $pass);

DBICTest::Schema->load_classes('ArtistFQN');
my $schema = DBICTest::Schema->connect($dsn, $user, $pass);

note "Oracle Version: " . $schema->storage->_server_info->{dbms_version};

my $dbh = $schema->storage->dbh;

do_creates($dbh);

{
    # Swiped from t/bindtype_columns.t to avoid creating my own Resultset.

    local $SIG{__WARN__} = sub {};
    eval { $dbh->do('DROP TABLE bindtype_test') };

    $dbh->do(qq[
        CREATE TABLE bindtype_test
        (
            id              integer      NOT NULL   PRIMARY KEY,
            bytea           integer      NULL,
            blob            blob         NULL,
            clob            clob         NULL
        )
    ],{ RaiseError => 1, PrintError => 1 });
}

# This is in Core now, but it's here just to test that it doesn't break
$schema->class('Artist')->load_components('PK::Auto');
# These are compat shims for PK::Auto...
$schema->class('CD')->load_components('PK::Auto::Oracle');
$schema->class('Track')->load_components('PK::Auto::Oracle');


# test primary key handling with multiple triggers
my $new = $schema->resultset('Artist')->create({ name => 'foo' });
is($new->artistid, 1, "Oracle Auto-PK worked for sqlt-like trigger");

like ($new->result_source->column_info('artistid')->{sequence}, qr/\.artist_pk_seq$/, 'Correct PK sequence selected for sqlt-like trigger');

$new = $schema->resultset('CD')->create({ artist => 1, title => 'foo', year => '2003' });
is($new->cdid, 1, "Oracle Auto-PK worked for custom trigger");

like ($new->result_source->column_info('cdid')->{sequence}, qr/\.cd_seq$/, 'Correct PK sequence selected for custom trigger');

# test again with fully-qualified table name
my $artistfqn_rs = $schema->resultset('ArtistFQN');
my $artist_rsrc = $artistfqn_rs->result_source;

delete $artist_rsrc->column_info('artistid')->{sequence};

$new = $artistfqn_rs->create( { name => 'bar' } );
is( $new->artistid, 2, "Oracle Auto-PK worked with fully-qualified tablename" );

delete $artist_rsrc->column_info('artistid')->{sequence};

$new = $artistfqn_rs->create( { name => 'bar', autoinc_col => 1000 } );
is( $new->artistid, 3, "Oracle Auto-PK worked with fully-qualified tablename" );
is( $new->autoinc_col, 1000, "Oracle Auto-Inc overruled with fully-qualified tablename");

like ($artist_rsrc->column_info('artistid')->{sequence}, qr/\.artist_pk_seq$/, 'Still correct PK sequence');

# test LIMIT support
for (1..6) {
    $schema->resultset('Artist')->create({ name => 'Artist ' . $_ });
}
my $it = $schema->resultset('Artist')->search( { name => { -like => 'Artist %' }},
    { rows => 3,
      offset => 4,
      order_by => 'artistid' }
);
is( $it->count, 2, "LIMIT count past end of RS ok" );
is( $it->next->name, "Artist 5", "iterator->next ok" );
is( $it->next->name, "Artist 6", "iterator->next ok" );
is( $it->next, undef, "next past end of resultset ok" );

my $cd = $schema->resultset('CD')->create({ artist => 1, title => 'EP C', year => '2003' });
is($cd->cdid, 2, "Oracle Auto-PK worked - using scalar ref as table name");

# test rel names over the 30 char limit
{
  my $query = $schema->resultset('Artist')->search({
    artistid => 1
  }, {
    prefetch => 'cds_very_very_very_long_relationship_name'
  });

  lives_and {
    is $query->first->cds_very_very_very_long_relationship_name->first->cdid, 2
  } 'query with rel name over 30 chars survived and worked';

  # rel name over 30 char limit with user condition
  # This requires walking the SQLA data structure.
  {
    local $TODO = 'user condition on rel longer than 30 chars';

    $query = $schema->resultset('Artist')->search({
      'cds_very_very_very_long_relationship_name.title' => 'EP C'
    }, {
      prefetch => 'cds_very_very_very_long_relationship_name'
    });

    lives_and {
      is $query->first->cds_very_very_very_long_relationship_name->first->cdid, 1
    } 'query with rel name over 30 chars and user condition survived and worked';
  }
}

# test join with row count ambiguity

my $track = $schema->resultset('Track')->create({ cd => $cd->cdid,
    position => 1, title => 'Track1' });
my $tjoin = $schema->resultset('Track')->search({ 'me.title' => 'Track1'},
        { join => 'cd',
          rows => 2 }
);

ok(my $row = $tjoin->next);

is($row->title, 'Track1', "ambiguous column ok");

# check count distinct with multiple columns
my $other_track = $schema->resultset('Track')->create({ cd => $cd->cdid, position => 1, title => 'Track2' });

my $tcount = $schema->resultset('Track')->search(
  {},
  {
    select => [ qw/position title/ ],
    distinct => 1,
  }
);
is($tcount->count, 2, 'multiple column COUNT DISTINCT ok');

$tcount = $schema->resultset('Track')->search(
  {},
  {
    columns => [ qw/position title/ ],
    distinct => 1,
  }
);
is($tcount->count, 2, 'multiple column COUNT DISTINCT ok');

$tcount = $schema->resultset('Track')->search(
  {},
  {
     group_by => [ qw/position title/ ]
  }
);
is($tcount->count, 2, 'multiple column COUNT DISTINCT using column syntax ok');

{
  my $rs = $schema->resultset('Track')->search( undef, { columns=>[qw/trackid position/], group_by=> [ qw/trackid position/ ] , rows => 2, offset=>1 });
  my @results = $rs->all;
  is( scalar @results, 1, "Group by with limit OK" );
}

# test identifiers over the 30 char limit
{
  lives_ok {
    my @results = $schema->resultset('CD')->search(undef, {
      prefetch => 'very_long_artist_relationship',
      rows => 3,
      offset => 0,
    })->all;
    ok( scalar @results > 0, 'limit with long identifiers returned something');
  } 'limit with long identifiers executed successfully';
}

# test with_deferred_fk_checks
lives_ok {
  $schema->storage->with_deferred_fk_checks(sub {
    $schema->resultset('Track')->create({
      trackid => 999, cd => 999, position => 1, title => 'deferred FK track'
    });
    $schema->resultset('CD')->create({
      artist => 1, cdid => 999, year => '2003', title => 'deferred FK cd'
    });
  });
} 'with_deferred_fk_checks code survived';

is eval { $schema->resultset('Track')->find(999)->title }, 'deferred FK track',
   'code in with_deferred_fk_checks worked'; 

throws_ok {
  $schema->resultset('Track')->create({
    trackid => 1, cd => 9999, position => 1, title => 'Track1'
  });
} qr/constraint/i, 'with_deferred_fk_checks is off';

# test auto increment using sequences WITHOUT triggers
for (1..5) {
    my $st = $schema->resultset('SequenceTest')->create({ name => 'foo' });
    is($st->pkid1, $_, "Oracle Auto-PK without trigger: First primary key");
    is($st->pkid2, $_ + 9, "Oracle Auto-PK without trigger: Second primary key");
    is($st->nonpkid, $_ + 19, "Oracle Auto-PK without trigger: Non-primary key");
}
my $st = $schema->resultset('SequenceTest')->create({ name => 'foo', pkid1 => 55 });
is($st->pkid1, 55, "Oracle Auto-PK without trigger: First primary key set manually");

SKIP: {
  my %binstr = ( 'small' => join('', map { chr($_) } ( 1 .. 127 )) );
  $binstr{'large'} = $binstr{'small'} x 1024;

  my $maxloblen = length $binstr{'large'};
  note "Localizing LongReadLen to $maxloblen to avoid truncation of test data";
  local $dbh->{'LongReadLen'} = $maxloblen;

  my $rs = $schema->resultset('BindType');
  my $id = 0;

  if ($DBD::Oracle::VERSION eq '1.23') {
    throws_ok { $rs->create({ id => 1, blob => $binstr{large} }) }
      qr/broken/,
      'throws on blob insert with DBD::Oracle == 1.23';

    skip 'buggy BLOB support in DBD::Oracle 1.23', 7;
  }

  # disable BLOB mega-output
  my $orig_debug = $schema->storage->debug;
  $schema->storage->debug (0);

  foreach my $type (qw( blob clob )) {
    foreach my $size (qw( small large )) {
      $id++;

      lives_ok { $rs->create( { 'id' => $id, $type => $binstr{$size} } ) }
      "inserted $size $type without dying";

      ok($rs->find($id)->$type eq $binstr{$size}, "verified inserted $size $type" );
    }
  }

  $schema->storage->debug ($orig_debug);
}


### test hierarchical queries
if ( $schema->storage->isa('DBIx::Class::Storage::DBI::Oracle::Generic') ) {
    my $source = $schema->source('Artist');

    $source->add_column( 'parentid' );

    $source->add_relationship('children', 'DBICTest::Schema::Artist',
        { 'foreign.parentid' => 'self.artistid' },
        {
            accessor => 'multi',
            join_type => 'LEFT',
            cascade_delete => 1,
            cascade_copy => 1,
        } );
    $source->add_relationship('parent', 'DBICTest::Schema::Artist',
        { 'foreign.artistid' => 'self.parentid' },
        { accessor => 'single' } );
    DBICTest::Schema::Artist->add_column( 'parentid' );
    DBICTest::Schema::Artist->has_many(
        children => 'DBICTest::Schema::Artist',
        { 'foreign.parentid' => 'self.artistid' }
    );
    DBICTest::Schema::Artist->belongs_to(
        parent => 'DBICTest::Schema::Artist',
        { 'foreign.artistid' => 'self.parentid' }
    );

    $schema->resultset('Artist')->create ({
        name => 'root',
        rank => 1,
        cds => [],
        children => [
            {
                name => 'child1',
                rank => 2,
                children => [
                    {
                        name => 'grandchild',
                        rank => 3,
                        cds => [
                            {
                                title => "grandchilds's cd" ,
                                year => '2008',
                                tracks => [
                                    {
                                        position => 1,
                                        title => 'Track 1 grandchild',
                                    }
                                ],
                            }
                        ],
                        children => [
                            {
                                name => 'greatgrandchild',
                                rank => 3,
                            }
                        ],
                    }
                ],
            },
            {
                name => 'child2',
                rank => 3,
            },
        ],
    });

    $schema->resultset('Artist')->create(
        {
            name     => 'cycle-root',
            children => [
                {
                    name     => 'cycle-child1',
                    children => [ { name => 'cycle-grandchild' } ],
                },
                { name => 'cycle-child2' },
            ],
        }
    );

    $schema->resultset('Artist')->find({ name => 'cycle-root' })
      ->update({ parentid => { -ident => 'artistid' } });

    # select the whole tree
    {
      my $rs = $schema->resultset('Artist')->search({}, {
        start_with => { name => 'root' },
        connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
      });

      is_same_sql_bind (
        $rs->as_query,
        '(
          SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
            FROM artist me
          START WITH name = ?
          CONNECT BY parentid = PRIOR artistid 
        )',
        [ [ name => 'root'] ],
      );
      is_deeply (
        [ $rs->get_column ('name')->all ],
        [ qw/root child1 grandchild greatgrandchild child2/ ],
        'got artist tree',
      );


      is_same_sql_bind (
        $rs->count_rs->as_query,
        '(
          SELECT COUNT( * )
            FROM artist me
          START WITH name = ?
          CONNECT BY parentid = PRIOR artistid 
        )',
        [ [ name => 'root'] ],
      );

      is( $rs->count, 5, 'Connect By count ok' );
    }

    # use order siblings by statement
    SKIP: {
      # http://download.oracle.com/docs/cd/A87860_01/doc/server.817/a85397/state21b.htm#2066123
      skip q{Oracle8i doesn't support ORDER SIBLINGS BY}, 1
        if $schema->storage->_server_info->{normalized_dbms_version} < 9;

      my $rs = $schema->resultset('Artist')->search({}, {
        start_with => { name => 'root' },
        connect_by => { parentid => { -prior => { -ident =>  'artistid' } } },
        order_siblings_by => { -desc => 'name' },
      });

      is_same_sql_bind (
        $rs->as_query,
        '(
          SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
            FROM artist me
          START WITH name = ?
          CONNECT BY parentid = PRIOR artistid 
          ORDER SIBLINGS BY name DESC
        )',
        [ [ name => 'root'] ],
      );

      is_deeply (
        [ $rs->get_column ('name')->all ],
        [ qw/root child2 child1 grandchild greatgrandchild/ ],
        'Order Siblings By ok',
      );
    }

    # get the root node
    {
      my $rs = $schema->resultset('Artist')->search({ parentid => undef }, {
        start_with => { name => 'root' },
        connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
      });

      is_same_sql_bind (
        $rs->as_query,
        '(
          SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
            FROM artist me
          WHERE ( parentid IS NULL )
          START WITH name = ?
          CONNECT BY parentid = PRIOR artistid 
        )',
        [ [ name => 'root'] ],
      );

      is_deeply(
        [ $rs->get_column('name')->all ],
        [ 'root' ],
        'found root node',
      );
    }

    # combine a connect by with a join
    SKIP: {
      # http://download.oracle.com/docs/cd/A87860_01/doc/server.817/a85397/state21b.htm#2066123
      skip q{Oracle8i doesn't support connect by with join}, 1
        if $schema->storage->_server_info->{normalized_dbms_version} < 9;

      my $rs = $schema->resultset('Artist')->search(
        {'cds.title' => { -like => '%cd'} },
        {
          join => 'cds',
          start_with => { 'me.name' => 'root' },
          connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
        }
      );

      is_same_sql_bind (
        $rs->as_query,
        '(
          SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
            FROM artist me
            LEFT JOIN cd cds ON cds.artist = me.artistid
          WHERE ( cds.title LIKE ? )
          START WITH me.name = ?
          CONNECT BY parentid = PRIOR artistid 
        )',
        [ [ 'cds.title' => '%cd' ], [ 'me.name' => 'root' ] ],
      );

      is_deeply(
        [ $rs->get_column('name')->all ],
        [ 'grandchild' ],
        'Connect By with a join result name ok'
      );


      is_same_sql_bind (
        $rs->count_rs->as_query,
        '(
          SELECT COUNT( * )
            FROM artist me
            LEFT JOIN cd cds ON cds.artist = me.artistid
          WHERE ( cds.title LIKE ? )
          START WITH me.name = ?
          CONNECT BY parentid = PRIOR artistid 
        )',
        [ [ 'cds.title' => '%cd' ], [ 'me.name' => 'root' ] ],
      );

      is( $rs->count, 1, 'Connect By with a join; count ok' );
    }

    # combine a connect by with order_by
    {
      my $rs = $schema->resultset('Artist')->search({}, {
        start_with => { name => 'root' },
        connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
        order_by => { -asc => [ 'LEVEL', 'name' ] },
      });

      is_same_sql_bind (
        $rs->as_query,
        '(
          SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid
          FROM artist me
          START WITH name = ?
          CONNECT BY parentid = PRIOR artistid 
          ORDER BY LEVEL ASC, name ASC
        )',
        [ [ name => 'root' ] ],
      );


      # Don't use "$rs->get_column ('name')->all" they build a query arround the $rs.
      #   If $rs has a order by, the order by is in the subquery and this doesn't work with Oracle 8i.
      # TODO: write extra test and fix order by handling on Oracle 8i
      is_deeply (
        [ map { $_->[1] } $rs->cursor->all ],
        [ qw/root child1 child2 grandchild greatgrandchild/ ],
        'Connect By with a order_by - result name ok (without get_column)'
      );

      SKIP: {
          skip q{Connect By with a order_by - result name ok (with get_column), Oracle8i doesn't support order by in a subquery},1
            if $schema->storage->_server_info->{normalized_dbms_version} < 9;
          is_deeply (
            [  $rs->get_column ('name')->all ],
            [ qw/root child1 child2 grandchild greatgrandchild/ ],
            'Connect By with a order_by - result name ok (with get_column)'
          );
      }
    }


    # limit a connect by
    SKIP: {
      skip q{Oracle8i doesn't support order by in a subquery}, 1
        if $schema->storage->_server_info->{normalized_dbms_version} < 9;

      my $rs = $schema->resultset('Artist')->search({}, {
        start_with => { name => 'root' },
        connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
        order_by => { -asc => 'name' },
        rows => 2,
      });

      is_same_sql_bind (
        $rs->as_query,
        '(
            SELECT artistid, name, rank, charfield, parentid FROM (
              SELECT
                  me.artistid,
                  me.name,
                  me.rank,
                  me.charfield,
                  me.parentid
                FROM artist me
              START WITH name = ?
              CONNECT BY parentid = PRIOR artistid
              ORDER BY name ASC 
            ) me
            WHERE ROWNUM <= 2
        )',
        [ [ name => 'root' ] ],
      );

      is_deeply (
        [ $rs->get_column ('name')->all ],
        [qw/child1 child2/],
        'LIMIT a Connect By query - correct names'
      );

      is_same_sql_bind (
        $rs->count_rs->as_query,
        '(
          SELECT COUNT( * ) FROM (
            SELECT artistid
              FROM (
                SELECT
                  me.artistid
                FROM artist me 
                START WITH name = ? 
                CONNECT BY parentid = PRIOR artistid
              ) me
            WHERE ROWNUM <= 2
          ) me
        )',
        [ [ name => 'root' ] ],
      );

      is( $rs->count, 2, 'Connect By; LIMIT count ok' );
    }

    # combine a connect_by with group_by and having
    {
      my $rs = $schema->resultset('Artist')->search({}, {
        select => { count => 'rank', -as => 'cnt' },
        start_with => { name => 'root' },
        connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
        group_by => ['rank'],
        having => \[ 'count(rank) < ?', [ cnt => 2 ] ],
      });

      is_same_sql_bind (
        $rs->as_query,
        '(
            SELECT COUNT(rank) AS cnt
            FROM artist me
            START WITH name = ?
            CONNECT BY parentid = PRIOR artistid
            GROUP BY rank HAVING count(rank) < ?
        )',
        [ [ name => 'root' ], [ cnt => 2 ] ],
      );

      is_deeply (
        [ $rs->get_column ('cnt')->all ],
        [1, 1],
        'Group By a Connect By query - correct values'
      );
    }


    # select the whole cycle tree without nocylce
    {
      my $rs = $schema->resultset('Artist')->search({}, {
        start_with => { name => 'cycle-root' },
        connect_by => { parentid => { -prior => { -ident => 'artistid' } } },
      });
      eval { $rs->get_column ('name')->all };
      if ( $@ =~ /ORA-01436/ ){ # ORA-01436:  CONNECT BY loop in user data
        pass "connect by initify loop detection without nocycle";
      }else{
        fail "connect by initify loop detection without nocycle, not detected by oracle";
      }
    }

    # select the whole cycle tree with nocylce
    SKIP: {
      # http://download.oracle.com/docs/cd/A87860_01/doc/server.817/a85397/expressi.htm#1023748
      skip q{Oracle8i doesn't support connect by nocycle}, 1
        if $schema->storage->_server_info->{normalized_dbms_version} < 9;

      my $rs = $schema->resultset('Artist')->search({}, {
        start_with => { name => 'cycle-root' },
        '+select'  => \ 'CONNECT_BY_ISCYCLE',
        '+as'      => [ 'connector' ],
        connect_by_nocycle => { parentid => { -prior => { -ident => 'artistid' } } },
      });

      is_same_sql_bind (
        $rs->as_query,
        '(
          SELECT me.artistid, me.name, me.rank, me.charfield, me.parentid, CONNECT_BY_ISCYCLE
            FROM artist me
          START WITH name = ?
          CONNECT BY NOCYCLE parentid = PRIOR artistid 
        )',
        [ [ name => 'cycle-root'] ],
      );
      is_deeply (
        [ $rs->get_column ('name')->all ],
        [ qw/cycle-root cycle-child1 cycle-grandchild cycle-child2/ ],
        'got artist tree with nocycle (name)',
      );
      is_deeply (
        [ $rs->get_column ('connector')->all ],
        [ qw/1 0 0 0/ ],
        'got artist tree with nocycle (CONNECT_BY_ISCYCLE)',
      );


      is_same_sql_bind (
        $rs->count_rs->as_query,
        '(
          SELECT COUNT( * )
            FROM artist me
          START WITH name = ?
          CONNECT BY NOCYCLE parentid = PRIOR artistid 
        )',
        [ [ name => 'cycle-root'] ],
      );

      is( $rs->count, 4, 'Connect By Nocycle count ok' );
    }
}

my $schema2;

# test sequence detection from a different schema
SKIP: {
TODO: {
  skip ((join '',
'Set DBICTEST_ORA_EXTRAUSER_DSN, _USER and _PASS to a *DIFFERENT* Oracle user',
' to run the cross-schema autoincrement test.'),
    1) unless $dsn2 && $user2 && $user2 ne $user;

  # Oracle8i Reference Release 2 (8.1.6) 
  #   http://download.oracle.com/docs/cd/A87860_01/doc/server.817/a76961/ch294.htm#993
  # Oracle Database Reference 10g Release 2 (10.2)
  #   http://download.oracle.com/docs/cd/B19306_01/server.102/b14237/statviews_2107.htm#sthref1297
  local $TODO = "On Oracle8i all_triggers view is empty, i don't yet know why..."
    if $schema->storage->_server_info->{normalized_dbms_version} < 9;

  $schema2 = DBICTest::Schema->connect($dsn2, $user2, $pass2);

  my $schema1_dbh  = $schema->storage->dbh;

  $schema1_dbh->do("GRANT INSERT ON artist TO $user2");
  $schema1_dbh->do("GRANT SELECT ON artist_pk_seq TO $user2");

  my $rs = $schema2->resultset('ArtistFQN');

  # first test with unquoted (default) sequence name in trigger body

  lives_and {
    my $row = $rs->create({ name => 'From Different Schema' });
    ok $row->artistid;
  } 'used autoinc sequence across schemas';

  # now quote the sequence name
  $schema1_dbh->do(qq{
    CREATE OR REPLACE TRIGGER artist_insert_trg_pk
    BEFORE INSERT ON artist
    FOR EACH ROW
    BEGIN
      IF :new.artistid IS NULL THEN
        SELECT "ARTIST_PK_SEQ".nextval
        INTO :new.artistid
        FROM DUAL;
      END IF;
    END;
  });

  # sequence is cached in the rsrc
  delete $rs->result_source->column_info('artistid')->{sequence};

  lives_and {
    my $row = $rs->create({ name => 'From Different Schema With Quoted Sequence' });
    ok $row->artistid;
  } 'used quoted autoinc sequence across schemas';

  my $schema_name = uc $user;

  is $rs->result_source->column_info('artistid')->{sequence},
    qq[${schema_name}."ARTIST_PK_SEQ"],
    'quoted sequence name correctly extracted';
} }

done_testing;

sub do_creates {
  my $dbh = shift;

  eval {
    $dbh->do("DROP SEQUENCE artist_autoinc_seq");
    $dbh->do("DROP SEQUENCE artist_pk_seq");
    $dbh->do("DROP SEQUENCE cd_seq");
    $dbh->do("DROP SEQUENCE track_seq");
    $dbh->do("DROP SEQUENCE pkid1_seq");
    $dbh->do("DROP SEQUENCE pkid2_seq");
    $dbh->do("DROP SEQUENCE nonpkid_seq");
    $dbh->do("DROP TABLE artist");
    $dbh->do("DROP TABLE sequence_test");
    $dbh->do("DROP TABLE track");
    $dbh->do("DROP TABLE cd");
  };
  $dbh->do("CREATE SEQUENCE artist_autoinc_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE artist_pk_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE cd_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE track_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE pkid1_seq START WITH 1 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE pkid2_seq START WITH 10 MAXVALUE 999999 MINVALUE 0");
  $dbh->do("CREATE SEQUENCE nonpkid_seq START WITH 20 MAXVALUE 999999 MINVALUE 0");

  $dbh->do("CREATE TABLE artist (artistid NUMBER(12), parentid NUMBER(12), name VARCHAR(255), autoinc_col NUMBER(12), rank NUMBER(38), charfield VARCHAR2(10))");
  $dbh->do("ALTER TABLE artist ADD (CONSTRAINT artist_pk PRIMARY KEY (artistid))");

  $dbh->do("CREATE TABLE sequence_test (pkid1 NUMBER(12), pkid2 NUMBER(12), nonpkid NUMBER(12), name VARCHAR(255))");
  $dbh->do("ALTER TABLE sequence_test ADD (CONSTRAINT sequence_test_constraint PRIMARY KEY (pkid1, pkid2))");

  $dbh->do("CREATE TABLE cd (cdid NUMBER(12), artist NUMBER(12), title VARCHAR(255), year VARCHAR(4), genreid NUMBER(12), single_track NUMBER(12))");
  $dbh->do("ALTER TABLE cd ADD (CONSTRAINT cd_pk PRIMARY KEY (cdid))");

  $dbh->do("CREATE TABLE track (trackid NUMBER(12), cd NUMBER(12) REFERENCES cd(cdid) DEFERRABLE, position NUMBER(12), title VARCHAR(255), last_updated_on DATE, last_updated_at DATE, small_dt DATE)");
  $dbh->do("ALTER TABLE track ADD (CONSTRAINT track_pk PRIMARY KEY (trackid))");

  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER artist_insert_trg_auto
    BEFORE INSERT ON artist
    FOR EACH ROW
    BEGIN
      IF :new.autoinc_col IS NULL THEN
        SELECT artist_autoinc_seq.nextval
        INTO :new.autoinc_col
        FROM DUAL;
      END IF;
    END;
  });
  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER artist_insert_trg_pk
    BEFORE INSERT ON artist
    FOR EACH ROW
    BEGIN
      IF :new.artistid IS NULL THEN
        SELECT artist_pk_seq.nextval
        INTO :new.artistid
        FROM DUAL;
      END IF;
    END;
  });
  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER cd_insert_trg
    BEFORE INSERT OR UPDATE ON cd
    FOR EACH ROW
    DECLARE
    tmpVar NUMBER;

    BEGIN
      tmpVar := 0;

      IF :new.cdid IS NULL THEN
        SELECT cd_seq.nextval
        INTO tmpVar
        FROM dual;

        :new.cdid := tmpVar;
      END IF;
    END;
  });
  $dbh->do(qq{
    CREATE OR REPLACE TRIGGER track_insert_trg
    BEFORE INSERT ON track
    FOR EACH ROW
    BEGIN
      IF :new.trackid IS NULL THEN
        SELECT track_seq.nextval
        INTO :new.trackid
        FROM DUAL;
      END IF;
    END;
  });
}

# clean up our mess
END {
  for my $dbh (map $_->storage->dbh, grep $_, ($schema, $schema2)) {
    eval {
      $dbh->do("DROP SEQUENCE artist_autoinc_seq");
      $dbh->do("DROP SEQUENCE artist_pk_seq");
      $dbh->do("DROP SEQUENCE cd_seq");
      $dbh->do("DROP SEQUENCE track_seq");
      $dbh->do("DROP SEQUENCE pkid1_seq");
      $dbh->do("DROP SEQUENCE pkid2_seq");
      $dbh->do("DROP SEQUENCE nonpkid_seq");
      $dbh->do("DROP TABLE artist");
      $dbh->do("DROP TABLE sequence_test");
      $dbh->do("DROP TABLE track");
      $dbh->do("DROP TABLE cd");
      $dbh->do("DROP TABLE bindtype_test");
    };
  }
}
