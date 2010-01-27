package Module::Install::Catalyst;

use strict;

our @ISA;
require Module::Install::Base;
@ISA = qw/Module::Install::Base/;

use File::Find;
use FindBin;
use File::Copy::Recursive 'rcopy';
use File::Spec ();
use Getopt::Long qw(GetOptionsFromString :config no_ignore_case);
use Data::Dumper;

my $SAFETY = 0;

our @IGNORE =
  qw/Build Build.PL Changes MANIFEST META.yml Makefile.PL Makefile README
  _build blib lib script t inc .*\.svn \.git _darcs \.bzr \.hg
  debian build-stamp install-stamp configure-stamp/;
our @CLASSES   = ();
our $ENGINE    = 'CGI';
our $SCRIPT    = '';
our $USAGE     = '';
our %PAROPTS   = ();

=head1 NAME

  Module::Install::Catalyst - Module::Install extension for Catalyst

=head1 SYNOPSIS

  use inc::Module::Install;

  name 'MyApp';
  all_from 'lib/MyApp.pm';

  requires 'Catalyst::Runtime' => '5.7014';

  catalyst_ignore('.*temp');
  catalyst_ignore('.*tmp');
  catalyst;
  WriteAll;

=head1 DESCRIPTION

L<Module::Install> extension for Catalyst.

=head1 METHODS

=head2 catalyst

Calls L<catalyst_files> and L<catalyst_par>. Should be the last catalyst*
command called in C<Makefile.PL>.

=cut

sub catalyst {
    my $self = shift;
    print <<EOF;
*** Module::Install::Catalyst
EOF
    $self->catalyst_files;
    $self->catalyst_par;
    print <<EOF;
*** Module::Install::Catalyst finished.
EOF
}

=head2 catalyst_files

Collect a list of all files a Catalyst application consists of and copy it
inside the blib/lib/ directory. Files and directories that match the modules
ignore list are excluded (see L<catalyst_ignore> and L<catalyst_ignore_all>).

=cut

sub catalyst_files {
    my $self = shift;

    chdir $FindBin::Bin;

    my @files;
    opendir CATDIR, '.';
  CATFILES: for my $name ( readdir CATDIR ) {
        for my $ignore (@IGNORE) {
            next CATFILES if $name =~ /^$ignore$/;
            next CATFILES if $name !~ /\w/;
        }
        push @files, $name;
    }
    closedir CATDIR;
    my @path = split '-', $self->name;
    for my $orig (@files) {
        my $path = File::Spec->catdir( 'blib', 'lib', @path, $orig );
        rcopy( $orig, $path );
    }
}

=head2 catalyst_ignore_all(\@ignore)

This function replaces the built-in default ignore list with the given list.

=cut

sub catalyst_ignore_all {
    my ( $self, $ignore ) = @_;
    @IGNORE = @$ignore;
}

=head2 catalyst_ignore(\@ignore)

Add a regexp to the list of ignored patterns. Can be called multiple times.

=cut

sub catalyst_ignore {
    my ( $self, @ignore ) = @_;
    push @IGNORE, @ignore;
}

=head2 catalyst_par($name)

=cut

# Workaround for a namespace conflict
sub catalyst_par {
    my ( $self, $par ) = @_;
    $par ||= '';
    return if $SAFETY;
    $SAFETY++;
    my $name  = $self->name;
    my $usage = $USAGE;
    $usage =~ s/"/\\"/g;
    my $class_string = join "', '", @CLASSES;
    $class_string = "'$class_string'" if $class_string;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Pad = ' ';
    my $paropts_string = Dumper(\%PAROPTS) || "{ }";
    $self->postamble(<<EOF);
catalyst_par :: all
\t\$(NOECHO) \$(PERL) -Ilib -Minc::Module::Install -MModule::Install::Catalyst -e"Catalyst::Module::Install::_catalyst_par( '$par', '$name', { CLASSES => [$class_string], PAROPTS => $paropts_string, ENGINE => '$ENGINE', SCRIPT => '$SCRIPT', USAGE => q#$usage# } )"
EOF
    print <<EOF;
Please run "make catalyst_par" to create the PAR package!
EOF
}

=head2 catalyst_par_core($core)

=cut

sub catalyst_par_core {
    my ( $self, $core ) = @_;
    $core ? ( $PAROPTS{'B'} = $core ) : $PAROPTS{'B'}++;
}

=head2 catalyst_par_classes(@clases)

=cut

sub catalyst_par_classes {
    my ( $self, @classes ) = @_;
    push @CLASSES, @classes;
}

=head2 catalyst_par_engine($engine)

=cut

sub catalyst_par_engine {
    my ( $self, $engine ) = @_;
    $ENGINE = $engine;
}

=head2 catalyst_par_multiarch($multiarch)

=cut

sub catalyst_par_multiarch {
    my ( $self, $multiarch ) = @_;
    $multiarch ? ( $PAROPTS{'m'} = $multiarch ) : $PAROPTS{'m'}++;
}

=head2 catalyst_par_options($optstring)

This command can be used in Makefile.PL to customise the PAR creation process.
The parameter "$optstring" contains a string with arguments in identical syntax
as arguments of B<pp> command from L<PAR::Packer> package.

Example:

    # part of your Makefile.PL

    catalyst_par_options("--verbose=2 -f Bleach -z 9");
    # verbose mode; use filter 'Bleach'; zip with compression level 9
    catalyst;

Note1: There is no reason to use catalyst_par_options() command multiple times
as you can spacify in "$optstring" as many options as you want. Still, it
is supported to call catalyst_par_options() more than once. In that case the
specified options are merged (collisions are handled on principle "later wins").
BEWARE: you are discouraged from using parameters -a -A -X -f -F -I -l -M in
multiple catalyst_par_options() as they are not merged but replaced as you would
expected.

Note2: By default the options "-x -p -o=<appname>.par" are set and option "-n"
is unset. This default always overrides whatever you specify by
catalyst_par_options().

=cut

sub catalyst_par_options {
    my ( $self, $optstring ) = @_;
    my %o = ();
    eval "use PAR::Packer ()";
    if ($@) {
        warn "WARNING: catalyst_par_options ignored - you need PAR::Packer\n"
    }
    else {
        GetOptionsFromString($optstring, \%o, PAR::Packer->options);
        %PAROPTS = ( %PAROPTS, %o);
    }	
}

=head2 catalyst_par_script($script)

=cut

sub catalyst_par_script {
    my ( $self, $script ) = @_;
    $SCRIPT = $script;
}

=head2 catalyst_par_usage($usage)

=cut

sub catalyst_par_usage {
    my ( $self, $usage ) = @_;
    $USAGE = $usage;
}

package Catalyst::Module::Install;

use strict;
use FindBin;
use File::Copy::Recursive 'rmove';
use File::Spec ();

sub _catalyst_par {
    my ( $par, $class_name, $opts ) = @_;

    my $ENGINE    = $opts->{ENGINE};
    my $CLASSES   = $opts->{CLASSES} || [];
    my $USAGE     = $opts->{USAGE};
    my $SCRIPT    = $opts->{SCRIPT};
    my $PAROPTS   = $opts->{PAROPTS};

    my $name = $class_name;
    $name =~ s/::/_/g;
    $name = lc $name;
    $par ||= "$name.par";
    my $engine = $ENGINE || 'CGI';

    # Check for PAR
    eval "use PAR ()";
    die "Please install PAR\n" if $@;
    eval "use PAR::Packer ()";
    die "Please install PAR::Packer\n" if $@;
    eval "use App::Packer::PAR ()";
    die "Please install App::Packer::PAR\n" if $@;
    eval "use Module::ScanDeps ()";
    die "Please install Module::ScanDeps\n" if $@;

    my $root = $FindBin::Bin;
    $class_name =~ s/-/::/g;
    my $path = File::Spec->catfile( 'blib', 'lib', split( '::', $class_name ) );
    $path .= '.pm';
    unless ( -f $path ) {
        print qq/Not writing PAR, "$path" doesn't exist\n/;
        return 0;
    }
    print qq/Writing PAR "$par"\n/;
    chdir File::Spec->catdir( $root, 'blib' );

    my $par_pl = 'par.pl';
    unlink $par_pl;

    my $version = $Catalyst::VERSION;
    my $class   = $class_name;

    my $classes = '';
    $classes .= "    require $_;\n" for @$CLASSES;

    unlink $par_pl;

    my $usage = $USAGE || <<"EOF";
Usage:
    [parl] $name\[.par] [script] [arguments]

  Examples:
    parl $name.par $name\_server.pl -r
    myapp $name\_cgi.pl
EOF

    my $script   = $SCRIPT;
    my $tmp_file = IO::File->new("> $par_pl ");
    print $tmp_file <<"EOF";
if ( \$ENV{PAR_PROGNAME} ) {
    my \$zip = \$PAR::LibCache{\$ENV{PAR_PROGNAME}}
        || Archive::Zip->new(__FILE__);
    my \$script = '$script';
    \$ARGV[0] ||= \$script if \$script;
    if ( ( \@ARGV == 0 ) || ( \$ARGV[0] eq '-h' ) || ( \$ARGV[0] eq '-help' )) {
        my \@members = \$zip->membersMatching('.*script/.*\.pl');
        my \$list = "  Available scripts:\\n";
        for my \$member ( \@members ) {
            my \$name = \$member->fileName;
            \$name =~ /(\\w+\\.pl)\$/;
            \$name = \$1;
            next if \$name =~ /^main\.pl\$/;
            next if \$name =~ /^par\.pl\$/;
            \$list .= "    \$name\\n";
        }
        die <<"END";
$usage
\$list
END
    }
    my \$file = shift \@ARGV;
    \$file =~ s/^.*[\\/\\\\]//;
    \$file =~ s/\\.[^.]*\$//i;
    my \$member = eval { \$zip->memberNamed("./script/\$file.pl") };
    die qq/Can't open perl script "\$file"\n/ unless \$member;
    PAR::_run_member( \$member, 1 );
}
else {
    require lib;
    import lib 'lib';
    \$ENV{CATALYST_ENGINE} = '$engine';
    require $class;
    import $class;
    require Catalyst::Helper;
    require Catalyst::Test;
    require Catalyst::Engine::HTTP;
    require Catalyst::Engine::CGI;
    require Catalyst::Controller;
    require Catalyst::Model;
    require Catalyst::View;
    require Getopt::Long;
    require Pod::Usage;
    require Pod::Text;
    $classes
}
EOF
    $tmp_file->close;

    # Create package
    local $SIG{__WARN__} = sub { };
    open my $olderr, '>&STDERR';
    open STDERR, '>', File::Spec->devnull;
    my %opt = (
        %{$PAROPTS},
        # take user defined options first and override them with harcoded defaults
        'x' => 1,
        'n' => 0,
        'o' => $par,
        'p' => 1,
    );
    # do not replace the whole $opt{'a'} array; just push required default value
    push @{$opt{'a'}}, grep( !/par.pl/, glob '.' );

    App::Packer::PAR->new(
        frontend  => 'Module::ScanDeps',
        backend   => 'PAR::Packer',
        frontopts => \%opt,
        backopts  => \%opt,
        args      => ['par.pl'],
    )->go;

    open STDERR, '>&', $olderr;

    unlink $par_pl;
    chdir $root;
    rmove( File::Spec->catfile( 'blib', $par ), $par );
    return 1;
}

=head1 AUTHORS

Catalyst Contributors, see Catalyst.pm

=head1 LICENSE

This library is free software. You can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
