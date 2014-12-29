package Bread::Board::LazyLoader;

use Moose;

# ABSTRACT: lazy loader for Bread::Board containers

=head1 SYNOPSIS

    package MyApp::IOC;
    use strict;
    use warnings;

    use Path::Class qw(dir);
    use Bread::Board::LazyLoader;

    # loads all *.ioc files under .../MyApp/IOC/
    # from each .../MyApp/IOC/<REL_PATH>.ioc file
    # a <REL_PATH> subcontainer is created
    # from .../MyApp/IOC/Root.ioc a root container is created
    #
    # examples
    # file .../MyApp/IOC/Root.ioc defines the root container
    # file .../MyApp/IOC/Database.ioc defines the Database subcontainer 
    # file .../MyApp/IOC/WebServices/Extranet.ioc defines the WebServices/Extranet subcontainer

    sub loader {  
        my $dir = __FILE__;
        $dir =~ s/\.pm$//;

        my $loader = Bread::Board::LazyLoader->new;

        dir($dir)->traverse(sub {
            my ($f, $cont, $rel) = @_;

            return $cont->( [ $rel ? @$rel : (), $f->basename ] ) if -d $f;
            my ($name) = -f $f && $f->basename =~ /(.*)\.bb$/
                or return;

            $loader->add_file( $f,
                $name eq 'Root' && @$rel == 1
                ? ()
                : join( '/', ( splice @$rel, 1, ), $name ) );
        });
        return $loader->build;
    }

    sub root {
        my $this = shift;
        return $this->loader(@_)->build;
    }

=head1 DESCRIPTION

Imagine we have a large L<Bread::Board> root container (with nested subcontainers). 
This container is used among scripts, psgi application files, ...
Each place of usage uses only part of the tree (usually it resolves one service only).

You can have the root container defined in a single file, but such extensive file can be hard to maintain.
Also the complete structure is loaded in every place of usage, 
which can be quite consuming (if some part of your tree is an L<OX> aplication for example). 

Bread::Board::LazyLoader enables you to define your containers (subcontainers) 
in independent files which are loaded lazily when the container is asked for
(C<< $parent->get_subcontainer >>).

Having our IOC root defined like

    my $dir     = '...';
    my $builder = Bread::Board::LazyLoader->new;
    $builder->add_file("$dir/Root.ioc");
    $builder->add_file( "$dir/Database.ioc"    => 'Database' );
    $builder->add_file( "$dir/WebServices.ioc" => 'WebServices' );
    $builder->add_file( "$dir/Integration.ioc" => 'Integration' );
    $builder->build;

we can have Integration/manager service resolved in a script 
while the time consuming WebServices container (OX application)
is not loaded.

=head2 Definition file

Definition file for a container is a perl file returning 
(the last expression of file is) an anonymous subroutine.

The subroutine is called with the name of the container 
and returns the container (L<Bread::Board::Container> instance)
with the same name.

The file may look like:

    use strict;
    use Bread::Board;

    sub {
        my $name = shift;
        container $name => as {
            ...
        }
    };

Of course we can create the instance of our own container

    use strict;
    use Bread::Board;
    
    use MyApp::Extranet; # our big OX based application

    sub {
        my $name = shift;
        MyApp::Extranet->new(
            name => $name
        );
    };

A single container can be built from more definition files,
the subroutine from second file is then called with the container created
by the first subroutine call: C<< my $container = $sub3->($sub2->($sub1->($name))); >>

The construction C<< container $name => as { ... }; >> from L<Bread::Board>
can be used even when C<< $name >> is a container, not a name.

The definition files (the subroutines) are applied 
even if the container was already created inside parent container.

=head1 METHODS

=over 4

=item C<new(%args)>

Constructor with optional arguments

=over 4

=item name

The name of container built, default is C<Root>.

=item cache_codes

Whether the subroutines returned from builder files are remembered.
Default is 1.

=back

=item C<add_file(FILE, [ UNDER ])>

Adds a file building the current or nested container. 
Optional second parameter is is a path to nested container.  

=item C<add_code(CODEREF, [ UNDER ])>

Similar to add_file, but the anonymous subroutine is passed directly
not loaded from a file.

=item C<add_tree(DIR, EXTENSION, [ UNDER ])>

Adds all files under directory with given extension (without leading .) to
builder.

Having files C<./IOC/Root.ioc>, C<./IOC/Database.ioc>, C<./IOC/WebServices/REST.ioc>
then C<< $loader->add('./IOC', 'ioc') >> adds first file into current container 
(if its name is Root), the other files cause subcontainers to be created.


=item C<build>

Builds the current container. Each call of <build> returns a new container.

=back

=cut

use Moose::Util ();
use Bread::Board;
use Bread::Board::LazyLoader::Container;
use Carp qw(croak);

has name => ( is => 'ro', required => 1, default => 'Root' );

# remember the subs returned from builder files
has cache_codes => ( is => 'ro', default => 1 );

# builders (files and codes) for current container
has builders => (
    is      => 'ro',
    isa     => 'ArrayRef[ArrayRef]',
    default => sub { [] },
);

# builders for sub_containers
has sub_builders => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { {} },
);

has container_role => (
    is      => 'ro',
    default => __PACKAGE__ . '::Role::Container',
);

has container_class => (
    is      => 'ro',
    default => __PACKAGE__ . '::Container',
);

sub new_sub_builder {
    my $this = shift;
    return ref($this)->new(@_);
}

sub new_container {
    my $this = shift;
    return $this->container_class->new(@_);
}

sub _add {
    my ( $this, $builder, $where ) = @_;

    my ( $sub_name, $rest ) = defined $where ? $where =~ m{([^/]+)(.*)} : ()
        or return push @{ $this->builders }, $builder;

    my $sub_builder = $this->sub_builders->{$sub_name}
        ||= $this->new_sub_builder( name => $sub_name);
    $sub_builder->_add( $builder, $rest );
}

sub add_file {
    my ( $this, $file, $where ) = @_;

    $this->_add( [ file => $file ], $where );
}

sub add_code {
    my ( $this, $code, $where ) = @_;

    ref($code) eq 'CODE'
        or croak "\$builder->add_code( CODEREF, [ \$under ])\n";
    $this->_add( [ code => $code ], $where );
}

sub add_tree {
    my ( $this, $dir, $extension, $where ) = @_;

    $this->_add_tree( $dir, $extension,
        defined $where && $where =~ m{[^/]} ? $where : '' );
}

sub _add_tree {
    my ( $this, $dir, $extension, $where ) = @_;

    opendir( my $dh, $dir ) or die "can't opendir $dir: $!";
    for my $basename ( grep { /[^\.]/ } readdir($dh) ) {
        my $path = "$dir/$basename";
        if ( -f $path ) {
            if ( my ($name) = $basename =~ /(.*)\Q.$extension\E$/ ) {
                $this->add_file( $path,
                    !$where && $name eq $this->name
                    ? ()
                    : "$where/$name"  );
            }
        }
        elsif ( -d $path ) {
            $this->_add_tree( $path, $extension, "$where/$basename");
        }
    }
    closedir $dh;
}

# ->build($container) ...
# ->build($name) ...
# ->build() ...
sub build {
    my ( $this, $in ) = @_;

    # applying the builders
    my $cc = $in || $this->name;
    for my $builder ( @{$this->builders} ) {
        my ( $type, $value ) = @$builder;

        my $method = '_apply_' . $type;
        $cc = $this->$method( $cc, $value );
        blessed($cc) && $cc->isa('Bread::Board::Container')
            or croak $this->_error_msg("Builder did not return a container");
        $cc->name eq $this->name
            or croak $this->_error_msg("Builder returns container with different name '". $cc->name. "'");
    }

    # there may be no builders caused by "inner" container on the way
    my $c
        = blessed($cc)
        ? $cc
        : $this->new_container( name => $cc );

    Moose::Util::ensure_all_roles( $c, $this->container_role );
    for my $name ( keys %{$this->sub_builders} ){
	my $old = $c->sub_builders->{$name};
	my $new = $this->sub_builders->{$name};
	$c->sub_builders->{$name} = $old? $old->_merge( $new): $new;
    }
    return $c;
}

sub _merge {
    my ( $this, $new ) = @_;

    my $builder = $this->new_sub_builder( name => $this->name );
    $builder->add_code(
        sub {
 	    return $new->build( $this->build( @_  ) );
        }
    );
    return $builder;
}

sub _error_msg {
    my ( $this, $msg ) = @_;

    return "$msg, while building '" . $this->name . "' container\n";
}

# loads file in a sandbox package
sub get_code_from {
    my ( $this, $file ) = @_;

    my $package = $file;
    $package =~ s/([^A-Za-z0-9_])/sprintf("_%2x", unpack("C", $1))/eg;

    my $code = eval sprintf <<'END_EVAL', __PACKAGE__, $package;
package %s::Sandbox::%s;
{
    my $code = do $file;
    if ( !$code && ( my $error = $@ || $! )) { die $error; }
    $code;
}
END_EVAL

    croak $this->_error_msg("Evaluation of '$file' failed with: $@") if $@;
    ref($code) eq 'CODE'
        or croak $this->_error_msg("File '$file' did not return a coderef");
    return $code;
}

my %code_from;
around get_code_from => sub {
    my ( $orig, $this, $file ) = @_;

    return $this->cache_codes
        ? $code_from{$file} ||= $this->$orig($file)
        : $this->$orig($file);
};

sub _apply_file {
    my ( $this, $c, $file ) = @_;

    -f $file or croak $this->_error_msg("File '$file' does not exist");
    return $this->get_code_from($file)->($c);;
}

sub _apply_code {
    my ( $this, $c, $code ) = @_;

    return $code->($c);
}

__PACKAGE__->meta->make_immutable;
1;

# vim: expandtab:shiftwidth=4:tabstop=4:softtabstop=0:textwidth=78: 
