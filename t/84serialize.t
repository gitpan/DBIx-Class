use strict;
use warnings;  

use Test::More;
use lib qw(t/lib);
use DBICTest;
use Storable qw(dclone freeze thaw);

my $schema = DBICTest->init_schema();

my %stores = (
    dclone_method           => sub { return $schema->dclone($_[0]) },
    dclone_func             => sub { return dclone($_[0]) },
    "freeze/thaw_method"    => sub {
        my $ice = $schema->freeze($_[0]);
        return $schema->thaw($ice);
    },
    "freeze/thaw_func"      => sub {
        thaw(freeze($_[0]));
    },
);

plan tests => (7 * keys %stores);

for my $name (keys %stores) {
    my $store = $stores{$name};

    my $artist = $schema->resultset('Artist')->find(1);
    
    # Test that the procedural versions will work if there's a registered
    # schema as with CDBICompat objects and that the methods work
    # without.
    if( $name =~ /func/ ) {
        $artist->result_source_instance->schema($schema);
        DBICTest::CD->result_source_instance->schema($schema);
    }
    else {
        $artist->result_source_instance->schema(undef);
        DBICTest::CD->result_source_instance->schema(undef);
    }

    my $copy = eval { $store->($artist) };
    is_deeply($copy, $artist, "serialize row object works: $name");

    # Test that an object with a related_resultset can be serialized.
    my @cds = $artist->related_resultset("cds");

    ok $artist->{related_resultsets}, 'has key: related_resultsets';

    $copy = eval { $store->($artist) };
    for my $key (keys %$artist) {
        next if $key eq 'related_resultsets';
        next if $key eq '_inflated_column';
        is_deeply($copy->{$key}, $artist->{$key},
                  qq[serialize with related_resultset "$key"]);
    }
  
    ok eval { $copy->discard_changes; 1 } or diag $@;
    is($copy->id, $artist->id, "IDs still match ");
}
