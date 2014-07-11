#! /usr/bin/perl -w
#
# (c) 2014 jw@owncloud.com - GPLv2 or ask.
#
# 
# Iterate over customer-themes github repo, get a list of themes.
# for each theme, 
#  - generate the branding tar ball
#  - run ./setup_oem_client.pl with the dest_prj, (to be created on demand)
#  - run ./genbranding.pl with a build token number.
#
# Poll obs every 5 minutes:
#  For each packge in the obs tree
#   - check all enabled targets for binary packages with the given build token number.
#     if a package has them all ready. Generate the linux package binary tar ball.
#
use Data::Dumper;
use File::Temp ();		# tempdir()
use File::Path;
use POSIX;			# strftime()


my $customer_themes_git = 'git@github.com:owncloud/customer-themes.git';
my $source_git = 'https://github.com/owncloud/mirall.git';
my $osc_cmd = 'osc -Ahttps://s2.owncloud.com';
my $container_project = 'home:jw:oem';
my $build_token = 'jw_'.strftime("%Y%m%d", localtime);
my $genbranding = "env OBS_INTEGRATION_OSC='$osc' ./genbranding.pl -p '$container_project' -r '<CI_CNT>.<B_CNT>.$build_token' -o -f";

my $TMPDIR_TEMPL = '_oem_XXXXX';
our $verbose = 1;
our $no_op = 0;

sub run
{
  my ($cmd) = @_;
  print "+ $cmd\n" if $::verbose;
  return if $::no_op;
  system($cmd) and die "failed to run '$cmd': Error $!\n";
}

sub pull_VERSION_cmake
{
  my ($file) = @_;
  my ($maj,$min,$pat,$so) = (0,0,0,0);

  open(my $fd, "<$file") or die "cannot read $file\n";
  while (defined(my $line = <$fd>))
    {
      chomp $line;
      $maj = $1 if $line =~ m{MIRALL_VERSION_MAJOR\s+(\d+)};
      $min = $1 if $line =~ m{MIRALL_VERSION_MINOR\s+(\d+)};
      $pat = $1 if $line =~ m{MIRALL_VERSION_PATCH\s+(\d+)};
      $so  = $1 if $line =~ m{MIRALL_SOVERSION\s+(\d+)};
    }
  close $fd;
  return "$maj.$min.$pat";
}

my $tmp = File::Temp::tempdir($TMPDIR_TEMPL, DIR => '/tmp/');
$tmp = '/tmp/_oem_KxE90';
my $tmp_t = "$tmp/customer_themes_git";
my $tmp_s = "$tmp/mirall_git";

my $source_tar = shift || 'v1.6.1';
if ($source_tar =~ m{^v[\d\.]+$})
  {
    # CAUTION: keep in sync with
    # https://rotor.owncloud.com/view/mirall/job/mirall-source-master/configure
    my $branch = $source_tar;
    my $version = $1 if $branch =~ m{^v([\d\.]+)$};
#    run("git clone --depth 1 --branch $branch $source_git $tmp_s");
    my $v_git = pull_VERSION_cmake("$tmp_s/VERSION.cmake");
    if ($v_git ne $version)
      {
        warn "oops: asked for git branch v$version, but got version $v_git\n";
	$version = $v_git;
      }
    else
      {
        print "$version == $v_git, yeah!\n";
      }

    my $pkgname = "mirall-${version}";
    $source_tar = "$tmp/$pkgname.tar.bz2";
#    run("cd $tmp_s && git archive HEAD --prefix=$pkgname/ --format tar | bzip2 > $source_tar");
  }

print Dumper $source_tar;
die "need a source_tar or version number matching /^v[\\d\\.]+$/\n" unless defined $source_tar;

if (0)
  {
    run("git clone --depth 1 $customer_themes_git $tmp_t");
  }

opendir(DIR, $tmp_t) or die("cannot opendir my own $tmp: $!");
my @d = grep { ! /^\./ } readdir(DIR);
closedir(DIR);

my @candidates = ();
for my $dir (sort @d)
  {
    next unless -d "$tmp_t/$dir/mirall";
    #  - generate the branding tar ball
    # CAUTION: keep in sync with jenkins jobs customer_themes
    # https://rotor.owncloud.com/view/mirall/job/customer-themes/configure
    chdir($tmp_t);
    run("tar cjf ../$dir.tar.bz2 ./$dir");
    push @candidates, $dir if -f "$tmp_t/$dir/mirall/package.cfg";
  }

print Dumper \@candidates;

sub obs_prj_from_template
{
  my ($osc_cmd, $template_prj, $prj, $title) = @_;
  open(my $ifd, "$osc_cmd meta prj '$template_prj'|") or die "cannot fetch meta prj desktop: $!\n";
  my $meta_prj_template = join(<$ifd>);
  close($ifd);
  die "not impl";
}

sub obs_pkg_from_template
{
  my ($osc_cmd, $template_prj, $template_pkg, $prj, $pkg, $title) = @_;
  die "not impl";
}

obs_prj_from_template('desktop', $osc_cmd, $container_project, "OwnCloud Desktop Client OEM Container project");

for my $branding ('switchdrive')	# @candidates)
  {
    warn("skeleton code follows\n");
    # generate the container projects
    obs_prj_from_template($osc_cmd, 'desktop', "$container_project:$branding", "OwnCloud Desktop Client project $branding");
    obs_pkg_from_template($osc_cmd, 'desktop', 'owncloud-client', '$container_project:$branding' '$branding-client', '$branding Desktop Client');
    run("$genbranding '$source_tar' '$tmp/$branding.tar.bz2'");	# checkout branding-client, update, checkin.
    run("./setup_oem_client.pl '$branding' '$container_project'");
  }
die("unfinished artwork in $tmp");
