package # hide from PAUSE
    DBIx::Class::Relationship::CascadeActions;

sub delete {
  my ($self, @rest) = @_;
  return $self->next::method(@rest) unless ref $self;
    # I'm just ignoring this for class deletes because hell, the db should
    # be handling this anyway. Assuming we have joins we probably actually
    # *could* do them, but I'd rather not.

  my $ret = $self->next::method(@rest);

  my $source = $self->result_source;
  my %rels = map { $_ => $source->relationship_info($_) } $source->relationships;
  my @cascade = grep { $rels{$_}{attrs}{cascade_delete} } keys %rels;
  foreach my $rel (@cascade) {
    $self->search_related($rel)->delete;
  }
  return $ret;
}

sub update {
  my ($self, @rest) = @_;
  return $self->next::method(@rest) unless ref $self;
    # Because update cascades on a class *really* don't make sense!

  my $ret = $self->next::method(@rest);

  my $source = $self->result_source;
  my %rels = map { $_ => $source->relationship_info($_) } $source->relationships;
  my @cascade = grep { $rels{$_}{attrs}{cascade_update} } keys %rels;
  foreach my $rel (@cascade) {
    $_->update for $self->$rel;
  }
  return $ret;
}

1;
