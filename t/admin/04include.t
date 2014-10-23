use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    require DBIx::Class;
    plan skip_all => 'Test needs ' . DBIx::Class::Optional::Dependencies->req_missing_for('admin')
      unless DBIx::Class::Optional::Dependencies->req_ok_for('admin');
}

if(use_ok 'DBIx::Class::Admin') {
  my $admin = DBIx::Class::Admin->new(
      include_dirs => ['t/lib/testinclude'],
      schema_class => 'DBICTestAdminInc',
      config => { DBICTestAdminInc => {} },
      config_stanza => 'DBICTestAdminInc'
  );
  lives_ok { $admin->_build_schema } 'should survive attempt to load module located in include_dirs';
  {
    no warnings 'once';
    ok($DBICTestAdminInc::loaded);
  }
}

done_testing;
