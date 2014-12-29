package Bread::Board::LazyLoader::Site;

use strict;
use warnings;

# ABSTRACT: loads tree of IOC files alongside pm file

=head1 SYNOPSIS

In module dir we have files, each one containing the definition of 
one Bread::Board::Container

    lib/My/Site/Supp/Database.ioc
    lib/My/Site/Root.ioc
    lib/My/Site/Config.ioc
    lib/My/Site/Database.ioc
    lib/My/Site/Planner.ioc
    lib/My/Site/AQ.ioc
       
the "site" module C<lib/My/Site.pm> is defined like

    package My::Site;
    use strict;
    use warnings;

    use Bread::Board::LazyLoader::Site;

    1;

in the script 

    use My::Site;

    my $root = My::Site->root;
    my $db_container = $root->fetch('Database');
    my $dbh = $root->resolve(service => 'Database/dbh');


=head1 DESCRIPTION

Bread::Board::LazyLoader::Site is an abstraction on top of Bread::Board::LazyLoader.
When used import into caller two class methods 

=over 4

=item C<root>

Returns Bread::Board container with the structure of sub containers loaded
lazily from a directory tree.

=back

=head2 import parameters

   use Bread::Board::LazyLoader::Site %params;

=over 4

=item dir  

Directory searched for container files. By default it is the directory with the same name
as module file without suffix. 

=item suffix

Suffix of container files. By default C<ioc>.

=item base

Another site module (must have C<loader> method). All container files are loaded on top of the base file containers.

=back

=cut

# imports methods loader and root into caller's namespace
use Bread::Board::LazyLoader;
use Carp qw(confess croak);
use Class::Load;

# import imports into caller namespace 2 class methods
# loader - returns Bread::Board::LazyLoader instance
# root   - returns the appropriate root

sub import {
    my $this = shift;
    my ( $caller_package, $caller_filename ) = caller;

    my $to_import = $this->_build( $caller_package, $caller_filename, @_ );
    for my $method ( keys %$to_import ) {
        no strict 'refs';
        *{ join '::', $caller_package, $method } = $to_import->{$method};
    }
}

sub _throw {
    croak join '', __PACKAGE__, '->import: ', @_, "\n";
}

sub _build {
    my ( $this, $caller_package, $caller_filename, %args ) = @_;

    # base is a package which loader we use and add to
    my $base = delete $args{base};
    if ($base) {
        Class::Load::load_class($base);
        $base->can('loader')
          or _throw "base package '$base' has no method loader";
    }

    # load all ioc files "belonging" to perl file
    # given $dir/Manggis/Core.pm
    # loads all *.ioc files under $dir/Manggis/Core/
    my $dir = delete $args{dir}
      || do {

        # we add files according to *.pm
        $caller_filename =~ /^(.*)\.pm$/;
        $1;
      };

    -d $dir or _throw "There is no directory $dir to look for ioc files";

    my $suffix = delete $args{suffix} || 'ioc';

    !%args
      or _throw sprintf
      "Unrecognized or ambiguous parameters (%s)", join( ', ', keys %args );

    return {
        loader => sub {
            my $loader = Bread::Board::LazyLoader->new;
            $loader->add_tree( $dir, $suffix );
            return $loader;
        },
        root => sub {
            my $this = shift;
            return $this->loader->build( $base ? $base->root(@_) : @_ );
        },
    };
}

1;

# vim: expandtab:shiftwidth=4:tabstop=4:softtabstop=0:textwidth=78:
