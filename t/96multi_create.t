use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

plan tests => 89;

my $schema = DBICTest->init_schema();

# simple create + parent (the stuff $rs belongs_to)
eval {
  my $cd = $schema->resultset('CD')->create({
    artist => { 
      name => 'Fred Bloggs' 
    },
    title => 'Some CD',
    year => 1996
  });

  isa_ok($cd, 'DBICTest::CD', 'Created CD object');
  isa_ok($cd->artist, 'DBICTest::Artist', 'Created related Artist');
  is($cd->artist->name, 'Fred Bloggs', 'Artist created correctly');
};
diag $@ if $@;

# same as above but the child and parent have no values,
# except for an explicit parent pk
eval {
  my $bm_rs = $schema->resultset('Bookmark');
  my $bookmark = $bm_rs->create({
    link => {
      id => 66,
    },
  });

  isa_ok($bookmark, 'DBICTest::Bookmark', 'Created Bookrmark object');
  isa_ok($bookmark->link, 'DBICTest::Link', 'Created related Link');
  is (
    $bm_rs->search (
      { 'link.title' => $bookmark->link->title },
      { join => 'link' },
    )->count,
    1,
    'Bookmark and link made it to the DB',
  );
};
diag $@ if $@;

# create over > 1 levels of has_many create (A => { has_many => { B => has_many => C } } )
eval {
  my $artist = $schema->resultset('Artist')->first;
  my $cd = $artist->create_related (cds => {
    title => 'Music to code by',
    year => 2007,
    tags => [
      { 'tag' => 'rock' },
    ],
  });

  isa_ok($cd, 'DBICTest::CD', 'Created CD');
  is($cd->title, 'Music to code by', 'CD created correctly');
  is($cd->tags->count, 1, 'One tag created for CD');
  is($cd->tags->first->tag, 'rock', 'Tag created correctly');

};
diag $@ if $@;

throws_ok (
  sub {
    # Create via update - add a new CD <--- THIS SHOULD HAVE NEVER WORKED!
    $schema->resultset('Artist')->first->update({
      cds => [
        { title => 'Yet another CD',
          year => 2006,
        },
      ],
    });
  },
  qr/Recursive update is not supported over relationships of type multi/,
  'create via update of multi relationships throws an exception'
);

# Create m2m while originating in the linker table
eval {
  my $artist = $schema->resultset('Artist')->first;
  my $c2p = $schema->resultset('CD_to_Producer')->create ({
    cd => {
      artist => $artist,
      title => 'Bad investment',
      year => 2008,
      tracks => [
        { position => 1, title => 'Just buy' },
        { position => 2, title => 'Why did we do it' },
        { position => 3, title => 'Burn baby burn' },
      ],
    },
    producer => {
      name => 'Lehman Bros.',
    },
  });

  isa_ok ($c2p, 'DBICTest::CD_to_Producer', 'Linker object created');
  my $prod = $schema->resultset ('Producer')->find ({ name => 'Lehman Bros.' });
  isa_ok ($prod, 'DBICTest::Producer', 'Producer row found');
  is ($prod->cds->count, 1, 'Producer has one production');
  my $cd = $prod->cds->first;
  is ($cd->title, 'Bad investment', 'CD created correctly');
  is ($cd->tracks->count, 3, 'CD has 3 tracks');

};
diag $@ if $@;

# create over > 1 levels of might_have (A => { might_have => { B => has_many => C } } )
eval {
  my $artist = $schema->resultset('Artist')->first;
  my $cd = $schema->resultset('CD')->create ({
    artist => $artist,
    title => 'Music to code by at night',
    year => 2008,
    tracks => [
      {
        position => 1,
        title => 'Off by one again',
      },
      {
        position => 2,
        title => 'The dereferencer',
        cd_single => {
          artist => $artist,
          year => 2008,
          title => 'Was that a null (Single)',
          tracks => [
            { title => 'The dereferencer', position => 1 },
            { title => 'The dereferencer II', position => 2 },
          ],
          cd_to_producer => [
            {
              producer => {
                name => 'K&R',
              }
            }
          ]
        },
      },
    ],
  });

  isa_ok ($cd, 'DBICTest::CD', 'Main CD object created');
  is ($cd->title, 'Music to code by at night', 'Correct CD title');
  is ($cd->tracks->count, 2, 'Two tracks on main CD');

  my ($t1, $t2) = $cd->tracks->all;
  is ($t1->title, 'Off by one again', 'Correct 1st track name');
  is ($t1->cd_single, undef, 'No single for 1st track');
  is ($t2->title, 'The dereferencer', 'Correct 2nd track name');
  isa_ok ($t2->cd_single, 'DBICTest::CD', 'Created a single for 2nd track');

  my $single = $t2->cd_single;
  is ($single->tracks->count, 2, 'Two tracks on single CD');
  is ($single->tracks->find ({ position => 1})->title, 'The dereferencer', 'Correct 1st track title');
  is ($single->tracks->find ({ position => 2})->title, 'The dereferencer II', 'Correct 2nd track title');

  is ($single->cd_to_producer->count, 1, 'One producer created with the single cd');
  is ($single->cd_to_producer->first->producer->name, 'K&R', 'Producer name correct');
};
diag $@ if $@;

TODO: {
local $TODO = "Todoify for multicreate branch";
# test might_have again but with a PK == FK in the middle (obviously not specified)
eval {
  my $artist = $schema->resultset('Artist')->first;
  my $cd = $schema->resultset('CD')->create ({
    artist => $artist,
    title => 'Music to code by at twilight',
    year => 2008,
    artwork => {
      images => [
        { name => 'recursive descent' },
        { name => 'tail packing' },
      ],
    },
  });

  isa_ok ($cd, 'DBICTest::CD', 'Main CD object created');
  is ($cd->title, 'Music to code by at twilight', 'Correct CD title');
  isa_ok ($cd->artwork, 'DBICTest::Artwork', 'Artwork created');

  # this test might look weird, but it failed at one point, keep it there
  my $art_obj = $cd->artwork;
  ok ($art_obj->has_column_loaded ('cd_id'), 'PK/FK present on artwork object');
  is ($art_obj->images->count, 2, 'Correct artwork image count via the new object');
  is_deeply (
    [ sort $art_obj->images->get_column ('name')->all ],
    [ 'recursive descent', 'tail packing' ],
    'Images named correctly in objects',
  );


  my $artwork = $schema->resultset('Artwork')->search (
    { 'cd.title' => 'Music to code by at twilight' },
    { join => 'cd' },
  )->single;

  is ($artwork->images->count, 2, 'Correct artwork image count via a new search');

  is_deeply (
    [ sort $artwork->images->get_column ('name')->all ],
    [ 'recursive descent', 'tail packing' ],
    'Images named correctly after search',
  );
};
diag $@ if $@;

# test might_have again but with just a PK and FK (neither specified) in the mid-table
eval {
  my $cd = $schema->resultset('CD')->first;
  my $track = $schema->resultset ('Track')->create ({
    cd => $cd,
    position => 66,
    title => 'Black',
    lyrics => {
      lyric_versions => [
        { text => 'The color black' },
        { text => 'The colour black' },
      ],
    },
  });

  isa_ok ($track, 'DBICTest::Track', 'Main track object created');
  is ($track->title, 'Black', 'Correct track title');
  isa_ok ($track->lyrics, 'DBICTest::Lyrics', 'Lyrics created');

  # this test might look weird, but it was failing at one point, keep it there
  my $lyric_obj = $track->lyrics;
  ok ($lyric_obj->has_column_loaded ('lyric_id'), 'PK present on lyric object');
  ok ($lyric_obj->has_column_loaded ('track_id'), 'FK present on lyric object');
  is ($lyric_obj->lyric_versions->count, 2, 'Correct lyric versions count via the new object');
  is_deeply (
    [ sort $lyric_obj->lyric_versions->get_column ('text')->all ],
    [ 'The color black', 'The colour black' ],
    'Lyrics text in objects matches',
  );


  my $lyric = $schema->resultset('Lyrics')->search (
    { 'track.title' => 'Black' },
    { join => 'track' },
  )->single;

  is ($lyric->lyric_versions->count, 2, 'Correct lyric versions count via a new search');

  is_deeply (
    [ sort $lyric->lyric_versions->get_column ('text')->all ],
    [ 'The color black', 'The colour black' ],
    'Lyrics text via search matches',
  );
};
diag $@ if $@;
}

# nested find_or_create
eval {
  my $newartist2 = $schema->resultset('Artist')->find_or_create({ 
    name => 'Fred 3',
    cds => [
      { 
        title => 'Noah Act',
        year => 2007,
      },
    ],
  });
  is($newartist2->name, 'Fred 3', 'Created new artist with cds via find_or_create');
};
diag $@ if $@;

# multiple same level has_many create
eval {
  my $artist2 = $schema->resultset('Artist')->create({
    name => 'Fred 4',
    cds => [
      {
        title => 'Music to code by',
        year => 2007,
      },
    ],
    cds_unordered => [
      {
        title => 'Music to code by',
        year => 2007,
      },
    ]
  });

  is($artist2->in_storage, 1, 'artist with duplicate rels inserted okay');
};
diag $@ if $@;

# first create_related pass
eval {
	my $artist = $schema->resultset('Artist')->first;
	
	my $cd_result = $artist->create_related('cds', {
	
		title => 'TestOneCD1',
		year => 2007,
		tracks => [
		
			{ position=>111,
			  title => 'TrackOne',
			},
			{ position=>112,
			  title => 'TrackTwo',
			}
		],

	});
	
	ok( $cd_result && ref $cd_result eq 'DBICTest::CD', "Got Good CD Class");
	ok( $cd_result->title eq "TestOneCD1", "Got Expected Title");
	
	my $tracks = $cd_result->tracks;
	
	ok( ref $tracks eq "DBIx::Class::ResultSet", "Got Expected Tracks ResultSet");
	
	foreach my $track ($tracks->all)
	{
		ok( $track && ref $track eq 'DBICTest::Track', 'Got Expected Track Class');
	}
};
diag $@ if $@;

# second create_related with same arguments
eval {
	my $artist = $schema->resultset('Artist')->first;
	
	my $cd_result = $artist->create_related('cds', {
	
		title => 'TestOneCD2',
		year => 2007,
		tracks => [
		
			{ position=>111,
			  title => 'TrackOne',
			},
			{ position=>112,
			  title => 'TrackTwo',
			}
		],

    liner_notes => { notes => 'I can haz liner notes?' },

	});
	
	ok( $cd_result && ref $cd_result eq 'DBICTest::CD', "Got Good CD Class");
	ok( $cd_result->title eq "TestOneCD2", "Got Expected Title");
  ok( $cd_result->notes eq 'I can haz liner notes?', 'Liner notes');
	
	my $tracks = $cd_result->tracks;
	
	ok( ref $tracks eq "DBIx::Class::ResultSet", "Got Expected Tracks ResultSet");
	
	foreach my $track ($tracks->all)
	{
		ok( $track && ref $track eq 'DBICTest::Track', 'Got Expected Track Class');
	}
};
diag $@ if $@;

# create of parents of a record linker table
eval {
  my $cdp = $schema->resultset('CD_to_Producer')->create({
    cd => { artist => 1, title => 'foo', year => 2000 },
    producer => { name => 'jorge' }
  });
  ok($cdp, 'join table record created ok');
};
diag $@ if $@;

#SPECIAL_CASE
eval {
  my $kurt_cobain = { name => 'Kurt Cobain' };

  my $in_utero = $schema->resultset('CD')->new({
      title => 'In Utero',
      year  => 1993
    });

  $kurt_cobain->{cds} = [ $in_utero ];


  $schema->resultset('Artist')->populate([ $kurt_cobain ]); # %)
  $a = $schema->resultset('Artist')->find({name => 'Kurt Cobain'});

  is($a->name, 'Kurt Cobain', 'Artist insertion ok');
  is($a->cds && $a->cds->first && $a->cds->first->title, 
		  'In Utero', 'CD insertion ok');
};
diag $@ if $@;

#SPECIAL_CASE2
eval {
  my $pink_floyd = { name => 'Pink Floyd' };

  my $the_wall = { title => 'The Wall', year  => 1979 };

  $pink_floyd->{cds} = [ $the_wall ];


  $schema->resultset('Artist')->populate([ $pink_floyd ]); # %)
  $a = $schema->resultset('Artist')->find({name => 'Pink Floyd'});

  is($a->name, 'Pink Floyd', 'Artist insertion ok');
  is($a->cds && $a->cds->first->title, 'The Wall', 'CD insertion ok');
};
diag $@ if $@;

## Create foreign key col obj including PK
## See test 20 in 66relationships.t
eval {
  my $new_cd_hashref = { 
    cdid => 27, 
    title => 'Boogie Woogie', 
    year => '2007', 
    artist => { artistid => 17, name => 'king luke' }
  };

  my $cd = $schema->resultset("CD")->find(1);

  is($cd->artist->id, 1, 'rel okay');

  my $new_cd = $schema->resultset("CD")->create($new_cd_hashref);
  is($new_cd->artist->id, 17, 'new id retained okay');
};
diag $@ if $@;

eval {
	$schema->resultset("CD")->create({ 
              cdid => 28, 
              title => 'Boogie Wiggle', 
              year => '2007', 
              artist => { artistid => 18, name => 'larry' }
             });
};
is($@, '', 'new cd created without clash on related artist');

# Make sure exceptions from errors in created rels propogate
eval {
    my $t = $schema->resultset("Track")->new({ cd => { artist => undef } });
    #$t->cd($t->new_related('cd', { artist => undef } ) );
    #$t->{_rel_in_storage} = 0;
    $t->insert;
};
like($@, qr/cd.artist may not be NULL/, "Exception propogated properly");

# Test multi create over many_to_many
eval {
  $schema->resultset('CD')->create ({
    artist => {
      name => 'larry', # should already exist
    },
    title => 'Warble Marble',
    year => '2009',
    cd_to_producer => [
      { producer => { name => 'Cowboy Neal' } },
    ],
  });

  my $m2m_cd = $schema->resultset('CD')->search ({ title => 'Warble Marble'});
  is ($m2m_cd->count, 1, 'One CD row created via M2M create');
  is ($m2m_cd->first->producers->count, 1, 'CD row created with one producer');
  is ($m2m_cd->first->producers->first->name, 'Cowboy Neal', 'Correct producer row created');
};

# and some insane multicreate 
# (should work, despite the fact that no one will probably use it this way)

# first count how many rows do we initially have
my $counts;
$counts->{$_} = $schema->resultset($_)->count for qw/Artist CD Genre Producer Tag/;

# do the crazy create
eval {
  $schema->resultset('CD')->create ({
    artist => {
      name => 'james',
    },
    title => 'Greatest hits 1',
    year => '2012',
    genre => {
      name => '"Greatest" collections',
    },
    tags => [
      { tag => 'A' },
      { tag => 'B' },
    ],
    cd_to_producer => [
      {
        producer => {
          name => 'bob',
          producer_to_cd => [
            {
              cd => { 
                artist => {
                  name => 'lars',
                  cds => [
                    {
                      title => 'Greatest hits 2',
                      year => 2012,
                      genre => {
                        name => '"Greatest" collections',
                      },
                      tags => [
                        { tag => 'A' },
                        { tag => 'B' },
                      ],
                      # This cd is created via artist so it doesn't know about producers
                      cd_to_producer => [
                        # if we specify 'bob' here things bomb
                        # as the producer attached to Greatest Hits 1 is
                        # already created, but not yet inserted.
                        # Maybe this can be fixed, but things are hairy
                        # enough already.
                        #
                        #{ producer => { name => 'bob' } },
                        { producer => { name => 'paul' } },
                        { producer => {
                          name => 'flemming',
                          producer_to_cd => [
                            { cd => {
                              artist => {
                                name => 'kirk',
                                cds => [
                                  {
                                    title => 'Greatest hits 3',
                                    year => 2012,
                                    genre => {
                                      name => '"Greatest" collections',
                                    },
                                    tags => [
                                      { tag => 'A' },
                                      { tag => 'B' },
                                    ],
                                  },
                                  {
                                    title => 'Greatest hits 4',
                                    year => 2012,
                                    genre => {
                                      name => '"Greatest" collections2',
                                    },
                                    tags => [
                                      { tag => 'A' },
                                      { tag => 'B' },
                                    ],
                                  },
                                ],
                              },
                              title => 'Greatest hits 5',
                              year => 2013,
                              genre => {
                                name => '"Greatest" collections2',
                              },
                            }},
                          ],
                        }},
                      ],
                    },
                  ],
                },
                title => 'Greatest hits 6',
                year => 2012,
                genre => {
                  name => '"Greatest" collections',
                },
                tags => [
                  { tag => 'A' },
                  { tag => 'B' },
                ],
              },
            },
            {
              cd => { 
                artist => {
                  name => 'lars',    # should already exist
                  # even though the artist 'name' is not uniquely constrained
                  # find_or_create will arguably DWIM 
                },
                title => 'Greatest hits 7',
                year => 2013,
              },
            },
          ],
        },
      },
    ],
  });

  is ($schema->resultset ('Artist')->count, $counts->{Artist} + 3, '3 new artists created');
  is ($schema->resultset ('Genre')->count, $counts->{Genre} + 2, '2 additional genres created');
  is ($schema->resultset ('Producer')->count, $counts->{Producer} + 3, '3 new producer');
  is ($schema->resultset ('CD')->count, $counts->{CD} + 7, '7 new CDs');
  is ($schema->resultset ('Tag')->count, $counts->{Tag} + 10, '10 new Tags');

  my $cd_rs = $schema->resultset ('CD')
    ->search ({ title => { -like => 'Greatest hits %' }}, { order_by => 'title'} );
  is ($cd_rs->count, 7, '7 greatest hits created');

  my $cds_2012 = $cd_rs->search ({ year => 2012});
  is ($cds_2012->count, 5, '5 CDs created in 2012');

  is (
    $cds_2012->search(
      { 'tags.tag' => { -in => [qw/A B/] } },
      { join => 'tags', group_by => 'me.cdid' }
    ),
    5,
    'All 10 tags were pairwise distributed between 5 year-2012 CDs'
  );

  my $paul_prod = $cd_rs->search (
    { 'producer.name' => 'paul'},
    { join => { cd_to_producer => 'producer' } }
  );
  is ($paul_prod->count, 1, 'Paul had 1 production');
  my $pauls_cd = $paul_prod->single;
  is ($pauls_cd->cd_to_producer->count, 2, 'Paul had one co-producer');
  is (
    $pauls_cd->search_related ('cd_to_producer',
      { 'producer.name' => 'flemming'},
      { join => 'producer' }
    )->count,
    1,
    'The second producer is flemming',
  );

  my $kirk_cds = $cd_rs->search ({ 'artist.name' => 'kirk' }, { join => 'artist' });
  is ($kirk_cds, 3, 'Kirk had 3 CDs');
  is (
    $kirk_cds->search (
      { 'cd_to_producer.cd' => { '!=', undef } },
      { join => 'cd_to_producer' },
    ),
    1,
    'Kirk had a producer only on one cd',
  );

  my $lars_cds = $cd_rs->search ({ 'artist.name' => 'lars' }, { join => 'artist' });
  is ($lars_cds->count, 3, 'Lars had 3 CDs');
  is (
    $lars_cds->search (
      { 'cd_to_producer.cd' => undef },
      { join => 'cd_to_producer' },
    ),
    0,
    'Lars always had a producer',
  );
  is (
    $lars_cds->search_related ('cd_to_producer',
      { 'producer.name' => 'flemming'},
      { join => 'producer' }
    )->count,
    1,
    'Lars produced 1 CD with flemming',
  );
  is (
    $lars_cds->search_related ('cd_to_producer',
      { 'producer.name' => 'bob'},
      { join => 'producer' }
    )->count,
    2,
    'Lars produced 2 CDs with bob',
  );

  my $bob_prod = $cd_rs->search (
    { 'producer.name' => 'bob'},
    { join => { cd_to_producer => 'producer' } }
  );
  is ($bob_prod->count, 3, 'Bob produced a total of 3 CDs');

  is (
    $bob_prod->search ({ 'artist.name' => 'james' }, { join => 'artist' })->count,
    1,
    "Bob produced james' only CD",
  );
};
diag $@ if $@;

1;
