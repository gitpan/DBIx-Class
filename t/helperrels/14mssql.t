use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBICTest::HelperRels;

require "t/run/14mssql.tl";
run_tests();
