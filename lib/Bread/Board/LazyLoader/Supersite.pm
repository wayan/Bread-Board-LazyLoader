package Bread::Board::LazyLoader::Supersite;

use strict;
use warnings;

# ABSTRACT: loads the proper IOC root with your Bread::Board setup

=head1 SYNOPSIS

    package MY::IOC;
    use strict;
    use warnings;

    use Bread::Board::LazyLoader::SuperSite 
	env_var => 'MY_APP_SITE',
        site => {
            prefix => 'My::Site',
            filter => qr{^[a-z]}
        };

=head1 DESCRIPTION

This module is yet quite experimental.

=cut 

use Class::Load;
use Carp qw(croak);
use Module::Find qw(findsubmod);
use Bread::Board::LazyLoader;

sub _throw {
    croak join '', __PACKAGE__, '->import: ', @_, "\n";
}

sub import {
    my $this = shift;

    # sites is a list of subroutines building the container
    my @sites = _get_sites(@_);
    my %to_import = (

        # site   => sub { $site },
        root => sub {
            my $this = shift;
	    # there may be more than one site
            my ($first, @next) = reverse @sites;
            my $root = $first->(@_);
	    $root = $_->($root) for @next;
	    return $root;
        }
    );

    my $caller_package = caller;
    for my $method ( keys %to_import ) {
        no strict 'refs';
        *{ join '::', $caller_package, $method } = $to_import{$method};
    }
}

sub _load_module_site {
    my ( $module) = @_;

    Class::Load::load_class($module);
    return sub {
	$module->root(@_);
    };
}

sub _load_file_site {
    my ($file) = @_;

    my $loader = Bread::Board::LazyLoader->new;
    $loader->add_file($file);
    return sub {
        $loader->build(@_);
    };
}

# the variable may contain more than one site (either module or file) separated by semicolon
sub _load_var_sites {
    my ($content) = @_;

    my @content = split /;/, $content;
    return
        map { m{/} ? _load_file_site($_) : _load_module_site($_); } @content;
}

sub _get_sites {
    return @_ == 1 && ref $_[0] eq 'ARRAY'

        # array ref
        ? map { _get_sites($_) } @{ shift() }

        # hashref
        : ( @_ == 1 && ref $_[0] eq 'HASH' ) ? _get_sites( %{ shift() } )
        :                                      _get_site(@_);
}

sub _get_site {
    my %args = @_;

    my $env_var = $args{env_var};
    if (my $site = $env_var && $ENV{$env_var}){
        return _load_var_sites( $site );
    }

    if (my $file = delete $args{file}){
        return _load_file_site( $file );
    }

    my $site = delete $args{site}
      or _throw "No site argument supplied";

    if (! ref $site ){
        return _load_module_site($site);
    }
    elsif ( ref $site eq 'HASH' ){
        # we select the only site which fulfills the condition
        my $prefix = $site->{prefix};
        my $filter = $site->{filter};

        $prefix && $filter or _throw "Invalid site argument $site";

        return _load_only_module($prefix, $filter);
    }
    else {
        _throw "Invalid site argument $site";
    }

}

# there must be just one site module $prefix:: conforming the selection
# for example Manggis::Site::<name> module where name starts with lowercase (cz, sk)
sub _load_only_module {
    my ($prefix, $filter) = @_;

    my $select =
        ref $filter eq 'Regexp' ? sub { $_ =~ $filter }
      : ref $filter eq 'CODE'  ? $filter
      :                       _throw "Inapropriate filter $filter";
    my @sites = grep {  
            my ($name) = /^${prefix}::(.*)/;
            local $_ = $name;
            $select->($name);
    } findsubmod($prefix);

    _throw "No site module $prefix\:\:* conforming your selection found\n" if !@sites;
    _throw "More than one site module $prefix\:\:* found (" . join( ', ', @sites ) . ')'
        if @sites > 1;
    return _load_module_site($sites[0]); # "found as the only proper $prefix\:\:* installed module");
}

1;

# vim: expandtab:shiftwidth=4:tabstop=4:softtabstop=0:textwidth=78:
