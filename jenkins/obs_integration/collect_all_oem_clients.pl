#! /usr/bin/perl -w
#
# (c) 2014 jw@owncloud.com - GPLv2 or ask.
#
# 2014-09-04, unfinsihed draft. 
# 2014-10-24, jw: Finished prettyprint_urls(). Already very useful for statistics.
# 
# This should eventually allow jenkins to collect the build results on a polling basis.
# Currently we only create a shell script for a human to run on s2.
#
# Caution: This script expects, that eventually all build jobs finish.
# It will not print pack_client_oem instructions, while builds keep re-starting
# Force printing of instructions with -k option.

use Getopt::Std;
use Data::Dumper;

my %blacklist = map { $_ => 1 } qw( oem:SURFdrive oem:beta );
			# beta is a container. Only subprojects are interesting, if any.
			# oem:SURFdrive is only for windows and mac. For linux we have surfdrivelinux.

my $osc_cmd             = 'osc -Ahttps://s2.owncloud.com';
my $out_dir 		= '/tmp';
my $scriptfile 		= "$out_dir/pack_oem.sh";
my $container_project   = 'oem';	 #'home:jw:oem';
my $verbose		= 1;
use vars qw($opt_p $opt_v $opt_f $opt_r $opt_h $opt_o $opt_k $opt_t);
getopts('hp:f:r:o:ktv');

$container_project = $opt_p if defined $opt_p;
$container_project =~ s{:$}{};

$out_dir = $opt_o if defined $opt_o;

$client_filter		= $opt_f || "";
my @client_filter	= split(/[,\|\s]/, $client_filter);

sub help() {
  print<<ENDHELP

  collect_all_oem_clients - harvest from the build service, what setup_all_oem_clients started there.

  Options:
  -h                 help, displays help text
  -p "project"	     obs project to pull from. Default: '$container_project'
  -r "relid"	     specify a build release identifier to look for. Default: grab any.
  -f "clients,..."   A filter to select only a few matching brandings. Default all.
  -o "outdir"        Directory where to write collected binaries to. Default: "$out_dir";
  -k                 Keep going. Default: Abort if we have failed or still building binaries.
  -t                 Trigger rebuilds for all failed binaries.

ENDHELP
;
  exit 1;
}
help() if $opt_h;

print "project=$container_project, osc='$osc_cmd', client_filter='$client_filter' out_dir='$out_dir'\n";

my @oem_projects;

if (@client_filter)
  {
    @oem_projects = map { "$container_project:$_" } @client_filter;
  }
else
  {
    open(my $ifd, "$osc_cmd ls|") or die "cannot list projects: $!\n";
    my $info = join("",<$ifd>);
    close $ifd;
    my @all_prj = split(/\s+/, $info);
    for my $p (@all_prj)
      {
        next if $blacklist{$p};
        push @oem_projects, $p if $p =~ m{^\Q$container_project\E:};
      }
  }

# die Dumper \@oem_projects;

my %failed;
my %building;
my %succeeded;
for my $prj (@oem_projects)
  {
    my $pkg = $prj;
    $pkg =~ s{^\Q$container_project\E:}{};
    $pkg .= '-client';

    print STDERR ".";

    # check for failed builds
    open(my $ifd, "$osc_cmd r -v $prj $pkg|") or die "cannot get build results for $prj $pkg: $!\n";
    my $info = join("",<$ifd>);
    close $ifd;

    ## handle continuation lines....
    my @results;
    for my $r (split(/\n/, $info))
      {
        if ($r =~ m{^\s+(.*)})
	  {
	    $results[-1] .= ', ' . $r;
	  }
	else
	  {
            push @results, $r;
	  }
      }

    ## now we have proper records.
    for my $r (@results)
      {
	my ($target,$arch,$status) = ($1,$2,$3) if $r =~ m{^(\S+)\s+(\S+)\s+(.*)$};
	die Dumper $r unless defined $status;
	if ($status =~ m{(failed|broken|unresolvable)})
	  {
	    $failed{"$prj/$target/$arch"} = $status;
	  }
	elsif ($status =~ m{(scheduled|building|finished|signing)})
	  {
	    $building{"$prj/$target/$arch"} = $status;
	  }
	else
	  {
	    $succeeded{"$prj/$target/$arch"} = $status;
	  }
      }
  }
print STDERR "\n";

printf "building: %d, failed: %d, succeeded: %d\n", scalar keys %building, scalar keys %failed, scalar keys %succeeded if $verbose;
if (%building)
  {
    my @k = keys %building;
    printf("%d binaries currently building.\n $k[0] $building{$k[0]}\n", scalar keys %building);
    prettyprint_urls(\%failed);
    print "\n  Wait a bit?\n";

    exit(1) unless $opt_k;
  }

if ($opt_t)
  {
    ## trigger all that failed.
    my %prj_meta_visited;

    for my $f (keys %failed)
      {
	my ($prj,$target,$arch) = split /\//, $f;
	my $pkg = $prj;
	$pkg =~ s{^\Q$container_project\E:}{};
	$pkg .= '-client';

	unless ($prj_meta_visited{$prj})
	  {
	    ## if we have a status of broken: interconnect error: api.opensuse.org: no such host
	    ## then a simple rebuildpac does not help. We have to touch the meta data of the project
	    ## to trigger the rebuild.
	    $prj_meta_visited{$prj}++;
	    touch_meta_prj($osc_cmd, $prj);
	  }
	my $cmd = "$osc_cmd rebuildpac $prj $pkg $target $arch";
	print "retrying reason was: '$failed{$f}'\n+ $cmd\n";
	system($cmd);
      }
  }

if (%failed)
  {
    if ($opt_t)
      {
        printf("%d binaries retriggered\n", scalar keys %failed);
      }
    else
      {
        printf("%d binaries failed. Try with -t to trigger rebuilds or investigate?\n", scalar keys %failed);
        prettyprint_urls(\%failed) unless %building;
      }
    exit(1) unless $opt_k;
  }

printf("%d binaries succeeded.\n", scalar keys %succeeded);

# die Dumper \%succeeded;

my $script = qq{#!/bin/sh
# generated by $0, } . scalar(localtime) . q{
#
# Run this as root@s2.owncloud.com
#
# If some commands are commented out here, then they had build failures 
# or were still building when this script was generated.
#
};

my $caution = 0;
for my $oem (@oem_projects)
  {
    my $b_or_f = has_building_or_failed($oem);
    my $version = find_consistent_version($oem);

    $oem =~ s{^.*:}{};
    $script .= "\n# " . mk_url($oem) . "\n# " if $b_or_f;
    $script .= "bin/pack_client_oem $oem $version\n";
    $caution += $b_or_f;
  }

# generate a shell script with all pack_client_oem calls
open OUT, ">", $scriptfile;
print OUT $script;
close OUT or die "could not write $scriptfile: $!\n";

print "CAUTION: $caution oem builds did not succeed 100%\n - commented out, please review.\n" if $caution;
print "$scriptfile written.\n";

exit 0;
###########################################################

sub mk_url
{
  my ($name) = @_;
  return "https://s2.owncloud.com/package/show/oem:$name/$name-client";
}

sub find_consistent_version
{
  my ($oemprj) = @_;

  my $pkg = "$1-client" if $oemprj =~ m{:(.*)};
  my $cmd = "$osc_cmd ls -b $oemprj $pkg";
  my %vers;
  open(my $ifd, "$cmd|") or die "cannot list binaries $cmd: $!\n";
    # xUbuntu_12.04/x86_64
    #  _statistics
    #  libtubcloudsync-dev_1.6.3-0.jw20140905_amd64.deb
    #  libtubcloudsync0_1.6.3-0.jw20140905_amd64.deb
    #  tubcloud-client-doc_1.6.3-0.jw20140905_all.deb
    #  tubcloud-client-l10n_1.6.3-0.jw20140905_all.deb
    #  tubcloud-client_1.6.3-0.jw20140905.diff.gz
    #  tubcloud-client_1.6.3-0.jw20140905.dsc
    #  tubcloud-client_1.6.3-0.jw20140905_amd64.deb
    #  tubcloud-client_1.6.3.orig.tar.gz
    # openSUSE_13.1/i586
    #  _statistics
    #  libtubcloudsync-devel-1.6.3-2.1.i586.rpm
    #  libtubcloudsync0-1.6.3-2.1.i586.rpm
    #  rpmlint.log
    #  tubcloud-client-1.6.3-2.1.i586.rpm
    #  tubcloud-client-1.6.3-2.1.src.rpm
    #  tubcloud-client-appdata.xml
    #  tubcloud-client-doc-1.6.3-2.1.i586.rpm
    #  tubcloud-client-l10n-1.6.3-2.1.i586.rpm
  while (defined(my $line = <$ifd>))
    {
      chomp $line;
      if ($line =~ m{^\s*\Q$pkg\E[-_](\d[\d\.]+\d)})
        {
          $vers{$1}++;
        }
    }
  close $ifd;
  my @vers = keys %vers;
  die "$oemprj $pkg: built differing versions: @vers\n" if scalar @vers > 1;
  return $vers[0];
}

sub has_building_or_failed
{
  my ($oemprj) = @_;
  for my $k (keys %building, keys %failed)
    {
      return 1 if $k =~ m{^\Q$oemprj\E/};
    }
  return 0;
}

sub touch_meta_prj
{
  my ($osc_cmd, $prj) = @_;
  open(my $ifd, "$osc_cmd meta prj '$prj'|") or die "cannot fetch meta prj $prj: $!\n";
  my $meta_prj_template = join("",<$ifd>);
  close($ifd);
  $meta_prj_template .= ' ';	# make an insignificant change
  open(my $ofd, "|$osc_cmd meta prj '$prj' -F - >/dev/null") or die "cannot touch meta: $!\n";
  print $ofd $meta_prj_template;
  close($ofd) or die "touching prj meta failed: $!\n";
  print "Project '$prj' meta touched.\n";
}

sub prettyprint_urls
{
  my ($f_all, $prefix) = @_;
  # 'oem:surfdrivelinux/xUbuntu_12.04/x86_64' => 'unresolvable: nothing provides qtkeychain-dev,       nothing provides libqtkeychain0 >= 0.3',

  my %names;

  for my $f (keys %$f_all)
    {
      if ($f =~ m{^([^/]+)/(.*)$})
        {
	  my ($name,$plat) = ($1,$2);
	  push @{$names{$name}{target}}, $plat;
	  for my $e (split(/,\s*/, $f_all->{$f}))
	    {
	      if ($e =~ s{^(unresolvable: )?nothing provides }{})
	        {
	          $names{$name}{depends}{$e}++;
		}
	      else
	        {
	          $names{$name}{err}{$f_all->{$f}}++;
		}
	    }
	}
    }

  for my $name (keys %names)
    {
      my $err = join(',', keys(%{$names{$name}{err}}));
      my $dep = join(',', keys(%{$names{$name}{depends}}));
      my $n = scalar @{$names{$name}{target}};
      print mk_url($name) . " (${n}x): ";
      print "$err; " if $err;
      print "dependencies: $dep" if $dep;
      print "\n";
    }
}
