use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Data::Dumper;

my $schema = DBICTest->init_schema();

my $orig_debug = $schema->storage->debug;

use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 74 );
}

# figure out if we've got a version of sqlite that is older than 3.2.6, in
# which case COUNT(DISTINCT()) doesn't work
my $is_broken_sqlite = 0;
my ($sqlite_major_ver,$sqlite_minor_ver,$sqlite_patch_ver) =
    split /\./, $schema->storage->dbh->get_info(18);
if( $schema->storage->dbh->get_info(17) eq 'SQLite' &&
    ( ($sqlite_major_ver < 3) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver < 2) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver == 2 && $sqlite_patch_ver < 6) ) ) {
    $is_broken_sqlite = 1;
}

# bug in 0.07000 caused attr (join/prefetch) to be modifed by search
# so we check the search & attr arrays are not modified
my $search = { 'artist.name' => 'Caterwauler McCrae' };
my $attr = { prefetch => [ qw/artist liner_notes/ ],
             order_by => 'me.cdid' };
my $search_str = Dumper($search);
my $attr_str = Dumper($attr);

my $rs = $schema->resultset("CD")->search($search, $attr);

is(Dumper($search), $search_str, 'Search hash untouched after search()');
is(Dumper($attr), $attr_str, 'Attribute hash untouched after search()');
cmp_ok($rs + 0, '==', 3, 'Correct number of records returned');

# A search() with prefetch seems to pollute an already joined resultset
# in a way that offsets future joins (adapted from a test case by Debolaz)
{
  my ($cd_rs, $attrs);

  # test a real-life case - rs is obtained by an implicit m2m join
  $cd_rs = $schema->resultset ('Producer')->first->cds;
  $attrs = Dumper $cd_rs->{attrs};

  $cd_rs->search ({})->all;
  is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after a simple search');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after search with prefetch');
  }, 'first prefetching search ok');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after another search with prefetch')
  }, 'second prefetching search ok');


  # test a regular rs with an empty seen_join injected - it should still work!
  $cd_rs = $schema->resultset ('CD');
  $cd_rs->{attrs}{seen_join}  = {};
  $attrs = Dumper $cd_rs->{attrs};

  $cd_rs->search ({})->all;
  is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after a simple search');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after search with prefetch');
  }, 'first prefetching search ok');

  lives_ok (sub {
    $cd_rs->search ({'artist.artistid' => 1}, { prefetch => 'artist' })->all;
    is (Dumper ($cd_rs->{attrs}), $attrs, 'Resultset attributes preserved after another search with prefetch')
  }, 'second prefetching search ok');
}


my $queries = 0;
$schema->storage->debugcb(sub { $queries++; });
$schema->storage->debug(1);

my @cd = $rs->all;

is($cd[0]->title, 'Spoonful of bees', 'First record returned ok');

ok(!defined $cd[0]->liner_notes, 'No prefetch for NULL LEFT join');

is($cd[1]->{_relationship_data}{liner_notes}->notes, 'Buy Whiskey!', 'Prefetch for present LEFT JOIN');

is(ref $cd[1]->liner_notes, 'DBICTest::LinerNotes', 'Prefetch returns correct class');

is($cd[2]->{_inflated_column}{artist}->name, 'Caterwauler McCrae', 'Prefetch on parent object ok');

is($queries, 1, 'prefetch ran only 1 select statement');

$schema->storage->debug($orig_debug);
$schema->storage->debugobj->callback(undef);

# test for partial prefetch via columns attr
my $cd = $schema->resultset('CD')->find(1,
    {
      columns => [qw/title artist artist.name/], 
      join => { 'artist' => {} }
    }
);
ok(eval { $cd->artist->name eq 'Caterwauler McCrae' }, 'single related column prefetched');

# start test for nested prefetch SELECT count
$queries = 0;
$schema->storage->debugcb(sub { $queries++ });
$schema->storage->debug(1);

$rs = $schema->resultset('Tag')->search(
  {},
  {
    prefetch => { cd => 'artist' }
  }
);

my $tag = $rs->first;

is( $tag->cd->title, 'Spoonful of bees', 'step 1 ok for nested prefetch' );

is( $tag->cd->artist->name, 'Caterwauler McCrae', 'step 2 ok for nested prefetch');

# count the SELECTs
#$selects++ if /SELECT(?!.*WHERE 1=0.*)/;
is($queries, 1, 'nested prefetch ran exactly 1 select statement (excluding column_info)');

$queries = 0;

is($tag->search_related('cd')->search_related('artist')->first->name,
   'Caterwauler McCrae',
   'chained belongs_to->belongs_to search_related ok');

is($queries, 0, 'chained search_related after belontgs_to->belongs_to prefetch ran no queries');

$queries = 0;

$cd = $schema->resultset('CD')->find(1, { prefetch => 'artist' });

is($cd->{_inflated_column}{artist}->name, 'Caterwauler McCrae', 'artist prefetched correctly on find');

is($queries, 1, 'find with prefetch ran exactly 1 select statement (excluding column_info)');

$queries = 0;

$schema->storage->debugcb(sub { $queries++; });

$cd = $schema->resultset('CD')->find(1, { prefetch => { cd_to_producer => 'producer' } });

is($cd->producers->first->name, 'Matt S Trout', 'many_to_many accessor ok');

is($queries, 1, 'many_to_many accessor with nested prefetch ran exactly 1 query');

$queries = 0;

my $producers = $cd->search_related('cd_to_producer')->search_related('producer');

is($producers->first->name, 'Matt S Trout', 'chained many_to_many search_related ok');

is($queries, 0, 'chained search_related after many_to_many prefetch ran no queries');

$schema->storage->debug($orig_debug);
$schema->storage->debugobj->callback(undef);

$rs = $schema->resultset('Tag')->search(
  {},
  {
    join => { cd => 'artist' },
    prefetch => { cd => 'artist' }
  }
);

cmp_ok( $rs->count, '>=', 0, 'nested prefetch does not duplicate joins' );

my ($artist) = $schema->resultset("Artist")->search({ 'cds.year' => 2001 },
                 { order_by => 'artistid DESC', join => 'cds' });

is($artist->name, 'Random Boy Band', "Join search by object ok");

my @cds = $schema->resultset("CD")->search({ 'liner_notes.notes' => 'Buy Merch!' },
                               { join => 'liner_notes' });

cmp_ok(scalar @cds, '==', 1, "Single CD retrieved via might_have");

is($cds[0]->title, "Generic Manufactured Singles", "Correct CD retrieved");

my @artists = $schema->resultset("Artist")->search({ 'tags.tag' => 'Shiny' },
                                       { join => { 'cds' => 'tags' } });

cmp_ok( @artists, '==', 2, "two-join search ok" );

$rs = $schema->resultset("CD")->search(
  {},
  { group_by => [qw/ title me.cdid /] }
);

SKIP: {
    skip "SQLite < 3.2.6 doesn't understand COUNT(DISTINCT())", 1
        if $is_broken_sqlite;
    cmp_ok( $rs->count, '==', 5, "count() ok after group_by on main pk" );
}

cmp_ok( scalar $rs->all, '==', 5, "all() returns same count as count() after group_by on main pk" );

$rs = $schema->resultset("CD")->search(
  {},
  { join => [qw/ artist /], group_by => [qw/ artist.name /] }
);

SKIP: {
    skip "SQLite < 3.2.6 doesn't understand COUNT(DISTINCT())", 1
        if $is_broken_sqlite;
    cmp_ok( $rs->count, '==', 3, "count() ok after group_by on related column" );
}

$rs = $schema->resultset("Artist")->search(
  {},
      { join => [qw/ cds /], group_by => [qw/ me.name /], having =>{ 'MAX(cds.cdid)'=> \'< 5' } }
);

cmp_ok( $rs->all, '==', 2, "results ok after group_by on related column with a having" );

$rs = $rs->search( undef, {  having =>{ 'count(*)'=> \'> 2' }});

cmp_ok( $rs->all, '==', 1, "count() ok after group_by on related column with a having" );

$rs = $schema->resultset("Artist")->search(
        { 'cds.title' => 'Spoonful of bees',
          'cds_2.title' => 'Forkful of bees' },
        { join => [ 'cds', 'cds' ] });

SKIP: {
    skip "SQLite < 3.2.6 doesn't understand COUNT(DISTINCT())", 1
        if $is_broken_sqlite;
    cmp_ok($rs->count, '==', 1, "single artist returned from multi-join");
}

is($rs->next->name, 'Caterwauler McCrae', "Correct artist returned");

$cd = $schema->resultset('Artist')->first->create_related('cds',
    {
    title   => 'Unproduced Single',
    year    => 2007
});

my $left_join = $schema->resultset('CD')->search(
    { 'me.cdid' => $cd->cdid },
    { prefetch => { cd_to_producer => 'producer' } }
);

cmp_ok($left_join, '==', 1, 'prefetch with no join record present');

$queries = 0;
$schema->storage->debugcb(sub { $queries++ });
$schema->storage->debug(1);

my $tree_like =
     $schema->resultset('TreeLike')->find(5,
       { join     => { parent => { parent => 'parent' } },
         prefetch => { parent => { parent => 'parent' } } });

is($tree_like->name, 'quux', 'Bottom of tree ok');
$tree_like = $tree_like->parent;
is($tree_like->name, 'baz', 'First level up ok');
$tree_like = $tree_like->parent;
is($tree_like->name, 'bar', 'Second level up ok');
$tree_like = $tree_like->parent;
is($tree_like->name, 'foo', 'Third level up ok');

$schema->storage->debug($orig_debug);
$schema->storage->debugobj->callback(undef);

cmp_ok($queries, '==', 1, 'Only one query run');

$tree_like = $schema->resultset('TreeLike')->search({'me.id' => 2});
$tree_like = $tree_like->search_related('children')->search_related('children')->search_related('children')->first;
is($tree_like->name, 'quux', 'Tree search_related ok');

$tree_like = $schema->resultset('TreeLike')->search_related('children',
    { 'children.id' => 3, 'children_2.id' => 4 },
    { prefetch => { children => 'children' } }
  )->first;
is(eval { $tree_like->children->first->children->first->name }, 'quux',
   'Tree search_related with prefetch ok');

$tree_like = eval { $schema->resultset('TreeLike')->search(
    { 'children.id' => 3, 'children_2.id' => 6 }, 
    { join => [qw/children children/] }
  )->search_related('children', { 'children_4.id' => 7 }, { prefetch => 'children' }
  )->first->children->first; };
is(eval { $tree_like->name }, 'fong', 'Tree with multiple has_many joins ok');

# test that collapsed joins don't get a _2 appended to the alias

my $sql = '';
$schema->storage->debugcb(sub { $sql = $_[1] });
$schema->storage->debug(1);

eval {
  my $row = $schema->resultset('Artist')->search_related('cds', undef, {
    join => 'tracks',
    prefetch => 'tracks',
  })->search_related('tracks')->first;
};

like( $sql, qr/^SELECT tracks_2\.trackid/, "join not collapsed for search_related" );

$schema->storage->debug($orig_debug);
$schema->storage->debugobj->callback(undef);

$rs = $schema->resultset('Artist');
$rs->create({ artistid => 4, name => 'Unknown singer-songwriter' });
$rs->create({ artistid => 5, name => 'Emo 4ever' });
@artists = $rs->search(undef, { prefetch => 'cds', order_by => 'artistid' });
is(scalar @artists, 5, 'has_many prefetch with adjacent empty rows ok');

# -------------
#
# Tests for multilevel has_many prefetch

# artist resultsets - with and without prefetch
my $art_rs = $schema->resultset('Artist');
my $art_rs_pr = $art_rs->search(
    {},
    {
        join     => [ { cds => ['tracks'] } ],
        prefetch => [ { cds => ['tracks'] } ],
        cache    => 1 # last test needs this
    }
);

# This test does the same operation twice - once on a
# set of items fetched from the db with no prefetch of has_many rels
# The second prefetches 2 levels of has_many
# We check things are the same by comparing the name or title
# we build everything into a hash structure and compare the one
# from each rs to see what differs

sub make_hash_struc {
    my $rs = shift;

    my $struc = {};
    foreach my $art ( $rs->all ) {
        foreach my $cd ( $art->cds ) {
            foreach my $track ( $cd->tracks ) {
                $struc->{ $art->name }{ $cd->title }{ $track->title }++;
            }
        }
    }
    return $struc;
}

$queries = 0;
$schema->storage->debugcb(sub { $queries++ });
$schema->storage->debug(1);

my $prefetch_result = make_hash_struc($art_rs_pr);

is($queries, 1, 'nested prefetch across has_many->has_many ran exactly 1 query');

my $nonpre_result   = make_hash_struc($art_rs);

is_deeply( $prefetch_result, $nonpre_result,
    'Compare 2 level prefetch result to non-prefetch result' );

$queries = 0;

is($art_rs_pr->search_related('cds')->search_related('tracks')->first->title,
   'Fowlin',
   'chained has_many->has_many search_related ok'
  );

is($queries, 0, 'chained search_related after has_many->has_many prefetch ran no queries');

# once the following TODO is complete, remove the 2 warning tests immediately after the TODO block
# (the TODO block itself contains tests ensuring that the warns are removed)
TODO: {
    local $TODO = 'Prefetch of multiple has_many rels at the same level (currently warn to protect the clueless git)';

    #( 1 -> M + M )
    my $cd_rs = $schema->resultset('CD')->search ({ 'me.title' => 'Forkful of bees' });
    my $pr_cd_rs = $cd_rs->search ({}, {
        prefetch => [qw/tracks tags/],
    });

    my $tracks_rs = $cd_rs->first->tracks;
    my $tracks_count = $tracks_rs->count;

    my ($pr_tracks_rs, $pr_tracks_count);

    $queries = 0;
    $schema->storage->debugcb(sub { $queries++ });
    $schema->storage->debug(1);

    my $o_mm_warn;
    {
        local $SIG{__WARN__} = sub { $o_mm_warn = shift };
        $pr_tracks_rs = $pr_cd_rs->first->tracks;
    };
    $pr_tracks_count = $pr_tracks_rs->count;

    ok(! $o_mm_warn, 'no warning on attempt to prefetch several same level has_many\'s (1 -> M + M)');

    is($queries, 1, 'prefetch one->(has_many,has_many) ran exactly 1 query');
    is($pr_tracks_count, $tracks_count, 'equal count of prefetched relations over several same level has_many\'s (1 -> M + M)');

    for ($pr_tracks_rs, $tracks_rs) {
        $_->result_class ('DBIx::Class::ResultClass::HashRefInflator');
    }

    is_deeply ([$pr_tracks_rs->all], [$tracks_rs->all], 'same structure returned with and without prefetch over several same level has_many\'s (1 -> M + M)');

    #( M -> 1 -> M + M )
    my $note_rs = $schema->resultset('LinerNotes')->search ({ notes => 'Buy Whiskey!' });
    my $pr_note_rs = $note_rs->search ({}, {
        prefetch => {
            cd => [qw/tags tracks/]
        },
    });

    my $tags_rs = $note_rs->first->cd->tags;
    my $tags_count = $tags_rs->count;

    my ($pr_tags_rs, $pr_tags_count);

    $queries = 0;
    $schema->storage->debugcb(sub { $queries++ });
    $schema->storage->debug(1);

    my $m_o_mm_warn;
    {
        local $SIG{__WARN__} = sub { $m_o_mm_warn = shift };
        $pr_tags_rs = $pr_note_rs->first->cd->tags;
    };
    $pr_tags_count = $pr_tags_rs->count;

    ok(! $m_o_mm_warn, 'no warning on attempt to prefetch several same level has_many\'s (M -> 1 -> M + M)');

    is($queries, 1, 'prefetch one->(has_many,has_many) ran exactly 1 query');

    is($pr_tags_count, $tags_count, 'equal count of prefetched relations over several same level has_many\'s (M -> 1 -> M + M)');

    for ($pr_tags_rs, $tags_rs) {
        $_->result_class ('DBIx::Class::ResultClass::HashRefInflator');
    }

    is_deeply ([$pr_tags_rs->all], [$tags_rs->all], 'same structure returned with and without prefetch over several same level has_many\'s (M -> 1 -> M + M)');
};

# remove this closure once the TODO above is working
my $w;
{
    local $SIG{__WARN__} = sub { $w = shift };

    my $rs = $schema->resultset('CD')->search ({ 'me.title' => 'Forkful of bees' }, { prefetch => [qw/tracks tags/] });
    for (qw/all count next first/) {
        undef $w;
        my @stuff = $rs->search()->$_;
        like ($w, qr/will currently disrupt both the functionality of .rs->count\(\), and the amount of objects retrievable via .rs->next\(\)/,
            "warning on ->$_ attempt prefetching several same level has_manys (1 -> M + M)");
    }
    my $rs2 = $schema->resultset('LinerNotes')->search ({ notes => 'Buy Whiskey!' }, { prefetch => { cd => [qw/tags tracks/] } });
    for (qw/all count next first/) {
        undef $w;
        my @stuff = $rs2->search()->$_;
        like ($w, qr/will currently disrupt both the functionality of .rs->count\(\), and the amount of objects retrievable via .rs->next\(\)/,
            "warning on ->$_ attempt prefetching several same level has_manys (M -> 1 -> M + M)");
    }
}
