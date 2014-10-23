package # hide from PAUSE 
    DBICTest::Schema::TwoKeyTreeLike;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/Core/);

__PACKAGE__->table('twokeytreelike');
__PACKAGE__->add_columns(
  'id1' => { data_type => 'integer' },
  'id2' => { data_type => 'integer' },
  'parent1' => { data_type => 'integer' },
  'parent2' => { data_type => 'integer' },
  'name' => { data_type => 'varchar',
    size      => 100,
 },
);
__PACKAGE__->set_primary_key(qw/id1 id2/);
__PACKAGE__->belongs_to('parent', 'TwoKeyTreeLike',
                          { 'foreign.id1' => 'self.parent1', 'foreign.id2' => 'self.parent2'});

1;
