use strict;
use warnings;

use Test::More;

use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIx::Class::SQLMaker::LimitDialects;

my ($TOTAL, $OFFSET) = (
   DBIx::Class::SQLMaker::LimitDialects->__total_bindtype,
   DBIx::Class::SQLMaker::LimitDialects->__offset_bindtype,
);

my $s = DBICTest->init_schema (no_deploy => 1, );
$s->storage->sql_maker->limit_dialect ('RowNum');

my $rs = $s->resultset ('CD');

is_same_sql_bind (
  $rs->search ({}, { rows => 1, offset => 3,columns => [
      { id => 'foo.id' },
      { 'bar.id' => 'bar.id' },
      { bleh => \ 'TO_CHAR (foo.womble, "blah")' },
    ]})->as_query,
  '(
    SELECT id, bar__id, bleh
      FROM (
        SELECT id, bar__id, bleh, ROWNUM rownum__index
          FROM (
            SELECT foo.id AS id, bar.id AS bar__id, TO_CHAR(foo.womble, "blah") AS bleh
              FROM cd me
          ) me
        WHERE ROWNUM <= ?
      ) me
    WHERE rownum__index >= ?
  )',
  [
    [ $TOTAL => 4 ],
    [ $OFFSET => 4 ],
  ],
  'Rownum subsel aliasing works correctly'
);

is_same_sql_bind (
  $rs->search ({}, { rows => 2, offset => 3,columns => [
      { id => 'foo.id' },
      { 'ends_with_me.id' => 'ends_with_me.id' },
    ]})->as_query,
  '(SELECT id, ends_with_me__id
      FROM (
        SELECT id, ends_with_me__id, ROWNUM rownum__index
          FROM (
            SELECT foo.id AS id, ends_with_me.id AS ends_with_me__id
              FROM cd me
          ) me
        WHERE ROWNUM <= ?
      ) me
    WHERE rownum__index >= ?
  )',
  [
    [ $TOTAL => 5 ],
    [ $OFFSET => 4 ],
  ],
  'Rownum subsel aliasing works correctly'
);

{
my $subq = $s->resultset('Owners')->search({
   'count.id' => { -ident => 'owner.id' },
}, { alias => 'owner' })->count_rs;

my $rs_selectas_rel = $s->resultset('BooksInLibrary')->search ({}, {
  columns => [
     { owner_name => 'owner.name' },
     { owner_books => $subq->as_query },
  ],
  join => 'owner',
  rows => 2,
  offset => 3,
});

is_same_sql_bind(
  $rs_selectas_rel->as_query,
  '(
    SELECT owner_name, owner_books
      FROM (
        SELECT owner_name, owner_books, ROWNUM rownum__index
          FROM (
            SELECT  owner.name AS owner_name,
              ( SELECT COUNT( * ) FROM owners owner WHERE (count.id = owner.id)) AS owner_books
              FROM books me
              JOIN owners owner ON owner.id = me.owner
            WHERE ( source = ? )
          ) me
        WHERE ROWNUM <= ?
      ) me
    WHERE rownum__index >= ?
  )',
  [
    [ { sqlt_datatype => 'varchar', sqlt_size => 100, dbic_colname => 'source' }
      => 'Library' ],
    [ $TOTAL => 5 ],
    [ $OFFSET => 4 ],
  ],

  'pagination with subquery works'
);

}

{
  $rs = $s->resultset('Artist')->search({}, {
    columns => 'name',
    offset => 1,
    order_by => 'name',
  });
  local $rs->result_source->{name} = "weird \n newline/multi \t \t space containing \n table";

  like (
    ${$rs->as_query}->[0],
    qr| weird \s \n \s newline/multi \s \t \s \t \s space \s containing \s \n \s table|x,
    'Newlines/spaces preserved in final sql',
  );
}


done_testing;
