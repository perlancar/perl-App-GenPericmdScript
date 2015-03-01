package App::GenPericmdScript;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Data::Dump qw(dump);
use File::Which;

use Exporter qw(import);
our @EXPORT_OK = qw(gen_perinci_cmdline_script);

our %SPEC;

sub _get_meta {
    my ($url, $main_args) = @_;

    state $pa = do {
        require Perinci::Access;
        my $pa = Perinci::Access->new;
        $pa;
    };

    local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0
        unless $main_args->{ssl_verify_hostname};

    $pa->request(meta => $url);
}

$SPEC{gen_perinci_cmdline_script} = {
    v => 1.1,
    summary => 'Generate Perinci::CmdLine CLI script',
    args => {

        output_file => {
            summary => 'Path to output file',
            schema => ['str*'],
            default => '-',
            cmdline_aliases => { o=>{} },
            tags => ['category:output'],
            'x.schema.entity' => 'filename',
        },
        overwrite => {
            schema => [bool => default => 0],
            summary => 'Whether to overwrite output if previously exists',
            tags => ['category:output'],
        },

        url => {
            summary => 'URL to function (or package, if you have subcommands)',
            schema => 'str*',
            'x.schema.entity' => 'riap_url',
            pos => 0,
            req => 1,
        },
        subcommand => {
            summary => 'Subcommand name followed by colon and function URL',
            schema => ['array*', of=>'str*'],
            cmdline_aliases => { s=>{} },
        },
        cmdline => {
            summary => 'Specify module to use',
            schema  => 'str',
            default => 'Perinci::CmdLine::Any',
            'x.schema.entity' => 'perl_module',
        },
        prefer_lite => {
            summary => 'Prefer Perinci::CmdLine::Lite backend',
            'summary.alt.bool.not' => 'Prefer Perinci::CmdLine::Classic backend',
            schema  => 'bool',
            default => 1,
        },
        log => {
            summary => 'Will be passed to Perinci::CmdLine constructor',
            schema  => 'bool',
        },
        default_log_level => {
            schema  => ['str', in=>[qw/trace debug info warn error fatal none/]],
        },
        ssl_verify_hostname => {
            summary => q[If set to 0, will add: $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;' to code],
            schema  => 'bool',
            default => 1,
        },
        snippet_before_instantiate_cmdline => {
            schema => 'str',
        },
        config_filename => {
            summary => 'Will be passed to Perinci::CmdLine constructor',
            schema => 'str',
        },
        load_module => {
            summary => 'Load extra modules',
            schema => ['array', of=>'str*'],
            'x.schema.element_entity' => 'perl_module',
        },
        interpreter_path => {
            summary => 'What to put on shebang line',
            schema => 'str',
        },
        script_name => {
            schema => 'str',
        },

    },
};
sub gen_perinci_cmdline_script {
    my %args = @_;

    my $output_file = $args{output_file};

    my $script_name = $args{script_name};
    unless ($script_name) {
        if ($output_file eq '-') {
            $script_name = 'script';
        } else {
            $script_name = $output_file;
            $script_name =~ s!.+[\\/]!!;
        }
    }

    my $cmdline_mod = "Perinci::CmdLine::Any";
    if ($args{cmdline}) {
        my $val = $args{cmdline};
        if ($val eq 'any') {
            $cmdline_mod = "Perinci::CmdLine::Any";
        } elsif ($val eq 'classic') {
            $cmdline_mod = "Perinci::CmdLine::Classic";
        } elsif ($val eq 'lite') {
            $cmdline_mod = "Perinci::CmdLine::Lite";
        } else {
            $cmdline_mod = $val;
        }
    }

    my $subcommands;
    if ($args{subcommand} && @{ $args{subcommand} }) {
        $subcommands = {};
        for (@{ $args{subcommand} }) {
            my ($sc_name, $sc_url, $sc_summary) = split /:/, $_, 3;
            $subcommands->{$sc_name} = {
                url => $sc_url,
                summary => $sc_summary,
            };
        }
    }

    # request metadata to, to get summary (etc)
    my $res = _get_meta($args{url}, \%args);
    return [500, "Can't meta $args{url}: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;
    my $meta = $res->[2];

    # the resulting code
    my $code = join(
        "",
        "#!", ($args{interpreter_path} // $^X), "\n",
        "\n",
        "# Note: This script is a CLI interface",
        ($meta->{args} ? " to Riap function $args{url}" : ""), # a quick hack to guess meta is func metadata (XXX should've done an info Riap request)
        "\n",
        "# and generated automatically using ", __PACKAGE__,
        " version ", ($App::GenPericmdScript::VERSION // '?'), "\n",
        "\n",
        "# DATE\n",
        "# VERSION\n",
        "\n",
        "use 5.010001;\n",
        "use strict;\n",
        "use warnings;\n",
        "\n",

        ($args{load_module} && @{$args{load_module}} ?
             join("", map {"use $_;\n"} @{$args{load_module}})."\n" : ""),

        ($args{default_log_level} ?
             "BEGIN { no warnings; \$main::Log_Level = '$args{default_log_level}'; }\n\n" : ""),

        "use $cmdline_mod",
        ($cmdline_mod eq 'Perinci::CmdLine::Any' &&
             defined($args{prefer_lite}) && !$args{prefer_lite} ? " -prefer_lite=>0" : ""),
        ";\n\n",

        ($args{ssl_verify_hostname} ? "" : '$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;' . "\n\n"),

        ($args{snippet_before_instantiate_cmdline} ? "# snippet_before_instantiate_cmdline\n" . $args{snippet_before_instantiate_cmdline} . "\n\n" : ""),

        "$cmdline_mod->new(\n",
        "    url => ", dump($args{url}), ",\n",
        (defined($subcommands) ? "    subcommands => " . dump($subcommands) . ",\n" : ""),
        (defined($args{log}) ? "    log => " . dump($args{log}) . ",\n" : ""),
        (defined($args{config_filename}) ? "    config_filename => " . dump($args{config_filename}) . ",\n" : ""),
        ")->run;\n",
        "\n",
    );

    # abstract line
    $code .= "# ABSTRACT: " . ($meta->{summary} // $script_name) . "\n";

    # podname
    $code .= "# PODNAME: $script_name\n";

    if ($output_file ne '-') {
        $log->trace("Outputing result to %s ...", $output_file);
        if ((-f $output_file) && !$args{overwrite}) {
            return [409, "Output file '$output_file' already exists (please use --overwrite if you want to override)"];
        }
        open my($fh), ">", $output_file
            or return [500, "Can't open '$output_file' for writing: $!"];

        print $fh $code;
        close $fh
            or return [500, "Can't write '$output_file': $!"];

        chmod 0755, $output_file or do {
            $log->warn("Can't 'chmod 0755, $output_file': $!");
        };

        my $output_name = $output_file;
        $output_name =~ s!.+[\\/]!!;

        if (which("shcompgen") && which($output_name)) {
            $log->trace("We have shcompgen in PATH and output ".
                            "$output_name is also in PATH, running shcompgen ...");
            system "shcompgen", "generate", $output_name;
        }

        $code = "";
    }

    [200, "OK", $code, {
        'func.cmdline_module' => $cmdline_mod,
        'func.cmdline_module_version' => 0,
        'func.script_name' => 0,
    }];
}

1;
# ABSTRACT:
