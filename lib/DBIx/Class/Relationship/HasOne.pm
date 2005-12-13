package DBIx::Class::Relationship::HasOne;

use strict;
use warnings;

sub might_have {
  shift->_has_one('LEFT' => @_);
}

sub has_one {
  shift->_has_one(undef => @_);
}

sub _has_one {
  my ($class, $join_type, $rel, $f_class, $cond, $attrs) = @_;
  eval "require $f_class";
  if ($@) {
    $class->throw($@) unless $@ =~ /Can't locate/;
  }

  unless (ref $cond) {
    my ($pri, $too_many) = $class->primary_columns;
    $class->throw( "might_have/has_one can only infer join for a single primary key; ${class} has more" )
      if $too_many;
    my $f_key;
    my $f_class_loaded = eval { $f_class->columns };
    my $guess;
    if (defined $cond && length $cond) {
      $f_key = $cond;
      $guess = "caller specified foreign key '$f_key'";
    } elsif ($f_class_loaded && $f_class->has_column($rel)) {
      $f_key = $rel;
      $guess = "using given relationship '$rel' for foreign key";
    } else {
      ($f_key, $too_many) = $f_class->primary_columns;
      $class->throw( "might_have/has_one can only infer join for a single primary key; ${f_class} has more" )
        if $too_many;
      $guess = "using primary key of foreign class for foreign key";
    }
    $class->throw("No such column ${f_key} on foreign class ${f_class} ($guess)")
      if $f_class_loaded && !$f_class->has_column($f_key);
    $cond = { "foreign.${f_key}" => "self.${pri}" };
  }
  $class->add_relationship($rel, $f_class,
   $cond,
   { accessor => 'single',
     cascade_update => 1, cascade_delete => 1,
     ($join_type ? ('join_type' => $join_type) : ()),
     %{$attrs || {}} });
  1;
}

1;
