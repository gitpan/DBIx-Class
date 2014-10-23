use strict;
use warnings; 

use Test::More;
use lib qw(t/lib);
use DBICTest;
use DBIC::SqlMakerTest;
use DBIC::DebugObj;

my $schema = DBICTest->init_schema();

plan tests => 6;

ok ( $schema->storage->debug(1), 'debug' );
ok ( defined(
       $schema->storage->debugfh(
         IO::File->new('t/var/sql.log', 'w')
       )
     ),
     'debugfh'
   );

$schema->storage->debugfh->autoflush(1);
my $rs = $schema->resultset('CD')->search({});
$rs->count();

my $log = new IO::File('t/var/sql.log', 'r') or die($!);
my $line = <$log>;
$log->close();
ok($line =~ /^SELECT COUNT/, 'Log success');

$schema->storage->debugfh(undef);
$ENV{'DBIC_TRACE'} = '=t/var/foo.log';
$rs = $schema->resultset('CD')->search({});
$rs->count();
$log = new IO::File('t/var/foo.log', 'r') or die($!);
$line = <$log>;
$log->close();
ok($line =~ /^SELECT COUNT/, 'Log success');
$schema->storage->debugobj->debugfh(undef);
delete($ENV{'DBIC_TRACE'});
open(STDERRCOPY, '>&STDERR');
stat(STDERRCOPY); # nop to get warnings quiet
close(STDERR);
eval {
    $rs = $schema->resultset('CD')->search({});
    $rs->count();
};
ok($@, 'Died on closed FH');
open(STDERR, '>&STDERRCOPY');

# test trace output correctness for bind params
{
    my ($sql, @bind);
    $schema->storage->debugobj(DBIC::DebugObj->new(\$sql, \@bind));
    $schema->storage->debug(1);

    my @cds = $schema->resultset('CD')->search( { artist => 1, cdid => { -between => [ 1, 3 ] }, } );
    is_same_sql_bind (
        $sql, \@bind,
        q/SELECT me.cdid, me.artist, me.title, me.year FROM cd me WHERE ( artist = ? AND (cdid BETWEEN ? AND ?) )/,
        [qw/'1' '1' '3'/],
        'got correct SQL with all bind parameters'
    );
}

1;
