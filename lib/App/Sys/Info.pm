package App::Sys::Info;
use strict;
use warnings;
use vars qw( $VERSION );

$VERSION = '0.10';

use constant CP_UTF8      => 65_001;
use constant KB           =>   1024;
use constant LAST_ELEMENT =>     -1;

use Carp                 qw( croak );
use Number::Format       qw();
use POSIX                qw(locale_h);
use Text::Table          qw();
use Time::Elapsed        qw( elapsed );
use Sys::Info            qw();
use Sys::Info::Constants qw(NEW_PERL);

my $NEED_CHCP;

BEGIN {
    no strict qw( refs );
    foreach my $id ( qw( info os  cpu nf meta NA ) ) {
        *{ $id } = sub () { return shift->{$id} };
    }
}

my $oldcp;

END {
   system chcp => $oldcp, '2>nul', '1>nul' if $NEED_CHCP && $oldcp;
}

sub new {
    my($class) = @_;
    my $i    = Sys::Info->new;
    my $self = {
        LOCALE => setlocale( LC_CTYPE ),
        NA     => 'N/A',
        info   => $i,
        os     => $i->os,
        cpu    => $i->device('CPU'),
        nf     => Number::Format->new(
                    THOUSANDS_SEP => q{,},
                    DECIMAL_POINT => q{.},
                ),
    };
    $self->{meta} = { $self->{os}->meta };
    bless $self, $class;
    return $self;
}

sub run {
    my $self   = __PACKAGE__->new;
    $NEED_CHCP = $self->os->is_winnt && $ENV{PROMPT};
    my @probe  = $self->probe();

    if ( $NEED_CHCP ) {
        ## no critic (InputOutput::ProhibitBacktickOperators)
        chomp($oldcp = (split /:\s?/xms, qx(chcp))[LAST_ELEMENT]);
        system chcp => CP_UTF8, '2>nul', '1>nul' if $oldcp; # try to change it to unicode
        if ( NEW_PERL ) {
            my $eok = eval q{ binmode STDOUT, ':utf8'; 1; };
        }
    }
    my @titles = ( "FIELD\n=====", "VALUE\n=====");
    @titles = ( q{}, q{});

    my $tb = Text::Table->new( @titles );
    $tb->load( @probe );
    print "\n", $tb or croak "Unable to orint to STDOUT: $!";
    return;
}

sub probe {
    my $self = shift;
    my @rv   = eval { $self->_probe(); };
    croak "Error fetching information: $@" if $@;
    return @rv;
}

sub _probe {
    my $self = shift;
    my $meta = $self->meta;
    my $NA   = $self->NA;
    my $i    = $self->info;
    my $os   = $self->os;
    my @rv   = (
    [ 'Sys::Info Version'         => Sys::Info->VERSION                       ],
    [ 'Perl Version'              => $i->perl_long                            ],
    [ 'Host Name'                 => $os->host_name                           ],
    [ 'OS Name'                   => $self->_os_name()                        ],
    [ 'OS Version'                => $self->_os_version()                     ],
    [ 'OS Manufacturer'           => $meta->{manufacturer}          || $NA    ],
    [ 'OS Configuration'          => $os->product_type              || $NA    ],
    [ 'OS Build Type'             => $meta->{build_type}            || $NA    ],
    [ 'Running on'                => $self->_bitness()                        ],
    [ 'Registered Owner'          => $meta->{owner}                 || $NA    ],
    [ 'Registered Organization'   => $meta->{organization}          || $NA    ],
    [ 'Product ID'                => $meta->{product_id}            || $NA    ],
    [ 'Original Install Date'     => $self->_install_date()                   ],
    [ 'System Up Time'            => elapsed($os->tick_count)       || $NA    ],
    [ 'System Manufacturer'       => $meta->{system_manufacturer}   || $NA    ],
    [ 'System Model'              => $meta->{system_model}          || $NA    ],
    [ 'System Type'               => $meta->{system_type}           || $NA    ],
    [ 'Processor(s)'              => $self->_processors()           || $NA    ],
    [ 'BIOS Version'              => $self->_bios_version()                   ],
    [ 'Windows Directory'         => $meta->{windows_dir}           || $NA    ],
    [ 'System Directory'          => $meta->{system_dir}            || $NA    ],
    [ 'Boot Device'               => $meta->{boot_device}           || $NA    ],
    [ 'System Locale'             => $self->{LOCALE}                || $NA    ],
    [ 'Input Locale'              => $self->{LOCALE}                || $NA    ],
    [ 'Time Zone'                 => $os->tz                        || $NA    ],
    [ 'Total Physical Memory'     => $self->_mb($meta->{physical_memory_total}    ) ],
    [ 'Available Physical Memory' => $self->_mb($meta->{physical_memory_available}) ],
    [ 'Virtual Memory: Max Size'  => $self->_mb($meta->{page_file_total}          ) ],
    [ 'Virtual Memory: Available' => $self->_mb($meta->{page_file_available}      ) ],
    [ 'Virtual Memory: In Use'    => $self->_vm()                             ],
    [ 'Page File Location(s)'     => $meta->{page_file_path}        || $NA    ],
    [ 'Domain'                    => $os->domain_name               || $NA    ],
    [ 'Logon Server'              => $os->logon_server              || $NA    ],
    );
    push @rv,
    [ 'Windows CD Key'            => $os->cdkey                     || $NA    ],
    [ 'Microsoft Office CD Key'   => $self->_office_cdkey()                   ],
    if $os->is_windows;
    return @rv;
}

sub _processors {
    my $self = shift;
    my $rv   = sprintf '%s ~%sMHz', scalar($self->cpu->identify), $self->cpu->speed;
    $rv =~ s{\s+}{ }xmsg;
    return $rv;
}

sub _vm {
    my $self = shift;
    my $tot  = $self->meta->{page_file_total}     || return $self->NA;
    my $av   = $self->meta->{page_file_available} || return $self->NA;
    return $self->_mb( $tot - $av );
}

sub _mb {
    my $self = shift;
    my $kb   = shift || return $self->NA;
    my $int  = sprintf '%.0f', $kb / KB;
    return sprintf '%s MB', $self->nf->format_number( $int );
}

sub _os_name {
    my $self = shift;
    return $self->os->name( long => 1, edition => 1 );
}

sub _os_version {
    my $self = shift;
    return $self->os->version . q{.} . $self->os->build;
}

sub _office_cdkey {
    my $self = shift;
    return ($self->os->cdkey( office => 1 ))[0] || $self->NA ;
}

sub _bitness {
    my $self = shift;
    my %bit = (
        cpu => $self->cpu->bitness || q{??},
        os  => $self->os->bitness  || q{??},
    );
    return "$bit{cpu}bit CPU & $bit{os}bit OS";
}

sub _install_date {
    my $self = shift;
    return $self->meta->{install_date} ? scalar localtime $self->meta->{install_date} : $self->NA;
}

sub _bios_version {
    my $self = shift;
    local $@;
    my $bv = eval {
                $self->info->device('bios')->version;
             };
    return $bv;
}

1;

__END__

=pod

=head1 NAME

App::Sys::Info - An application of Sys::Info to gather information from the host system

=head1 SYNOPSIS

Run C<sysinfo> from the command line.

=head1 DESCRIPTION

The output is identical to I<systeminfo> windows command.

=cut
