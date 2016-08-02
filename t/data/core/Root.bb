use common::sense;

use Bread::Board;
use Test::More;
use t::Utils qw(mark_file_loaded);

mark_file_loaded(__FILE__);

sub {
    my ( $name, $next ) = @_;

    is( __PACKAGE__, 'Bread::Board::LazyLoader::Sandbox::t_2fdata_2fcore_2fRoot_2ebb', 'Root file is evaled in special package');

    container $name => as {	
	service file => __FILE__;
    };
};
