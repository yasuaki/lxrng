# Copyright (C) 2008 Arne Georg Gleditsch <lxr@linux.no>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# The full GNU General Public License is included in this distribution
# in the file called COPYING.

package LXRng::Repo::Plain::File;

use strict;

use base qw(LXRng::Repo::File);
use Fcntl;

sub new {
    my ($class, $name, $path) = @_;

    my @stat = stat($path);

    return undef unless @stat;

    return LXRng::Repo::Plain::Directory->new($name, $path, \@stat) if -d _;

    return bless({name => $name, path => $path, stat => \@stat}, $class);
}

sub time {
    my ($self) = @_;

    return $$self{'stat'}[9];
}

sub size {
    my ($self) = @_;

    return $$self{'stat'}[7];
}

sub phys_path {
    my ($self) = @_;

    return $$self{'path'};
}

sub revision {
    my ($self) = @_;

    return $self->time.'.'.$self->size;
}

sub handle {
    my ($self) = @_;

    sysopen(my $handle, $self->phys_path, O_RDONLY) or die($!);
    return $handle;
}

1;
