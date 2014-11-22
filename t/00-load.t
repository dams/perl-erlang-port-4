#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Erlang::Port4' );
}

diag( "Testing Erlang::Port4 $Erlang::Port4::VERSION, Perl $], $^X" );
