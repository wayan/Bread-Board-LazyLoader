use strict;
use warnings;

# test of Bread::Board::LazyLoader (Yet another lazy loader)
# which loads Bread::Board containers lazily from files
use Test::More;
use Test::Exception;
use t::Utils;

use Bread::Board::LazyLoader;

subtest 'File does not exist' => sub {
    my $loader = Bread::Board::LazyLoader->new;

    my $file = 'this_file_doesnot_exist.bb';
    lives_ok {
    $loader->add_file($file);
    } "Existence of file is checked in build time";
    
    throws_ok {
        my $c = $loader->build;
    } qr{^\QFile '$file' does not exist, while building 'Root' container};
};

subtest 'File does not return coderef' => sub {
    my $file = create_builder_file(<<'END_FILE');
use strict;

1;
END_FILE
    my $loader = Bread::Board::LazyLoader->new(name => 'Database');
    $loader->add_file($file);
    throws_ok {
        my $c = $loader->build;
    } qr{^\QFile '$file' did not return a coderef, while building 'Database' container};
};

subtest 'File returns a coderef, which doesnot return a container' => sub {
    my $file = create_builder_file(<<'END_FILE');
use strict;
{
    package OtherObj;
    use Moose;
}

sub {
    return OtherObj->new;
};

END_FILE
    my $loader = Bread::Board::LazyLoader->new;
    $loader->add_file($file);
    throws_ok {
        my $c = $loader->build;
    } qr{^\QBuilder did not return a container, while building 'Root' container};
};

subtest 'File returns a coderef, which returns a container with different name' => sub {
    my $file = create_builder_file(<<'END_FILE');
use strict;
use Bread::Board;
sub {
    container C => as {
    };
}
END_FILE
    my $loader = Bread::Board::LazyLoader->new(name => 'WebServices');
    $loader->add_file($file);
    throws_ok {
        my $c = $loader->build;
    } qr{^\QBuilder returns container with different name 'C', while building 'WebServices' container};
};

done_testing();
# vim: expandtab:shiftwidth=4:tabstop=4:softtabstop=0:textwidth=78: 
