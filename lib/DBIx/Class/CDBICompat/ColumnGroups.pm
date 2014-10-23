package DBIx::Class::CDBICompat::ColumnGroups;

use strict;
use warnings;
use NEXT;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('_column_groups' => { });

sub columns {
  my $proto = shift;
  my $class = ref $proto || $proto;
  my $group = shift || "All";
  $class->_add_column_group($group => @_) if @_;
  return $class->all_columns    if $group eq "All";
  return $class->primary_column if $group eq "Primary";
  return keys %{$class->_column_groups->{$group}};
}

sub _add_column_group {
  my ($class, $group, @cols) = @_;
  $class->_register_column_group($group => @cols);
  $class->add_columns(@cols);
}

sub _register_column_group {
  my ($class, $group, @cols) = @_;

  my $groups = { %{$class->_column_groups} };

  if ($group eq 'Primary') {
    $class->set_primary_key(@cols);
    $groups->{'Essential'}{$_} ||= {} for @cols;
  }

  if ($group eq 'All') {
    unless (exists $class->_column_groups->{'Primary'}) {
      $groups->{'Primary'}{$cols[0]} = {};
      $class->set_primary_key($cols[0]);
    }
    unless (exists $class->_column_groups->{'Essential'}) {
      #$class->_register_column_group('Essential' => $cols[0]);
      $groups->{'Essential'}{$cols[0]} = {};
      #$groups->{'Essential'}{$_} ||= {} for keys %{ $class->_primaries || {} };
    }
  }

  $groups->{$group}{$_} ||= {} for @cols;
  #if ($group eq 'Essential') {
  #  $groups->{$group}{$_} ||= {} for keys %{ $class->_primaries || {} };
  #}

  $class->_column_groups($groups);
}

sub all_columns { return keys %{$_[0]->_columns}; }

sub primary_column {
  my ($class) = @_;
  my @pri = keys %{$class->_primaries};
  return wantarray ? @pri : $pri[0];
}

sub find_column {
  my ($class, $col) = @_;
  return $col if $class->_columns->{$col};
}

sub __grouper {
  my ($class) = @_;
  return bless({ class => $class}, 'DBIx::Class::CDBICompat::ColumnGroups::GrouperShim');
}

sub _find_columns {
  my ($class, @col) = @_;
  return map { $class->find_column($_) } @col;
}

package DBIx::Class::CDBICompat::ColumnGroups::GrouperShim;

sub groups_for {
  my ($self, @cols) = @_;
  my %groups;
  foreach my $col (@cols) {
    foreach my $group (keys %{$self->{class}->_column_groups}) {
      $groups{$group} = 1 if $self->{class}->_column_groups->{$group}->{$col};
    }
  }
  return keys %groups;
}
    

1;
