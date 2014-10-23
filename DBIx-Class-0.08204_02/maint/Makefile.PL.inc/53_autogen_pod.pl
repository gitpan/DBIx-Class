# leftovers in old checkouts
unlink 'lib/DBIx/Class/Optional/Dependencies.pod'
  if -f 'lib/DBIx/Class/Optional/Dependencies.pod';

my $pod_dir = 'maint/.Generated_Pod';
my $ver = Meta->version;

# cleanup the generated pod dir (again - kill leftovers from old checkouts)
if (-d $pod_dir) {
  require File::Path;
  require File::Glob;
  File::Path::rmtree( File::Glob::bsd_glob("$pod_dir/*"), { verbose => 0 } );
}
else {
  mkdir $pod_dir or die "Unable to create $pod_dir: $!";
}

# generate the OptDeps pod both in the clone-dir and during the makefile distdir
{
  print "Regenerating Optional/Dependencies.pod\n";
  require DBIx::Class::Optional::Dependencies;
  DBIx::Class::Optional::Dependencies->_gen_pod ($ver, $pod_dir);

  postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_optdeps_pod

dbic_clonedir_gen_optdeps_pod :
\t\$(ABSPERLRUN) -Ilib -MDBIx::Class::Optional::Dependencies -e "DBIx::Class::Optional::Dependencies->_gen_pod(qw($ver $pod_dir))"

EOP
}


# generate the inherit pods both in the clone-dir and during the makefile distdir
{
  print "Regenerating project documentation to include inherited methods\n";

  # if the author doesn't have them, don't fail the initial "perl Makefile.pl" step
  do "maint/gen_pod_inherit" or print "\n!!! FAILED: $@\n";

  postamble <<"EOP";

clonedir_generate_files : dbic_clonedir_gen_inherit_pods

dbic_clonedir_gen_inherit_pods :
\t\$(ABSPERLRUN) maint/gen_pod_inherit

EOP
}


# copy the contents of $pod_dir over to lib/
# (yes, overwriting is fine, though nothing should reside there)
{
  postamble <<"EOP";

clonedir_post_generate_files : dbic_clonedir_copy_generated_pod

dbic_clonedir_copy_generated_pod :
\t\$(RM_F) $pod_dir.packlist
\t\$(ABSPERLRUN) -MExtUtils::Install -e 'install([ from_to => {qw($pod_dir lib write $pod_dir.packlist)}, verbose => 0, uninstall_shadows => 0, skip => [] ]);'

EOP
}


# everything that came from $pod_dir, needs to be removed from our lib/
{
  postamble <<"EOP";

clonedir_cleanup_generated_files : dbic_clonedir_cleanup_generated_pod_copies

dbic_clonedir_cleanup_generated_pod_copies :
\t\$(ABSPERLRUN) -MExtUtils::Install -e 'uninstall(qw($pod_dir.packlist))'

EOP
}

# keep the Makefile.PL eval happy
1;
