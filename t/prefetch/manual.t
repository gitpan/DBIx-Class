use strict;
use warnings;

use Test::More;
use Test::Deep;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema(no_populate => 1);

$schema->resultset('Artist')->create({ name => 'JMJ', cds => [{
  title => 'Magnetic Fields',
  year => 1981,
  genre => { name => 'electro' },
  tracks => [
    { title => 'm1' },
    { title => 'm2' },
    { title => 'm3' },
    { title => 'm4' },
  ],
} ] });

$schema->resultset('CD')->create({
  title => 'Equinoxe',
  year => 1978,
  artist => { name => 'JMJ' },
  genre => { name => 'electro' },
  tracks => [
    { title => 'e1' },
    { title => 'e2' },
    { title => 'e3' },
  ],
  single_track => {
    title => 'o1',
    cd => {
      title => 'Oxygene',
      year => 1976,
      artist => { name => 'JMJ' },
      tracks => [
        { title => 'o2', position => 2},  # the position should not be here, bug in MC
      ],
    },
  },
});

my $rs = $schema->resultset ('CD')->search ({}, {
  join => [ 'tracks', { single_track => { cd => { artist => { cds => 'tracks' } } } }  ],
  collapse => 1,
  columns => [
    { 'year'                                    => 'me.year' },               # non-unique
    { 'genreid'                                 => 'me.genreid' },            # nullable
    { 'tracks.title'                            => 'tracks.title' },          # non-unique (no me.id)
    { 'single_track.cd.artist.cds.cdid'         => 'cds.cdid' },              # to give uniquiness to ...tracks.title below
    { 'single_track.cd.artist.artistid'         => 'artist.artistid' },       # uniqufies entire parental chain
    { 'single_track.cd.artist.cds.year'         => 'cds.year' },              # non-unique
    { 'single_track.cd.artist.cds.genreid'      => 'cds.genreid' },           # nullable
    { 'single_track.cd.artist.cds.tracks.title' => 'tracks_2.title' },        # unique when combined with ...cds.cdid above
    { 'latest_cd'                     => \ "(SELECT MAX(year) FROM cd)" },    # random function
    { 'title'                                   => 'me.title' },              # uniquiness for me
    { 'artist'                                  => 'me.artist' },             # uniquiness for me
  ],
  order_by => [{ -desc => 'cds.year' }, { -desc => 'me.title'} ],
});

my $hri_rs = $rs->search({}, { result_class => 'DBIx::Class::ResultClass::HashRefInflator' });

cmp_deeply (
  [$hri_rs->all],
  [
    {
      artist => 1,
      genreid => 1,
      latest_cd => 1981,
      single_track => {
        cd => {
          artist => {
            artistid => 1,
            cds => [
              {
                cdid => 1,
                genreid => 1,
                tracks => [
                  {
                    title => "m1"
                  },
                  {
                    title => "m2"
                  },
                  {
                    title => "m3"
                  },
                  {
                    title => "m4"
                  }
                ],
                year => 1981
              },
              {
                cdid => 3,
                genreid => 1,
                tracks => [
                  {
                    title => "e1"
                  },
                  {
                    title => "e2"
                  },
                  {
                    title => "e3"
                  }
                ],
                year => 1978
              },
              {
                cdid => 2,
                genreid => undef,
                tracks => [
                  {
                    title => "o1"
                  },
                  {
                    title => "o2"
                  }
                ],
                year => 1976
              }
            ]
          }
        }
      },
      title => "Equinoxe",
      tracks => [
        {
          title => "e1"
        },
        {
          title => "e2"
        },
        {
          title => "e3"
        }
      ],
      year => 1978
    },
    {
      artist => 1,
      genreid => undef,
      latest_cd => 1981,
      single_track => undef,
      title => "Oxygene",
      tracks => [
        {
          title => "o1"
        },
        {
          title => "o2"
        }
      ],
      year => 1976
    },
    {
      artist => 1,
      genreid => 1,
      latest_cd => 1981,
      single_track => undef,
      title => "Magnetic Fields",
      tracks => [
        {
          title => "m1"
        },
        {
          title => "m2"
        },
        {
          title => "m3"
        },
        {
          title => "m4"
        }
      ],
      year => 1981
    },
  ],
  'W00T, manual prefetch with collapse works'
);

TODO: {
  my $row = $rs->next;
  local $TODO = 'Something is wrong with filter type rels, they throw on incomplete objects >.<';

  lives_ok {
    cmp_deeply (
      { $row->single_track->get_columns },
      {},
      'empty intermediate object ok',
    )
  } 'no exception';
}

is ($rs->cursor->next, undef, 'cursor exhausted');


TODO: {
local $TODO = 'this does not work at all, need to promote rsattrs to an object on its own';
# make sure has_many column redirection does not do weird stuff when collapse is requested
for my $pref_args (
  { prefetch => 'cds'},
  { collapse => 1 }
) {
  for my $col_and_join_args (
    { '+columns' => { 'cd_title' => 'cds_2.title' }, join => [ 'cds', 'cds' ] },
    { '+columns' => { 'cd_title' => 'cds.title' }, join => 'cds', }
  ) {

    my $weird_rs = $schema->resultset('Artist')->search({}, {
      %$col_and_join_args, %$pref_args,
    });

    for (qw/next all first/) {
      throws_ok { $weird_rs->$_ } qr/not yet determined exception text/;
    }
  }
}
}

# multi-has_many with underdefined root, with rather random order
$rs = $schema->resultset ('CD')->search ({}, {
  join => [ 'tracks', { single_track => { cd => { artist => { cds => 'tracks' } } } }  ],
  collapse => 1,
  columns => [
    { 'single_track.trackid'                    => 'single_track.trackid' },  # definitive link to root from 1:1:1:1:M:M chain
    { 'year'                                    => 'me.year' },               # non-unique
    { 'tracks.cd'                               => 'tracks.cd' },             # \ together both uniqueness for second multirel
    { 'tracks.title'                            => 'tracks.title' },          # / and definitive link back to root
    { 'single_track.cd.artist.cds.cdid'         => 'cds.cdid' },              # to give uniquiness to ...tracks.title below
    { 'single_track.cd.artist.cds.year'         => 'cds.year' },              # non-unique
    { 'single_track.cd.artist.artistid'         => 'artist.artistid' },       # uniqufies entire parental chain
    { 'single_track.cd.artist.cds.genreid'      => 'cds.genreid' },           # nullable
    { 'single_track.cd.artist.cds.tracks.title' => 'tracks_2.title' },        # unique when combined with ...cds.cdid above
  ],
});

for (1..3) {
  $rs->create({ artist => 1, year => 1977, title => "fuzzy_$_" });
}

my $rs_random = $rs->search({}, { order_by => \ 'RANDOM()' });
is ($rs_random->count, 6, 'row count matches');

if ($ENV{TEST_VERBOSE}) {
 my @lines = (
    [ "What are we actually trying to collapse (Select/As, tests below will see a *DIFFERENT* random order):" ],
    [ map { my $s = $_; $s =~ s/single_track\./sngl_tr./; $s } @{$rs_random->{_attrs}{select} } ],
    $rs_random->{_attrs}{as},
    [ "-" x 159 ],
    $rs_random->cursor->all,
  );

  diag join ' # ', map { sprintf '% 15s', (defined $_ ? $_ : 'NULL') } @$_
    for @lines;
}

my $queries = 0;
$schema->storage->debugcb(sub { $queries++ });
my $orig_debug = $schema->storage->debug;
$schema->storage->debug (1);

for my $use_next (0, 1) {
  my @random_cds;
  if ($use_next) {
    while (my $o = $rs_random->next) {
      push @random_cds, $o;
    }
  }
  else {
    @random_cds = $rs_random->all;
  }

  is (@random_cds, 6, 'object count matches');

  for my $cd (@random_cds) {
    if ($cd->year == 1977) {
      is( scalar $cd->tracks, 0, 'no tracks on 1977 cd' );
      is( $cd->single_track, undef, 'no single_track on 1977 cd' );
    }
    elsif ($cd->year == 1976) {
      is( scalar $cd->tracks, 2, 'Two tracks on 1976 cd' );
      like( $_->title, qr/^o\d/, "correct title" )
        for $cd->tracks;
      is( $cd->single_track, undef, 'no single_track on 1976 cd' );
    }
    elsif ($cd->year == 1981) {
      is( scalar $cd->tracks, 4, 'Four tracks on 1981 cd' );
      like( $_->title, qr/^m\d/, "correct title" )
        for $cd->tracks;
      is( $cd->single_track, undef, 'no single_track on 1981 cd' );
    }
    elsif ($cd->year == 1978) {
      is( scalar $cd->tracks, 3, 'Three tracks on 1978 cd' );
      like( $_->title, qr/^e\d/, "correct title" )
        for $cd->tracks;
      ok( defined $cd->single_track, 'single track prefetched on 1987 cd' );
      is( $cd->single_track->cd->artist->id, 1, 'Single_track->cd->artist prefetched on 1978 cd' );
      is( scalar $cd->single_track->cd->artist->cds, 6, '6 cds prefetched on artist' );
    }
  }
}

$schema->storage->debugcb(undef);
$schema->storage->debug($orig_debug);
is ($queries, 2, "Only two queries for rwo prefetch calls total");

# can't cmp_deeply a random set - need *some* order
my @hris = sort { $a->{year} cmp $b->{year} } @{$rs->search({}, {
  order_by => [ 'tracks_2.title', 'tracks.title', 'cds.cdid', \ 'RANDOM()' ],
})->all_hri};
is (@hris, 6, 'hri count matches' );

cmp_deeply (\@hris, [
  {
    single_track => undef,
    tracks => [
      {
        cd => 2,
        title => "o1"
      },
      {
        cd => 2,
        title => "o2"
      }
    ],
    year => 1976
  },
  {
    single_track => undef,
    tracks => [],
    year => 1977
  },
  {
    single_track => undef,
    tracks => [],
    year => 1977
  },
  {
    single_track => undef,
    tracks => [],
    year => 1977
  },
  {
    single_track => {
      cd => {
        artist => {
          artistid => 1,
          cds => [
            {
              cdid => 4,
              genreid => undef,
              tracks => [],
              year => 1977
            },
            {
              cdid => 5,
              genreid => undef,
              tracks => [],
              year => 1977
            },
            {
              cdid => 6,
              genreid => undef,
              tracks => [],
              year => 1977
            },
            {
              cdid => 3,
              genreid => 1,
              tracks => [
                {
                  title => "e1"
                },
                {
                  title => "e2"
                },
                {
                  title => "e3"
                }
              ],
              year => 1978
            },
            {
              cdid => 1,
              genreid => 1,
              tracks => [
                {
                  title => "m1"
                },
                {
                  title => "m2"
                },
                {
                  title => "m3"
                },
                {
                  title => "m4"
                }
              ],
              year => 1981
            },
            {
              cdid => 2,
              genreid => undef,
              tracks => [
                {
                  title => "o1"
                },
                {
                  title => "o2"
                }
              ],
              year => 1976
            }
          ]
        }
      },
      trackid => 6
    },
    tracks => [
      {
        cd => 3,
        title => "e1"
      },
      {
        cd => 3,
        title => "e2"
      },
      {
        cd => 3,
        title => "e3"
      },
    ],
    year => 1978
  },
  {
    single_track => undef,
    tracks => [
      {
        cd => 1,
        title => "m1"
      },
      {
        cd => 1,
        title => "m2"
      },
      {
        cd => 1,
        title => "m3"
      },
      {
        cd => 1,
        title => "m4"
      },
    ],
    year => 1981
  },
], 'W00T, multi-has_many manual underdefined root prefetch with collapse works');

done_testing;
