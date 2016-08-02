package # hide from PAUSE
  Bread::Board::LazyLoader::Container;

# DEPRECATED - use Bread::Board::LazyLoader qw(load_container)
use Moose;

# ABSTRACT: building subcontainers lazily

extends 'Bread::Board::Container';
with 'Bread::Board::LazyLoader::Role::Container';

__PACKAGE__->meta->make_immutable;
1;

# vim: expandtab:shiftwidth=4:tabstop=4:softtabstop=0:textwidth=78: 
