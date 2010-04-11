package App::Sys::Info;
use strict;
use warnings;
use vars qw( $VERSION );

$VERSION = '0.12';

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

my($NEED_CHCP, $OLDCP);

BEGIN {
    no strict qw( refs );
    foreach my $id ( qw( info os  cpu nf meta NA ) ) {
        *{ $id } = sub () { return shift->{$id} };
    }
}

END {
   system chcp => $OLDCP, '2>nul', '1>nul' if $NEED_CHCP && $OLDCP;
}

sub new {
    my $class  = shift;
    my $i      = Sys::Info->new;
    my $self   = {
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
        chomp($OLDCP = (split /:\s?/xms, qx(chcp))[LAST_ELEMENT]);
        system chcp => CP_UTF8, '2>nul', '1>nul' if $OLDCP; # try to change it to unicode
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
    my $pt   = $os->product_type;
    my $proc = $self->_processors;
    my $tz   = $os->tz;
    my @rv;

    push @rv,
    [ 'Sys::Info Version' => Sys::Info->VERSION   ],
    [ 'Perl Version'      => $i->perl_long        ],
    [ 'Host Name'         => $os->host_name       ],
    [ 'OS Name'           => $self->_os_name()    ],
    [ 'OS Version'        => $self->_os_version() ],
    ;

    push @rv, [ 'OS Manufacturer'  => $meta->{manufacturer} ] if $meta->{manufacturer};
    push @rv, [ 'OS Configuration' => $pt                   ] if $pt;
    push @rv, [ 'OS Build Type'    => $meta->{build_type}   ] if $meta->{build_type};

    $self->_bitness(      \@rv );
    $self->_current_user( \@rv );

    if ( $os->is_windows ) {
        push @rv, [ 'Registered Owner'        => $meta->{owner}        ] if $meta->{owner};
        push @rv, [ 'Registered Organization' => $meta->{organization} ] if $meta->{organization};
    }

    push @rv, [ 'Product ID'     => $meta->{product_id}      ] if $meta->{product_id};
    $self->_install_date( \@rv );
    push @rv, [ 'System Up Time' => elapsed($os->tick_count) ] if $os->tick_count;

    if ( $os->is_windows ) {
        push @rv, [ 'System Manufacturer' => $meta->{system_manufacturer} ] if $meta->{system_manufacturer};
        push @rv, [ 'System Model'        => $meta->{system_model}        ] if $meta->{system_model};
    }

    push @rv, [ 'System Type'  => $meta->{system_type} ] if $meta->{system_type};
    push @rv, [ 'Processor(s)' => $proc                ] if $proc;

    $self->_proc_meta(    \@rv );
    $self->_bios_version( \@rv );

    push @rv, [ 'Windows Directory' => $meta->{windows_dir} ] if $meta->{windows_dir};
    push @rv, [ 'System Directory'  => $meta->{system_dir}  ] if $meta->{system_dir};
    push @rv, [ 'Boot Device'       => $meta->{boot_device} ] if $meta->{boot_device};
    push @rv, [ 'System Locale'     => $self->{LOCALE}      ] if $self->{LOCALE};
    push @rv, [ 'Input Locale'      => $self->{LOCALE}      ] if $self->{LOCALE};
    push @rv, [ 'Time Zone'         => $tz                  ] if $tz;
    push @rv,
    [ 'Total Physical Memory'     => $self->_mb($meta->{physical_memory_total}    ) ],
    [ 'Available Physical Memory' => $self->_mb($meta->{physical_memory_available}) ],
    [ 'Virtual Memory: Max Size'  => $self->_mb($meta->{page_file_total}          ) ],
    [ 'Virtual Memory: Available' => $self->_mb($meta->{page_file_available}      ) ],
    ;

    $self->_vm( \@rv );

    my $domain = $os->domain_name;
    my $logon  = $os->logon_server;
    my $ip     = $os->ip;

    push @rv, [ 'Page File Location(s)' => $meta->{page_file_path} ] if $meta->{page_file_path};
    push @rv, [ 'Domain'                => $domain                 ] if $domain;
    push @rv, [ 'Logon Server'          => $logon                  ] if $logon;
    push @rv, [ 'IP Address'            => $os->ip                 ] if $ip;

    if ( $os->is_windows ) {
        my $cdkey = $os->cdkey;
        my $okey  = $self->_office_cdkey;
        push @rv, [ 'Windows CD Key'          => $cdkey ] if $cdkey;
        push @rv, [ 'Microsoft Office CD Key' => $okey  ] if $okey;
    }

    return @rv;
}

sub _current_user {
    my($self, $rv_ref) = @_;
    my $os   = $self->os;
    my $user = $os->login_name || return;
    my $real = $os->login_name( real => 1 );
    return if ! $user || ! $real;
    my $display = $real && ($real ne $user) ? qq{$real ($user)} : $user;
    $display .= $os->is_root ? q{ is an administrator} : q{};
    push @{ $rv_ref }, [ 'Current User', $display ];
    return;
}

sub _proc_meta {
    my $self = shift;
    my $data = shift;
    my @cpu  = $self->cpu->identify;
    my $prop = $cpu[0] || {};
    my $load = $self->cpu->load;
    my $L1   = $prop->{L1_cache}{max_cache_size};
    my $L2   = $prop->{L2_cache}{max_cache_size};
    my $sock = $prop->{socket_designation};
    my $id   = $prop->{processor_id};
    my @rv;

    my $check_lc = sub {
        my $ref = shift || return;
        return if ! ${ $ref };
        ${ $ref } .= q{ KB} if ${ $ref } !~ m{\sKB\z}xms;
        return;
    };

    $check_lc->( \$L1 );
    $check_lc->( \$L2 );

    push @rv, qq{Load    : $load}  if $load;
    push @rv, qq{L1 Cache: $L1}    if $L1;
    push @rv, qq{L2 Cache: $L2}    if $L2;
    push @rv, qq{Package : $sock}  if $sock;
    push @rv, qq{ID      : $id}    if $id;

    my $buf = q{ } x 2**2;
    push @{$data}, [ q{ }, $buf . $_ ] for @rv;
    return;
}

sub _processors {
    my $self = shift;
    my $cpu  = $self->cpu;
    my $name = scalar $cpu->identify;
    my $rv   = sprintf '%s ~%sMHz', $name, $cpu->speed;
    $rv =~ s{\s+}{ }xmsg;
    return $rv;
}

sub _vm {
    my($self, $rv_ref) = @_;
    my $tot = $self->meta->{page_file_total}     || return;
    my $av  = $self->meta->{page_file_available} || return;
    push @{ $rv_ref }, [ 'Virtual Memory: In Use' => $self->_mb( $tot - $av ) ];
    return;
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
    my($self, $rv_ref) = @_;
    my $cpu = $self->cpu->bitness || q{??};
    my $os  = $self->os->bitness  || q{??};
    push @{ $rv_ref }, [ 'Running on' => qq{${cpu}bit CPU & ${os}bit OS} ];
    return;
}

sub _install_date {
    my($self, $rv_ref) = @_;
    my $date = $self->meta->{install_date} || return;
    push @{ $rv_ref }, [ 'Original Install Date' => scalar localtime $date ];
    return;
}

sub _bios_version {
    my($self, $rv_ref) = @_;
    local $@;
    my $bv = eval { $self->info->device('bios')->version; };
    return if $@ || ! $bv;
    push @{ $rv_ref }, [ 'BIOS Version' => $bv ];
    return;
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

=head1 METHODS

=head2 NA

=head2 cpu

=head2 info

=head2 meta

=head2 new

=head2 nf

=head2 os

=head2 probe

=head2 run

=cut
