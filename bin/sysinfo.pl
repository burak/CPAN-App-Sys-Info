#!/usr/bin/perl -w
use strict;
use warnings;
use vars qw( $VERSION );
use App::Sys::Info;

$VERSION = '0.10';

App::Sys::Info->run;

1;

__END__

=pod

=head1 NAME

sysinfo.pl - Front end to App::Sys::Info

=head1 SYNOPSIS

Excute from command line.

=head1 DESCRIPTION

Front end to App::Sys::Info.

=head1 SEE ALSO

L<App::Sys::Info>.

=cut