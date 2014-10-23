package DBIx::Class::ResultSetManager;
use strict;
use base 'DBIx::Class';
use Class::Inspector;

__PACKAGE__->mk_classdata($_) for qw/ base_resultset_class table_resultset_class_suffix /;
__PACKAGE__->base_resultset_class('DBIx::Class::ResultSet');
__PACKAGE__->table_resultset_class_suffix('::_resultset');

sub table {
    my ($self,@rest) = @_;
    my $ret = $self->next::method(@rest);
    if (@rest) {
        $self->_register_attributes;
        $self->_register_resultset_class;        
    }
    return $ret;
}

sub load_resultset_components {
    my ($self,@comp) = @_;
    my $resultset_class = $self->_setup_resultset_class;
    $resultset_class->load_components(@comp);
}

sub _register_attributes {
    my $self = shift;
    return unless $self->can('_attr_cache');

    my $cache = $self->_attr_cache;
    foreach my $meth (@{Class::Inspector->methods($self) || []}) {
        my $attrs = $cache->{$self->can($meth)};
        next unless $attrs;
        if ($attrs->[0] eq 'ResultSet') {
            no strict 'refs';
            my $resultset_class = $self->_setup_resultset_class;
            *{"$resultset_class\::$meth"} = $self->can($meth);
            undef *{"$self\::$meth"};
        }
    }
}

sub _setup_resultset_class {
    my $self = shift;
    my $resultset_class = $self . $self->table_resultset_class_suffix;
    no strict 'refs';
    unless (@{"$resultset_class\::ISA"}) {
        @{"$resultset_class\::ISA"} = ($self->base_resultset_class);
    }
    return $resultset_class;
}

sub _register_resultset_class {
    my $self = shift;
    my $resultset_class = $self . $self->table_resultset_class_suffix;
    no strict 'refs';
    if (@{"$resultset_class\::ISA"}) {
        $self->result_source_instance->resultset_class($resultset_class);        
    } else {
        $self->result_source_instance->resultset_class($self->base_resultset_class);        
    }
}

1;

__END__

=head1 NAME 

    DBIx::Class::ResultSetManager - helpful methods for managing resultset classes (EXPERIMENTAL)

=head1 SYNOPSIS

    # in a table class
    __PACKAGE__->load_components(qw/ResultSetManager/);
    __PACKAGE__->load_resultset_components(qw/AlwaysRS/);
    
    # will be removed from the table class and inserted into a table-specific resultset class
    sub foo : ResultSet { ... }

=head1 DESCRIPTION

This package implements two useful features for customizing resultset classes.
C<load_resultset_components> loads components in addition to C<DBIx::Class::ResultSet>
(or whatever you set as C<base_resultset_class>). Any methods tagged with the C<ResultSet>
attribute will be moved into a table-specific resultset class (by default called
C<Class::_resultset>).

=head1 AUTHORS

David Kamholz <dkamholz@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
