use strict;
use warnings;

# test of Bread::Board::LazyLoader (Yet another lazy loader)
# which loads Bread::Board containers lazily from files
use t::Utils;
use Test::More;

BEGIN {
    use_ok('Bread::Board::LazyLoader');
}

subtest 'No file, no name' => sub {
    my $loader = Bread::Board::LazyLoader->new;
    my $c      = $loader->build;
    isa_ok( $c, 'Bread::Board::Container',
        'build returns a Bread::Board::Container instance' );
    is( $c->name, 'Root', 'Default container name is Root' );
};

subtest 'No file'  => sub {
    my $loader = Bread::Board::LazyLoader->new(name => 'A');
    my $c = $loader->build;
    isa_ok($c, 'Bread::Board::Container');
    is($c->name, 'A');
};

# only root file
subtest 'Only root file' => sub {
    my $file = create_builder_file(<<'END_FILE');
use Bread::Board;
use t::Utils;

sub {
    my $name = shift;

    test_shared($name);

    container $name => as {
        service s1 => 'ANY';
    };
};
END_FILE

    my $loader = Bread::Board::LazyLoader->new(name => 'A');
    $loader->add_file( $file );

    test_shared(undef);
    my $c = $loader->build;
    isa_ok($c, 'Bread::Board::Container');  
    is (test_shared(), 'A', "The name was passed");
    ok($c->has_service('s1'));
};

# file at level one, without root
subtest 'File at level one, no root file' => sub {
    my $file = create_builder_file(<<'END_FILE');
use Bread::Board;
use t::Utils;

push @{test_shared()},__FILE__;

sub {
    my $name = shift;

    push @{test_shared()}, $name;

    container $name => as {
        service dbh => 'ANY';
    };
};
END_FILE

    test_shared([]);

    my $loader = Bread::Board::LazyLoader->new;
    $loader->add_file( $file, 'Database' );
    my $c = $loader->build;
    isa_ok($c, 'Bread::Board::Container', 'Root container was created even without file');  
    is_deeply( test_shared(), [], "The inner container was not resolved" );
    ok( $c->has_sub_container('Database'),
        "The inner container is detectable"
    );
    is_deeply( [ $c->get_sub_container_list ],
        ["Database"], "The inner container is listed" );
    is_deeply( test_shared(), [], "The inner container still was not resolved" );
    my $database = $c->fetch("Database");
    is_deeply(test_shared(), [$file, 'Database'], "Inner container is resolved now");
};

subtest 'File and code combination' => sub {

    my $root_file = create_builder_file(<<'END_FILE');
use strict;
use Bread::Board;
sub {
    my $name = shift;
    container $name => as {
        container Database => as {
            service s1 => 'S1'; 
            service s3 => 'XY'
        };
    };
};
END_FILE

    my $database_file =  create_builder_file(<<'END_FILE');
use strict;
use Bread::Board;
use t::Utils;

sub {
    my $name = shift;

    test_shared($name);
    container $name => as {
        service s2 => 'S2';
        service s3 => 'AB'
    };
};
END_FILE

    test_shared(undef);

    my $loader = Bread::Board::LazyLoader->new;
    $loader->add_file( $root_file);
    $loader->add_file( $database_file, 'Database' );

    my $c = $loader->build;
    ok( !defined test_shared(), "The inner container was not resolved" );
    my $database = $c->get_sub_container('Database');
    isa_ok( test_shared(), 'Bread::Board::Container', "arg passed is container" );

    is_deeply( { map { ( $_ => 1 ) } $database->get_service_list },
        { s1 => 1, s2 => 1, s3 => 1 } );
    is( $database->resolve( service => 's3' ), 'AB' );
};

done_testing();
# vim: expandtab:shiftwidth=4:tabstop=4:softtabstop=0:textwidth=78: 
