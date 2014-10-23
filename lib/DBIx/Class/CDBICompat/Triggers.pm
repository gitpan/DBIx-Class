package DBIx::Class::CDBICompat::Triggers;

use strict;
use warnings;
use Class::Trigger;

sub insert {
  my $self = shift;
  $self->call_trigger('before_create');
  $self->NEXT::ACTUAL::insert(@_);
  $self->call_trigger('after_create');
  return $self;
}

sub update {
  my $self = shift;
  $self->call_trigger('before_update');
  my @to_update = keys %{$self->{_dirty_columns} || {}};
  return -1 unless @to_update;
  $self->NEXT::ACTUAL::update(@_);
  $self->call_trigger('after_update');
  return $self;
}

sub delete {
  my $self = shift;
  $self->call_trigger('before_delete') if ref $self;
  $self->NEXT::ACTUAL::delete(@_);
  $self->call_trigger('after_delete') if ref $self;
  return $self;
}

sub store_column {
  my ($self, $column, $value, @rest) = @_;
  my $vals = { $column => $value };
  $self->call_trigger("before_set_${column}", $value, $vals);
  return $self->NEXT::ACTUAL::store_column($column, $vals->{$column});
}

1;
