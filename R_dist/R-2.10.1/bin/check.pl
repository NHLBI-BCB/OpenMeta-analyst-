#-*- perl -*-

# Copyright (C) 2000-2009 R Development Core Team
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the GNU
# General Public License for more details.
#
# A copy of the GNU General Public License is available at
# http://www.r-project.org/Licenses/

# Send any bug reports to r-bugs@r-project.org

use Cwd;
use File::Basename;
use File::Copy;
use File::Copy::Recursive qw(dircopy);
use File::Find;
use File::Path;
use Getopt::Long;
use IO::File;
use R::Dcf;
use R::Logfile;
use R::Utils;
use R::Vars;
use Text::Wrap;

## Don't buffer output.
$| = 1;

my $revision = ' $Rev: 50471 $ ';
my $version;
my $name;
$revision =~ / ([\d\.]*) /;
$version = $1;
($name = $0) =~ s|.*/||;

### Options
my $opt_clean = 1;
my $opt_examples = 1;
my $opt_tests = 1;
my $opt_latex = 1;
my $opt_use_gct = 0;
my $opt_codoc = 1;
my $opt_install = 1;
my $spec_install = 0;
my $opt_vignettes = 1;
my $opt_use_valgrind = 0;
my $opt_rcfile = "";		# Only set this if $ENV{"HOME"} is set.
$opt_rcfile = &file_path($ENV{"HOME"}, ".R", "check.conf")
    if defined($ENV{"HOME"});
my $opt_subdirs;
my $HAVE_LATEX = 0;
my $HAVE_PDFLATEX = 0;

my $INSTALL_OPTS ="";

my $WINDOWS = ($R::Vars::OSTYPE eq "windows");

R::Vars::error("R_HOME", "R_EXE");

my @known_options = ("help|h", "version|v", "outdir|o:s", "library|l:s",
		     "no-clean", "no-examples", "no-tests", "no-latex",
		     "use-gct" => \$opt_use_gct, "no-codoc",
		     "install=s" => \$opt_install, "no-install",
		     "no-vignettes", "use-valgrind" => \$opt_use_valgrind,
		     "install-args=s" => \$opt_install_args,
		     "rcfile=s" => \$opt_rcfile,
		     "check-subdirs=s" => \$opt_subdirs);
GetOptions(@known_options) or usage();

R_version("R add-on package checker", $version) if $opt_version;
usage() if $opt_help;

## record some of the options used.
my @opts;
push @opts,"--install=fake" if $opt_install eq "fake";
push @opts,"--install=no" if $opt_install eq "no";
push @opts,"--no-install" if $opt_no_install;

$opt_clean = 0 if $opt_no_clean;
$opt_examples = 0 if $opt_no_examples;
$opt_tests = 0 if $opt_no_tests;
$opt_latex = 0 if $opt_no_latex;
$opt_codoc = 0 if $opt_no_codoc;
$opt_install = 0 if $opt_no_install;
$opt_vignettes = 0 if $opt_no_vignettes;

if($opt_install eq "fake") {
    ## If we fake installation, then we cannot *run* any code.
    $opt_examples = $opt_tests = $opt_vignettes = 0;
    $spec_install = 1;
}
$opt_install = 0 if($opt_install eq "no");
$spec_install = 1 if !$opt_install;

my $opt_ff_calls = 1;
## The neverending story ...
## For the time being, allow to turn this off by setting the environment
## variable _R_CHECK_FF_CALLS_ to a Perl 'null' value.
if(defined($ENV{"_R_CHECK_FF_CALLS_"})) {
    $opt_ff_calls = $ENV{"_R_CHECK_FF_CALLS_"};
}

## Use system default unless explicitly specified otherwise.
$ENV{"R_DEFAULT_PACKAGES"} = "";

### Configurable variables
my $R_check_use_install_log =
    &R_getenv("_R_CHECK_USE_INSTALL_LOG_", "TRUE");
my $R_check_subdirs_nocase =
    &R_getenv("_R_CHECK_SUBDIRS_NOCASE_", "FALSE");
my $R_check_all_non_ISO_C =
    &R_getenv("_R_CHECK_ALL_NON_ISO_C_", "FALSE");
my $R_check_weave_vignettes =
    &R_getenv("_R_CHECK_WEAVE_VIGNETTES_", "TRUE");

## This needs texi2dvi.  MiKTeX has a binary texi2dvi, but other
## Windows' LaTeX distributions do not.  We check later.
my $R_check_latex_vignettes =
    &R_getenv("_R_CHECK_LATEX_VIGNETTES_", "TRUE");

my $R_check_subdirs_strict =
    &R_getenv("_R_CHECK_SUBDIRS_STRICT_", "default");
my $R_check_Rd_xrefs =
    &R_getenv("_R_CHECK_RD_XREFS_", "TRUE");
my $R_check_use_codetools =
    &R_getenv("_R_CHECK_USE_CODETOOLS_", "TRUE");
my $R_check_force_suggests =
    &R_getenv("_R_CHECK_FORCE_SUGGESTS_", "TRUE");
my $R_check_Rd_style =
    &R_getenv("_R_CHECK_RD_STYLE_", "TRUE");
my $R_check_executables =
    &R_getenv("_R_CHECK_EXECUTABLES_", "TRUE");
my $R_check_executables_exclusions =
    &R_getenv("_R_CHECK_EXECUTABLES_EXCLUSIONS_", "TRUE");
# my $R_check_Rd_parse =
#     &R_getenv("_R_CHECK_RD_PARSE_", "TRUE");
## This check needs codetools
my $R_check_dot_internal =
    &R_getenv("_R_CHECK_DOT_INTERNAL_", "FALSE");

## Only relevant when the package is loaded, thus installed.
my $R_check_suppress_RandR_message =
    ($opt_install &&
     &R_getenv("_R_CHECK_SUPPRESS_RANDR_MESSAGE_", "TRUE"));

## Maybe move basic configuration (and documentation) to
##   &file_path($R::Vars::R_HOME, "etc", "check.conf")
## eventually ...
for my $file ($opt_rcfile) {
    if(-r $file) {
	open(FILE, "< $file")
	    or die "Error: cannot open file '$file' for reading\n";
	my @lines = <FILE>;
	close(FILE);
	eval("@lines");
	die "Error: failed to eval config file '$file'\n$@\n" if ($@);
	## <NOTE>
	## We prefer the above to the usual recommendation
	##	unless ($return = do($file)) {
	##	    warn "couldn't parse $file: $@" if $@;
	##	    warn "couldn't do $file: $!"    unless defined $return;
	##	    warn "couldn't run $file"       unless $return;
	##  }
	## as do(FILE) cannot see lexicals in the enclosing scope.
	## </NOTE>
    }
}

$R_check_use_install_log =
    &config_val_to_logical($R_check_use_install_log);
$R_check_subdirs_nocase =
    &config_val_to_logical($R_check_subdirs_nocase);
$R_check_all_non_ISO_C =
    &config_val_to_logical($R_check_all_non_ISO_C);
$R_check_weave_vignettes =
    &config_val_to_logical($R_check_weave_vignettes);
$R_check_latex_vignettes =
    &config_val_to_logical($R_check_latex_vignettes);
$R_check_Rd_xrefs =
    &config_val_to_logical($R_check_Rd_xrefs);
$R_check_use_codetools =
    &config_val_to_logical($R_check_use_codetools);
$R_check_Rd_style =
    &config_val_to_logical($R_check_Rd_style);
$R_check_executables =
    &config_val_to_logical($R_check_executables);
$R_check_executables_exclusions =
    &config_val_to_logical($R_check_executables_exclusions);
# $R_check_Rd_parse =
#     &config_val_to_logical($R_check_Rd_parse);
$R_check_dot_internal =
    &config_val_to_logical($R_check_dot_internal);
## <NOTE>
## This looks a bit strange, but tools:::.check_package_depends()
## currently gets the information about forcing suggests via an
## environment variable rather than an explicit argument.
$R_check_force_suggests =
    &config_val_to_logical($R_check_force_suggests);
## And in fact, it gets even stranger ...
## <FIXME>
## Compatibility code for old-style interface: sanitize eventually.
$R_check_force_suggests =
    $R_check_force_suggests ? "true" : "false";
$ENV{"_R_CHECK_FORCE_SUGGESTS_"} = $R_check_force_suggests;
## </FIXME>
## </NOTE>
$R_check_suppress_RandR_message =
    &config_val_to_logical($R_check_suppress_RandR_message);

$opt_subdirs = $R_check_subdirs_strict if $opt_subdirs eq "";

my $startdir = R_cwd();
$opt_outdir = $startdir unless $opt_outdir;
chdir($opt_outdir)
    or die "Error: cannot change to directory '$opt_outdir'\n";
my $outdir = R_cwd();
chdir($startdir);

my $R_LIBS = $ENV{'R_LIBS'};
my $library;
if($opt_library) {
    chdir($opt_library)
	or die "Error: cannot change to directory '$opt_library'\n";
    $library = R_cwd();
    $ENV{'R_LIBS'} = env_path($library, $R_LIBS);

    chdir($startdir);
}

my $tar = R_getenv("TAR", "tar");

my $R_opts = "--vanilla";

if($opt_latex) {
    my $log = new R::Logfile();
    $log->checking("for working pdflatex");
    open(TEXFILE,
	 "> " . &file_path(${R::Vars::TMPDIR}, "Rtextest$$.tex"))
      or die "Error: cannot open file 'Rtextest$$.tex' for writing\n";
    print TEXFILE "\\nonstopmode\\documentclass\n\{article\}\n\\begin\{document\}\n" .
	"test\n\\end\{document\}\n";
    close(TEXFILE);
    chdir($R::Vars::TMPDIR);
    ## print "\ntesting ${R::Vars::PDFLATEX}\n";
    if(R_system("${R::Vars::PDFLATEX} Rtextest$$ > Rtextest$$.out")) {
	$log->result("NO");
    } else {
	$log->result("OK");
	$HAVE_PDFLATEX = 1;
	$HAVE_LATEX = 1;
    }
    unlink(<Rtextest$$.*>);
    if(!$HAVE_PDFLATEX) {
	$log->checking("for working latex");
	open(TEXFILE,
	     "> " . &file_path(${R::Vars::TMPDIR}, "Rtextest$$.tex"))
	  or die "Error: cannot open file 'Rtextest$$.tex' for writing\n";
	print TEXFILE "\\nonstopmode\\documentclass\n\{article\}\n\\begin\{document\}\n" .
	    "test\n\\end\{document\}\n";
	close(TEXFILE);
	chdir($R::Vars::TMPDIR);
	if(R_system("${R::Vars::LATEX} Rtextest$$ > Rtextest$$.out")) {
	    $log->result("NO");
	} else {
	    $log->result("OK");
	    $HAVE_LATEX = 1;
	}
	unlink(<Rtextest$$.*>);
    }
    chdir($startdir);
    $log->close();
}

my @msg_DESCRIPTION = ("See the information on DESCRIPTION files",
		     "in the chapter 'Creating R packages'",
		     "of the 'Writing R Extensions' manual.\n");

## This is the main loop over all packages to be checked.
(scalar(@ARGV) > 0) or die "Error: no packages were specified\n";
foreach my $pkg (@ARGV) {
    ## $pkg should be the path to the package (bundle) root source
    ## directory, either absolute or relative to $startdir.
    ## As from 2.1.0 it can also be a tarball

    ## $pkgdir is the corresponding absolute path.
    ## $pkgname is the name of the package (bundle).
    chdir($startdir);
    $pkg =~ s+/$++;  # strip any trailing '/'
    my $pkgname = basename($pkg);
    my $opkgname = $pkgname;
    $is_ascii = 0;

    my $thispkg_subdirs = $opt_subdirs;
    ## is this a tar archive?
    my $istar = 0;
    if(-d $pkg) {
	$thispkg_subdirs = "no" if $thispkg_subdirs eq "default";
    } else {
	$istar = 1;
	$thispkg_subdirs = "yes-maybe" if $thispkg_subdirs eq "default";
	$pkgname =~ s/\.(tar\.gz|tgz|tar\.bz2)$//;
	$pkgname =~ s/_[0-9\.-]*$//;
    }

    my $pkgoutdir = &file_path($outdir, "$pkgname.Rcheck");
    rmtree($pkgoutdir) if ($opt_clean && (-d $pkgoutdir)) ;
    if(!(-d $pkgoutdir)) {
	mkdir($pkgoutdir, 0755)
	  or die("Error: cannot create directory '$pkgoutdir'\n");
    }

    if($istar) {
	my $dir = &file_path("$pkgoutdir", "00_pkg_src");
	mkdir($dir, 0755)
	  or die("Error: cannot create directory '$dir'\n");
	if($WINDOWS) {
	    ## workaround for paths in Cygwin tar
	    $pkg =~ s+^([A-Za-z]):+/cygdrive/\1+;
	}
	## ATT 'tar x' did not support -C.
	## Note that $pkg, $dir might contain spaces
	my $pkgq = &shell_quote_file_path($pkg);
	my $dirq = &shell_quote_file_path($dir);
	if($opkgname =~ /\.bz2$/) {
	    my $bzip = R_getenv("R_BZIPCMD", "bzip2");
	    if(R_system("$bzip -dc $pkgq | $tar -xf - -C $dirq")) {
		die "Error: cannot untar '$pkg'\n";
	    }
	} elsif ($opkgname =~ /\.(tar\.gz|tgz)$/) {
	    my $gzip = R_getenv("R_GZIPCMD", "gzip");
	    if(R_system("$gzip -dc $pkgq | $tar -xf - -C $dirq")) {
		die "Error: cannot untar '$pkg'\n";
	    }
	} else {
	    ## let tar automagically fathom out compression (if any)
	    if(R_system("$tar -xf $pkgq -C $dirq")) {
		die "Error: cannot untar '$pkg'\n";
	    }
	}
	$pkg = &file_path($dir, $pkgname);
    }

    $pkg =~ s/\/$//;
    (-d $pkg) or die "Error: package dir '$pkg' does not exist\n";
    chdir($pkg)
	or die "Error: cannot change to directory '$pkg'\n";
    my $pkgdir = R_cwd();
    ## my $pkgname = basename($pkgdir);
    my $thispkg_src_subdir = $thispkg_subdirs;
    if($thispkg_src_subdir eq "yes-maybe") {
	## now see if there is a 'configure' file
	## configure files are only used if executable, but
	## -x is always false on Windows.
	if($WINDOWS) {
	    $thispkg_src_subdir = "no" if (-f "configure");
	} else {
	    $thispkg_src_subdir = "no" if (-x "configure");
	}
    }
    chdir($startdir);

    $log = new R::Logfile(&file_path($pkgoutdir, "00check.log"));
    $log->message("using log directory '$pkgoutdir'");
    my @out = R_runR("cat(R.version.string, '\\n', sep='')",
		     "--slave --vanilla");
    $log->message("using @out");
    @out = R_runR("tools:::.find_charset()", "--slave --vanilla");
    $log->message("using session @out");
    $is_ascii = 1 if $out[0] =~ /ASCII$/;

    ## report options used
    push @opts,"--no-codoc" if !$opt_codoc;
    push @opts,"--no-examples" if !$opt_examples && !$spec_install;
    push @opts,"--no-tests" if !$opt_tests && !$spec_install;
    push @opts,"--no-vignettes" if !$opt_vignettes && !$spec_install;
    push @opts,"--use-gct" if $opt_use_gct;
    push @opts,"--use-valgrind" if $opt_use_valgrind;
    if (@opts == 1) {
	$log->message("using option '" . $opts[0] . "'");
    } elsif (@opts) {
	$log->message("using options '" . join(" ", @opts) . "'");
    }

    if(!$opt_library) {
	$library = $pkgoutdir;
	$ENV{'R_LIBS'} = env_path($library, $R_LIBS);
    }
    if($WINDOWS) { ## need to avoid spaces in $library
	$library = Win32::GetShortPathName($library) if $library =~ / /;
    }

    my $description;
    my $is_base_pkg = 0;
    my $is_bundle = 0;
    my $package_or_bundle = "package";
    my $package_or_bundle_name;
    my $encoding;
    ## Package sources from the R distribution are special.  They have a
    ## 'DESCRIPTION.in' file (instead of 'DESCRIPTION'), with Version
    ## field containing '@VERSION@' for substitution by configure.  We
    ## test for such packages by looking for 'DESCRIPTION.in' (and 'Makefile.in') with
    ## Priority 'base', and skip the installation test for such
    ## packages.  We have to check for Makefile.in in addition to DESCRIPTION.in
    ## so that we can allow packages to have a DESCRIPTION.in.  Such DESCRIPTION.in files will
    ## have their content completed via the package's configuration which we have not yet run.
    ## The DESCRIPTION.in file may be malformed (according to R::Dcf()), e.g if it has a line
    ## @SYSTEM@ which is either empty or "System: ...." depending on the configuration script.
    if(-r &file_path($pkgdir, "DESCRIPTION.in") && -r &file_path($pkgdir, "Makefile.in")) {
	$description =
	  new R::Dcf(&file_path($pkgdir, "DESCRIPTION.in"));
	if($description->{"Priority"} eq "base") {
	    $log->message("looks like '${pkgname}' is a base package");
	    $log->message("skipping installation test");
	    $is_base_pkg = 1;
	}
    }

    if(!$is_base_pkg) {
	$log->checking(join("",
			    ("for file '",
			     &file_path($pkgname, "DESCRIPTION"),
			     "'")));
	if(-r &file_path($pkgdir, "DESCRIPTION")) {
	    $description =
	      new R::Dcf(&file_path($pkgdir, "DESCRIPTION"));
	    $log->result("OK");
	    $encoding = $description->{"Encoding"};
	}
	else {
	    $log->result("NO");
	    exit(1);
	}
	if($description->{"Type"}) { # standard packages do not have this
	    $log->checking("extension type");
	    $log->result($description->{"Type"});
	    if($description->{"Type"} ne "Package") {
		$log->print("Only Type = Package extensions can be checked.\n");
		exit(0);
	    }
	}

	if($description->{"Bundle"}) {
	    $is_bundle = 1;
	    $log->message("looks like '${pkgname}' is a package bundle");
	    $package_or_bundle = "bundle";
	    $package_or_bundle_name = $description->{"Bundle"};
	}
	else {
	    $package_or_bundle_name = $description->{"Package"};
	}
	$log->message("this is $package_or_bundle " .
		      "'$package_or_bundle_name' " .
		      "version '$description->{\"Version\"}'");

	if(defined $encoding) {$log->message("package encoding: $encoding");}

	## Check if we have any hope of installing

	my $OS_type = $description->{"OS_type"};
	if($opt_install && $OS_type) {
	    if($WINDOWS && $OS_type ne "windows") {
		$log->message("will not attempt to install this package on Windows");
		$opt_install = 0;
	    }
	    if(!$WINDOWS && $OS_type eq "windows" && $opt_install == 1) {
		$log->message("this is a Windows-only package, skipping installation");
		$opt_install = 0;
	    }
	}

	## Check CRAN incoming feasibility.
	if(&config_val_to_logical(&R_getenv("_R_CHECK_CRAN_INCOMING_",
					    "FALSE"))) {
	    $log->checking("CRAN incoming feasibility");
	    my $Rcmd = "tools:::.check_package_CRAN_incoming(\"${pkgdir}\")\n";
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=NULL");
	    @out = grep(!/^\>/, @out);
	    if(scalar(@out) > 0) {
		my $err = scalar(grep(/^Conflicting/, @out) > 0);
		if($err) {
		    $log->error();
		} elsif(scalar(grep(/^Insufficient/, @out) > 0)) {
		    $log->warning();
		} else {
		    $log->note();
		}
		$log->print(join("\n", @out) . "\n");
		exit(1) if($err);
	    } else {
		$log->result("OK");
	    }
	}	    

	## Check package dependencies.

	## <NOTE>
	## We want to check for dependencies early, since missing
	## dependencies may make installation fail, and in any case we
	## give up if they are missing.  But we don't check them if
	## we are not going to install and hence not run any code.
	## </NOTE>

	if($opt_install) {
	    ## Try figuring out whether the package dependencies can be
	    ## resolved at run time.  Ideally, the installation
	    ## mechanism would do this, and we also do not check
	    ## versions ... also see whether vignette and namespace
	    ## package dependencies are recorded in DESCRIPTION.

	    ## <NOTE>
	    ## We are not checking base packages here, so all packages do
	    ## have a description file.  Bundles should have dependencies
	    ## only at the top level to be usable by install.packages and
	    ## friends, and `Writing R Extensions' requires this.
	    ## </NOTE>

	    ## <NOTE>
	    ## If a package has a namespace, checking dependencies will
	    ## try making use of it without the NAMESPACE file ever
	    ## being validated.  Uncaught errors can lead to messages
	    ## like
	    ##   * checking package dependencies ... ERROR
	    ##   Error in e[[1]] : object is not subsettable
	    ##   Execution halted
	    ## which are not too helpful :-(
	    ## Hence, we try to intercept this here.
	    ## Note that for *bundles*, the respective namespaces are not
	    ## checked this way (and perhaps should be lateron when the
	    ## per-package checks are performed).
	    if(-f &file_path($pkgdir, "NAMESPACE")) {
		$log->checking("package name space information");

		my @msg_NAMESPACE =
		    ("See section 'Package name spaces'",
		     "of the 'Writing R Extensions' manual.\n");

		my $Rcmd = "tools:::.check_namespace(\"${pkgdir}\")";
		my @out = R_runR($Rcmd, "${R_opts} --quiet",
				 "R_DEFAULT_PACKAGES=NULL");
		@out = grep(!/^\>/, @out);
		if(scalar(@out) > 0) {
		    $log->error();
		    $log->print(join("\n", @out) . "\n");
		    $log->print(wrap("", "", @msg_NAMESPACE));
		    exit(1);
		} else {
		    $log->result("OK");
		}
	    }

	    $log->checking("$package_or_bundle dependencies");
	    ## Everything listed in Depends or Suggests or Imports
	    ## should be available for successfully running R CMD check.
	    ## \VignetteDepends{} entries not "required" by the package code
	    ## must be in Suggests.  Note also that some of us think that a
	    ## package vignette must require its own package, which OTOH is
	    ## not required in the package DESCRIPTION file.
	    ## Namespace imports must really be in Depends.
	    my $Rcmd = "options(warn=1,warnEscapes=FALSE); tools:::.check_package_depends(\"${pkgdir}\")\n";
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=NULL");
	    @out = grep(!/^\>/, @out);
	    if(scalar(@out) > 0) {
		$log->error();
		$log->print(join("\n", @out) . "\n");
		$log->print(wrap("", "", @msg_DESCRIPTION));
		exit(1);
	    } else {
		$log->result("OK");
	    }
	}

	## <NOTE>
	## This check should be adequate, but would not catch a manually
	## installed package, nor one installed prior to 1.4.0.
	## </NOTE>
	$log->checking("if this is a source $package_or_bundle");
	if(defined($description->{"Built"})) {
	    $log->error();
	    $log->print("Only *source* packages can be checked.\n");
	    exit(1);
	}
	elsif($opt_install !~ /^check/) {
	    ## Check for package/bundle 'src' subdirectories with object
	    ## files (but not if installation was already performed).
	    my $any;
	    my $pat = "(a|o|[ls][ao]|sl|obj)"; # Object file extensions.
	    my @dirs;
	    if($is_bundle) {
		foreach my $ppkg (split(/\s+/,
					$description->{"Contains"})) {
		    push(@dirs, &file_path($ppkg, "src"));
		}
	    }
	    else {
		@dirs = ("src");
	    }
	    foreach my $dir (@dirs) {
		if((-d &file_path($pkgdir, $dir))
		   && &list_files_with_exts(&file_path($pkgdir, $dir),
					    $pat)) {
		    $log->warning() unless $any;
		    $any++;
		    $dir = &file_path($pkgname, $dir);
		    $log->print("Subdirectory '$dir' " .
				"contains object files.\n");
		}
	    }

	    if($thispkg_src_subdir ne "no") {
		## Recognized extensions for sources or headers.
		my $exts = "(" .
		    &make_file_exts("sources") . "|" .
		    &make_file_exts("headers") . ")";
		foreach my $dir (@dirs) {
		    if((-d &file_path($pkgdir, $dir))) {
			chdir(&file_path($pkgdir, $dir));
			if(!(-f "Makefile") && !(-f "Makefile.win")) {
			    opendir(DIR, ".") or die "cannot opendir $dir: $!";
			    @srcfiles = grep {
				!(/\.$exts$/ || /^Makevars/ || /-win\.def$/ )
				    && -f "$_" } readdir(DIR);
			    closedir(DIR);
			    if(@srcfiles) {
				$log->warning() unless $any;
				$any++;
				$log->print("Subdirectory '$dir' contains:\n");
				$log->print(wrap("  ", "  ",
						 join(" ", sort @srcfiles) . "\n"));
				$log->print(wrap("", "",
						 ("These are unlikely file names",
						  "for src files.\n")));
			    }
			}
			chdir($startdir);
		    }
		}
	    }
	    $log->result("OK") unless $any;
	}
	else {
	    $log->result("OK");
	}

	## we need to do this before installation
	if ($R_check_executables) {
	    ## this is tailored to the FreeBSD/Linux file,
	    ## see http://www.darwinsys.com/file/
	    my $have_free_file = 0;
	    my $tmpfile = R_tempfile("file");
	    ## version 4.21 writes to stdout, 4.23 to stderr
	    ## and set an error status code
	    R_system("file --version > $tmpfile 2>&1");
	    open FILE, "< $tmpfile";
	    my @lines = <FILE>;
	    close(FILE);
	    ## a reasonable check -- it does not identify itself well
	    $have_free_file = 1 if grep(/^(file-[45]|magic file from)/, @lines);
	    if ($have_free_file) {
		$log->checking("for executable files");
		my @exec_files = ();
		sub find_execs {
		    my $file_path = $File::Find::name;
		    ## False positives:
		    ## * foreign/tests/datefactor.dta gives
		    ##     setgid mc68020 pure executable not stripped
		    return if $file_path =~
			m+foreign/tests/datefactor.dta$+;
		    ## * msProcess/inst/data[12]/*.txt give
		    ##     setgid MS-DOS executable, MZ for MS-DOS
		    return if $file_path =~
			m+msProcess/inst/data[12]/.*.txt$+;
		    my $file_name = basename($file_path);
		    my $bare_path = $file_path;
		    $bare_path =~ s+^$pkgdir/++;
		    ## watch out for spaces in file names here
		    R_system("file '$file_name' > $tmpfile");
		    open FILE, "< $tmpfile";
		    my @lines = <FILE>;
		    close(FILE);
		    my $line = $lines[0];
		    my $t1 = $line =~ /executable/;
		    my $t2 = $line =~ /script text/;
		    push @exec_files, $bare_path if ($t1 && ! $t2);
		}
		find(\&find_execs, "$pkgdir");
		if($R_check_executables_exclusions &&
		   -f "$pkgdir/BinaryFiles") {
		    my %bin;
		    open FILE, "< $pkgdir/BinaryFiles";
		    while (<FILE>) {
			chomp;
			s/\r$//;  # careless people get Windows files on other OSes
			$bin{$_} = $_;
		    }
		    close(FILE);
		    my @exec_files0 = @exec_files;
		    @exec_files = ();
		    foreach my $file (@exec_files0) {
			push @exec_files, $file unless $bin{$file};
		    }
		}
		if(($opt_install =~ /^check/) &&
		   (-f &file_path($pkgdir, ".install_timestamp"))) {
		    my $its = (-M &file_path($pkgdir,
					     ".install_timestamp"));
		    my @exec_files_in = @exec_files;
		    @exec_files = ();
		    foreach my $path (@exec_files_in) {
			push @exec_files, $path unless
			    ((-M &file_path($pkgdir, $path)) < $its);
		    }
		}
		if(scalar(@exec_files) > 0) {
		    $log->warning();
		    $log->print("Found the following executable file(s):\n");
		    $log->print("  " . join("\n  ", @exec_files) . "\n");
		    $log->print(wrap("", "",
				     ("Source packages should not contain undeclared executable files.\n",
				      "See section 'Package structure'",
				      "in manual 'Writing R Extensions'.\n")));
		}
		else {
		    $log->result("OK");
		}
	    } else {	       # no 'file', so just check extensions
		$log->checking("for .dll and .exe files");
		my @exec_files = ();
		sub find_execs2 {
		    my $file_path = $File::Find::name;
		    my $bare_path = $file_path;
		    $bare_path =~ s+^$pkgdir/++;
		    push @exec_files, $bare_path
			if $file_path =~ /\.(exe|dll)$/;
		}
		find(\&find_execs2, "$pkgdir");
		if(R_check_executables_exclusions &&
		   -f "$pkgdir/BinaryFiles") {
		    my %bin;
		    open FILE, "< $pkgdir/BinaryFiles";
		    while (<FILE>) {
			chomp;
			s/\r$//;
			$bin{$_} = $_;
		    }
		    close(FILE);
		    my @exec_files0 = @exec_files;
		    @exec_files = ();
		    foreach my $file (@exec_files0) {
			push @exec_files, $file unless $bin{$file};
		    }
		}
		if(scalar(@exec_files) > 0) {
		    $log->warning();
		    $log->print("Found the following executable file(s):\n");
		    $log->print("  " . join("\n  ", @exec_files) . "\n");
		    $log->print(wrap("", "",
				     ("Source packages should not contain executable files.\n",
				      "See section 'Package structure'",
				      "in manual 'Writing R Extensions'.\n")));
		}
		else {
		    $log->result("OK");
		}
	    }
	    unlink $tmpfile;
	}

	## Option '--no-install' turns off installation and the tests
	## which require the package to be installed.  When testing
	## recommended packages bundled with R we can skip installation,
	## and do so if '--install=skip' was given.  If command line
	## option '--install' is of the form 'check:FILE', it is assumed
	## that installation was already performed with stdout/stderr to
	## FILE, the contents of which need to be checked (without
	## repeating the installation).
	## <NOTE>
	## In this case, one also needs to specify *where* the package
	## was installed to using command line option '--library'.
	## Perhaps we should check for that, although '--install=check'
	## is really only meant for repository maintainers.
	## </NOTE>
	if($opt_install) {
	    if($opt_install eq "skip") {
		$log->message("skipping installation test");
	    }
	    else {
		my $use_install_log =
		    (($opt_install =~ /^check/) ||
		     $R_check_use_install_log ||
		     !(-t STDIN && -t STDOUT));
		$INSTALL_opts = $opt_install_args;
		## don't use HTML, checkRd goes over the same ground.
		$INSTALL_opts = $INSTALL_opts .  " --no-html";
		#$INSTALL_opts = $INSTALL_opts .  " --no-chm" if $WINDOWS;
		$INSTALL_opts = $INSTALL_opts . " --fake" if($opt_install eq "fake");
		my $cmd;
		if($WINDOWS) {
		    ## avoid some quoting hell
		    my $pkgd = Win32::GetShortPathName($pkgdir);
		    $cmd = join(" ",
				("Rcmd.exe INSTALL -l",
				 &shell_quote_file_path($library),
				 "$INSTALL_opts",
				 &shell_quote_file_path($pkgd)));
		} else {
		    $cmd = join(" ",
				(&shell_quote_file_path(${R::Vars::R_EXE}),
				 "CMD INSTALL -l",
				 &shell_quote_file_path($library),
				 "$INSTALL_opts",
				 &shell_quote_file_path($pkgdir)));
		}
		if(!$use_install_log) {
		    ## Case A: No redirection of stdout/stderr from
		    ## installation.
		    print("\n");
		    if(R_system($cmd)) {
			$log->error();
			$log->print("Installation failed.\n");
			exit(1);
		    }
		    print("\n");
		}
		else {
		    ## Case B. All output from installation redirected,
		    ## or already available in the log file.
		    $log->checking("whether $package_or_bundle " .
				   "'$package_or_bundle_name' " .
				   "can be installed");
		    my $out = &file_path($pkgoutdir, "00install.out");
		    my $install_error;
		    my @lines;
		    if($opt_install =~ /^check/) {
			copy(substr($opt_install, 6), $out);
			$opt_install = "check";
			@lines = &read_lines($out);
			## <NOTE>
			## We used to have
			## $install_error =
			##    ($lines[$#lines] !~ /^\* DONE/);
			## but what if there is output from do_cleanup
			## in (Unix) R CMD INSTALL?
			$install_error =
			    (scalar(grep(/^\* DONE/, @lines)) == 0);
			## </NOTE>
		    }
		    else {
			## record in the log what options were used
			open(LOG, "> $out");
			print LOG "* install options are '$INSTALL_opts'\n\n";
			close(LOG);
			$cmd .= " >>" .
			    &shell_quote_file_path($out) .
			    " 2>&1";
			$install_error = &R_system($cmd);
			if($WINDOWS) {
			    ## MS Html Help Compiler gives lines terminated
			    ## by CRCRLF, so we clean up the log file.
			    my $line;
			    ## read_lines does chomp.
			    @lines = &read_lines($out);
			    ## error codes seem unreliable, so check here
			    $install_error =
				(scalar(grep(/^\* DONE/, @lines)) == 0);
			    open(FILE, "> $out")
				or die "Error: cannot open file '$out' for re-writing\n";
			    foreach my $line (@lines) {
				$line =~ s/\r$//;
				print FILE $line, "\n";
			    }
			    close(FILE);
			}
		    }
		    if($install_error) {
			$log->error();
			$log->print("Installation failed.\n");
			$log->print("See '$out' for details.\n");
			exit(1);
		    }
		    ## There could still be some important warnings that
		    ## we'd like to report.  For the time being, start
		    ## with compiler warnings about non ISO C code (or
		    ## at least, what looks like it), and also include
		    ## warnings resulting from the const char * CHAR()
		    ## change in R 2.6.0.  (In theory, we should only do
		    ## this when using GCC ...)
		    @lines = &read_lines($out)
			unless($opt_install eq "check");
		    my $warn_re =
			"(" . join("|", ("^WARNING:",
					 "^Warning:",
					 ## <FIXME>
					 ## New style Rd conversion
					 ## which may even show errors:
					 "^Rd (warning|error): ",
					 ## </FIXME>
					 ": warning: .*ISO C",
					 ": warning: implicit declaration of function",
					 ": warning: .* discards qualifiers from pointer target type",
					 ": warning: .* is used uninitialized",
					 "missing link\\(s\\):")) . ")";
		    @lines = grep(/$warn_re/, @lines);

		    ## Ignore install time readLines() warnings about
		    ## files with incomplete final lines.  Most of these
		    ## come from .install_package_indices(), and should be
		    ## safe to ignore ...
		    $warn_re = "Warning: incomplete final line " .
			"found by readLines";
		    @lines = grep(!/$warn_re/, @lines);

		    ## Package writers cannot really do anything about
		    ## non ISO C code in *system* headers.  Also, GCC
		    ## 3.4 or better warns about function pointers
		    ## casts which are "needed" for dlsym(), but it
		    ## seems that all systems which have dlsym() also
		    ## support the cast.  Hence, try to ignore these by
		    ## default, but make it possible to get all ISO C
		    ## warnings via an environment variable.
		    if(!$R_check_all_non_ISO_C) {
			@lines = grep(!/^ *\/.*: warning: .*ISO C/,
				      @lines);
			$warn_re = "warning: *ISO C forbids.*" .
			    "function pointer";
			@lines = grep(!/$warn_re/, @lines);
		    }

		    ## Warnings spotted by gcc with
		    ## '-Wimplicit-function-declaration', which is
		    ## implied by '-Wall'.  Currently only accessible
		    ## via an internal environment variable.
		    my $check_src_flag =
			&R_getenv("_R_CHECK_SRC_MINUS_W_IMPLICIT_",
				  "FALSE");
		    ## (Not quite perfect, as the name should really
		    ## include 'IMPLICIT_FUNCTION_DECLARATION'.)
		    $check_src_flag =
			&config_val_to_logical($check_src_flag);
		    if(!$check_src_flag) {
			my $warn_re = "warning: implicit declaration of function";
			@lines = grep(!/$warn_re/, @lines);
		    }

		    ## Warnings spotted by gcc with '-Wunused', which is
		    ## implied by '-Wall'.  Currently only accessible
		    ## via an internal environment variable.
		    my $check_src_flag =
			&R_getenv("_R_CHECK_SRC_MINUS_W_UNUSED_",
				  "FALSE");
		    $check_src_flag =
			&config_val_to_logical($check_src_flag);
		    if(!$check_src_flag) {
			my $warn_re = "warning: unused";
			@lines = grep(!/$warn_re/i, @lines);
		    }
		    ## (gfortran seems to use upper case.)

		    ## Warnings spotted by gfortran 4.0 or better with
		    ## -Wall.  Justified in principle, it seems.  Let's
		    ## filter them for the time being, and maybe revert
		    ## this lateron ... but make it possible to suppress
		    ## filtering out by setting the internal environment
		    ## variable _R_CHECK_WALL_FORTRAN_ to something
		    ## "true".
		    my $R_check_Wall_FORTRAN =
			&R_getenv("_R_CHECK_WALL_FORTRAN_", "FALSE");
		    $R_check_Wall_FORTRAN =
			&config_val_to_logical($R_check_Wall_FORTRAN);
		    if(!$R_check_Wall_FORTRAN) {
			my $warn_re =
			    "(" .
			    join("|",
				 ("Label .* at \\(1\\) defined but not used",
				  "Line truncated at \\(1\\)",
				  "ASSIGN statement at \\(1\\)",
				  "Assigned GOTO statement at \\(1\\)",
				  "arithmetic IF statement at \\(1\\)",
				  "Nonconforming tab character (in|at)"
				 )) .
			    ")";
			@lines = grep(!/$warn_re/, @lines);
		    }

		    ## 'Warning' from deldir 0.0-10
		    my $warn_re = "Warning: The process for determining duplicated points";
		    @lines = grep(!/$warn_re/, @lines);

		    if(scalar(@lines) > 0) {
			$log->warning();
			$log->print("Found the following " .
				    "significant warnings:\n");
			$log->print("  " . join("\n  ", @lines) . "\n");
			$log->print("See '$out' for details.\n");
		    }
		    else {
			$log->result("OK");
		    }
		}
	    }
	}

    }

    if($is_bundle) {
	my @bundlepkgs = split(/\s+/, $description->{"Contains"});
	if(! $opt_install) {
	    ## Since we are not installing, we have to use the source
	    ## directories.  Quite a bit of the R code needs to read the
	    ## DESCRIPTION files for each package, so we do that bit
	    ## of the install in Perl.
	    my @lines0 = &read_lines(&file_path($pkgdir, "DESCRIPTION"));
	    foreach my $ppkg (@bundlepkgs) {
		$dfile = &file_path($pkgdir, $ppkg, "DESCRIPTION");
		my $fh = new IO::File($dfile, "w")
		    or die "Error: cannot open file '$dpath' for writing\n";
		my @lines = (@lines0,
			     &read_lines(&file_path($pkgdir, $ppkg,
						    "DESCRIPTION.in")));
		@lines = grep(!/^\s*$/, @lines); # Remove blank lines.
		$fh->print(join("\n", @lines), "\n");
		$fh->close();
	    }
	}
	foreach my $ppkg (@bundlepkgs) {
	    $log->message("checking '$ppkg' in bundle '$pkgname'");
	    $log->setstars("**");
	    chdir($startdir);
	    check_pkg(&file_path($pkgdir, $ppkg), $pkgoutdir, $startdir,
		      $library, $is_bundle, $description, $log,
		      $is_base_pkg);
	    $log->setstars("*");
	}
	## We could use the latex-ed pages, but we need the DESCRIPTION.in
	check_pkg_manual($pkgdir, basename($pkgdir), $log);
    }
    else {
	chdir($startdir);
	check_pkg($pkgdir, $pkgoutdir, $startdir, $library,
		  $is_bundle, $description, $log, $is_base_pkg,
		  $thispkg_subdirs);
	my $instdir = &file_path($library, $pkgname);
	if (-d &file_path($instdir, "help")) {
	    check_pkg_manual($instdir, $description->{"Package"}, $log);
	} else {
	    check_pkg_manual($pkgdir, $description->{"Package"}, $log);
	}
    }

    if($log->{"warnings"}) {
	print("\n") ;
	$log->summary();
    }
    $log->close();
    print("\n");
}


sub check_pkg {

    my ($pkg, $pkgoutdir, $startdir, $library,
	$in_bundle, $description, $log, $is_base_pkg, $subdirs) = @_;
    my ($pkgdir, $pkgname);

    ## $pkg is the argument we received from the main loop.
    ## $pkgdir is the corresponding absolute path,
    ## $pkgname the name of the package.
    ## Note that we need to repeat the checking from the main loop in
    ## the case of package bundles (and we could check for this).

    $log->checking("package directory");
    chdir($startdir);
    $pkg =~ s/\/$//;
    if(-d $pkg) {
	chdir($pkg)
	  or die "Error: will not change to directory '$pkg'\n";
	$pkgdir = R_cwd();
	if($in_bundle) {
	    $pkgname = basename($pkgdir);
	} else {
	    $pkgname = $description->{"Package"};
	}
    }
    else {
	$log->error();
	$log->print("Package directory '$pkg' does not exist.\n");
	exit(1);
    }
    $log->result("OK");

    chdir($pkgdir);

    ## Build list of exclude patterns.

    my @exclude_patterns = R::Utils::get_exclude_patterns();
    my $exclude_file = ".Rbuildignore";
    ## This is a bit tricky for bundles where the build ignore pattern
    ## file is in the top-level bundle dir.
    $exclude_file = &file_path(dirname($pkgdir), $exclude_file);
    if(-f $exclude_file) {
	open(RBUILDIGNORE, "< $exclude_file");
	while(<RBUILDIGNORE>) {
	    chomp;
	    s/\r$//;  # careless people get Windows files on other OSes
	    push(@exclude_patterns, $_) if $_;
	}
	close(RBUILDIGNORE);
    }

    ## Check for portable file names.

    ## Ensure that the names of the files in the package are valid for
    ## at least the supported OS types.
    ## Under Unix, we definitely cannot have '/'.
    ## Under Windows, the control characters as well as  " * : < > ? \ |
    ## (i.e., ASCII characters 1 to 31 and 34, 36, 58, 60, 62, 63, 92,
    ## and 124) are or can be invalid.  (In addition, one cannot have
    ## one-character file names consisting of just ' ', '.', or '~'.)
    ## Based on information by Uwe Ligges, Duncan Murdoch, and Brian
    ## Ripley.

    ## In addition, Windows does not allow the following DOS type device
    ## names (by themselves or with possible extensions), see e.g.
    ## http://msdn.microsoft.com/library/default.asp?url=/library/en-us/fileio/fs/naming_a_file.asp
    ## and http://en.wikipedia.org/wiki/Filename (which as of 2007-04-22
    ## is wrong about claiming that COM0 and LPT0 are disallowed):
    ##
    ## CON: Keyboard and display
    ## PRN: System list device, usually a parallel port
    ## AUX: Auxiliary device, usually a serial port
    ## NUL: Bit-bucket device
    ## CLOCK$: System real-time clock
    ## COM1, COM2, COM3, COM4, COM5, COM6, COM7, COM8, COM9:
    ##   Serial communications ports 1-9
    ## LPT1, LPT2, LPT3, LPT4, LPT5, LPT6, LPT7, LPT8, LPT9:
    ##   parallel printer ports 1-9

    ## In addition, the names of help files get converted to HTML file
    ## names and so should be valid in URLs.  We check that they are
    ## ASCII and do not contain %, which is what is known to cause
    ## troubles.

    $log->checking("for portable file names");
    my @bad_files = ();
    my @non_ASCII_files = ();
    sub find_wrong_names {
	my $file_path = $File::Find::name;
	$file_path =~ s/^\.[^\/]*\///;
	foreach my $p (@exclude_patterns) {
	    if($WINDOWS) {
		## Argh: Windows is case-honoring but not
		## case-insensitive ...
		return 0 if($file_path =~ /$p/i);
	    }
	    else {
		## Hmm, but Unix-alikes such as Mac OS X have such file systems
		return 0 if($file_path =~ /$p/);
	    }
	}
	my $file_name = basename($file_path);
	{
	    ## collation is ASCII as 'use locale' is not in effect.
	    ## NB: the omission of ' ' is deliberate.
	    if (grep(/[^-A-Za-z0-9._!\#\$%&+,;=@^\(\)\{\}\'\[\]]/, $file_name))  {
		push(@non_ASCII_files, $file_path);
	    }
	}
	if(grep(/[[:cntrl:]\"\*\/\:\<\>\?\\\|]/, $file_name)) {
	    push(@bad_files, $file_path);
	} elsif(dirname($file_path) =~ /man$/) {
	    ## perhaps use ranges here, /([^ -~]|%)/ ?
	    foreach my $ch (split //, $file_name) {
		## collation is ASCII as 'use locale' is not in effect.
		if ($ch eq "%" || $ch lt " " || $ch gt "~")  {
		    push(@bad_files, $file_path);
		    last;
		}
	    }
	} else {
	    $file_name =~ tr/A-Z/a-z/;  # collation is ASCII
	    $file_name =~ s/\..*//;
	    push(@bad_files, $file_path)
	      if(grep(/^(con|prn|aux|clock\$|nul|lpt[1-9]|com[1-9])$/,
		     $file_name));
	}
    }
    if($in_bundle) {
	chdir(dirname($pkgdir));
	find(\&find_wrong_names, $pkgname);
	chdir($pkgname);
    }
    else {
	find(\&find_wrong_names, ".");
    }
    if(scalar(@bad_files) > 0) {
	$log->error();
	$log->print("Found the following file(s) with " .
		    "non-portable file names:\n");
	$log->print("  " . join("\n  ", @bad_files) . "\n");
	$log->print(wrap("", "",
			 ("These are not valid file names",
			  "on all R platforms.\n",
			  "Please rename the files and try again.\n",
			  "See section 'Package structure'",
			  "in manual 'Writing R Extensions'.\n")));
	exit(1);
    }

    ## Next check for name clashes on case-insensitive file systems
    ## (that is on Windows).
    %seen = ();
    my @duplicated = ();
    sub check_case_names {
	my $file_path = lc($File::Find::name);
	if($seen{$file_path}) {push(@duplicated, $file_path);}
	$seen{$file_path}  = 1;
    }
    if($in_bundle) {
	chdir(dirname($pkgdir));
	find(\&check_case_names, $pkgname);
	chdir($pkgname);
    }
    else {
	find(\&check_case_names, ".");
    }
    if(scalar(@duplicated) > 0) {
	$log->error();
	$log->print("Found the following file(s) with " .
		    "duplicate lower-cased file names:\n");
	$log->print("  " . join("\n  ", @duplicated) . "\n");
	$log->print(wrap("", "",
			 ("File names must not differ just by case",
			  "to be usable on all R platforms.\n",
			  "Please rename the files and try again.\n",
			  "See section 'Package structure'",
			  "in manual 'Writing R Extensions'.\n")));
	exit(1);
    }

    if(scalar(@non_ASCII_files) > 0) {
	$log->warning();
	$log->print("Found the following file(s) with " .
		    "non-portable file names:\n");
	$log->print("  " . join("\n  ", @non_ASCII_files) . "\n");
	$log->print(wrap("", "",
			 ("These are not fully portable file names\n",
			  "See section 'Package structure'",
			  "in manual 'Writing R Extensions'.\n")));
    }
    else {
	$log->result("OK");
    }


    ## Check for sufficient file permissions (Unix only).

    ## This used to be much more 'aggressive', requiring that dirs and
    ## files have mode >= 00755 and 00644, respectively (with an error
    ## if not), and that files know to be 'text' have mode 00644 (with a
    ## warning if not).  We now only require that dirs and files have
    ## mode >= 00700 and 00400, respectively, and try to fix
    ## insufficient permission in the INSTALL code (Unix only).
    ##
    ## In addition, we check whether files 'configure' and 'cleanup'
    ## exists in the top-level directory but are not executable, which
    ## is most likely not what was intended.

    if($R::Vars::OSTYPE eq "unix") {
	$log->checking("for sufficient/correct file permissions");
	my @bad_files = ();

	## Phase A.  Directories at least 700, files at least 400.
	sub find_wrong_perms_A {
	    my $filename = $File::Find::name;
	    $filename =~ s/^\.[^\/]*\///;
	    foreach my $p (@exclude_patterns) {
		## Unix only, so no special casing for Windows.
		return 0 if($filename =~ /$p/);
	    }
	    if(-d $_ && (((stat $_)[2] & 00700) < oct("700"))) {
		push(@bad_files, $filename);
	    }
	    if(-f $_ && (((stat $_)[2] & 00400) < oct("400"))) {
		push(@bad_files, $filename);
	    }
	}
	if($in_bundle) {
	    chdir(dirname($pkgdir));
	    find(\&find_wrong_perms_A, $pkgname);
	    chdir($pkgname);
	}
	else {
	    find(\&find_wrong_perms_A, ".");
	}
	if(scalar(@bad_files) > 0) {
	    $log->error();
	    $log->print("Found the following files with " .
			"insufficient permissions:\n");
	    $log->print("  " . join("\n  ", @bad_files) . "\n");
	    $log->print(wrap("", "",
			     ("Permissions should be at least 700",
			      "for directories and 400 for files.\n",
			      "Please fix permissions",
			      "and try again.\n")));
	    exit(1);
	}

	## Phase B.  Top-level scripts 'configure' and 'cleanup' should
	## really be mode at least 500, or they will not be necessarily
	## be used (or should we rather change *that*?)
	@bad_files = ();
	foreach my $filename ("configure", "cleanup") {
	    ## This is a bit silly ...
	    my $ignore = 0;
	    foreach my $p (@exclude_patterns) {
		if($filename =~ /$p/) {
		    $ignore = 1;
		    last;
		}
	    }
	    if(!$ignore
	       && (-f $filename)
	       && (((stat $filename)[2] & 00500) < oct("500"))) {
		push(@bad_files, $filename);
	    }
	}
	if(scalar(@bad_files) > 0) {
	    $log->warning();
	    $log->print(wrap("", "",
			     "The following files should most likely",
			     "be executable (for the owner):\n"));
	    $log->print("  " . join("\n  ", @bad_files) . "\n");
	    $log->print(wrap("", "",
			     "Please fix permissions.\n"));
	}
	else {
	    $log->result("OK");
	}
    }

    ## Check DESCRIPTION meta-information.

    ## If we just installed the package (via R CMD INSTALL), we already
    ## validated most of the package DESCRIPTION metadata.  Otherwise,
    ## let us be defensive about this ...

    my $full =
	!$opt_install || ($opt_install eq "skip") || $is_base_pkg;
    &R::Utils::check_package_description($pkgdir, $pkgname, $log,
					 $in_bundle, $is_base_pkg,
					 $full);

    $log->checking("top-level files");
    opendir(DIR, ".") or die "cannot opendir package: $!";
    my @topfiles = grep { /^install.R$/ || /^R_PROFILE.R/
			      && -f "$_" } readdir(DIR);
    closedir(DIR);
    if(@topfiles) {
	$log->warning();
	    $log->print(join(" ", @topfiles) . "\n");
	    $log->print(wrap("", "",
			     ("These files are deprecated.",
			      "See manual 'Writing R Extensions'.\n")));
    } else {
	$log->result("OK");
    }

    ## Check index information.

    $log->checking("index information");
    my @msg_index = ("See the information on INDEX files and package",
		     "subdirectories in the chapter 'Creating R packages'",
		     "of the 'Writing R Extensions' manual.\n");
    my $any = 0;
    if(-z "INDEX") {
	## If there is an empty INDEX file, we get no information about
	## the package contents ...
	$any++;
	$log->warning();
	$log->print("Empty file 'INDEX'.\n");
    }
    if((-d "demo")
       && &list_files_with_type("demo", "demo")) {
	my $index = &file_path("demo", "00Index");
	if(!(-s $index)) {
	    $log->warning() unless($any);
	    $any++;
	    $log->print("Empty or missing file '$index'.\n");
	}
	else {
	    my $dir = "demo";
	    my $Rcmd = "options(warn=1)\ntools:::.check_demo_index(\"$dir\")\n";
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=NULL");
	    @out = grep(!/^\>/, @out);
	    if(scalar(@out) > 0) {
		$log->warning() unless($any);
		$any++;
		$log->print(join("\n", @out) . "\n");
	    }
	}
    }
    if((-d &file_path("inst", "doc"))
       && &list_files_with_type(&file_path("inst", "doc"),
				"vignette")) {
	my $dir = &file_path("inst", "doc");
	my $Rcmd = "options(warn=1)\ntools:::.check_vignette_index(\"$dir\")\n";
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(@out) > 0) {
	    $log->warning() unless($any);
	    $any++;
	    $log->print(join("\n", @out) . "\n");
	}
    }
    if($any) {
	$log->print(wrap("", "", @msg_index));
    }
    else {
	$log->result("OK");
    }

    ## checks below look for R code.  Package WWGbook has an empty R dir.
    my $haveR = -d "R";

    ## Check package subdirectories.

    $log->checking("package subdirectories");
    my $any;
    if ($haveR) {
	opendir(DIR, "R") or die "cannot open dir R\n";
	my @files = readdir(DIR);
	closedir(DIR);
	my $valid = 0;
	foreach my $f (@files) {
	   $valid = 1 if $f =~ /\.[RrSsq]/;
	}
	if(!$valid) {
	    $haveR = 0;
	    $log->warning() unless $any;
	    $any++;
	    $log->print("Found directory 'R' with no source files.\n");
	}
    }
    if($R_check_subdirs_nocase) {
	## Argh.  We often get submissions where 'R' comes out as 'r',
	## or 'man' comes out as 'MAN', and we've just ran into 'DATA'
	## instead of 'data' (2007-03-31).  Maybe we should warn about
	## this unconditionally ...
	## <FIXME>
	## Actually, what we should really do is check whether there is
	## any directory with lower-cased name matching a lower-cased
	## name of a standard directory, while differing in name.
	## </FIXME>
	if((-d "r")) {
	    $log->warning() unless $any;
	    $any++;
	    $log->print("Found subdirectory 'r'.\n");
	    $log->print("Most likely, this should be 'R'.\n")
	}
	if((-d "MAN")) {
	    $log->warning() unless $any;
	    $any++;
	    $log->print("Found subdirectory 'MAN'.\n");
	    $log->print("Most likely, this should be 'man'.\n")
	}
	if((-d "DATA")) {
	    $log->warning() unless $any;
	    $any++;
	    $log->print("Found subdirectory 'DATA'.\n");
	    $log->print("Most likely, this should be 'data'.\n")
	}
    }

    ## several packages have had check dirs in the sources, e.g.
    ## ./languageR/languageR.Rcheck
    ## ./locfdr/man/locfdr.Rcheck
    ## ./clustvarsel/inst/doc/clustvarsel.Rcheck
    ## ./bicreduc/OldFiles/bicreduc.Rcheck
    ## ./waved/man/waved.Rcheck
    ## ./waved/..Rcheck
    my @check_files = ();
    sub find_check_names {
	my $file_path = $File::Find::name;
	my $file_name = basename($file_path);
	my $bare_path = $file_path;
	$bare_path =~ s+^\./++;
	push(@check_files, $bare_path)
	    if -d $file_name && $file_path =~ /\.Rcheck$/;
    }
    find(\&find_check_names, ".");
    if(scalar(@check_files) > 0) {
	$log->warning() unless($any);
	$any++;
	$log->print("Found the following directory(s) with " .
		    "names of check directories:\n");
	$log->print("  " . join("\n  ", @check_files) . "\n");
	$log->print("Most likely, these were included erroneously.\n")
    }

    sub check_subdirs {
	my ($dpath) = @_;
	my $Rcmd = "tools:::.check_package_subdirs(\"$dpath\")\n";
	## We don't run this in the C locale, as we only require
	## certain filenames to start with ASCII letters/digits, and not
	## to be entirely ASCII.
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(@out) > 0) {
	    $log->warning() unless $any;
	    $any++;
	    $log->print(join("\n", @out) . "\n");
	    $log->print(wrap("", "",
			     ("Please remove or rename the files.\n",
			      "See section 'Package subdirectories'",
			      "in manual 'Writing R Extensions'.\n")));
	}
    }

    &check_subdirs(".") unless ($subdirs eq "no");
    sub has_lazyload_data {
	my ($dir) = @_;
	my @files;
	my $ans = 0;
	if (-s &file_path($dir, "Rdata.rdb")
	    && -s &file_path($dir, "Rdata.rds")
	    && -s &file_path($dir, "Rdata.rdx")) {
	    $ans = 1;
	}
	$ans;
    }
    ## Subdirectory 'data' without data sets?
    if((-d "data") && !&list_files_with_type("data", "data")
       && !&has_lazyload_data("data")) {
	$log->warning() unless $any;
	$any++;
	$log->print("Subdirectory 'data' contains no data sets.\n");
    }
    ## Subdirectory 'demo' without demos?
    if((-d "demo") && !&list_files_with_type("demo", "demo")) {
	$log->warning() unless $any;
	$any++;
	$log->print("Subdirectory 'demo' contains no demos.\n");
    }
    ## Subdirectory 'exec' without files?
    if((-d "exec") && !&list_files("exec")) {
	$log->warning() unless $any;
	$any++;
	$log->print("Subdirectory 'exec' contains no files.\n");
    }
    ## Subdirectory 'inst' without files?
    if((-d "inst") && scalar(&list_files("inst", 1) < 3)) {
	$log->warning() unless $any;
	$any++;
	$log->print("Subdirectory 'inst' contains no files.\n");
    }
    ## Subdirectory 'src' without sources?
    ## <NOTE>
    ## If there is a Makefile (or a Makefile.win), we cannot assume
    ## that source files have the predefined extensions.
    ## </NOTE>
    if( (-d "src") && !( (-f &file_path("src", "Makefile"))
			 || (-f &file_path("src", "Makefile.win")) )) {
	if( !(&list_files_with_type("src", "sources"))) {
	    $log->warning() unless $any;
	    $any++;
	    $log->print("Subdirectory 'src' contains no source files.\n");
	}
    }
    ## Do subdirectories of 'inst' interfere with R package system
    ## subdirectories?
    if((-d "inst")) {
	my @R_system_subdirs =
	    ("Meta", "R", "data", "demo", "exec", "libs",
	     "man", "help", "html", "latex", "R-ex");
	my @bad_dirs = ();
	foreach my $dir (@R_system_subdirs) {
	    push(@bad_dirs, $dir)
		if((-d &file_path("inst", $dir))
		   && &list_files(file_path("inst", $dir)));
	}
	if(scalar(@bad_dirs) > 0) {
	    $log->warning() unless $any;
	    $any++;
	    $log->print(wrap("", "",
			     ("Found the following non-empty",
			      "subdirectories of 'inst' also",
			      "used by R:\n")));
	    $log->print("  " . join(" ", @bad_dirs) . "\n");
	    $log->print(wrap("", "",
			     ("It is recommended not to interfere",
			      "with package subdirectories",
			      "used by R.\n")));
	}
    }
    ## Valid CITATION metadata?
    ## For the time being, only try parsing inst/CITATION ...
    my $file = &file_path("inst", "CITATION");
    if(-f $file) {
	my $Rcmd = "tools:::.check_citation(\"${file}\")";
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=utils");
	@out = grep(!/^\>/, @out);
	if(scalar(@out) > 0) {
	    $log->warning() unless $any;
	    $any++;
	    $log->print("Invalid citation information in 'inst/CITATION':\n");
	    $log->print("  " . join("\n  ", @out) . "\n");
	}
    }
    $log->result("OK") unless $any;

    ## Check R code for syntax errors and for non-ASCII chars which
    ## might be syntax errors in some locales.
    ## We need to do the non-ASCII check first to get the more
    ## specific warning message before an error.

    if(!$is_base_pkg && $haveR) {
	$log->checking("R files for non-ASCII characters");
	my @out = R_runR("tools:::.check_package_ASCII_code('.')",
			 "${R_opts} --slave");
	if(scalar(@out) > 0) {
	    if(defined($description->{"Encoding"})) {
		$log->note();
	    } else {
		$log->warning();
	    }
	    $log->print(wrap("", "",
			     ("Found the following files with",
			      "non-ASCII characters:\n")));
	    $log->print("  " . join("\n  ", @out) . "\n");
	    $log->print(wrap("", "",
			     ("Portable packages must use only ASCII",
			      "characters in their R code,\n",
			      "except perhaps in comments.\n")));
	} else {
	    $log->result("OK");
	}

	$log->checking("R files for syntax errors");
	## we do want to warn on unrecognized escapes here
	my $Rcmd = "options(warn=1);tools:::.check_package_code_syntax(\"R\")";
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(grep(/^Error/, @out)) > 0) {
	    $log->error();
	    $log->print(join("\n", @out) . "\n");
	    exit(1);
	} elsif(scalar(@out) > 0) {
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	} else {
	    $log->result("OK");
	}
    }

    ## Check we can actually load the package

    if($opt_install) {
	$log->checking("whether the package can be loaded");
	my $Rcmd = "library(${pkgname})";
	my @out = R_runR($Rcmd, "${R_opts} --quiet");
	@out = grep(!/^\>/, @out);
	if(scalar(grep(/^Error/, @out)) > 0) {
	    $log->error();
	    $log->print(join("\n", @out) . "\n");
	    $log->print(wrap("", "",
			     ("\nIt looks like this package",
			      "has a loading problem: see the messages",
			      "for details.\n")));
	    exit(1);
	} else {
	    $log->result("OK");
	}
	$log->checking("whether the package can be loaded with stated dependencies");
	my $Rcmd = "library(${pkgname})";
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(grep(/^Error/, @out)) > 0) {
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	    $log->print(wrap("", "",
			     ("\nIt looks like this package",
			      "(or one of its dependent packages)",
			      "has an unstated dependence on a standard",
			      "package.  All dependencies must be",
			      "declared in DESCRIPTION.\n")));
	    $log->print(wrap("", "", @msg_DESCRIPTION));
	} else {
	    $log->result("OK");
	}
    }

    ## and if it has a namespace, that we can load just the namespace

    if($opt_install && -f "${pkgdir}/NAMESPACE") {
	$log->checking("whether the name space can be loaded with stated dependencies");
	my $Rcmd = "loadNamespace(\"${pkgname}\")";
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(grep(/^Error/, @out)) > 0) {
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	    $log->print(wrap("", "",
			     ("\nA namespace must be able to be loaded",
			      "with just the base namespace loaded:",
			      "otherwise if the namespace gets loaded by a",
			      "saved object, the session will be unable",
			      "to start.\n\n",
			      "Probably some imports need to be declared",
			      "in the NAMESPACE file.\n")));
	} else {
	    $log->result("OK");
	}
    }

    if(!$is_base_pkg && $haveR) {
	if($opt_install) {
	    $log->checking("for unstated dependencies in R code");
	    my $Rcmd = "options(warn=1,warnEscapes=FALSE);tools:::.check_packages_used(package=\"${pkgname}\")\n";
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=NULL");
	    @out = grep(!/^\>/, @out);
	    @out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			@out)
		if($R_check_suppress_RandR_message);
	    if(scalar(@out) > 0) {
		$log->warning();
		$log->print(join("\n", @out) . "\n");
		$log->print(wrap("", "", @msg_DESCRIPTION));
	    } else {
		$log->result("OK");
	    }
	} else {
	    ## this needs to read the package code, and will fail on
	    ## syntax errors such as non-ASCII code.
	    $log->checking("for unstated dependencies in R code");
	    my $Rcmd = "options(warn=1,warnEscapes=FALSE);tools:::.check_packages_used(dir=\"${pkgdir}\")\n";
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=NULL");
	    @out = grep(!/^\>/, @out);
	    if(scalar(@out) > 0) {
		$log->warning();
		$log->print(join("\n", @out) . "\n");
		$log->print(wrap("", "", @msg_DESCRIPTION));
	    } else {
		$log->result("OK");
	    }
	}
    }


    ## Check whether methods have all arguments of the corresponding
    ## generic.

    if($haveR) {
	$log->checking("S3 generic/method consistency");

	my @msg_S3_methods =
	  ("See section 'Generic functions and methods'",
	   "of the 'Writing R Extensions' manual.\n");

	my $Rcmd = "options(warn=1,warnEscapes=FALSE)\n";
	$Rcmd .= "options(expressions=1000)\n";
	if($opt_install) {
	    $Rcmd .= "tools::checkS3methods(package = \"${pkgname}\")\n";
	}
	else {
	    $Rcmd .= "tools::checkS3methods(dir = \"${pkgdir}\")\n";
	}

	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
	@out = grep(!/^\>/, @out);
	@out = grep(!/^Xlib: *extension "RANDR" missing on display/,
		    @out)
	    if($R_check_suppress_RandR_message);
	if(scalar(@out) > 0) {
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	    $log->print(wrap("", "", @msg_S3_methods));
	}
	else {
	    $log->result("OK");
	}
    }

    ## Check whether replacement functions have their final argument
    ## named 'value'.

    if($haveR) {
	$log->checking("replacement functions");

	my @msg_replace_funs =
	  ("In R, the argument of a replacement function",
	   "which corresponds to the right hand side",
	   "must be named 'value'.\n");

	my $Rcmd = "options(warn=1,warnEscapes=FALSE)\n";
	if($opt_install) {
	    $Rcmd .= "tools::checkReplaceFuns(package = \"${pkgname}\")\n";
	}
	else {
	    $Rcmd .= "tools::checkReplaceFuns(dir = \"${pkgdir}\")\n";
	}

	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
	@out = grep(!/^\>/, @out);
		    @out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			@out)
		if($R_check_suppress_RandR_message);
	if(scalar(@out) > 0) {
	    ## <NOTE>
	    ## We really want to stop if we find offending replacement
	    ## functions.  But we cannot use error() because output may
	    ## contain warnings ...
	    $log->warning();
	    ## </NOTE>
	    $log->print(join("\n", @out) . "\n");
	    $log->print(wrap("", "", @msg_replace_funs));
	}
	else {
	    $log->result("OK");
	}
    }

    ## Check foreign function calls.

    if($opt_ff_calls && $haveR) {
	$log->checking("foreign function calls");

	my @msg_ff_calls =
	  ("See the chapter 'System and foreign language interfaces'",
	   "of the 'Writing R Extensions' manual.\n");

	my $Rcmd = "options(warn=1,warnEscapes=FALSE)\n";
	if($opt_install) {
	    $Rcmd .= "tools::checkFF(package = \"${pkgname}\")\n";
	}
	else {
	    $Rcmd .= "tools::checkFF(dir = \"${pkgdir}\")\n";
	}

	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
	@out = grep(!/^\>/, @out);
	@out = grep(!/^Xlib: *extension "RANDR" missing on display/,
		    @out)
	    if($R_check_suppress_RandR_message);
	if(scalar(@out) > 0) {
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	    $log->print(wrap("", "", @msg_ff_calls));
	}
	else {
	    $log->result("OK");
	}
    }

    ## Check R code for possible problems, including tests based on LT's
    ## codetools package.

    if($haveR) {
	$log->checking("R code for possible problems");

	my $any;

	if(!$is_base_pkg) {
	    my $Rcmd = "options(warn=1,warnEscapes=FALSE);tools:::.check_package_code_shlib(\"R\")";
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=NULL");
	    @out = grep(!/^\>/, @out);
	    if(scalar(@out) > 0) {
		$log->error();
		$log->print(wrap("", "",
				 "Incorrect (un)loading of package",
				 "shared libraries.\n"));
		$log->print(join("\n", @out) . "\n");
		$log->print(wrap("", "",
				 ("The system-specific extension for",
				  "shared libraries must not be added.\n",
				  "See ?library.dynam.\n")));

		exit(1);
	    }
	}

	if($R_check_use_codetools && $opt_install) {
	    my $Rcmd = "options(warn=1,warnEscapes=FALSE)\n";
	    $Rcmd .= "tools:::.check_code_usage_in_package(package = \"${pkgname}\")\n";
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=");
	    @out = grep(!/^\>/, @out);
	    @out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			@out)
		if($R_check_suppress_RandR_message);
	    if(scalar(@out) > 0) {
		$log->note() unless $any;
		$any++;
		$log->print(join("\n", @out) . "\n");
	    }
	}

	if($R_check_use_codetools) {
	    my $Rcmd = "options(warn=1,warnEscapes=FALSE)\n";
	    if($opt_install) {
		$Rcmd .= "tools:::.check_T_and_F(package = \"${pkgname}\")\n";
	    }
	    else {
		$Rcmd .= "tools:::.check_T_and_F(dir = \"${pkgdir}\")\n";
	    }
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=");
	    @out = grep(!/^\>/, @out);
	    @out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			@out)
		if($R_check_suppress_RandR_message);
	    if(scalar(@out) > 0) {
		$log->note() unless $any;
		$any++;
		$log->print(join("\n", @out) . "\n");
	    }
	}

	## .Internal is intended for base packages
	if((!$is_base_pkg) && $R_check_use_codetools && $R_check_dot_internal) {
	    my $Rcmd = "options(warn=1,warnEscapes=FALSE)\n";
	    if($opt_install) {
		$Rcmd .= "tools:::.check_dotInternal(package = \"${pkgname}\")\n";
	    }
	    else {
		$Rcmd .= "tools:::.check_dotInternal(dir = \"${pkgdir}\")\n";
	    }
	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES=");
	    @out = grep(!/^\>/, @out);
	    @out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			@out)
		if($R_check_suppress_RandR_message);
	    if(scalar(@out) > 0) {
		$log->note() unless $any;
		$any++;
		$log->print(join("\n", @out) . "\n");
	    }
	}

	$log->result("OK") unless $any;
    }

    ## Check R documentation files.

    my @msg_writing_Rd
      = ("See the chapter 'Writing R documentation files'",
	 "in manual 'Writing R Extensions'.\n");

    if(-d "man") {
	$log->checking("Rd files");
	my $minlevel = &R_getenv("_R_CHECK_RD_CHECKRD_MINLEVEL_", "-1");
	my $Rcmd = "options(warn=1)\ntools:::.check_package_parseRd('.', minlevel=$minlevel)\n";
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(@out) > 0) {
	    if(scalar(grep(!/^prepare.*Dropping empty section/, @out)) > 0) {
		$log->warning();
	    } else {
		$log->note();
	    }
	    $log->print(join("\n", @out) . "\n");
	} else {
	    $log->result("OK");
	}

	$log->checking("Rd metadata");
	my $Rcmd = "options(warn=1)\n";
	if($opt_install) {
	    $Rcmd .= "tools:::.check_Rd_metadata(package = \"${pkgname}\")\n";
	}
	else {
	    $Rcmd .= "tools:::.check_Rd_metadata(dir = \"${pkgdir}\")\n";
	}
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(@out) > 0) {
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	}
	else {
	    $log->result("OK");
	}
    }
	    
    ## Check cross-references in R documentation files.

    ## <NOTE>
    ## Installing a package warns about missing links (and hence R CMD
    ## check knows about this too provided an install log is used).
    ## However, under Windows the install-time check verifies the links
    ## against what is available in the default library, which might be
    ## considerably more than what can be assumed to be available.
    ##
    ## The formulations in section "Cross-references" of R-exts are not
    ## quite clear about this, but CRAN policy has for a long time
    ## enforced anchoring links to targets (aliases) from non-base
    ## packages.
    ## </NOTE>

    if($R_check_Rd_xrefs && (-d "man")) {
	$log->checking("Rd cross-references");

	my $Rcmd = "options(warn=1)\n";
	if($opt_install) {
	    $Rcmd .= "tools:::.check_Rd_xrefs(package = \"${pkgname}\")\n";
	}
	else {
	    $Rcmd .= "tools:::.check_Rd_xrefs(dir = \"${pkgdir}\")\n";
	}

	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(@out) > 0) {
	    if(scalar(grep(!/^Package\(s\) unavailable/, @out)) > 0) {
		$log->warning();
	    } else {
		$log->note();
	    }
	    $log->print(join("\n", @out) . "\n");
	}
	else {
	    $log->result("OK");
	}
    }

    ## Check for missing documentation entries.

    if($haveR || (-d "data")) {
	$log->checking("for missing documentation entries");

	my $Rcmd= "options(warn=1,warnEscapes=FALSE)\n";
	if($opt_install) {
	    $Rcmd .= "tools::undoc(package = \"${pkgname}\")\n";
	}
	else {
	    $Rcmd .= "tools::undoc(dir = \"${pkgdir}\")\n";
	}

	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
	my @err = grep(/^Error/, @out);
	@out = grep(!/^\>/, @out);
	@out = grep(!/^Xlib: *extension "RANDR" missing on display/,
		    @out)
	    if($R_check_suppress_RandR_message);
	if(scalar(@err) > 0) {
	    $log->error();
	    $log->print(join("\n", @err) . "\n");
	    exit(1);
	}
	elsif(scalar(@out) > 0) {
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	    my $details;
	    $details = " (including S4 classes and methods)"
	      if(grep(/^Undocumented S4/, @out));
	    $log->print(wrap("", "",
			     ("All user-level objects",
			      "in a package${details} should",
			      "have documentation entries.\n")));
	    $log->print(wrap("", "", @msg_writing_Rd));
	}
	else {
	    $log->result("OK");
	}
    }
    ## Check for code/documentation mismatches.

    if((-d "man")) {
	$log->checking("for code/documentation mismatches");

	if(!$opt_codoc) {
	    $log->result("SKIPPED");
	} else {
	    my $any = 0;

	    ## Check for code/documentation mismatches in functions.
	    if($haveR) {
		my $Rcmd = "options(warn=1,warnEscapes=FALSE)\n";
		if($opt_install) {
		    $Rcmd .= "tools::codoc(package = \"${pkgname}\")\n";
		}
		else {
		    $Rcmd .= "tools::codoc(dir = \"${pkgdir}\")\n";
		}
		my @out = R_runR($Rcmd, "${R_opts} --quiet",
				 "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
		@out = grep(!/^\>/, @out);
		@out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			    @out)
		    if($R_check_suppress_RandR_message);
		if(scalar(@out) > 0) {
		    $any++;
		    $log->warning();
		    $log->print(join("\n", @out) . "\n");
		}
	    }

	    ## Check for code/documentation mismatches in data sets.
	    if($opt_install) {
		my $Rcmd = "options(warn=1,warnEscapes=FALSE)\ntools::codocData(package = \"${pkgname}\")\n";
		my @out = R_runR($Rcmd, "${R_opts} --quiet",
				 "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
		@out = grep(!/^\>/, @out);
		@out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			    @out)
		    if($R_check_suppress_RandR_message);
		if(scalar(@out) > 0) {
		    $log->warning() unless($any);
		    $any++;
		    $log->print(join("\n", @out) . "\n");
		}
	    }

	    ## Check for code/documentation mismatches in S4 classes.
	    if($opt_install && $haveR) {
		my $Rcmd = "options(warn=1,warnEscapes=FALSE)\ntools::codocClasses(package = \"${pkgname}\")\n";
		my @out = R_runR($Rcmd, "${R_opts} --quiet",
				 "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
		@out = grep(!/^\>/, @out);
		@out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			    @out)
		    if($R_check_suppress_RandR_message);
		if(scalar(@out) > 0) {
		    $log->warning() unless($any);
		    $any++;
		    $log->print(join("\n", @out) . "\n");
		}
	    }

	    $log->result("OK") unless($any);

	}
    }

    ## Check Rd files, for consistency of \usage with \arguments (are
    ## all arguments shown in \usage documented in \arguments?) and
    ## aliases (do all functions shown in \usage have an alias?)

    if(-d "man") {
	$log->checking("Rd \\usage sections");

	my $any;

	my @msg_doc_files =
	  ("Functions with \\usage entries",
	   "need to have the appropriate \\alias entries,",
	   "and all their arguments documented.\n",
	   "The \\usage entries must correspond to syntactically",
	   "valid R code.\n");

	my $Rcmd = "options(warn=1)\n";
	if($opt_install) {
	    $Rcmd .= "tools::checkDocFiles(package = \"${pkgname}\")\n";
	}
	else {
	    $Rcmd .= "tools::checkDocFiles(dir = \"${pkgdir}\")\n";
	}

	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
	@out = grep(!/^\>/, @out);
	if(scalar(@out) > 0) {
	    $any++;
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	    $log->print(wrap("", "", @msg_doc_files));
	    $log->print(wrap("", "", @msg_writing_Rd));
	}

	if($R_check_Rd_style && $haveR) {

	    my @msg_doc_style =
		("The \\usage entries for S3 methods should use",
		 "the \\method markup and not their full name.\n");

	    $Rcmd = "options(warn=1)\n";
	    if($opt_install) {
		$Rcmd .= "tools::checkDocStyle(package = \"${pkgname}\")\n";
	    }
	    else {
		$Rcmd .= "tools::checkDocStyle(dir = \"${pkgdir}\")\n";
	    }

	    my @out = R_runR($Rcmd, "${R_opts} --quiet",
			     "R_DEFAULT_PACKAGES='utils,grDevices,graphics,stats'");
	    @out = grep(!/^\>/, @out);
	    @out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			@out)
		if($R_check_suppress_RandR_message);
	    if(scalar(@out) > 0) {
		$log->note() unless($any);
		$any++;
		$log->print(join("\n", @out) . "\n");
		$log->print(wrap("", "", @msg_doc_style));
		$log->print(wrap("", "", @msg_writing_Rd));
	    }
	}

	$log->result("OK") unless($any);
    }

    if(!$is_base_pkg && (-d "data")) {
	$log->checking("data for non-ASCII characters");
	my @out = R_runR("tools:::.check_package_datasets('.')",
			 "${R_opts} --slave");
	@out = grep(!/Loading required package/, @out);
	my @bad = grep(/^Warning:/, @out);
	if(scalar(@out) > 0) {
	    if(scalar(@bad)) {
		$log->warning();
	    } else {
		$log->note();
	    }
	    $log->print("  " . join("\n  ", @out) . "\n");
	    $log->print(wrap("", "",
			     ("Portable packages use only ASCII",
			      "characters in their datasets.\n")));
	} else {
	    $log->result("OK");
	}
    }

    ## Check C/C++/Fortran sources/headers for CRLF line endings.

    ## <FIXME>
    ## Does ISO C really require LF line endings?  (Reference?)
    ## We definitely know that some versions of Solaris cc and f77/f95
    ## will not accept CRLF or CR line endings.
    ## (Sun Studio 12 definitely objects to CR in both C and Fortran).
    ## </FIXME>

    if(!$is_base_pkg && (-d "src")) {
	$log->checking("line endings in C/C++/Fortran sources/headers");
	my @src_files = &list_files_with_type("src", "src_no_CRLF");
	my @bad_files = ();
	foreach my $file (@src_files) {
	    open(FILE, "< $file")
	      or die "Error: cannot open '$file' for reading\n";
	    binmode(FILE);	# for Windows
	    ## with CR line endings we will just get one incomplete line
	    ## so all we can do is look for CR.
	    while(<FILE>) {
		if($_ =~ /\r/) {
		    push(@bad_files, $file);
		    last;
		}
	    }
	    close(FILE);
	}
	if(scalar(@bad_files) > 0) {
	    $log->warning();
	    $log->print("Found the following sources/headers with " .
			"CR or CRLF line endings:\n");
	    $log->print("  " . join("\n  ", @bad_files) . "\n");
	    $log->print("Some Unix compilers require LF line endings.\n");
	}
	else {
	    $log->result("OK");
	}
    }

    ## Check src/Make* for LF line endings, as Sun make does not accept CRLF

    if(!$is_base_pkg && (-d "src")) {
	$log->checking("line endings in Makefiles");
	## .win files are not checked, as CR/CRLF work there
	my @src_files = ("src/Makevars", "src/Makevars.in",
			 "src/Makefile", "src/Makefile.in");
	my @bad_files = ();
	foreach my $file (@src_files) {
	    open(FILE, "< $file") or next;
	    binmode(FILE);	# for Windows
	    ## with CR line endings we will just get one incomplete line
	    ## so all we can do is look for CR.
	    while(<FILE>) {
		if($_ =~ /\r/) {
		    push(@bad_files, $file);
		    last;
		}
	    }
	    close(FILE);
	}
	if(scalar(@bad_files) > 0) {
	    $log->warning();
	    $log->print("Found the following Makefiles with " .
			"CR or CRLF line endings:\n");
	    $log->print("  " . join("\n  ", @bad_files) . "\n");
	    $log->print("Some Unix makes require LF line endings.\n");
	}
	else {
	    $log->result("OK");
	}
    }

    ## Check src/Makevars[.in] for portable compilation flags.

    if((-f &file_path("src", "Makevars.in"))
       || (-f &file_path("src", "Makevars"))) {
	$log->checking("for portable compilation flags in Makevars");
	my $Rcmd = "tools:::.check_make_vars(\"src\")\n";
	my @out = R_runR($Rcmd, "${R_opts} --quiet",
			 "R_DEFAULT_PACKAGES=NULL");
	@out = grep(!/^\>/, @out);
	if(scalar(@out) > 0) {
	    $log->warning();
	    $log->print(join("\n", @out) . "\n");
	}
	else {
	    $log->result("OK");
	}
    }

    ## check src/Makevar*, src/Makefile* for correct use of BLAS_LIBS
    ## FLIBS is not needed on Windows, at least currently (as it is
    ## statically linked).
    if(-d "src") {
	my $any;
	$log->checking("for portable use of \$BLAS_LIBS");
	my @makefiles;
	push(@makefiles, &file_path("src", "Makevars"))
	    if (-f &file_path("src", "Makevars"));
	push(@makefiles, &file_path("src", "Makevars.in"))
	    if (-f &file_path("src", "Makevars.in"));
	push(@makefiles, &file_path("src", "Makefile"))
	    if (-f &file_path("src", "Makefile"));
	push(@makefiles, &file_path("src", "Makefile.in"))
	    if (-f &file_path("src", "Makefile.in"));
	foreach my $f (@makefiles) {
	    open(FILE, "< $f")
		or die("Error: cannot open file '$f' for reading\n");
	    while(<FILE>) {
		if(/PKG_LIBS/ && /\$[\{\(]{0,1}BLAS_LIBS/ && !/FLIBS/) {
		    $log->warning() unless $any;
		    $any++;
		    chomp;
		    s/\r$//;  # some packages have CRLF terminators
		    $log->print("apparently missing \$(FLIBS) in '".$_."'\n");
		}
	    }
	    close(FILE);
	}
	$log->result("OK") unless($any);
    }

    chdir($pkgoutdir);

    ## Run the examples.
    ## This setting applies to vignettes below too.
    ${R_opts} = ${R_opts}." -d valgrind" if $opt_use_valgrind;

    ## this will be skipped if installation was
    if( -d &file_path($library, $pkgname, "help") ) {
	$log->checking("examples");
	if(!$opt_examples) {
	    $log->result("SKIPPED");
	} else {
	    my $pkgtopdir = &file_path($library, $pkgname);
	    $cmd = join(" ",
			("(echo 'tools:::.createExdotR(\"${pkgname}\", \"${pkgtopdir}\", silent = TRUE)'",
			 "| LC_ALL=C",
			 &shell_quote_file_path(${R::Vars::R_EXE}),
			 "--vanilla --slave)"
			));
	    if(R_system($cmd)) {
		$log->error();
		$log->print("Running massageExamples to create " .
			    "'${pkgname}-Ex.R' failed.\n");
		exit(1);
	    }

	    ## It ran, but did it create any examples?
	    if(-f "${pkgname}-Ex.R") {
		my $enc = "";
		if(defined($description->{"Encoding"})) {
		    $enc = "--encoding " . $description->{"Encoding"};
		    if ($is_ascii) {
			print "\n* WARNING: ",
			"checking a package with encoding '",
			$description->{"Encoding"},
			"' in an ASCII locale.\n";
		    }
		}
		## might be diff-ing results against tests/Examples later
		if($opt_use_gct) {
		    $cmd = join(" ",
				("(echo 'gctorture(TRUE)';",
				 "cat ${pkgname}-Ex.R) |",
				 "LANGUAGE=en",
				 &shell_quote_file_path(${R::Vars::R_EXE}),
				 "${R_opts}", $enc,
				 "> ${pkgname}-Ex.Rout 2>&1"));
		} else {
		    $cmd = join(" ",
				("LANGUAGE=en",
				 &shell_quote_file_path(${R::Vars::R_EXE}),
				 "${R_opts}", $enc,
				 "< ${pkgname}-Ex.R",
				 "> ${pkgname}-Ex.Rout 2>&1"));
		}
		if(R_system($cmd)) {
		    $log->error();
		    $log->print("Running examples in '${pkgname}-Ex.R' failed.\n");
		    ## Try to spot the offending example right away.
		    my $txt = join("\n", &read_lines("${pkgname}-Ex.Rout"));
		    ## Look for the header section anchored by a subsequent call
		    ## to flush(): needs to be kept in sync with the code in
		    ## massageExamples (in testing.R).  Should perhaps also be more
		    ## defensive about the prompt ...
		    my @chunks = split(/(> \#\#\# \* [^\n]+\n> \n> flush)/, $txt);
		    if(scalar(@chunks) > 2) {
			$log->print("The error most likely occurred in:\n\n");
			$log->print($chunks[$#chunks - 1]);
			$log->print($chunks[$#chunks] . "\n");
		    }
		    exit(1);
		}
		## Look at the output from running the examples.  For the time
		## being, report warnings about use of deprecated functions, as
		## the next release will make them defunct and hence using them
		## an error.  Also warn about loading defunct base package stubs,
		## as load special-casing for these will be removed eventually.
		my @lines = &read_lines("${pkgname}-Ex.Rout");
		my $any;
		my @bad_lines;
		@bad_lines = grep(/^Warning: .*is deprecated.$/, @lines);
		if(scalar(@bad_lines) > 0) {
		    $log->warning();
		    $any++;
		    $log->print("Found the following significant warnings:\n");
		    $log->print("  " . join("\n  ", @bad_lines) . "\n");
		    $log->print(wrap("", "",
				     ("Deprecated functions may be defunct as",
				      "soon as of the next release of R.\n",
				      "See ?Deprecated.\n")));
		}
		$log->result("OK") unless($any);

		## Try to compare results from running the examples to a saved
		## previous version.
		my $Rex_out_save =
		    &file_path($pkgdir, "tests", "Examples",
			       "${pkgname}-Ex.Rout.save");
		if(-f $Rex_out_save) {
		    $log->checking("differences from '${pkgname}-Ex.Rout' to '${pkgname}-Ex.Rout.save'");
		    my @out = R_runR("invisible(tools::Rdiff('${pkgname}-Ex.Rout', '${Rex_out_save}',TRUE,TRUE))", "--slave --vanilla");
		    if(scalar(@out) > 0) {
			$log->print("\n" . join("\n", @out) . "\n");
		    }
		    $log->result("OK");
		}
	    } else {
		## no examples found
		$log->result("NONE");
	    }
	}
    } elsif(-d &file_path($pkgdir, "man")) {
	$log->checking("examples");
	$log->result("SKIPPED");
    }

    ## Run the package-specific tests.

    if((-d &file_path($pkgdir, "tests"))
       && &list_files(&file_path($pkgdir, "tests"))) {
	$log->checking("tests");
	if ($opt_install && $opt_tests) {
	    my $testsrcdir = &file_path($pkgdir, "tests");
	    my $testdir = &file_path($pkgoutdir, "tests");
	    if(!(-d $testdir)) {
		mkdir($testdir, 0755)
		    or die "Error: cannot create directory '$testdir'\n";
	    }
	    chdir($testdir);
	    dircopy($testsrcdir, ".");
	    if($opt_use_valgrind) {
		if($opt_use_gct) {
		    $extra = "use_gct = TRUE, use_valgrind = TRUE";
		} else {
		    $extra = "use_valgrind = TRUE";
		}
	    } else {
		if($opt_use_gct) {
		    $extra = "use_gct = TRUE";
		} else {
		    $extra = "";
		}
	    }
	    $cmd = join(" ",
			("(echo 'tools:::.runPackageTestsR($extra)' |",
			 &shell_quote_file_path(${R::Vars::R_EXE}),
			 "--vanilla --slave)") );
	    if(R_system($cmd)) {
		$log->error();
		## Don't just fail: try to log where the problem occurred.
		## First, find the test which failed.
		my @bad_files = &list_files_with_exts($testdir,
						      "Rout.fail");
		if(scalar(@bad_files) > 0) {
		    ## Maybe there was an error without a failing test.
		    my $file = $bad_files[0];
		    ## Read in output from the failed test and retain at
		    ## most the last 13 lines (13? why not?).
		    my @lines = &read_lines($file);
		    my $to = $#{lines};
		    my $from = ($to >= 12) ? ($to - 12) : 0;
		    @lines = @lines[$from..$to];
		    $file =~ s/out\.fail//;
		    $file = &file_path("tests", basename($file));
		    $log->print("Running the tests in '$file' failed.\n");
		    $log->print("Last 13 lines of output:\n");
		    $log->print("  " . join("\n  ", @lines) . "\n");
		}
		exit(1);
	    }
	    chdir($pkgoutdir);
	    $log->result("OK");
	} else {
	    $log->result("SKIPPED");
	}
    }

    ## Check package vignettes.

    chdir($pkgoutdir);

    my $vignette_dir = &file_path($pkgdir, "inst", "doc");
    if((-d $vignette_dir)
       && &list_files_with_type($vignette_dir, "vignette")) {
	$log->checking(join(" ",
			    ("package vignettes in",
			     &sQuote(&file_path("inst", "doc")))));
	my $any = 0;

	## Do PDFs exist for all package vignettes?
	my @vignette_files =
	  &list_files_with_type($vignette_dir, "vignette");
	my @bad_vignettes = ();
	foreach my $file (@vignette_files) {
	    my $pdf_file = $file;
	    $pdf_file =~ s/\.[[:alpha:]]+$/.pdf/;
	    push(@bad_vignettes, $file) unless(-f $pdf_file);
	}
	## A base source package may not have PDFs to avoid blowing out
	## the distribution size.  *Note* that it is assumed that base
	## packages can be woven (i.e., that they only contain
	## "standard" LaTeX).
	if(!$is_base_pkg && scalar(@bad_vignettes) > 0) {
	    $log->warning();
	    $any++;
	    $log->print("Package vignettes without corresponding PDF:\n");
	    $log->print("  " . join("\n  ", @bad_vignettes) . "\n");
	}

	## Can we run the code in the vignettes?
	if($opt_install && $opt_vignettes) {
	    ## copy the inst directory to check directory
	    ## so we can work in place.
	    mkpath("inst/doc");
	    dircopy($vignette_dir, "inst/doc");
	    if ($R_check_latex_vignettes) {
		$R_check_latex_vignettes = 0
		    if R_system("texi2dvi --version > /dev/null");
	    }

	    my $Rcmd = "options(warn=1)\nlibrary(tools)\n";
	    ## Should checking the vignettes assume the system default
	    ## packages, or just base?
	    $Rcmd .= "checkVignettes(dir = '$pkgoutdir', workdir='src'";
	    $Rcmd .= ", weave = FALSE" unless $R_check_weave_vignettes;
	    $Rcmd .= ", tangle = FALSE" if $R_check_weave_vignettes;
	    $Rcmd .= ", latex = TRUE" if $R_check_latex_vignettes;
	    $Rcmd .= ")\n";
	    my @out = R_runR($Rcmd, "${R_opts} --quiet");
	    ## Vignette could redefine the prompt, e.g. to 'R>' ...
	    @out = grep(!/^[[:alnum:]]*\>/, @out);
	    ## Or to "empty".  As empty lines in the output will most
	    ## likely not indicate a problem ...
	    @out = grep(!/^[[:space:]]*$/, @out);
	    @out = grep(!/^Xlib: *extension "RANDR" missing on display/,
			@out)
		if($R_check_suppress_RandR_message);
	    if(scalar(@out) > 0) {
		if(grep(/^\*\*\* (Tangle|Weave|Source) Errors \*\*\*$/,
			@out)) {
		    $log->warning() unless($any);
		} else {
		    $log->note() unless($any);
		}
		$any++;
		$log->print(join("\n", @out) . "\n");
	    }
	} else {
	    $any++;
	    $log->result("SKIPPED");
	}

	$log->result("OK") unless($any);
    }
}


## NB Bundles should have a bundle manual, not one for each package,
## so this is no longer part of check_pkg.
sub check_pkg_manual {
    my ($pkgdir, $pkgname, $log) = @_;
    ## Run LaTeX on the manual, if there are man pages
    ## If it is installed with docs there is a 'help' dir
    ## and for a source package, there is a 'man' dir
    if ( (-d &file_path($pkgdir, "help")) ||
	 (-d &file_path($pkgdir, "man")) ) {
	if($opt_latex && $HAVE_LATEX) {
	    $topdir = $pkgdir;
	    my $Rd2dvi_opts = "--batch --no-preview";
	    my $fmt;
	    if($HAVE_PDFLATEX) {
		$Rd2dvi_opts = $Rd2dvi_opts . " --pdf";
		$fmt = "pdf";
	    } else {
		$fmt = "dvi";
	    }
	    $log->checking("\U$fmt\E version of manual");
	    my $cmd0, $cmd;
	    my $build_dir = R_tempfile("Rd2dvi");
	    if($WINDOWS) {
		$cmd0 = "Rcmd.exe";
	    } else {
		$cmd0 = &shell_quote_file_path("${R::Vars::R_EXE}");
		$cmd0 = "$cmd0 CMD";
	    }
	    $cmd = join(" ",
			($cmd0, "Rd2dvi $Rd2dvi_opts",
			 "--build-dir=${build_dir} --no-clean",
			 "-o ${pkgname}-manual.${fmt} > Rdlatex.log 2>&1",
			 "$topdir"));
	    my $res = R_system($cmd);
	    my $latex_log = &file_path($build_dir, "Rd2.log");
	    if(-f $latex_log) {copy($latex_log, "${pkgname}-manual.log");}
	    if($res == 2816) { ## 11*256
		$log->error();
		$log->print("Rd conversion errors:\n");
		@lines = &read_lines("Rdlatex.log");
		foreach my $line (@lines) {
		    $log->print($line . "\n") unless $line =~ /^(Hmm|Execution)/;
		}
		rmtree($build_dir);
		exit(1);
	    } elsif($res) {
		my $latex_file = &file_path($build_dir, "Rd2.tex");
		if(-f $latex_file) {copy($latex_file, "${pkgname}-manual.tex");}
		$log->warning();
		$log->print("LaTeX errors when creating \U$fmt\E version.\n");
		$log->print("This typically indicates Rd problems.\n");
		## If possible, indicate the problems found.
		my $latex_log = &file_path($build_dir, "Rd2.log");
		## Note that Rd2dvi works on 'Rd2.tex'.
		if(-f $latex_log) {
		    my $Rcmd = "writeLines(tools:::.get_LaTeX_errors_from_log_file(\"${latex_log}\"))";
		    my @out = R_runR($Rcmd, "${R_opts} --quiet",
				     "R_DEFAULT_PACKAGES=NULL");
		    @out = grep(!/^\>/, @out);
		    if(scalar(@out) > 0) {
			$log->print("LaTeX errors found:\n");
			$log->print(join("\n", @out) . "\n");
		    }
		}
		rmtree($build_dir);
		$log->checking("\U$fmt\E version of manual without index");
		$cmd = join(" ",
			    ($cmd0, "Rd2dvi $Rd2dvi_opts",
			     "--build-dir=${build_dir} --no-clean --no-index",
			     "-o ${pkgname}-manual.${fmt} >/dev/null 2>&1",
			     "$topdir"));
		if(R_system($cmd)) {
		    $log->error();
		    if(-f $latex_log) {
			copy($latex_log, "${pkgname}-manual.log");
		    } else {
			## No log file and thus no chance to find out
			## what went wrong.  Hence, re-run without
			## redirecting stdout/stderr and hope that this
			## gives the same problem ...
			## Ideally, we would have a version of
			## R_system() similar to R_run_R() which returns 
			## both the exit status and stdout/stderr.
			$log->print("LaTeX error when running command:\n");
			$log->print(wrap("  ", "    ", ($cmd)) . "\n");
			$log->print("Re-running with no redirection of stdout/stderr.\n");
			$cmd = join(" ",
				    ($cmd0, "Rd2dvi $Rd2dvi_opts",
				     "--build-dir=${build_dir} --no-clean --no-index",
				     "-o ${pkgname}-manual.${fmt} $topdir"));
			R_system($cmd);
		    }
		    rmtree($build_dir);
		    exit(1);
		}
	    } else {
		rmtree($build_dir);
		$log->result("OK");
	    }
	}
    }
}



sub usage {
    print <<END;
Usage: R CMD $name [options] pkgs

Check R packages from package sources, which can be directories or
package 'tar' archives with extension '.tar.gz', '.tar.bz2' or '.tgz'.

A variety of diagnostic checks on directory structure, index and
control files are performed.  The package is installed into the log
directory (which includes the translation of all Rd files into several
formats), and the Rd files are tested by LaTeX (if available).  All
examples and tests provided by the package are tested to see if they
run successfully.

Options:
  -h, --help            print short help message and exit
  -v, --version         print version info and exit
  -l, --library=LIB     library directory used for test installation
			of packages (default is outdir)
  -o, --outdir=DIR      directory used for logfiles, R output, etc.
			(default is 'pkg.Rcheck' in current directory,
			where 'pkg' is the name of the package checked)
      --no-clean        do not clean outdir before using it
      --no-codoc        do not check for code/documentation mismatches
      --no-examples     do not run the examples in the Rd files
      --no-install      skip installation and associated tests
      --no-tests        do not run code in tests subdirectory
      --no-vignettes    do not check vignettes in Sweave format
      --no-latex        do not run LaTeX on help files
      --use-gct         use 'gctorture(TRUE)' when running examples/tests
      --use-valgrind    use 'valgrind' when running examples/tests/vignettes
      --install-args=	command-line args to be passed to INSTALL
      --check-subdirs=default|yes|no
			run checks on the package subdirectories
			(default is yes for a tarball, no otherwise)
      --rcfile=FILE     read configuration values from FILE

By default, all test sections are turned on.

Report bugs to <r-bugs\@r-project.org>.
END
    exit 0;
}