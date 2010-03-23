package App::perlbrew;
use strict;

our $VERSION = "0.01";

local $\ = "\n";

my $ROOT = "$ENV{HOME}/perl5/perlbrew";

sub run_command {
    my (undef, $x, @args) = @_;
    my $self = bless {}, __PACKAGE__;

    $x ||= "help";
    my $s = $self->can("run_command_$x") or die "Unknow command: `$x`. Typo?\n";
    $self->$s(@args);
}

sub run_command_help {
    print <<HELP;

Usage:

    perlbrew init
    perlbrew install perl-5.11.1
    perlbrew installed
    perlbrew switch perl-5.11.1

HELP
}

sub run_command_init {
    require File::Path;
    File::Path::make_path(
        "$ROOT/perls",
        "$ROOT/dists",
        "$ROOT/build",
        "$ROOT/etc",
        "$ROOT/bin"
    );

    system <<RC;
echo 'export PATH=$ROOT/bin:$ROOT/perls/current/bin:\${PATH}' > $ROOT/etc/bashrc
echo 'setenv PATH $ROOT/bin:$ROOT/perls/current/bin:\$PATH' > $ROOT/etc/cshrc
RC

    my($shrc, $yourshrc);
    if ($ENV{SHELL} =~ /(t?csh)/) {
        $shrc = 'cshrc';
        $yourshrc = $1 . "rc";
    } else {
        $shrc = $yourshrc = 'bashrc';
    }

    print <<INSTRUCTION;
Perlbrew environment initiated, required directories are created under

    $ROOT

Well-done! Congradulations! Please add the following line to the end
of your ~/.${yourshrc}

    source $ROOT/etc/${shrc}

After that, exit this shell, start a new one, and install some fresh
perls:

    perlbrew install perl-5.12.0-RC0
    perlbrew install perl-5.10.1

For further instructions, simply run:

    perlbrew

The default help messages will popup an tell you what to do!

Enjoy perlbrew at \$HOME!!
INSTRUCTION

}

sub run_command_install {
    my ($self, $dist) = @_;

    unless ($dist) {
        require File::Spec;
        require File::Path;
        require File::Copy;

        my $executable = $0;

        unless (File::Spec->file_name_is_absolute($executable)) {
            $executable = File::Spec->rel2abs($executable);
        }

        my $target = File::Spec->catfile($ROOT, "bin", "perlbrew");
        if ($executable eq $target) {
            print "You are already running the installed perlbrew:\n\n    $executable\n";
            exit;
        }

        File::Path::make_path("$ROOT/bin");
        File::Copy::copy($executable, $target);
        chmod(0755, $target);

        print <<HELP;
The perlbrew is installed as:

    $target

You may trash the downloaded $executable from now on.

Next, if this is the first time you run perlbrew installation, run:

    $target init

And follow the instruction on screen.
HELP
        return;
    }

    my ($dist_name, $dist_version) = $dist =~ m/^(.*)-([\d.]+)(?:-RC\d+)?$/;
    if ($dist_name eq 'perl') {
        require HTTP::Lite;

        my $http_get = sub {
            my ($url, $cb) = @_;
            my $ua = HTTP::Lite->new;

            my $loc = $url;
            my $status = $ua->request($loc) or die "Fail to get $loc";

            my $redir_count = 0;
            while ($status == 302 || $status == 301) {
                last if $redir_count++ > 5;
                for ($ua->headers_array) {
                    /Location: (\S+)/ and $loc = $1, last;
                }
                $loc or last;
                $status = $ua->request($loc) or die "Fail to get $loc";
            }
            if ($cb) {
                return $cb->($ua->body);
            }
            return $ua->body;
        };

        my $ua = HTTP::Lite->new;

        print "Fetching $dist...\n";

        my $html = $http_get->("http://search.cpan.org/dist/$dist");

        my ($dist_path, $dist_tarball) = $html =~ m[<a href="(/CPAN/authors/id/.+/(${dist}.tar.(gz|bz2)))">Download</a>];

        print "As ${ROOT}/dists/${dist_tarball}\n";
        print "Grab: http://search.cpan.org${dist_path}\n";

        $http_get->(
            "http://search.cpan.org${dist_path}",
            sub {
                my ($body) = @_;
                open my $BALL, "> ${ROOT}/dists/${dist_tarball}";
                print $BALL $body;
                close $BALL;
            }
        );

        my $usedevel = $dist_version =~ /5\.11/ ? "-Dusedevel" : "";
        print "Installing $dist...\n";

        my $tarx = "tar " . ($dist_tarball =~ /bz2/ ? "xjf" : "xzf");
        system(join ";",
            "cd $ROOT/build",
            "$tarx $ROOT/dists/${dist_tarball}",
            "cd $dist",
            "rm -f config.sh Policy.sh",
            "sh Configure -de -Dprefix=$ROOT/perls/$dist ${usedevel}",
            "make",
            "make test && make install"
        );
    }
}

sub run_command_installed {
    my $self = shift;
    my $current = readlink("$ROOT/perls/current");
    for (<$ROOT/perls/perl-*>) {
        my ($name) = $_ =~ m/(perl-.+)$/;
        print $name, ($name eq $current ? '(*)' : ''), "\n";
    }
}

sub run_command_switch {
    my ($self, $dist) = @_;
    die "${dist} is not installed\n" unless -d "$ROOT/perls/${dist}";
    my ($dist_name, $dist_version) = $dist =~ m/^(.*)-([\d.]+)(?:-RC\d+)?$/;
    unlink "$ROOT/perls/current";
    system "cd $ROOT/perls; ln -s $dist current";
    for my $executable (<$ROOT/perls/current/bin/*${dist_version}>) {
        my ($name) = $executable =~ m/bin\/(.+)${dist_version}/;
        system("ln -fs $executable $ROOT/bin/${name}");
    }
}

1;

__END__

=head1 NAME

perlbrew - Perl Environment manager.

=head1 INSTALLATION

The quickest way to install this is to copy and paste these lines

    curl -LO http://xrl.us/perlbrew
    chmod +x perlbrew
    ./perlbrew install

After that, C<perlbrew> installs itself to C<~/perl5/perlbrew/bin>,
and you should follow the instruction to setup your C<.bashrc> or
C<.cshrc> to put it in your PATH.

=head1 SYNOPSIS

    # Initialize
    perlbrew init

    # Install some Perls
    perlbrew install perl-5.8.1
    perlbrew install perl-5.11.5

    # See what were installed
    perlbrew installed

    # Switch perl in the $PATH
    perlbrew switch perl-5.11.5
    perl -v

    perlbrew switch perl-5.8.1
    perl -v

=head1 AUTHOR

Kang-min Liu  C<< <gugod@gugod.org> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2010, Kang-min Liu C<< <gugod@gugod.org> >>.

This is free software, licensed under:

    The MIT (X11) License

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.